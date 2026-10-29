import AppKit
import SwiftUI

struct ContentView: View {
    @EnvironmentObject var model: ScanModel

    var body: some View {
        Group {
            if model.scanning != nil {
                ScanProgressView()
            } else if let current = model.current {
                BrowserView(current: current)
            } else {
                StartView()
            }
        }
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button { model.goUp() } label: { Label("Enclosing Folder", systemImage: "chevron.up") }
                    .help("Enclosing folder (⌘↑)")
                    .disabled(!model.canGoUp || model.scanning != nil)
            }
            ToolbarItemGroup(placement: .primaryAction) {
                ScanMenu()
                Button { model.rescan() } label: { Label("Rescan", systemImage: "arrow.clockwise") }
                    .help("Scan the same folder again (⌘R)")
                    .disabled(!model.canRescan)
            }
        }
        .alert("Scan Failed", isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) {
            Button("OK") { model.error = nil }
        } message: {
            Text(model.error ?? "")
        }
    }
}

struct ScanMenu: View {
    @EnvironmentObject var model: ScanModel

    var body: some View {
        Menu {
            Button("\(ScanModel.volumeName(ScanModel.startupDisk)) (whole disk)") { model.scan(ScanModel.startupDisk) }
            Button("Home Folder") { model.scan(ScanModel.home) }
            Divider()
            Button("Choose Folder…") { model.chooseFolder() }
        } label: {
            Label("Scan", systemImage: "externaldrive")
        }
        .help("Choose what to scan")
    }
}

// MARK: Start

struct StartView: View {
    @EnvironmentObject var model: ScanModel

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "list.bullet.indent")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(.secondary)
            Text("See what's using your disk").font(.title2.weight(.semibold))
            Text("D-Tree adds up the size of every folder, then lists them largest first. Expand a folder to see its subfolders, or double-click one to look inside it.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 420)
            HStack(spacing: 10) {
                Button("Scan \(ScanModel.volumeName(ScanModel.startupDisk))") { model.scan(ScanModel.startupDisk) }
                    .keyboardShortcut(.defaultAction)
                Button("Scan Home Folder") { model.scan(ScanModel.home) }
                Button("Choose Folder…") { model.chooseFolder() }
            }
            .controlSize(.large)
            FullDiskAccessNote()
                .frame(maxWidth: 420)
                .padding(.top, 8)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct FullDiskAccessNote: View {
    static let settingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!

    var body: some View {
        VStack(spacing: 6) {
            Text("macOS hides some folders (Mail, Messages, other apps' data) unless D-Tree has Full Disk Access, so totals for your disk or home folder may come out low without it.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Open Full Disk Access Settings…") { NSWorkspace.shared.open(Self.settingsURL) }
                .buttonStyle(.link)
                .font(.caption)
        }
    }
}

// MARK: Progress

struct ScanProgressView: View {
    @EnvironmentObject var model: ScanModel

    var body: some View {
        VStack(spacing: 14) {
            ProgressView()
            Text("Scanning \(model.scanning.map { FileManager.default.displayName(atPath: $0.path) } ?? "")…")
                .font(.headline)
            Text("\(model.progress.directories.formatted()) folders")
                .monospacedDigit()
                .foregroundStyle(.secondary)
            Text(model.progress.path)
                .font(.caption)
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: 480)
            Button("Cancel") { model.cancel() }
                .keyboardShortcut(.cancelAction)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: Browser

struct BrowserView: View {
    @EnvironmentObject var model: ScanModel
    let current: DirNode
    @State private var selection: Set<DirNode> = []
    @State private var expanded: Set<DirNode> = []

    /// The heat map shows the folder selected (or last expanded) in the tree, else the one being viewed.
    private var mapped: DirNode { selection.count == 1 ? selection.first! : current }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            HSplitView {
                tree
                    .frame(minWidth: 340, idealWidth: 480, maxHeight: .infinity)
                TreemapView(node: mapped, open: open)
                    .frame(minWidth: 280, idealWidth: 420, maxHeight: .infinity)
            }
            Divider()
            footer
        }
        .onChange(of: current) { _ in
            selection = []
            expanded = []
        }
    }

    @ViewBuilder private var tree: some View {
        if current.children.isEmpty {
            Text(current.unreadable ? "D-Tree couldn't read this folder." : "No folders inside.")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List(selection: $selection) {
                TreeRows(nodes: current.children, total: current.size, expanded: $expanded) { node in
                    selection = [node]
                }
            }
            .contextMenu(forSelectionType: DirNode.self) { nodes in
                if let node = nodes.first {
                    Button("Show Folders Inside") { open(node) }
                    Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: node.path)]) }
                    Button("Copy Path") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(node.path, forType: .string)
                    }
                }
            } primaryAction: { nodes in
                if let node = nodes.first { open(node) }
            }
        }
    }

    private func open(_ node: DirNode) {
        model.current = node
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            if current.parent != nil { Breadcrumb(current: current) }
            HStack(alignment: .firstTextBaseline) {
                Text(current.displayName).font(.title2.weight(.semibold)).lineLimit(1).truncationMode(.middle)
                Spacer()
                Text(ScanModel.format(current.size)).font(.title2.weight(.semibold)).monospacedDigit()
            }
            if let parent = current.parent, parent.size > 0 {
                Text("\(Self.percent(current.size, of: parent.size)) of \(parent.displayName)")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var footer: some View {
        HStack(spacing: 12) {
            Text("Files directly in this folder: \(ScanModel.format(current.filesSize))")
            if let result = model.result, result.unreadable > 0 {
                Text("\(result.unreadable.formatted()) folders couldn't be read")
                    .help("Grant D-Tree Full Disk Access for complete totals.")
                Button("Full Disk Access…") { NSWorkspace.shared.open(FullDiskAccessNote.settingsURL) }
                    .buttonStyle(.link)
            }
            Spacer()
            if let result = model.result, let date = model.scanDate {
                if model.fromCache {
                    Text("Saved scan from \(date.formatted(.relative(presentation: .named))) · \(result.directories.formatted()) folders")
                        .help("Opened from the cache instead of scanning again. Rescan (⌘R) for up-to-date sizes.")
                } else {
                    Text("\(result.directories.formatted()) folders scanned in \(model.duration.formatted(.number.precision(.fractionLength(1)))) s")
                }
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
    }

    static func percent(_ part: Int64, of whole: Int64) -> String {
        guard whole > 0 else { return "–" }
        let value = Double(part) / Double(whole)
        return value.formatted(.percent.precision(.fractionLength(value < 0.1 ? 1 : 0)))
    }
}

/// Tree rows that can be expanded in place. Expanding one also selects it, so the heat map follows.
struct TreeRows: View {
    let nodes: [DirNode]
    /// Size of the folder being viewed; bars and percentages are shares of it.
    let total: Int64
    @Binding var expanded: Set<DirNode>
    let onExpand: (DirNode) -> Void

    var body: some View {
        ForEach(nodes) { node in
            if node.children.isEmpty {
                DirRow(node: node, total: total).tag(node)
            } else {
                DisclosureGroup(isExpanded: binding(for: node)) {
                    // AnyView breaks the recursive view type.
                    AnyView(TreeRows(nodes: node.children, total: total, expanded: $expanded, onExpand: onExpand))
                } label: {
                    DirRow(node: node, total: total)
                }
                .tag(node)
            }
        }
    }

    private func binding(for node: DirNode) -> Binding<Bool> {
        Binding(
            get: { expanded.contains(node) },
            set: { open in
                if open {
                    expanded.insert(node)
                    onExpand(node)
                } else {
                    expanded.remove(node)
                }
            })
    }
}

/// The scan root down to the current folder; click a step to go back to it.
struct Breadcrumb: View {
    @EnvironmentObject var model: ScanModel
    let current: DirNode

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                let steps = current.lineage
                ForEach(Array(steps.enumerated()), id: \.offset) { index, node in
                    if index > 0 {
                        Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary)
                    }
                    Button(node.displayName) { model.current = node }
                        .buttonStyle(.plain)
                        .font(.callout)
                        .foregroundStyle(node == current ? .primary : .secondary)
                        .disabled(node == current)
                }
            }
        }
    }
}

struct DirRow: View {
    let node: DirNode
    /// Size of the folder being viewed; bars and percentages are shares of it.
    let total: Int64

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: node.unreadable ? "lock.fill" : "folder.fill")
                .foregroundStyle(node.unreadable ? Color.secondary : Color.accentColor)
                .help(node.unreadable ? "D-Tree couldn't read this folder, so its size may be incomplete." : "")
            Text(node.name)
                .lineLimit(1)
                .truncationMode(.middle)
                .layoutPriority(1)
            Spacer(minLength: 12)
            SizeBar(fraction: total > 0 ? Double(node.size) / Double(total) : 0)
                .frame(width: 120, height: 8)
            Text(ScanModel.format(node.size))
                .monospacedDigit()
                .frame(width: 80, alignment: .trailing)
            Text(BrowserView.percent(node.size, of: total))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 52, alignment: .trailing)
        }
        .padding(.vertical, 1)
    }
}

struct SizeBar: View {
    let fraction: Double

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.secondary.opacity(0.15))
                Capsule().fill(Color.accentColor)
                    .frame(width: max(fraction > 0 ? 2 : 0, geo.size.width * min(fraction, 1)))
            }
        }
    }
}
