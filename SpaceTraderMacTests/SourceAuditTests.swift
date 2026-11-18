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

    @Test("UI-KEYS-035 a disabled view control shows its reason in a help tag unless the reason is on screen")
    func disabledControlsExplainThemselves() throws {
        // Files whose disabled controls explain themselves in visible text, with the reason for the exemption.
        let inlineReason: [String: String] = [
            "Views/Settings/SoundSettingsView.swift": "the Status row says why sound is off for this launch",
            "Views/Settings/IntelligenceSettingsView.swift": "the status line under the toggle gives the availability",
            "Views/Shell/SidebarView.swift": "the sidebar shows the In transit / In encounter label",
            "Views/NewGame/NewGameWizard.swift": "skill steppers stop at a visible bound; the step names the failing field",
            "Views/Designer/DesignerView.swift": "steppers stop at a visible bound",
            "Views/Encounter/EncounterMenuItems.swift": "a menu item: macOS menus show no help tags",
        ]
        let lines = try Self.lines()
        var checked = 0
        for (i, l) in lines.enumerated() where l.file.hasPrefix("Views/") && l.code.contains(".disabled(") {
            guard inlineReason[l.file] == nil else { continue }
            checked += 1
            // The help tag sits in the same modifier chain or on an enclosing stack, which closes a few lines later.
            let window = lines[max(0, i - 8)...min(lines.count - 1, i + 20)].filter { $0.file == l.file }
            #expect(window.contains { $0.code.contains(".help(") }, "\(l.file):\(l.number) is disabled without a help tag")
        }
        #expect(checked > 10, "the audit finds the disabled controls")
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

    /// The literal parts of a string literal that starts at `start` (interpolations `\(…)` removed), or nil.
    static func literalText(_ code: String, from start: String.Index) -> String? {
        guard code[start...].hasPrefix("\"") else { return nil }
        var out = "", i = code.index(after: start), depth = 0, escaped = false
        while i < code.endIndex {
            let ch = code[i]
            if depth > 0 {
                if ch == "(" { depth += 1 } else if ch == ")" { depth -= 1 }
            } else if escaped {
                escaped = false
                if ch == "(" { depth = 1 } else { out.append(ch) }
            } else if ch == "\\" {
                escaped = true
            } else if ch == "\"" {
                return out
            } else {
                out.append(ch)
            }
            i = code.index(after: i)
        }
        return nil
    }

    @Test("A11Y-036 localizable code: verbatim text is data only, no concatenated literals, no fragment or empty keys")
    func localizableCode() throws {
        let lines = try Self.lines()
        let allowText = try String(contentsOf: SourceAuditTests.appRoot.deletingLastPathComponent()
            .appendingPathComponent("scripts/l10n-allowlist.txt"), encoding: .utf8)
        let fragments = [" (loss %@ cr.)", " (profit %@ cr.)", " · Ended", " · Ironman", " · “%@”"]
        for l in lines {
            var search = l.code.startIndex
            while let r = l.code.range(of: "Text(verbatim:", range: search..<l.code.endIndex) {
                search = r.upperBound
                let start = l.code[r.upperBound...].firstIndex { $0 != " " } ?? l.code.endIndex
                if let literal = Self.literalText(l.code, from: start) {
                    #expect(!literal.contains { $0.isLetter }, "\(l.file):\(l.number) Text(verbatim:) with words: \(literal)")
                }
            }
            #expect(l.code.firstMatch(of: /(Text\(|String\(localized:)\s*"[^"]*"\s*\+/) == nil,
                    "\(l.file):\(l.number) concatenates a literal inside Text( or String(localized:")
            #expect(l.code.firstMatch(of: /(Text\(|String\(localized:)[^)]*\+\s*"/) == nil,
                    "\(l.file):\(l.number) concatenates a literal inside Text( or String(localized:")
        }
        // The fragment keys of the 2026-11-17 trial sync and the empty key are gone from the source and the catalog.
        let catalog = try String(contentsOf: SourceAuditTests.appRoot.appendingPathComponent("Resources/Localizable.xcstrings"),
                                 encoding: .utf8)
        for f in fragments where !allowText.contains(f) {
            if !f.contains("%@") {
                #expect(!lines.contains { $0.code.contains("\"" + f + "\"") }, "fragment \(f) is still in the source")
            }
            #expect(!catalog.contains("\n    \"" + f + "\" : {"), "fragment key \(f) is still in the catalog")
        }
        #expect(!catalog.contains("\n    \"\" : {"), "the empty key is in the catalog")
    }
}
