import CryptoKit
import Foundation

enum Prefs {
    /// How long finished scans are reused, in minutes; 0 turns the cache off.
    static let cacheMinutes = "cacheMinutes"
    static let defaultCacheMinutes = 60
}

/// Keeps finished scans for a while (in memory and in ~/Library/Caches), so scanning a folder
/// that a recent scan already covers — the same folder or one above it — opens instantly.
@MainActor
final class ScanCache {
    struct Entry: Codable, Equatable {
        /// The folder that was scanned.
        let path: String
        let date: Date
        /// Archive file name in the cache folder.
        let file: String
    }

    private var entries: [Entry] = []
    /// Recently used scans, by archive file name; the most recent last.
    private var loaded: [(file: String, result: Scanner.Result)] = []
    private static let keepInMemory = 3

    private let folder: URL = {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        return caches.appendingPathComponent("com.damonmatthews.dtree", isDirectory: true)
    }()
    private var indexURL: URL { folder.appendingPathComponent("index.json") }

    static var lifetime: TimeInterval {
        let minutes = UserDefaults.standard.object(forKey: Prefs.cacheMinutes) as? Int ?? Prefs.defaultCacheMinutes
        return TimeInterval(max(minutes, 0)) * 60
    }

    init() {
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        if let data = try? Data(contentsOf: indexURL),
           let saved = try? JSONDecoder().decode([Entry].self, from: data) {
            entries = saved
        }
        prune()
    }

    /// The newest scan still in date that covers `path`.
    func entry(covering path: String) -> Entry? {
        prune()
        return entries
            .filter { path == $0.path || path.hasPrefix($0.path.hasSuffix("/") ? $0.path : $0.path + "/") }
            .max { $0.date < $1.date }
    }

    /// The scan in memory, if it's still there.
    func memory(_ entry: Entry) -> Scanner.Result? {
        guard let i = loaded.firstIndex(where: { $0.file == entry.file }) else { return nil }
        let hit = loaded.remove(at: i)
        loaded.append(hit)
        return hit.result
    }

    /// Reads the scan back from disk (off the main thread).
    func load(_ entry: Entry) async -> Scanner.Result? {
        if let hit = memory(entry) { return hit }
        let url = folder.appendingPathComponent(entry.file)
        let result = await Task.detached(priority: .userInitiated) {
            (try? Data(contentsOf: url)).flatMap(ScanArchive.decode)
        }.value
        if let result { remember(entry.file, result) } else { remove(entry) }
        return result
    }

    /// Saves a finished scan. Older scans of the same folder, or of folders inside it, are dropped.
    func store(_ result: Scanner.Result, path: String, date: Date) {
        guard Self.lifetime > 0 else { return }
        let prefix = path.hasSuffix("/") ? path : path + "/"
        for old in entries where old.path == path || old.path.hasPrefix(prefix) { remove(old) }
        let file = SHA256.hash(data: Data(path.utf8)).prefix(12).map { String(format: "%02x", $0) }.joined() + ".dtree"
        let entry = Entry(path: path, date: date, file: file)
        entries.append(entry)
        remember(file, result)
        saveIndex()
        let url = folder.appendingPathComponent(file)
        Task.detached(priority: .utility) {
            try? ScanArchive.encode(result).write(to: url, options: .atomic)
        }
    }

    func clear() {
        for entry in entries { remove(entry) }
        loaded.removeAll()
    }

    var isEmpty: Bool { entries.isEmpty }

    private func remember(_ file: String, _ result: Scanner.Result) {
        loaded.removeAll { $0.file == file }
        loaded.append((file, result))
        if loaded.count > Self.keepInMemory { loaded.removeFirst(loaded.count - Self.keepInMemory) }
    }

    private func remove(_ entry: Entry) {
        entries.removeAll { $0 == entry }
        loaded.removeAll { $0.file == entry.file }
        try? FileManager.default.removeItem(at: folder.appendingPathComponent(entry.file))
        saveIndex()
    }

    /// Drops scans older than the cache lifetime (all of them when the cache is off).
    private func prune() {
        let cutoff = Date().addingTimeInterval(-Self.lifetime)
        for entry in entries where entry.date < cutoff || Self.lifetime == 0 { remove(entry) }
    }

    private func saveIndex() {
        try? JSONEncoder().encode(entries).write(to: indexURL, options: .atomic)
    }
}

/// Compact binary form of a scan: a header, then every directory in depth-first order as
/// depth, flags, size, files size and name.
enum ScanArchive {
    private static let magic: UInt32 = 0x4454_5231  // "DTR1"

    static func encode(_ result: Scanner.Result) -> Data {
        var data = Data()
        data.reserveCapacity(result.directories * 48)
        func put<T: FixedWidthInteger>(_ value: T) { withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) } }
        put(magic)
        put(UInt64(result.directories))
        put(UInt64(result.unreadable))
        var stack: [(DirNode, UInt16)] = [(result.root, 0)]
        while let (node, depth) = stack.popLast() {
            let name = Data(node.name.utf8)
            put(depth)
            put(UInt8(node.unreadable ? 1 : 0))
            put(node.size)
            put(node.filesSize)
            put(UInt32(name.count))
            data.append(name)
            // Reversed so children come out in their (largest-first) order.
            for child in node.children.reversed() { stack.append((child, depth &+ 1)) }
        }
        return data
    }

    static func decode(_ data: Data) -> Scanner.Result? {
        data.withUnsafeBytes { raw -> Scanner.Result? in
            var offset = 0
            func get<T: FixedWidthInteger>(_: T.Type) -> T? {
                guard offset + MemoryLayout<T>.size <= raw.count else { return nil }
                let value = raw.loadUnaligned(fromByteOffset: offset, as: T.self)
                offset += MemoryLayout<T>.size
                return T(littleEndian: value)
            }
            guard get(UInt32.self) == magic, let directories = get(UInt64.self), let unreadable = get(UInt64.self)
            else { return nil }
            var root: DirNode?
            var stack: [DirNode] = []
            while offset < raw.count {
                guard let depth = get(UInt16.self), let flags = get(UInt8.self), let size = get(Int64.self),
                      let filesSize = get(Int64.self), let length = get(UInt32.self),
                      offset + Int(length) <= raw.count
                else { return nil }
                let name = String(decoding: raw[offset..<offset + Int(length)], as: UTF8.self)
                offset += Int(length)
                guard Int(depth) <= stack.count, (depth == 0) == (root == nil) else { return nil }
                stack.removeLast(stack.count - Int(depth))
                let node = DirNode(name: name, parent: stack.last)
                node.size = size
                node.filesSize = filesSize
                node.unreadable = flags & 1 != 0
                stack.last?.children.append(node)
                if root == nil { root = node }
                stack.append(node)
            }
            guard let root else { return nil }
            return Scanner.Result(root: root, directories: Int(directories), unreadable: Int(unreadable))
        }
    }
}
