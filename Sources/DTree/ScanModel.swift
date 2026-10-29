import AppKit
import Foundation

@MainActor
final class ScanModel: ObservableObject {
    /// The last finished scan.
    @Published private(set) var result: Scanner.Result?
    /// The directory whose subdirectories are listed.
    @Published var current: DirNode?
    /// The folder being scanned right now.
    @Published private(set) var scanning: URL?
    @Published private(set) var progress = Scanner.Progress(directories: 0, path: "")
    /// How long the last finished scan took.
    @Published private(set) var duration: TimeInterval = 0
    @Published var error: String?

    private var flag: CancelFlag?
    private var started = Date()
    private var lastScanned: URL?

    static let startupDisk = URL(fileURLWithPath: "/")
    static let home = FileManager.default.homeDirectoryForCurrentUser

    func scan(_ url: URL) {
        flag?.set()
        let flag = CancelFlag()
        self.flag = flag
        scanning = url
        lastScanned = url
        error = nil
        progress = Scanner.Progress(directories: 0, path: url.path)
        started = Date()
        let path = url.path
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

    func rescan() {
        if let lastScanned { scan(lastScanned) }
    }

    var canRescan: Bool { lastScanned != nil && scanning == nil }

    func cancel() {
        flag?.set()
        flag = nil
        scanning = nil
    }

    private func finish(_ result: Scanner.Result?, path: String) {
        flag = nil
        scanning = nil
        guard let result else {
            error = "Couldn't read \(path)."
            return
        }
        duration = Date().timeIntervalSince(started)
        self.result = result
        current = result.root
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
