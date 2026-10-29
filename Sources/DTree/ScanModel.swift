import AppKit
import Foundation

@MainActor
final class ScanModel: ObservableObject {
    /// The scan being viewed. Its root can be above the folder asked for, when that came from the cache.
    @Published private(set) var result: Scanner.Result?
    /// The directory whose subdirectories are listed.
    @Published var current: DirNode?
    /// The folder being scanned (or loaded from the cache) right now.
    @Published private(set) var scanning: URL?
    /// True while a saved scan is read back from disk rather than scanned.
    @Published private(set) var loadingFromCache = false
    @Published private(set) var progress = Scanner.Progress(directories: 0, path: "")
    /// How long the viewed scan took, and when it was made.
    @Published private(set) var duration: TimeInterval = 0
    @Published private(set) var scanDate: Date?
    /// True when the viewed scan came from the cache instead of a new scan.
    @Published private(set) var fromCache = false
    @Published var error: String?

    let cache = ScanCache()
    private var flag: CancelFlag?
    private var started = Date()
    private var lastScanned: URL?
    /// After a rescan, the folder to come back to instead of the scanned one.
    private var returnTo: String?

    static let startupDisk = URL(fileURLWithPath: "/")
    static let home = FileManager.default.homeDirectoryForCurrentUser

    /// Shows `url`, from a recent enough scan when there is one; `force` always scans again.
    func scan(_ url: URL, force: Bool = false) {
        let path = Self.path(of: url)
        flag?.set()
        flag = nil
        lastScanned = url
        returnTo = nil
        error = nil
        if !force, let entry = cache.entry(covering: path) {
            if let cached = cache.memory(entry) {
                show(cached, at: path, date: entry.date, duration: nil)
                scanning = nil
                return
            }
            loadFromCache(entry, url: url, path: path)
            return
        }
        startScan(url, path: path)
    }

    private func loadFromCache(_ entry: ScanCache.Entry, url: URL, path: String) {
        let flag = CancelFlag()
        self.flag = flag
        scanning = url
        loadingFromCache = true
        progress = Scanner.Progress(directories: 0, path: path)
        Task {
            let cached = await cache.load(entry)
            guard self.flag === flag else { return }
            loadingFromCache = false
            if let cached {
                self.flag = nil
                scanning = nil
                show(cached, at: path, date: entry.date, duration: nil)
            } else {
                startScan(url, path: path)  // the saved copy was unreadable
            }
        }
    }

    private func startScan(_ url: URL, path: String) {
        let flag = CancelFlag()
        self.flag = flag
        scanning = url
        progress = Scanner.Progress(directories: 0, path: path)
        started = Date()
        Task.detached(priority: .userInitiated) {
            let result = Scanner.scan(path, isCancelled: { flag.isSet }) { update in
                Task { @MainActor in
                    if self.flag === flag { self.progress = update }
                }
            }
            await MainActor.run {
                if self.flag === flag { self.finish(result, path: path) }
            }
        }
    }

    private func finish(_ result: Scanner.Result?, path: String) {
        flag = nil
        scanning = nil
        guard let result else {
            error = "Couldn't read \(path)."
            return
        }
        let date = Date()
        cache.store(result, path: path, date: date)
        show(result, at: path, date: date, duration: date.timeIntervalSince(started))
    }

    /// `duration` nil = from the cache.
    private func show(_ result: Scanner.Result, at path: String, date: Date, duration: TimeInterval?) {
        self.result = result
        current = returnTo.flatMap { Self.find($0, in: result.root) } ?? Self.find(path, in: result.root) ?? result.root
        returnTo = nil
        scanDate = date
        fromCache = duration == nil
        if let duration { self.duration = duration }
    }

    /// The node for `path` inside a scan rooted at or above it.
    static func find(_ path: String, in root: DirNode) -> DirNode? {
        guard path != root.name else { return root }
        let base = root.name.hasSuffix("/") ? root.name : root.name + "/"
        guard path.hasPrefix(base) else { return nil }
        var node = root
        for name in path.dropFirst(base.count).split(separator: "/") {
            guard let next = node.children.first(where: { $0.name == name }) else { return nil }
            node = next
        }
        return node
    }

    /// A scan path without a trailing slash (except "/").
    static func path(of url: URL) -> String {
        let path = url.standardizedFileURL.path
        return path.count > 1 && path.hasSuffix("/") ? String(path.dropLast()) : path
    }

    /// Scans the last scanned folder again, ignoring the cache, and comes back to the folder being viewed.
    func rescan() {
        guard let lastScanned else { return }
        let viewing = current?.path
        scan(lastScanned, force: true)
        returnTo = viewing
    }

    var canRescan: Bool { lastScanned != nil && scanning == nil }

    func cancel() {
        flag?.set()
        flag = nil
        scanning = nil
        loadingFromCache = false
    }

    func clearCache() {
        cache.clear()
    }

    func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.treatsFilePackagesAsDirectories = true
        panel.prompt = "Scan"
        panel.message = "Choose a folder or disk to scan"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        scan(url)
    }

    func goUp() {
        if let parent = current?.parent { current = parent }
    }

    var canGoUp: Bool { current?.parent != nil }

    /// Name of the disk holding `url`, e.g. "Macintosh HD".
    static func volumeName(_ url: URL) -> String {
        (try? url.resourceValues(forKeys: [.volumeLocalizedNameKey]).volumeLocalizedName) ?? url.path
    }

    static func format(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}
