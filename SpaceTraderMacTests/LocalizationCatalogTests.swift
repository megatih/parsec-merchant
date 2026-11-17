// SPDX-License-Identifier: GPL-2.0-or-later
import Foundation
import ParsecEngine
import ParsecInsights
import Testing
@testable import ParsecMerchant

/// A11Y §9: the committed string catalogs (`SpaceTraderMac/Resources/*.xcstrings`, found from this file's path) and the
/// localization check script. `scripts/l10n-check.sh` also syncs against the build's .stringsdata; these tests repeat
/// its content checks (A11Y-033 steps 3 and 4) so app tests catch them without the script.
@MainActor
@Suite("Localization catalog (A11Y §9)")
struct LocalizationCatalogTests {
    static let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    static let resources = repo.appendingPathComponent("SpaceTraderMac/Resources")

    struct Catalog {
        var sourceLanguage: String
        var strings: [String: [String: Any]]
    }

    static func catalog(_ name: String) throws -> Catalog {
        let data = try Data(contentsOf: resources.appendingPathComponent("\(name).xcstrings"))
        let json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        return Catalog(sourceLanguage: json["sourceLanguage"] as? String ?? "",
                       strings: json["strings"] as? [String: [String: Any]] ?? [:])
    }

    /// `scripts/l10n-allowlist.txt`: a JSON string literal (the key), then a reason.
    static func allowlist() throws -> [String: String] {
        let text = try String(contentsOf: repo.appendingPathComponent("scripts/l10n-allowlist.txt"), encoding: .utf8)
        var out: [String: String] = [:]
        for raw in text.components(separatedBy: "\n") {
            let line = raw.trimmingCharacters(in: .whitespaces)
            guard line.hasPrefix("\"") else { continue }
            // The closing quote is the first unescaped quote after the opening one.
            var escaped = false, end: String.Index?
            for i in line.indices.dropFirst() {
                if escaped { escaped = false } else if line[i] == "\\" { escaped = true } else if line[i] == "\"" { end = i; break }
            }
            guard let end else { continue }
            let literal = String(line[...end])
            let key = try #require(try JSONSerialization.jsonObject(with: Data(literal.utf8), options: .fragmentsAllowed) as? String)
            out[key] = String(line[line.index(after: end)...]).trimmingCharacters(in: .whitespaces)
        }
        return out
    }

    /// Every stringUnit / stringSet below a node, with its path.
    static func units(_ node: Any, path: String = "") -> [(path: String, unit: [String: Any])] {
        guard let dict = node as? [String: Any] else { return [] }
        return dict.sorted { $0.key < $1.key }.flatMap { key, value -> [(path: String, unit: [String: Any])] in
            if key == "stringUnit" || key == "stringSet", let unit = value as? [String: Any] { return [(path + key, unit)] }
            return units(value, path: path + key + "/")
        }
    }

    static func hasPlural(_ node: Any) -> Bool {
        guard let dict = node as? [String: Any] else { return false }
        return dict["plural"] != nil || dict.values.contains { hasPlural($0) }
    }

    static func sourceUnit(_ entry: [String: Any], _ language: String = "en") -> Any {
        (entry["localizations"] as? [String: Any])?[language] ?? [String: Any]()
    }

    /// A key is fine when it has no source-language units (the value is the key) or all of them are translated.
    static func allTranslated(_ entry: [String: Any]) -> Bool {
        units(sourceUnit(entry)).allSatisfy { $0.unit["state"] as? String == "translated" }
    }

    // MARK: A11Y-032

    @Test("A11Y-032 the populated catalog has the source language en and the keys the app's fixture texts use")
    func populated() throws {
        let c = try Self.catalog("Localizable")
        #expect(c.sourceLanguage == "en")
        #expect(c.strings.count > 1_500, "the catalog is populated from the build (\(c.strings.count) keys)")
        for id in MenuItemID.allCases {
            let key = MenuCatalog.entry(for: id).titleKey.key
            #expect(c.strings[key] != nil, "menu title \(id): \(key)")
        }
        for s in Section.allCases { #expect(c.strings[s.title.key] != nil, "section \(s)") }
        #expect(c.strings[ReasonText.text(for: .insufficientFunds).key] != nil)
        #expect(c.strings["Not enough cash."] != nil)
    }

    // MARK: A11Y-033 (checks 3 and 4)

    @Test("A11Y-033 no stale entry, no new or needs_review unit, no empty or padded key, every count key has a plural or a reason")
    func content() throws {
        let allow = try Self.allowlist()
        #expect(allow.values.allSatisfy { !$0.isEmpty }, "every allowlisted key has a reason")
        let countSpec = /%(\d+\$)?(lld|ld|d)/
        for name in ["Localizable", "AppShortcuts"] {
            let c = try Self.catalog(name)
            #expect(c.sourceLanguage == "en")
            for (key, entry) in c.strings {
                #expect(entry["extractionState"] as? String != "stale", "\(name): \(key) is stale")
                for (path, unit) in Self.units(entry["localizations"] ?? [:]) {
                    let state = unit["state"] as? String
                    #expect(state != "new" && state != "needs_review", "\(name): \(key) \(path) is \(state ?? "?")")
                }
                #expect(!key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, "\(name): empty key")
                if key != key.trimmingCharacters(in: .whitespacesAndNewlines) {
                    #expect(allow[key] != nil, "\(name): \(key.debugDescription) has leading or trailing whitespace")
                }
                if name == "Localizable", key.contains(countSpec), allow[key] == nil {
                    #expect(Self.hasPlural(Self.sourceUnit(entry)), "\(key.debugDescription) has no plural variation")
                }
            }
        }
        let all = try Self.catalog("Localizable").strings.merging(try Self.catalog("AppShortcuts").strings) { a, _ in a }
        for key in allow.keys { #expect(all[key] != nil, "allowlisted \(key.debugDescription) is not a catalog key") }
    }

    @Test("A11Y-033 A11Y-034 A11Y-035 l10n-check.sh: pass/fail line, --fix, --export, wired into verify step 4 from M12")
    func scriptAndGate() throws {
        let script = try String(contentsOf: Self.repo.appendingPathComponent("scripts/l10n-check.sh"), encoding: .utf8)
        for needle in ["L10N CHECK PASS", "L10N CHECK FAIL", "xcstringstool\", \"sync", "--fix", "--export",
                       "-exportLocalizations", "-exportLanguage en", "en.xcloc", "ExtractedAppShortcutsMetadata",
                       "l10n-allowlist.txt", "catalog out of date: run scripts/l10n-check.sh --fix and review"] {
            #expect(script.contains(needle), "l10n-check.sh: \(needle)")
        }
        let verify = try String(contentsOf: Self.repo.appendingPathComponent("scripts/verify.sh"), encoding: .utf8)
        #expect(verify.contains("scripts/l10n-check.sh"))
        #expect(verify.contains("-ge 12"), "the check is gated on the milestone from lib-milestone.sh")
        // final-check.sh runs `verify.sh --ui`, which runs the check with --export.
        #expect(verify.contains("scripts/l10n-check.sh --export"))
        let final = try String(contentsOf: Self.repo.appendingPathComponent("scripts/final-check.sh"), encoding: .utf8)
        #expect(final.contains("scripts/verify.sh --ui"))
    }

    // MARK: A11Y-037

    @Test("A11Y-037 count strings have one/other plural variations and render 1 encounter / 2 encounters")
    func plurals() throws {
        let c = try Self.catalog("Localizable")
        for key in ["%lld encounters on the way.", "%lld days left", "%lld units", "%lld mercenaries for hire",
                    "We limped into %@ after %lld encounters on the way."] {
            let entry = try #require(c.strings[key], "\(key)")
            let json = String(bytes: try JSONSerialization.data(withJSONObject: Self.sourceUnit(entry)), encoding: .utf8) ?? ""
            #expect(Self.hasPlural(Self.sourceUnit(entry)) && json.contains("\"one\"") && json.contains("\"other\""), "\(key)")
        }
        let state = GameState(config: NewGameConfig(commanderName: "Text", seed: 1))
        func arrival(_ n: Int) -> String {
            let trip = TripArrival(system: 3, from: 0, viaWormhole: false, firstVisit: false, uneventful: false, encounterCount: n)
            return String(localized: LogEntryText.resource(for: .arrived(trip), state: state))
        }
        #expect(arrival(1).hasSuffix(" 1 encounter on the way."), "\(arrival(1))")
        #expect(arrival(2).hasSuffix(" 2 encounters on the way."), "\(arrival(2))")
        var a = FlavorCatalogText.Args()
        a.system = "Sol"
        a.count = 1
        #expect(FlavorCatalogText.resolve("flavor.arrival.eventful.1", a) == "We limped into Sol after 1 encounter on the way.")
        a.count = 2
        #expect(FlavorCatalogText.resolve("flavor.arrival.eventful.1", a) == "We limped into Sol after 2 encounters on the way.")
    }

    // MARK: A11Y-038 / LLM-030

    @Test("A11Y-038 LLM-030 every template flavor key resolves to a translated sentence key of the catalog")
    func flavorTemplates() throws {
        let c = try Self.catalog("Localizable")
        var a = FlavorCatalogText.Args()
        a.system = "Sol"
        a.ship = "Gnat"
        a.count = 3
        #expect(TemplateFlavorProvider.catalog.count >= 84)
        for entry in TemplateFlavorProvider.catalog {
            #expect(entry.key.hasPrefix("flavor."))
            let resource = try #require(FlavorCatalogText.resource(entry.key, a), "\(entry.key)")
            #expect(FlavorCatalogText.resolve(entry.key, a)?.isEmpty == false, "\(entry.key)")
            let catalogEntry = try #require(c.strings[resource.key], "\(entry.key): \(resource.key) is not a catalog key")
            #expect(Self.allTranslated(catalogEntry), "\(entry.key)")
            #expect(!resource.key.hasPrefix("flavor."), "\(entry.key) is a sentence key, not the flavor id")
        }
        #expect(FlavorCatalogText.resource("flavor.unknown.1", a) == nil)
    }

    // MARK: A11Y-039

    @Test("A11Y-039 App Intents titles, descriptions, dialogs and App Shortcuts phrases are catalog keys")
    func appIntents() throws {
        let c = try Self.catalog("Localizable")
        for key in [ContinueGameIntent.title.key, ShowCommanderStatusIntent.title.key,
                    "Opens Parsec Merchant and continues your latest game.",
                    "Tells you your commander's day, location, cash, debt and worth.",
                    "No saved game yet.", "There's no game to continue.",
                    "Commander %@, day %lld, at %@. %@ credits, debt %@, worth %@.", "Continue Game", "Commander Status"] {
            let entry = try #require(c.strings[key], "\(key)")
            #expect(Self.allTranslated(entry), "\(key)")
        }
        let shortcuts = try Self.catalog("AppShortcuts")
        for phrase in ["Continue my ${applicationName} game", "Show my ${applicationName} commander status"] {
            let entry = try #require(shortcuts.strings[phrase], "\(phrase)")
            #expect(Self.allTranslated(entry), "\(phrase)")
        }
    }

    // MARK: A11Y-041 fixture data names

    @Test("A11Y-041 the UI tests' data names equal the engine's system and crew names and the Quick Start commander")
    func fixtureDataNames() throws {
        let text = try String(contentsOf: Self.repo.appendingPathComponent("SpaceTraderMacUITests/UITestFixtures+Names.swift"),
                              encoding: .utf8)
        let literals = Set(text.matches(of: /"((?:[^"\\]|\\.)*)"/).map { String($0.output.1) })
        for name in GameNames.systems + GameNames.crew { #expect(literals.contains(name), "\(name)") }
        #expect(literals.contains(GameSession.defaultCommanderName))
        for person in AboutContent.credits.flatMap(\.people) { #expect(literals.contains(person), "\(person)") }
    }
}
