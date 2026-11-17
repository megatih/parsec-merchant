// SPDX-License-Identifier: GPL-2.0-or-later
import Foundation
import Testing

/// UI-KEYS-034: source audits of the app target (`SpaceTraderMac/**/*.swift`, found from this file's path). Comments are
/// ignored; each failure names the file and line.
@Suite("Source audit (UI-KEYS-034)")
struct SourceAuditTests {
    struct Line {
        var file: String
        var number: Int
        var code: String
    }

    static let appRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("SpaceTraderMac")

    /// Every code line of the app target, with `//` comments removed.
    static func lines() throws -> [Line] {
        let enumerator = FileManager.default.enumerator(at: appRoot, includingPropertiesForKeys: nil)
        var out: [Line] = []
        while let url = enumerator?.nextObject() as? URL {
            guard url.pathExtension == "swift" else { continue }
            let relative = String(url.path.dropFirst(appRoot.path.count + 1))
            let text = try String(contentsOf: url, encoding: .utf8)
            for (i, raw) in text.components(separatedBy: "\n").enumerated() {
                let code = raw.range(of: "//").map { String(raw[..<$0.lowerBound]) } ?? raw
                out.append(Line(file: relative, number: i + 1, code: code))
            }
        }
        return out
    }

    @Test("UI-KEYS-034 UI-SHELL-108 custom glass only on the map HUD and the encounter bar; no popovers; no disabled focus rings")
    func audit() throws {
        let lines = try Self.lines()
        #expect(Set(lines.map(\.file)).count > 100, "the app sources are found")
        let glassFiles: Set<String> = ["Map/MapHUDViews.swift", "Map/HeatmapHUDView.swift", "Views/Encounter/EncounterActionBar.swift"]
        for l in lines {
            if l.code.contains(".glassEffect(") {
                #expect(glassFiles.contains(l.file), "\(l.file):\(l.number) uses .glassEffect")
            }
            #expect(!l.code.contains("GlassEffectContainer"), "\(l.file):\(l.number) uses GlassEffectContainer")
            // Spelled in two parts so the SwiftLint `no_popover` rule does not flag this test.
            #expect(!l.code.contains("." + "popover("), "\(l.file):\(l.number) uses a popover")
            #expect(!l.code.contains("." + "popoverTip("), "\(l.file):\(l.number) uses a popover tip")
            #expect(!l.code.contains(".focusEffectDisabled()") && !l.code.contains(".focusEffectDisabled(true)"),
                    "\(l.file):\(l.number) disables the focus ring")
        }
    }

    @Test("UI-KEYS-034 UI-KEYS-020 a destructive button never carries .defaultAction")
    func destructiveNeverDefault() throws {
        let lines = try Self.lines()
        for (i, l) in lines.enumerated() where l.code.contains("role: .destructive") {
            // The rest of this Button declaration: up to the next Button or 8 lines, in the same file.
            for next in lines[(i + 1)...].prefix(8) where next.file == l.file {
                if next.code.contains("Button(") || next.code.contains("Button {") { break }
                #expect(!next.code.contains(".keyboardShortcut(.defaultAction)"), "\(l.file):\(next.number) gives a destructive button Return")
            }
            #expect(!l.code.contains(".keyboardShortcut(.defaultAction)"), "\(l.file):\(l.number)")
        }
    }

    @Test("UI-KEYS-018 UI-KEYS-019 the main window keeps one Esc router and Bridge › Warp has no Return")
    func windowKeys() throws {
        let lines = try Self.lines()
        func code(_ file: String) -> [String] { lines.filter { $0.file == file }.map(\.code) }
        for file in ["Views/Feed/FeedOverlay.swift", "Views/Sections/ShipyardSectionView.swift", "Views/Transit/TransitView.swift",
                     "Views/Encounter/EncounterView.swift"] {
            let c = code(file)
            #expect(!c.contains { $0.contains(".keyboardShortcut(.cancelAction)") || $0.contains(".onExitCommand") }, "\(file)")
        }
        let bridge = code("Views/Sections/BridgeSectionView.swift")
        let warp = try #require(bridge.firstIndex { $0.contains("Button(\"Warp\")") })
        #expect(!bridge[warp...].prefix(5).contains { $0.contains(".defaultAction") })
        #expect(code("Views/Shell/MainShellView.swift").contains { $0.contains("WindowEscapeRouter") })
    }
}
