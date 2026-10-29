import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

@main
struct DTreeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = ScanModel()

    var body: some Scene {
        Window("D-Tree", id: "main") {
            ContentView()
                .environmentObject(model)
                .frame(minWidth: 760, minHeight: 460)
                .onAppear {
                    // For testing: DTREE_SCAN=/some/folder scans it at launch.
                    if let path = ProcessInfo.processInfo.environment["DTREE_SCAN"], model.result == nil {
                        model.scan(URL(fileURLWithPath: path))
                    }
                }
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Scan \(ScanModel.volumeName(ScanModel.startupDisk))") { model.scan(ScanModel.startupDisk) }
                    .keyboardShortcut("1")
                Button("Scan Home Folder") { model.scan(ScanModel.home) }
                    .keyboardShortcut("2")
                Button("Scan Folder…") { model.chooseFolder() }
                    .keyboardShortcut("o")
                Divider()
                Button("Rescan") { model.rescan() }
                    .keyboardShortcut("r")
                    .disabled(!model.canRescan)
            }
            CommandMenu("Go") {
                Button("Enclosing Folder") { model.goUp() }
                    .keyboardShortcut(.upArrow)
                    .disabled(!model.canGoUp)
            }
        }

        Settings {
            SettingsView().environmentObject(model)
        }
    }
}

struct SettingsView: View {
    @EnvironmentObject var model: ScanModel
    @AppStorage(Prefs.cacheMinutes) private var minutes = Prefs.defaultCacheMinutes
    @State private var cleared = false

    private static let choices = [(0, "Don't keep"), (15, "15 minutes"), (60, "1 hour"), (360, "6 hours"),
                                  (1440, "1 day"), (10080, "1 week")]

    var body: some View {
        Form {
            Section {
                Picker("Keep scan results for", selection: $minutes) {
                    ForEach(Self.choices, id: \.0) { Text($0.1).tag($0.0) }
                }
                HStack {
                    Text(cleared ? "Saved scans cleared." : "Scanning a folder that a saved scan covers opens it instantly instead of scanning again. Rescan (⌘R) always scans afresh.")
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("Clear Saved Scans") {
                        model.clearCache()
                        cleared = true
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .fixedSize(horizontal: false, vertical: true)
        .onChange(of: minutes) { _ in cleared = false }
    }
}
