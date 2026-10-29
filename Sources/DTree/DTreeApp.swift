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
                .frame(minWidth: 640, minHeight: 420)
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
    }
}
