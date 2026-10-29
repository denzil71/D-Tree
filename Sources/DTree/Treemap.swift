import AppKit
import SwiftUI

/// One rectangle of the heat map: a subdirectory, or the leftover smaller ones (`node == nil`).
struct TreemapTile {
    let node: DirNode?
    let label: String
    let size: Int64
    let rect: CGRect
    /// 0 for the smallest tiles, 1 for the largest.
    let heat: Double
}

enum Treemap {
    /// Beyond this many subdirectories, the rest are merged into one "smaller folders" tile.
    static let maxTiles = 300

    /// Squarified layout (Bruls, Huizing & van Wijk) of `node`'s subdirectories, largest first.
    static func tiles(for node: DirNode, in bounds: CGRect) -> [TreemapTile] {
        guard bounds.width > 1, bounds.height > 1 else { return [] }
        let folders = node.children.filter { $0.size > 0 }
        var items: [(node: DirNode?, label: String, size: Int64)] =
            folders.prefix(maxTiles).map { ($0, $0.name, $0.size) }
        let rest = folders.dropFirst(maxTiles)
        if !rest.isEmpty {
            items.append((nil, "\(rest.count.formatted()) smaller folders", rest.reduce(0) { $0 + $1.size }))
        }
        let total = items.reduce(0.0) { $0 + Double($1.size) }
        guard total > 0 else { return [] }
        let scale = Double(bounds.width * bounds.height) / total
        let rects = squarify(items.map { Double($0.size) * scale }, in: bounds)
        let largest = Double(folders.first?.size ?? 1)
        return zip(items, rects).map { item, rect in
            TreemapTile(node: item.node, label: item.label, size: item.size, rect: rect,
                        heat: heat(Double(item.size), largest: largest))
        }
    }

    /// Logarithmic, so mid-sized folders don't all look the same as the smallest.
    static func heat(_ size: Double, largest: Double) -> Double {
        guard largest > 0 else { return 0 }
        return min(max(log1p(99 * size / largest) / log(100), 0), 1)
    }

    /// `areas` must be sorted largest first and add up to the area of `bounds`.
    static func squarify(_ areas: [Double], in bounds: CGRect) -> [CGRect] {
        var rects: [CGRect] = []
        rects.reserveCapacity(areas.count)
        var free = bounds
        var start = 0
        while start < areas.count {
            let side = Double(min(free.width, free.height))
            guard side > 0 else { break }
            // Grow the row while that keeps its worst aspect ratio from getting worse.
            var end = start + 1
            var sum = areas[start], low = areas[start], high = areas[start]
            var worst = ratio(sum: sum, low: low, high: high, side: side)
            while end < areas.count {
                let a = areas[end]
                let next = ratio(sum: sum + a, low: min(low, a), high: max(high, a), side: side)
                if next > worst { break }
                sum += a
                low = min(low, a)
                high = max(high, a)
                worst = next
                end += 1
            }
            let thickness = CGFloat(sum / side)
            if free.width >= free.height {
                // A column down the left edge.
                var y = free.minY
                for a in areas[start..<end] {
                    let h = CGFloat(a) / thickness
                    rects.append(CGRect(x: free.minX, y: y, width: thickness, height: h))
                    y += h
                }
                free = CGRect(x: free.minX + thickness, y: free.minY,
                              width: max(free.width - thickness, 0), height: free.height)
            } else {
                // A row along the top edge.
                var x = free.minX
                for a in areas[start..<end] {
                    let w = CGFloat(a) / thickness
                    rects.append(CGRect(x: x, y: free.minY, width: w, height: thickness))
                    x += w
                }
                free = CGRect(x: free.minX, y: free.minY + thickness,
                              width: free.width, height: max(free.height - thickness, 0))
            }
            start = end
        }
        return rects
    }

    private static func ratio(sum: Double, low: Double, high: Double, side: Double) -> Double {
        let s2 = sum * sum, w2 = side * side
        return max(w2 * high / s2, s2 / (w2 * max(low, .leastNonzeroMagnitude)))
    }

    /// Cool blue for small through to hot red for large.
    static func color(heat: Double) -> NSColor {
        NSColor(hue: 0.62 * (1 - heat), saturation: 0.72, brightness: 0.82, alpha: 1)
    }

    /// Black on light tiles (yellows and greens), white on the rest.
    static func textColor(on color: NSColor) -> Color {
        guard let c = color.usingColorSpace(.sRGB) else { return .white }
        let luminance = 0.2126 * c.redComponent + 0.7152 * c.greenComponent + 0.0722 * c.blueComponent
        return luminance > 0.6 ? .black : .white
    }
}

/// The right-hand pane: `node`'s subdirectories as a heat map. Clicking a tile opens that folder.
struct TreemapView: View {
    let node: DirNode
    let open: (DirNode) -> Void
    @State private var hovered: CGPoint?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text(node.displayName).font(.headline).lineLimit(1).truncationMode(.middle)
                Spacer()
                Text(ScanModel.format(node.size)).font(.headline).monospacedDigit()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            Divider()
            GeometryReader { geo in
                let tiles = Treemap.tiles(for: node, in: CGRect(origin: .zero, size: geo.size).insetBy(dx: 6, dy: 6))
                let hoveredTile = hovered.flatMap { point in tiles.first { $0.rect.contains(point) } }
                if tiles.isEmpty {
                    Text(node.unreadable ? "D-Tree couldn't read this folder." : "No folders inside.")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    Canvas { context, _ in
                        for tile in tiles { draw(tile, highlighted: tile.rect == hoveredTile?.rect, in: &context) }
                    }
                    .contentShape(Rectangle())
                    .gesture(SpatialTapGesture().onEnded { value in
                        if let target = tiles.first(where: { $0.rect.contains(value.location) })?.node { open(target) }
                    })
                    .onContinuousHover { phase in
                        if case .active(let point) = phase { hovered = point } else { hovered = nil }
                    }
                    .overlay(alignment: .bottomLeading) {
                        if let tile = hoveredTile { HoverLabel(tile: tile, total: node.size) }
                    }
                }
            }
            Divider()
            legend
        }
        .onChange(of: node) { _ in hovered = nil }
    }

    private func draw(_ tile: TreemapTile, highlighted: Bool, in context: inout GraphicsContext) {
        let rect = tile.rect.insetBy(dx: 1, dy: 1)
        guard rect.width > 0, rect.height > 0 else { return }
        let fill = tile.node == nil ? NSColor.systemGray : Treemap.color(heat: tile.heat)
        let shape = Path(roundedRect: rect, cornerRadius: min(4, rect.width / 4, rect.height / 4))
        context.fill(shape, with: .color(Color(nsColor: fill)))
        if highlighted { context.stroke(shape, with: .color(.white), lineWidth: 2) }
        guard rect.width > 44, rect.height > 30 else { return }
        let ink = Treemap.textColor(on: fill)
        context.drawLayer { layer in
            layer.clip(to: Path(rect))
            let inner = rect.insetBy(dx: 5, dy: 4)
            let name = layer.resolve(Text(tile.label).font(.system(size: 11, weight: .semibold)).foregroundColor(ink))
            layer.draw(name, in: CGRect(x: inner.minX, y: inner.minY, width: inner.width, height: 14))
            let size = layer.resolve(Text(ScanModel.format(tile.size)).font(.system(size: 10)).foregroundColor(ink.opacity(0.85)))
            layer.draw(size, in: CGRect(x: inner.minX, y: inner.minY + 15, width: inner.width, height: 13))
        }
    }

    private var legend: some View {
        HStack(spacing: 6) {
            Text("Smaller")
            LinearGradient(
                colors: stride(from: 0.0, through: 1.0, by: 0.25).map { Color(nsColor: Treemap.color(heat: $0)) },
                startPoint: .leading, endPoint: .trailing)
                .frame(width: 90, height: 6)
                .clipShape(Capsule())
            Text("Larger")
            Spacer()
            Text("Click a folder to look inside it")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }
}

private struct HoverLabel: View {
    let tile: TreemapTile
    let total: Int64

    var body: some View {
        HStack(spacing: 6) {
            Text(tile.label).fontWeight(.semibold).lineLimit(1).truncationMode(.middle)
            Text(ScanModel.format(tile.size)).monospacedDigit()
            Text(BrowserView.percent(tile.size, of: total)).monospacedDigit().foregroundStyle(.secondary)
        }
        .font(.caption)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6))
        .padding(10)
        .allowsHitTesting(false)
    }
}
