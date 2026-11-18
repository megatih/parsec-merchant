// SPDX-License-Identifier: GPL-2.0-or-later
import SwiftUI

/// A horizontal row that wraps onto further lines when its items do not fit (A11Y-025: button rows wrap at large Text
/// Sizes instead of clipping). Items keep their ideal sizes, up to the row's width; lines are centred unless `leading`.
/// SwiftUI mirrors the placement in a right-to-left layout.
struct WrappingHStack: Layout {
    var spacing: CGFloat = 8
    var lineSpacing: CGFloat = 8
    var leading = false

    struct Line {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    /// The item's ideal size; an item wider than the row gets the row's width (a long text then wraps inside it).
    private func itemSize(_ view: LayoutSubview, width: CGFloat) -> CGSize {
        let ideal = view.sizeThatFits(.unspecified)
        guard ideal.width > width, width.isFinite else { return ideal }
        return view.sizeThatFits(ProposedViewSize(width: width, height: nil))
    }

    func lines(for subviews: Subviews, width: CGFloat) -> [Line] {
        var result: [Line] = []
        var current = Line()
        for (i, view) in subviews.enumerated() {
            let size = itemSize(view, width: width)
            let needed = current.indices.isEmpty ? size.width : current.width + spacing + size.width
            if needed > width, !current.indices.isEmpty {
                result.append(current)
                current = Line()
            }
            current.width = current.indices.isEmpty ? size.width : current.width + spacing + size.width
            current.height = max(current.height, size.height)
            current.indices.append(i)
        }
        if !current.indices.isEmpty { result.append(current) }
        return result
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        let lines = lines(for: subviews, width: width)
        let height = lines.reduce(0) { $0 + $1.height } + lineSpacing * CGFloat(max(0, lines.count - 1))
        let used = lines.map(\.width).max() ?? 0
        return CGSize(width: proposal.width.map { min($0, used) } ?? used, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for line in lines(for: subviews, width: bounds.width) {
            var x = bounds.minX + (leading ? 0 : max(0, (bounds.width - line.width) / 2))
            for i in line.indices {
                let size = itemSize(subviews[i], width: bounds.width)
                subviews[i].place(at: CGPoint(x: x, y: y + (line.height - size.height) / 2), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += line.height + lineSpacing
        }
    }
}
