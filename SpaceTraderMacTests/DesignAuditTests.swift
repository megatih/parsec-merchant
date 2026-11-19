// SPDX-License-Identifier: GPL-2.0-or-later
import Foundation
import ParsecEngine
import SwiftUI
import Testing
@testable import ParsecMerchant

/// The source audits of release 2.0 (docs/PRD-UI-Revamp.md §3, UI-DS-021…026, UI-PG-070, UI-HIG-002…006): the game area
/// is built from the design tokens and components only.
@MainActor
@Suite("Design audits (UI-DS, UI-HIG)")
struct DesignAuditTests {
    struct Source {
        var name: String
        var text: String
        var lines: [String] { text.components(separatedBy: "\n") }
    }

    static let appRoot = PageLayoutTests.appRoot

    /// The Swift files under `folders` of the app target, named relative to the target's root.
    static func sources(_ folders: [String]) throws -> [Source] {
        var out: [Source] = []
        for folder in folders {
            let root = appRoot.appendingPathComponent(folder)
            let files = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)
            while let file = files?.nextObject() as? URL {
                guard file.pathExtension == "swift" else { continue }
                let name = folder + "/" + file.path.dropFirst(root.path.count + 1)
                out.append(Source(name: name, text: try String(contentsOf: file, encoding: .utf8)))
            }
        }
        return out.sorted { $0.name < $1.name }
    }

    /// Every line of `sources` that matches `pattern`, as "file:line: text".
    static func hits(_ pattern: Regex<Substring>, in sources: [Source]) -> [String] {
        sources.flatMap { source in
            source.lines.enumerated().compactMap { index, line in
                // A comment may name what the code no longer uses.
                let code = line.components(separatedBy: "//").first ?? line
                return code.contains(pattern) ? "\(source.name):\(index + 1): \(line.trimmingCharacters(in: .whitespaces))" : nil
            }
        }
    }

    @Test("UI-DS-021 no colour, font-size or corner-radius literals in the views and the map")
    func noLiterals() throws {
        let sources = try Self.sources(["Views", "Map"]).filter { $0.name != "Map/MapStyle.swift" }
        #expect(sources.count > 60)
        let colours = try Regex<Substring>(#"Color\(red:|Color\(\.s|Color\.(?:red|green|blue|orange|yellow|purple|pink)\b"#)
        let styles = try Regex<Substring>(#"\.foregroundStyle\(\.(?:red|green|orange|yellow|blue)\)"#)
        let fonts = try Regex<Substring>(#"\.font\(\.system\(size:"#)
        let radii = try Regex<Substring>(#"cornerRadius: *[0-9]"#)
        for (what, pattern) in [("colour literal", colours), ("colour style", styles), ("font size", fonts), ("corner radius", radii)] {
            let found = Self.hits(pattern, in: sources)
            #expect(found.isEmpty, "\(what): \(found.joined(separator: "\n"))")
        }
    }

    @Test("UI-DS-022 padding uses PMSpace: no numeric padding in the views")
    func noNumericPadding() throws {
        let found = Self.hits(try Regex<Substring>(#"\.padding\((?:[^)]*, *)?[0-9]"#), in: try Self.sources(["Views"]))
        #expect(found.isEmpty, "\(found.joined(separator: "\n"))")
    }

    @Test("UI-DS-023 no system containers in the game's views: GroupBox, Form, NavigationSplitView, inspector, toolbar")
    func noSystemContainers() throws {
        let exempt = ["Views/Settings/", "Views/About/", "Views/Developer/"]
        let sources = try Self.sources(["Views"]).filter { source in !exempt.contains { source.name.hasPrefix($0) } }
        let pattern = try Regex<Substring>(#"\bGroupBox\b|\bForm *[{(]|NavigationSplitView|\.inspector\(|\.toolbar\b|\.formStyle\("#)
        let found = Self.hits(pattern, in: sources)
        #expect(found.isEmpty, "\(found.joined(separator: "\n"))")
    }

    @Test("UI-PG-070 no view of the game uses a pre-revamp style")
    func noOldStyles() throws {
        // Settings, About, the developer sheet, the High Scores window and the exported career card follow the system look.
        let exempt = ["Views/Settings/", "Views/About/", "Views/Developer/", "Views/HighScores/", "Views/GameOver/CareerCardView.swift"]
        let sources = try Self.sources(["Views", "Map"]).filter { source in !exempt.contains { source.name.hasPrefix($0) } }
        let old = try Regex<Substring>(
            #"\.readableSecondary|\.signal(?:Red|Orange|Green)\b|\.background\(\.background|windowBackgroundColor|\.regularMaterial"#
                + #"|\.glassEffect\(|PointerButtonStyle\(\)"#)
        let found = Self.hits(old, in: sources).filter { !$0.hasPrefix("Views/Welcome/") || !$0.contains("PointerButtonStyle") }
        #expect(found.isEmpty, "\(found.joined(separator: "\n"))")
        // Every sheet is hosted in the console palette.
        let host = try String(contentsOf: Self.appRoot.appendingPathComponent("Views/Presentation/PresentationHost.swift"), encoding: .utf8)
        #expect(host.contains(".pmSheetChrome()"))
    }

    @Test("UI-DS-026 the retired words are gone from the strings")
    func vocabulary() throws {
        let url = Self.appRoot.appendingPathComponent("Resources/Localizable.xcstrings")
        let catalog = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let strings = try #require(catalog["strings"] as? [String: Any])
        #expect(strings.count > 2_000)
        let banned = ["Outfitter", "Inspector", "Untrack", "Fill Up", "Fill Fuel", "Galaxy Chart", "Daily Costs", "Notoriety", "Buy Max", "Take All"]
        for (key, entry) in strings {
            // The English value is the key unless the entry carries its own.
            let data = try JSONSerialization.data(withJSONObject: entry)
            let text = key + " " + (String(data: data, encoding: .utf8) ?? "")
            for word in banned {
                let whole = try Regex<Substring>("\\b\(word)\\b")
                #expect(!text.contains(whole), "\"\(word)\" in \"\(key)\"")
            }
        }
    }

    @Test("UI-DS-032 every interactive component carries an identifier, a label and a help tag")
    func componentsAreIdentified() throws {
        let controls = try String(contentsOf: Self.appRoot.appendingPathComponent("Design/Components/PMControls.swift"), encoding: .utf8)
        // The components take their identifier in the initializer and apply it, with the help tag, themselves.
        for needle in ["let identifier: String", ".probed(identifier)", ".help(disabledReason.map { Text(verbatim: $0) } ?? Text(help ?? title))",
                       ".accessibilityLabel(Text(label))"] {
            #expect(controls.contains(needle), "\(needle)")
        }
        let regex = try Regex(AXID.pattern)
        #expect(AXID.all.count > 900 && AXID.all.allSatisfy { $0.wholeMatch(of: regex) != nil })
        // A plain SwiftUI control in a view names its identifier within the lines that follow it.
        let opener = try Regex<Substring>(#"^\s*(?:Button|Toggle|Picker|TextField|Slider|Stepper)[ ({]"#)
        var missing: [String] = []
        for source in try Self.sources(["Views", "Map"]) {
            let lines = source.lines
            for (index, line) in lines.enumerated() where line.contains(opener) {
                // A context menu's items repeat a visible control that carries the identifier (UI-PTR-005); a row builder's
                // button is identified where the row is used.
                let before = lines[max(0, index - 12)..<index].joined(separator: "\n")
                if before.contains(".contextMenu") || before.contains("private var menu: some View") || before.contains("func choiceRow(") { continue }
                let window = lines[index..<min(lines.count, index + 24)].joined(separator: "\n")
                if !window.contains("accessibilityIdentifier(") && !window.contains(".probed(") && !window.contains("identifier:") {
                    missing.append("\(source.name):\(index + 1): \(line.trimmingCharacters(in: .whitespaces))")
                }
            }
        }
        #expect(missing.isEmpty, "\(missing.joined(separator: "\n"))")
    }

    @Test("UI-HIG-004 help tags: at most 75 characters, no ending punctuation, never the control's own name")
    func helpTags() throws {
        let literal = try Regex<(Substring, Substring)>(#"(?:\bhelp: |\.help\(Text\(|\.help\()"((?:[^"\\]|\\.)*)""#)
        let title = try Regex<(Substring, Substring)>(#"title: "((?:[^"\\]|\\.)*)""#)
        let interpolation = try Regex<Substring>(#"\\\([^)]*\)"#)
        var count = 0
        for source in try Self.sources(["Views", "Map", "Design"]) {
            for (index, line) in source.lines.enumerated() {
                for match in line.matches(of: literal) {
                    count += 1
                    let text = String(match.1).replacing(interpolation, with: "X")
                    let place = "\(source.name):\(index + 1): \(text)"
                    #expect(text.count <= 75, "too long (\(text.count)): \(place)")
                    #expect(!text.hasSuffix(".") && !text.hasSuffix("!") && !text.hasSuffix("?"), "ends with punctuation: \(place)")
                    #expect(text.first?.isUppercase == true || text.isEmpty, "sentence case: \(place)")
                    if let name = line.firstMatch(of: title) { #expect(String(name.1) != String(match.1), "repeats the name: \(place)") }
                }
            }
        }
        #expect(count > 60, "\(count) help tags checked")
        // A disabled control's help tag is the reason (the component's initializer takes it).
        let controls = try String(contentsOf: Self.appRoot.appendingPathComponent("Design/Components/PMControls.swift"), encoding: .utf8)
        #expect(controls.contains("var disabledReason: String?") && controls.contains(".disabled(disabledReason != nil)"))
    }

    @Test("UI-HIG-002 reserved shortcuts are never rebound and no binding uses Control alone; the key audit is clean")
    func reservedShortcuts() {
        let reserved: [MenuShortcut] = [
            MenuShortcut("q"), MenuShortcut("w"), MenuShortcut("w", [.option, .command]), MenuShortcut("h"), MenuShortcut("h", [.option, .command]),
            MenuShortcut("m"), MenuShortcut("m", [.option, .command]), MenuShortcut(","), MenuShortcut("`"), MenuShortcut("f", [.control, .command]),
            MenuShortcut("."), MenuShortcut("p"), MenuShortcut("z"), MenuShortcut("z", [.shift, .command]), MenuShortcut("x"), MenuShortcut("c"),
            MenuShortcut("v"), MenuShortcut("a"), MenuShortcut("g"), MenuShortcut(" "), MenuShortcut("d", [.option, .command]),
            MenuShortcut("3", [.shift, .command]), MenuShortcut("4", [.shift, .command]), MenuShortcut("5", [.shift, .command]),
            MenuShortcut("8", [.option, .command]),
        ]
        // The standard items keep their own keys: New, Open, Save, Save As, Find and Help.
        let standard: [MenuItemID: MenuShortcut] = [.newGame: MenuShortcut("n"), .open: MenuShortcut("o"), .save: MenuShortcut("s"),
                                                    .saveAs: MenuShortcut("s", [.shift, .command]), .find: MenuShortcut("f"), .help: MenuShortcut("?")]
        for (id, shortcut) in standard { #expect(MenuCatalog.entry(for: id).shortcut == shortcut, "\(id)") }
        for id in MenuItemID.allCases {
            guard let shortcut = MenuCatalog.entry(for: id).shortcut else { continue }
            #expect(!reserved.contains(shortcut), "\(id) takes the reserved \(shortcut.display)")
            #expect(shortcut.modifiers != [.control], "\(id) uses Control alone")
        }
        for binding in KeyBindingTable.all { #expect(binding.shortcut.modifiers != [.control], "\(binding.action)") }
        let conflicts = KeyAudit.staticConflicts(KeyBindingTable.all)
        #expect(conflicts.isEmpty, "\(conflicts.map(\.description).joined(separator: "\n"))")
    }

    @Test("UI-HIG-005 VoiceOver: values read with their label and unit; a cargo row has a sentence value, four actions and the Cargo Rows rotor")
    func voiceOver() throws {
        let cargo = try String(contentsOf: Self.appRoot.appendingPathComponent("Views/Bridge/BridgeCargoPanel.swift"), encoding: .utf8)
        for needle in [".accessibilityValue(Text(verbatim: MarketRowAccessibility.make(market, target: row.targetPrice).value))",
                       ".accessibilityAction(named: Text(\"Buy\"))", ".accessibilityAction(named: Text(\"Buy Maximum\"))",
                       ".accessibilityAction(named: Text(\"Sell\"))", ".accessibilityAction(named: Text(\"Sell All\"))",
                       ".accessibilityRotor(Text(\"Cargo Rows\"))", ".accessibilityRotor(Text(\"In Hold\"))",
                       ".accessibilityRotor(Text(\"Profitable at Target\"))"] {
            #expect(cargo.contains(needle), "\(needle)")
        }
        let session = try BridgeFixtures.session(ruleset: .modern, .fullHold)
        let row = try #require(session.bridgeCargo?.row(.water))
        let spoken = MarketRowAccessibility.make(row.market, target: row.targetPrice)
        #expect(spoken.label == "Water" && spoken.value.contains("credits") && spoken.value.contains("held"))
        // A status value is one element: its label, then the value with its unit.
        let stat = try String(contentsOf: Self.appRoot.appendingPathComponent("Design/Components/PMPanel.swift"), encoding: .utf8)
        #expect(stat.contains(".accessibilityLabel(Text(label))") && stat.contains(".accessibilityValue(Text(verbatim: value))"))
        #expect(StatusBarText.credits(12_345) == "12,345 cr.")
    }

    @Test("UI-HIG-006 the system's accessibility settings are respected: no materials, contrast and motion follow the preferences")
    func systemSettings() throws {
        let sources = try Self.sources(["Views", "Map", "Design", "Accessibility"])
        let materials = Self.hits(try Regex<Substring>(#"\.(?:ultraThin|thin|regular|thick|ultraThick)Material\b|\.glassEffect\("#), in: sources)
        #expect(materials.isEmpty, "\(materials.joined(separator: "\n"))")
        #expect(PMColor.border(increaseContrast: true) == PMColor.strongLine && PMColor.label(increaseContrast: true) == PMColor.textPrimary
            && PMColor.borderWidth(increaseContrast: true) == 2)
        #expect(PMMotion.animation(PMMotion.page, reduceMotion: true) == nil && PMMotion.animation(PMMotion.page, reduceMotion: false) != nil)
        let app = try String(contentsOf: Self.appRoot.appendingPathComponent("App/LaunchOptions.swift"), encoding: .utf8)
        #expect(app.contains("PMA11y"), "the launch argument still overrides the system settings for tests")
    }

    @Test("UI-NAV-012 the help pages describe the new screens in the new words")
    func helpPages() throws {
        let folder = Self.appRoot.appendingPathComponent("Resources/Help")
        var all = ""
        for topic in HelpTopic.allCases {
            let page = try String(contentsOf: folder.appendingPathComponent("\(topic.rawValue).md"), encoding: .utf8)
            #expect(page.hasPrefix("# ") && page.count > 60, "\(topic)")
            all += page
        }
        for old in ["Outfitter", "sidebar", "toolbar", "inspector", "Inspector", "Galaxy chart", "Galaxy Chart", "quantity chip", "Fill Fuel",
                    "The Market (", "Compare**"] {
            #expect(!all.contains(old), "\(old)")
        }
        for new in ["dock bar", "status bar", "Cargo", "Short-Range Chart", "Target System", "System Information", "Galactic Chart", "Selected System",
                    "Sell All Cargo", "Fill Tank", "Equipment", "Personnel", "Commander Status", "Price Details", "Fit Range"] {
            #expect(all.contains(new), "\(new)")
        }
        #expect(String(localized: HelpTopic.market.title) == "Cargo and Trading" && String(localized: HelpTopic.crew.title) == "Personnel"
            && String(localized: HelpTopic.outfitter.title) == "Equipment")
    }

    @Test("UI-HIG-001 UI-HIG-003 every button of the game area has a menu item of the same name; Esc and the page keys are in the key table")
    func menuTwins() throws {
        // Game-area commands and their menu items share a name (PRD-UI-Revamp §4.15).
        let twins: [(file: String, title: String, item: MenuItemID)] = [
            ("Views/Bridge/BridgeSystemPanel.swift", "Fill Tank", .fillFuel), ("Views/Bridge/BridgeSystemPanel.swift", "Repair Hull", .repair),
            ("Views/Bridge/BridgeCargoPanel.swift", "Sell All Cargo", .sellAllCargo), ("Views/Bridge/BridgeCargoPanel.swift", "\"Buy\"", .tradeBuy),
            ("Views/Bridge/BridgeCargoPanel.swift", "\"Sell\"", .tradeSell), ("Views/Bridge/BridgeTargetPanel.swift", "Warp", .warp),
        ]
        for twin in twins {
            let source = try String(contentsOf: Self.appRoot.appendingPathComponent(twin.file), encoding: .utf8)
            let name = twin.title.replacingOccurrences(of: "\"", with: "")
            #expect(source.contains(twin.title), "\(twin.file) has \(name)")
            #expect(String(localized: MenuCatalog.entry(for: twin.item).titleKey) == name, "\(twin.item)")
        }
        // Every page has a View item with a key; Esc is routed by the window.
        for page in Section.allCases { #expect(MenuCatalog.entry(for: MenuItemID.item(for: page)).shortcut != nil, "\(page)") }
        #expect(KeyBindingTable.all.contains { $0.shortcut.key == EncounterKeys.escapeKey })
        // The Cargo rows take arrows, B and S; they are focusable by Tab without Full Keyboard Access.
        let cargo = try String(contentsOf: Self.appRoot.appendingPathComponent("Views/Bridge/BridgeCargoPanel.swift"), encoding: .utf8)
        #expect(cargo.contains(".focusable(true, interactions: .edit)") && cargo.contains("case .upArrow, .downArrow:"))
    }

    @Test("A11Y-040 UI-BRG-034 a language that runs long gets smaller type instead of clipped text; English keeps its size")
    func languageFit() {
        #expect(PMFont.languageFit == 1, "the tests run in English")
        #expect(PMFont.fit(english: 100, localized: 100) == 1 && PMFont.fit(english: 100, localized: 115) == 1)
        #expect(abs(PMFont.fit(english: 100, localized: 130) - 100.0 / 130.0) < 0.001)
        #expect(abs(PMFont.fit(english: 100, localized: 210) - 100.0 / 210.0) < 0.001, "double-length pseudo-localization")
        #expect(PMFont.fit(english: 100, localized: 400) == 0.45 && PMFont.fit(english: 0, localized: 10) == 1)
    }
}
