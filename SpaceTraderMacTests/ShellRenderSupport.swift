// SPDX-License-Identifier: GPL-2.0-or-later
import AppKit
import ParsecEngine
import SwiftUI
import Testing
@testable import ParsecMerchant

/// Renders app views offscreen in a real hosting view (release 2.0 layout tests and QA pictures).
@MainActor
enum ShellRender {
    /// The view laid out at `size` in an offscreen window.
    static func host<V: View>(_ view: V, session: GameSession, size: CGSize) -> NSHostingView<AnyView> {
        let root = AnyView(view.environment(session).environment(HelpRouter()).frame(width: size.width, height: size.height))
        let hosting = NSHostingView(rootView: root)
        hosting.frame = CGRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: CGRect(origin: .zero, size: size), styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = hosting
        hosting.layoutSubtreeIfNeeded()
        // Let SwiftUI settle preferences and geometry readers.
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        hosting.layoutSubtreeIfNeeded()
        return hosting
    }

    static func png(_ hosting: NSView) -> Data? {
        guard let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else { return nil }
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        return rep.representation(using: .png, properties: [:])
    }

    /// Writes a QA picture into the test host's temporary folder and returns its path.
    @discardableResult
    static func save(_ hosting: NSView, name: String) -> String {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("pm-qa", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("\(name).png")
        try? png(hosting)?.write(to: url)
        return url.path
    }

    /// Every view below `view`, depth first.
    static func descendants(of view: NSView) -> [NSView] {
        view.subviews.flatMap { [$0] + descendants(of: $0) }
    }

    /// One probed element (see `LayoutProbe`).
    struct Element {
        var identifier: String
        /// In the rendered view's coordinates (origin top left).
        var frame: CGRect
        var enabled: Bool
    }

    final class Box {
        var records: [String: LayoutProbeRecord] = [:]
    }

    /// Lays `view` out at `size` with probing on and returns the hosting view and every probed element.
    static func probe<V: View>(_ view: V, session: GameSession, size: CGSize) -> (NSView, [String: Element]) {
        let box = Box()
        let hosting = host(view.layoutProbeRoot { box.records = $0 }, session: session, size: size)
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        return (hosting, box.records.reduce(into: [:]) { $0[$1.key] = Element(identifier: $1.key, frame: $1.value.frame, enabled: $1.value.enabled) })
    }
}
