// SPDX-License-Identifier: GPL-2.0-or-later
import Foundation
import ParsecEngine

// Pure models of the custom ship Designer (UI-SHELL-074…076).

/// A stepper of the Designer, in display order.
nonisolated enum DesignerField: String, CaseIterable, Sendable {
    case weaponSlots, shieldSlots, gadgetSlots, crewQuarters, fuelTanks, cargoBays, hull

    func value(_ d: ShipDesign) -> Int {
        switch self {
        case .weaponSlots: d.weaponSlots
        case .shieldSlots: d.shieldSlots
        case .gadgetSlots: d.gadgetSlots
        case .crewQuarters: d.crewQuarters
        case .fuelTanks: d.fuelTanks
        case .cargoBays: d.cargoBays
        case .hull: d.hull
        }
    }

    func set(_ d: inout ShipDesign, _ v: Int) {
        switch self {
        case .weaponSlots: d.weaponSlots = v
        case .shieldSlots: d.shieldSlots = v
        case .gadgetSlots: d.gadgetSlots = v
        case .crewQuarters: d.crewQuarters = v
        case .fuelTanks: d.fuelTanks = v
        case .cargoBays: d.cargoBays = v
        case .hull: d.hull = v
        }
    }

    /// The stepper increment: one fuel or hull unit of this size at this yard (Form_Shipyard.cs `UpdateAllocation`).
    func step(size: SystemSize, yard: ShipyardID) -> Int {
        let skill = DesignerTables.shipyard(yard).skill
        switch self {
        case .fuelTanks: return DesignerTables.perUnitFuel[size.rawValue]
        case .hull: return DesignerTables.perUnitHull[size.rawValue] + (skill == .hullPerUnit ? 5 : 0)
        case .weaponSlots, .shieldSlots, .gadgetSlots, .crewQuarters, .cargoBays: return 1
        }
    }

    var title: LocalizedStringResource {
        switch self {
        case .weaponSlots: "Weapon slots"
        case .shieldSlots: "Shield slots"
        case .gadgetSlots: "Gadget slots"
        case .crewQuarters: "Crew quarters"
        case .fuelTanks: "Fuel tanks"
        case .cargoBays: "Cargo bays"
        case .hull: "Hull strength"
        }
    }
}

/// The colour band of the "units used" bar: yellow from 80%, orange from 90%, red above 100% (UI-SHELL-074).
nonisolated enum UnitsLevel: Equatable, Sendable {
    case normal, caution, warning, over

    init(percent: Int) {
        if percent > 100 {
            self = .over
        } else if percent >= 90 {
            self = .warning
        } else if percent >= 80 {
            self = .caution
        } else {
            self = .normal
        }
    }
}

/// The Designer's editable state. Every change goes through `Designer.normalized` (UI-SHELL-074).
nonisolated struct DesignerDraft: Equatable, Sendable {
    let yard: ShipyardID
    private(set) var design: ShipDesign
    /// The silhouette for the preview (art arrives in M11); not part of the design.
    var silhouette: ShipType

    init(yard: ShipyardID, design: ShipDesign, silhouette: ShipType = .gnat) {
        self.yard = yard
        self.design = Self.fit(design, yard: yard)
        self.silhouette = ShipType.buyable.contains(silhouette) ? silhouette : .gnat
    }

    var sizes: [SystemSize] { Designer.sizes(for: yard) }

    var name: String {
        get { design.name }
        set { design.name = newValue }
    }

    var size: SystemSize {
        get { design.size }
        set {
            var d = design
            d.size = newValue
            design = Self.fit(d, yard: yard)
        }
    }

    func value(_ f: DesignerField) -> Int { f.value(design) }

    func canIncrement(_ f: DesignerField) -> Bool { stepped(f, by: 1).map { f.value($0) } != value(f) }
    func canDecrement(_ f: DesignerField) -> Bool { stepped(f, by: -1).map { f.value($0) } != value(f) }

    mutating func increment(_ f: DesignerField) { if let d = stepped(f, by: 1) { design = d } }
    mutating func decrement(_ f: DesignerField) { if let d = stepped(f, by: -1) { design = d } }

    /// Replaces every field with a template's; a template without a name keeps the current name.
    mutating func apply(_ template: ShipDesign) {
        let name = template.name.isEmpty ? design.name : template.name
        var d = template
        d.name = name
        design = Self.fit(d, yard: yard)
    }

    private func stepped(_ f: DesignerField, by direction: Int) -> ShipDesign? {
        var d = design
        f.set(&d, f.value(d) + direction * f.step(size: d.size, yard: yard))
        return Designer.normalized(d, yard: yard)
    }

    /// Normalizes a design for `yard`, moving an unavailable size to the nearest available one.
    static func fit(_ design: ShipDesign, yard: ShipyardID) -> ShipDesign {
        var d = design
        let sizes = Designer.sizes(for: yard)
        if !sizes.contains(d.size), let nearest = sizes.min(by: { abs($0.rawValue - d.size.rawValue) < abs($1.rawValue - d.size.rawValue) }) {
            d.size = nearest
        }
        return Designer.normalized(d, yard: yard)
    }
}

/// A Designer template (SHP-076, UI-SHELL-076).
nonisolated struct DesignTemplate: Identifiable, Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        case currentShip
        case minimum(SystemSize)
        case stock(ShipType)
        case saved(String)
    }

    let kind: Kind
    let design: ShipDesign

    var id: String {
        switch kind {
        case .currentShip: "current"
        case let .minimum(s): "minimum.\(s)"
        case let .stock(t): "stock.\(t)"
        case let .saved(name): "saved.\(name)"
        }
    }
}

nonisolated enum DesignTemplates {
    /// The current ship, the minimum design of each available size, each buyable type of an available size, and the
    /// saved designs of an available size (sorted by name), in that order (Form_Shipyard.cs `LoadTemplateList`).
    static func list(state: GameState, yard: ShipyardID, saved: [ShipDesign]) -> [DesignTemplate] {
        let sizes = Designer.sizes(for: yard)
        let ship = state.commander.ship.spec(state.ruleset)
        var out = [DesignTemplate(kind: .currentShip, design: design(from: ship, name: state.commander.shipName ?? ""))]
        out += sizes.map { DesignTemplate(kind: .minimum($0), design: Designer.minimumDesign(size: $0, yard: yard)) }
        out += ShipType.buyable.compactMap { t in
            let spec = state.ruleset.tables.ship(t)
            return sizes.contains(spec.size) ? DesignTemplate(kind: .stock(t), design: design(from: spec, name: "")) : nil
        }
        out += saved.filter { sizes.contains($0.size) }.sorted { $0.name < $1.name }
            .map { DesignTemplate(kind: .saved($0.name), design: $0) }
        return out
    }

    static func design(from spec: ShipSpec, name: String) -> ShipDesign {
        ShipDesign(name: name, size: spec.size, cargoBays: spec.cargoBays, fuelTanks: spec.fuelTanks, hull: spec.hullStrength,
                   weaponSlots: spec.weaponSlots, shieldSlots: spec.shieldSlots, gadgetSlots: spec.gadgetSlots,
                   crewQuarters: spec.crewQuarters)
    }
}

/// Saved designs: `Application Support/Parsec Merchant/Designs/<sanitized name>.json`, sorted-key JSON (UI-SHELL-076).
nonisolated struct DesignTemplateStore: Sendable {
    static let folderName = "Designs"
    let directory: URL

    init(root: URL) {
        directory = root.appendingPathComponent(Self.folderName, isDirectory: true)
    }

    /// Every readable design in the folder; unreadable files are skipped.
    func load() -> [ShipDesign] {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        return files.filter { $0.pathExtension == "json" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .compactMap { url in (try? Data(contentsOf: url)).flatMap { try? JSONDecoder().decode(ShipDesign.self, from: $0) } }
    }

    @discardableResult
    func save(_ design: ShipDesign) throws -> URL {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(Self.fileName(for: design.name))
        try Self.encode(design).write(to: url, options: .atomic)
        return url
    }

    static func encode(_ design: ShipDesign) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        return try encoder.encode(design)
    }

    /// Letters, digits, spaces, hyphens and underscores survive; anything else becomes "_". Empty names become "Design".
    static func fileName(for name: String) -> String {
        let kept = String(name.map { $0.isLetter || $0.isNumber || $0 == " " || $0 == "-" || $0 == "_" ? $0 : "_" })
            .trimmingCharacters(in: .whitespaces)
        return (kept.isEmpty ? "Design" : String(kept.prefix(64))) + ".json"
    }
}
