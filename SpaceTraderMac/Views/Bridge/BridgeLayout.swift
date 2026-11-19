// SPDX-License-Identifier: GPL-2.0-or-later
import CoreGraphics

/// The frames of the Bridge's four regions for a game area (PRD §4.2, "Size budget"). Pure, so the layout tests can
/// check it without a view. All measures are design points times the interface scale.
nonisolated struct BridgeLayout: Equatable, Sendable {
    var system: CGRect
    var cargo: CGRect
    var chart: CGRect
    var target: CGRect
    /// The height of one cargo row.
    var rowHeight: CGFloat

    static let margin: CGFloat = 8
    static let gap: CGFloat = 8
    /// The design size of the game area: the minimum window less the dock bar (44) and the status bar (36).
    static let designArea = CGSize(width: 1200, height: 600)
    static let leftWidth: CGFloat = 776
    static let rightWidth: CGFloat = 400
    static let systemHeight: CGFloat = 148
    static let cargoHeight: CGFloat = 428
    static let targetHeight: CGFloat = 296
    static let rowMinimum: CGFloat = 36
    static let rowMaximum: CGFloat = 44
    /// What the Cargo panel needs besides its ten rows: padding 8, the two summary lines 40 and the header row 20.
    static let cargoChrome: CGFloat = 68
    /// Of the width above the minimum, the share the right column takes.
    static let rightShare: CGFloat = 0.6

    static func make(size: CGSize, scale s: CGFloat) -> BridgeLayout {
        let margin = Self.margin * s, gap = Self.gap * s
        let extraWidth = max(0, size.width - designArea.width * s)
        let right = (rightWidth * s + extraWidth * rightShare).rounded(.down)
        let left = max(0, size.width - 2 * margin - gap - right)
        let height = max(0, size.height - 2 * margin)
        // Left column: the rows grow to their maximum first; the rest goes to System Information.
        let extraHeight = max(0, size.height - designArea.height * s)
        let row = min(rowMaximum * s, rowMinimum * s + extraHeight / 10)
        let cargoHeight = (cargoChrome * s + row * 10).rounded(.down)
        let systemHeight = max(0, height - gap - cargoHeight)
        // Right column: the Target panel keeps its height; the chart takes the rest.
        let targetHeight = Self.targetHeight * s
        let chartHeight = max(0, height - gap - targetHeight)
        let x2 = margin + left + gap
        return BridgeLayout(system: CGRect(x: margin, y: margin, width: left, height: systemHeight),
                            cargo: CGRect(x: margin, y: margin + systemHeight + gap, width: left, height: cargoHeight),
                            chart: CGRect(x: x2, y: margin, width: right, height: chartHeight),
                            target: CGRect(x: x2, y: margin + chartHeight + gap, width: right, height: targetHeight),
                            rowHeight: (cargoHeight - cargoChrome * s) / 10)
    }
}
