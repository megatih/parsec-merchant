// SPDX-License-Identifier: GPL-2.0-or-later
import AppKit

/// The Dock tile (UI-ENC-010/011): a thin transit progress bar over the app icon, the "!" badge and attention requests.
/// The fractions and badge text come from the pure `DockTileProgress` and `DockAttention`.
struct AppDock: SessionDock {
    func setProgress(_ fraction: Double?) {
        let tile = NSApp.dockTile
        if let fraction {
            let view = (tile.contentView as? DockProgressView) ?? DockProgressView()
            view.fraction = fraction
            tile.contentView = view
        } else {
            tile.contentView = nil
        }
        tile.display()
    }

    func setBadge(_ label: String?) {
        NSApp.dockTile.badgeLabel = label
    }

    func requestAttention() {
        NSApp.requestUserAttention(.informationalRequest)
    }
}

/// The app icon with a progress bar along its bottom edge.
private final class DockProgressView: NSView {
    var fraction = 0.0 {
        didSet { needsDisplay = true }
    }

    init() {
        super.init(frame: NSRect(x: 0, y: 0, width: 128, height: 128))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override func draw(_ dirtyRect: NSRect) {
        NSApp.applicationIconImage?.draw(in: bounds)
        let track = NSRect(x: bounds.width * 0.1, y: bounds.height * 0.08, width: bounds.width * 0.8, height: bounds.height * 0.07)
        NSColor.black.withAlphaComponent(0.55).setFill()
        NSBezierPath(roundedRect: track, xRadius: track.height / 2, yRadius: track.height / 2).fill()
        var bar = track.insetBy(dx: 2, dy: 2)
        bar.size.width *= min(1, max(0, fraction))
        NSColor.controlAccentColor.setFill()
        NSBezierPath(roundedRect: bar, xRadius: bar.height / 2, yRadius: bar.height / 2).fill()
    }
}
