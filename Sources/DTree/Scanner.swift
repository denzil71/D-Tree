import Darwin
import Foundation
import os

/// One directory in a finished scan. Built on the scanning thread, then only read on the main thread.
final class DirNode: Identifiable, Hashable, @unchecked Sendable {
    /// The full path for the scan's root; the last path component for everything else.
    let name: String
    private(set) weak var parent: DirNode?
    /// Space used by everything inside, recursively (allocated size, so sparse and compressed files count as stored).
    var size: Int64 = 0
    /// Space used by the files directly inside, not in subdirectories.
    var filesSize: Int64 = 0
    /// Largest first.
    var children: [DirNode] = []
    /// The directory couldn't be read (usually missing permission), so its size is incomplete.
    var unreadable = false

    init(name: String, parent: DirNode?) {
        self.name = name
        self.parent = parent
    }

    var id: ObjectIdentifier { ObjectIdentifier(self) }

    /// nil for a directory without subdirectories, so the tree shows no disclosure triangle.
    var childList: [DirNode]? { children.isEmpty ? nil : children }

    var path: String {
        guard let parent else { return name }
        let base = parent.path
        return base.hasSuffix("/") ? base + name : base + "/" + name
    }

    var displayName: String {
        parent == nil ? FileManager.default.displayName(atPath: name) : name
    }

    /// This directory and those above it, scan root first.
    var lineage: [DirNode] {
        var chain = [self]
        while let up = chain.last?.parent { chain.append(up) }
        return chain.reversed()
    }

    static func == (a: DirNode, b: DirNode) -> Bool { a === b }
    func hash(into hasher: inout Hasher) { hasher.combine(ObjectIdentifier(self)) }
}

enum Scanner {
    struct Progress: Sendable {
        var directories: Int
        var path: String
    }

    struct Result: Sendable {
        let root: DirNode
        let directories: Int
        let unreadable: Int
    }

    private struct FileKey: Hashable {
        let device: dev_t
        let inode: ino_t
    }

    /// Walks `rootPath` without following symlinks or crossing into other volumes.
    /// Scanning "/" includes the Data volume (where /Users, /Applications etc. really live)
    /// but skips /System/Volumes, which would count it twice.
    /// Returns nil when cancelled or when `rootPath` can't be opened.
    static func scan(_ rootPath: String, isCancelled: () -> Bool, progress: (Progress) -> Void) -> Result? {
        var info = stat()
        guard lstat(rootPath, &info) == 0 else { return nil }
        var devices: Set<dev_t> = [info.st_dev]
        var skip: Set<String> = []
        if rootPath == "/" {
            if lstat("/System/Volumes/Data", &info) == 0 { devices.insert(info.st_dev) }
            skip.insert("/System/Volumes")
        }

        var argv: [UnsafeMutablePointer<CChar>?] = [strdup(rootPath), nil]
        defer { free(argv[0]) }
        guard let fts = fts_open(&argv, FTS_PHYSICAL | FTS_NOCHDIR, nil) else { return nil }
        defer { fts_close(fts) }

        var root: DirNode?
        /// Directories being walked; a directory at fts level n sits at index n.
        var stack: [DirNode] = []
        /// Hard-linked files already counted, so each is counted once.
        var linked: Set<FileKey> = []
        var directories = 0
        var unreadable = 0
        var entries = 0

        func finish(_ node: DirNode) {
            node.children.sort { $0.size > $1.size }
            if let parent = stack.last { parent.size += node.size }
        }

        while let entry = fts_read(fts) {
            entries += 1
            if entries % 4096 == 0, isCancelled() { return nil }
            let level = Int(entry.pointee.fts_level)
            switch Int32(entry.pointee.fts_info) {
            case FTS_D:
                let path = String(cString: entry.pointee.fts_path)
                let stat = entry.pointee.fts_statp.pointee
                if level > 0, !devices.contains(stat.st_dev) || skip.contains(path) {
                    fts_set(fts, entry, FTS_SKIP)  // fts still reports it once more as FTS_DP; ignored below
                    continue
                }
                let node = DirNode(name: level == 0 ? path : (path as NSString).lastPathComponent, parent: stack.last)
                node.size = Int64(stat.st_blocks) * 512
                stack.last?.children.append(node)
                if root == nil { root = node }
                stack.append(node)
                directories += 1
                if directories % 1000 == 0 { progress(Progress(directories: directories, path: path)) }

            case FTS_DP:
                guard stack.count == level + 1, let node = stack.popLast() else { continue }  // a skipped directory
                finish(node)

            case FTS_DNR:
                unreadable += 1
                if stack.count == level + 1, let node = stack.popLast() {
                    // Reported as FTS_D first, then as unreadable with no FTS_DP to follow.
                    node.unreadable = true
                    finish(node)
                } else {
                    let path = String(cString: entry.pointee.fts_path)
                    let node = DirNode(name: level == 0 ? path : (path as NSString).lastPathComponent, parent: stack.last)
                    node.unreadable = true
                    stack.last?.children.append(node)
                    if root == nil { root = node }
                }

            case FTS_F, FTS_SL, FTS_SLNONE, FTS_DEFAULT:
                let stat = entry.pointee.fts_statp.pointee
                if stat.st_nlink > 1, !linked.insert(FileKey(device: stat.st_dev, inode: stat.st_ino)).inserted {
                    continue
                }
                let bytes = Int64(stat.st_blocks) * 512
                stack.last?.size += bytes
                stack.last?.filesSize += bytes

            default:
                break  // FTS_NS, FTS_ERR, FTS_DC (cycle): nothing to count
            }
        }
        guard let root else { return nil }
        return Result(root: root, directories: directories, unreadable: unreadable)
    }
}

/// A cancel flag the scanning thread polls.
final class CancelFlag: Sendable {
    private let state = OSAllocatedUnfairLock(initialState: false)
    var isSet: Bool { state.withLock { $0 } }
    func set() { state.withLock { $0 = true } }
}
