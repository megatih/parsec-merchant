// SPDX-License-Identifier: GPL-2.0-or-later
import SwiftUI

/// ART-033: the five encounter badges (engine `EncounterBadge`).
public enum EncounterBadgeKind: String, CaseIterable, Sendable, Hashable {
    case pirate, police, trader, alien, special
}

/// ART-033: a template shape for the badge; `EncounterBadgeGlyph` adds the brass for `special`.
public struct EncounterBadgeShape: Shape {
    public var badge: EncounterBadgeKind

    public init(badge: EncounterBadgeKind) { self.badge = badge }

    public func path(in rect: CGRect) -> Path { GlyphKit.fit(Self.unitPath(badge), in: rect) }

    static func unitPath(_ badge: EncounterBadgeKind) -> Path {
        typealias GK = GlyphKit
        switch badge {
        case .pirate:
            let blades = GK.union([GK.line([(0.12, 0.92), (0.88, 0.5)], width: 0.07), GK.line([(0.88, 0.92), (0.12, 0.5)], width: 0.07)])
            let skull = GK.union([GK.circle(0.5, 0.36, 0.26), GK.rect(0.36, 0.5, 0.28, 0.2, corner: 0.05)])
                .subtracting(GK.union([GK.circle(0.4, 0.36, 0.07), GK.circle(0.6, 0.36, 0.07), GK.poly([(0.5, 0.46), (0.46, 0.54), (0.54, 0.54)])]))
            return blades.subtracting(GK.circle(0.5, 0.42, 0.32)).union(skull)
        case .police:
            let shield = ArtGeometry.closedSpline([SplinePoint(0.12, 0.12, sharp: true), SplinePoint(0.88, 0.12, sharp: true),
                                                   SplinePoint(0.84, 0.56), SplinePoint(0.5, 0.94, sharp: true), SplinePoint(0.16, 0.56)])
            return shield.subtracting(ArtGeometry.star(center: CGPoint(x: 0.5, y: 0.46), points: 5, outer: 0.24, inner: 0.1))
        case .trader:
            let crate = GK.rect(0.12, 0.5, 0.76, 0.42, corner: 0.04).subtracting(GK.line([(0.2, 0.58), (0.8, 0.84)], width: 0.05))
            let coin = GK.circle(0.5, 0.3, 0.24).subtracting(GK.arc(0.5, 0.3, 0.15, from: 0, to: 360, width: 0.04))
            return crate.subtracting(GK.circle(0.5, 0.3, 0.29)).union(coin)
        case .alien:
            var parts = [ArtGeometry.closedSpline([SplinePoint(0.08, 0.36, sharp: true), SplinePoint(0.5, 0.1), SplinePoint(0.92, 0.36, sharp: true),
                                                   SplinePoint(0.5, 0.6)])]
            for x in [0.28, 0.5, 0.72] {
                parts.append(ArtGeometry.stroke(ArtGeometry.openSpline([SplinePoint(x, 0.5), SplinePoint(x - 0.06, 0.7), SplinePoint(x + 0.05, 0.82),
                                                                        SplinePoint(x - 0.02, 0.94)]), width: 0.07))
            }
            return GK.union(parts).subtracting(GK.circle(0.5, 0.35, 0.11))
        case .special:
            return GK.arc(0.5, 0.5, 0.42, from: 0, to: 360, width: 0.07)
                .union(ArtGeometry.star(center: CGPoint(x: 0.5, y: 0.5), points: 8, outer: 0.32, inner: 0.14))
        }
    }
}

/// ART-033: the badge glyph; `special` is drawn in brass, the others take the foreground style.
public struct EncounterBadgeGlyph: View {
    public var badge: EncounterBadgeKind
    @Environment(\.colorScheme) private var scheme

    public init(badge: EncounterBadgeKind) { self.badge = badge }

    public var body: some View {
        Group {
            if badge == .special {
                EncounterBadgeShape(badge: badge).fill(ArtPalette.resolve(.brass, scheme: scheme))
            } else {
                EncounterBadgeShape(badge: badge)
            }
        }
        .accessibilityHidden(true)
    }
}

/// ART-036: the medal tiers.
public enum AchievementTier: Int, CaseIterable, Sendable, Hashable {
    case bronze, silver, brass
}

/// ART-036: the emblem of a badge, from the glyph sets.
public enum AchievementEmblem: Hashable, Sendable {
    case commodity(CommodityGlyphKind)
    case equipment(EquipmentGlyphKind)
    case encounter(EncounterBadgeKind)
    case ship(ShipArtKind)
    case planet, crown, wormhole, tribble, star(points: Int)

    func unitPath() -> Path {
        switch self {
        case let .commodity(k): CommodityGlyph.unitPath(k)
        case let .equipment(k): EquipmentGlyph.unitPath(k)
        case let .encounter(k): EncounterBadgeShape.unitPath(k)
        case let .ship(k):
            ShipArtEmblem.path(k)
        case .planet:
            GlyphKit.circle(0.5, 0.5, 0.32).union(GlyphKit.rotated(GlyphKit.arc(0.5, 0.5, 0.44, from: 15, to: 165, width: 0.06), degrees: -15)
                .applying(CGAffineTransform(a: 1, b: 0, c: 0, d: 0.4, tx: 0, ty: 0.3)))
        case .crown:
            GlyphKit.poly([(0.1, 0.78), (0.14, 0.28), (0.32, 0.52), (0.5, 0.2), (0.68, 0.52), (0.86, 0.28), (0.9, 0.78)])
        case .wormhole:
            GlyphKit.union((0..<3).map { k in GlyphKit.arc(0.5, 0.5, 0.16 + 0.12 * Double(k), from: Double(k) * 120, to: Double(k) * 120 + 220, width: 0.07) })
        case .tribble:
            GlyphKit.circle(0.5, 0.55, 0.34).union(ArtGeometry.star(center: CGPoint(x: 0.5, y: 0.55), points: 16, outer: 0.42, inner: 0.32))
                .subtracting(GlyphKit.circle(0.4, 0.48, 0.05)).subtracting(GlyphKit.circle(0.6, 0.48, 0.05))
        case let .star(points):
            ArtGeometry.star(center: CGPoint(x: 0.5, y: 0.52), points: max(4, points), outer: 0.42, inner: 0.18)
        }
    }
}

/// A ship silhouette in a unit square (for emblems).
enum ShipArtEmblem {
    static func path(_ kind: ShipArtKind) -> Path {
        let g = ShipGeometry.make(ShipBlueprints.blueprint(kind))
        let b = g.bounds
        let s = 0.84 / max(b.width, b.height)
        return g.silhouette.applying(CGAffineTransform(a: s, b: 0, c: 0, d: s, tx: 0.5 - b.midX * s, ty: 0.5 - b.midY * s))
    }
}

/// ART-036: a hexagonal medal with a tier rim, an emblem, and a locked state (desaturated plus a padlock, not colour only).
public struct AchievementBadgeArt: View {
    public var shape: AchievementEmblem
    public var tier: AchievementTier
    public var locked: Bool
    @Environment(\.colorScheme) private var scheme

    public init(shape: AchievementEmblem, tier: AchievementTier, locked: Bool) {
        self.shape = shape
        self.tier = tier
        self.locked = locked
    }

    public var body: some View {
        let emblem = shape.unitPath(), tier = tier, locked = locked, ink = ArtInk(scheme: scheme, contrast: false)
        Canvas { ctx, size in
            let side = min(size.width, size.height)
            let o = CGPoint(x: (size.width - side) / 2, y: (size.height - side) / 2)
            let t = CGAffineTransform(a: side, b: 0, c: 0, d: side, tx: o.x, ty: o.y)
            let hex = ArtGeometry.star(center: CGPoint(x: 0.5, y: 0.5), points: 3, outer: 0.48, inner: 0.48, rotation: 0).applying(t)
            let inner = ArtGeometry.star(center: CGPoint(x: 0.5, y: 0.5), points: 3, outer: 0.4, inner: 0.4, rotation: 0).applying(t)
            var rim: ArtRGB = switch tier {
            case .bronze: ArtRGB(0.72, 0.45, 0.25)
            case .silver: ArtRGB(0.74, 0.77, 0.82)
            case .brass: ink.rgb(.brass)
            }
            var field = ink.rgb(.spaceTop).shade(1.2)
            if locked {
                rim = rim.saturation(0)
                field = field.saturation(0).shade(0.9)
            }
            ctx.fill(hex, with: .linearGradient(Gradient(colors: [rim.shade(1.3).color, rim.shade(0.7).color]), startPoint: o,
                                                endPoint: CGPoint(x: o.x + side, y: o.y + side)))
            ctx.fill(inner, with: .color(field.color))
            let e = emblem.applying(CGAffineTransform(a: 0.5, b: 0, c: 0, d: 0.5, tx: 0.25, ty: 0.25)).applying(t)
            ctx.fill(e, with: .color((locked ? ArtRGB(0.6, 0.6, 0.62) : rim.shade(1.25)).color))
            if locked {
                let body = GlyphKit.rect(0.6, 0.66, 0.24, 0.18, corner: 0.03).applying(t)
                let shackle = GlyphKit.arc(0.72, 0.66, 0.07, from: 180, to: 360, width: 0.04).applying(t)
                ctx.fill(shackle, with: .color(.white))
                ctx.fill(body, with: .color(.white))
                ctx.fill(GlyphKit.circle(0.72, 0.75, 0.025).applying(t), with: .color(ArtRGB(0.3, 0.3, 0.32).color))
            }
        }
        .accessibilityHidden(true)
    }
}
