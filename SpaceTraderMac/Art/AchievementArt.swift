// SPDX-License-Identifier: GPL-2.0-or-later
import ParsecArt
import ParsecInsights
import SwiftUI

/// ACH-023, ART-036: one drawn emblem and medal tier per achievement (an exhaustive table; every emblem is distinct).
nonisolated enum AchievementArt {
    // swiftlint:disable:next cyclomatic_complexity
    static func badge(_ id: AchievementID) -> (emblem: AchievementEmblem, tier: AchievementTier) {
        switch id {
        case .firstProfit: (.commodity(.water), .bronze)
        case .worth10k: (.commodity(.ore), .bronze)
        case .worth100k: (.commodity(.machines), .silver)
        case .worth1m: (.commodity(.robots), .brass)
        case .dragonfly: (.ship(.dragonfly), .brass)
        case .spaceMonster: (.ship(.spaceMonster), .brass)
        case .scarab: (.ship(.scarab), .brass)
        case .japori: (.commodity(.medicine), .silver)
        case .jarek: (.encounter(.trader), .silver)
        case .wild: (.equipment(.weapon(1)), .silver)
        case .reactor: (.equipment(.weapon(3)), .silver)
        case .gemulon: (.equipment(.gadget(5)), .silver)
        case .experiment: (.star(points: 7), .silver)
        case .artifact: (.encounter(.alien), .silver)
        case .sculpture: (.equipment(.gadget(6)), .silver)
        case .princess: (.equipment(.weapon(5)), .brass)
        case .moon: (.planet, .brass)
        case .waspKiller: (.ship(.wasp), .silver)
        case .closeCall: (.equipment(.gadget(1)), .bronze)
        case .hero: (.encounter(.police), .brass)
        case .villain: (.encounter(.pirate), .brass)
        case .debtFree: (.commodity(.food), .bronze)
        case .explorer50: (.star(points: 5), .silver)
        case .explorerAll: (.star(points: 8), .brass)
        case .wormhole: (.wormhole, .bronze)
        case .winHard: (.star(points: 6), .silver)
        case .winImpossible: (.crown, .brass)
        case .allCommodities: (.commodity(.furs), .silver)
        case .tribbleMax: (.tribble, .silver)
        case .marieCeleste: (.equipment(.gadget(4)), .bronze)
        case .famousCaptains: (.encounter(.special), .silver)
        case .escapePod: (.ship(.flea), .bronze)
        case .designer: (.ship(.custom), .silver)
        case .ironman: (.equipment(.shield(2)), .brass)
        case .bountyHunter: (.equipment(.gadget(3)), .silver)
        case .bigScore: (.star(points: 12), .brass)
        }
    }
}

/// ACH-023: the drawn medal of an achievement (locked: desaturated with a padlock).
struct AchievementBadgeView: View {
    let id: AchievementID
    let unlocked: Bool

    var body: some View {
        let art = AchievementArt.badge(id)
        AchievementBadgeArt(shape: art.emblem, tier: art.tier, locked: !unlocked)
            .accessibilityHidden(true)
    }
}

/// ART-038, ART-052: the Welcome starfield behind the wordmark (one `TimelineView`, paused when inactive, still under
/// Reduce Motion).
struct WelcomeBackdrop: View {
    @Environment(\.appearsActive) private var appearsActive

    var body: some View {
        ArtAccessibilityReader { a11y in
            TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !appearsActive || a11y.reduceMotion)) { timeline in
                WelcomeScene(phase: timeline.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: WelcomeScene.cycle * 30),
                             accessibility: a11y, showsWordmark: false)
            }
        }
        .accessibilityHidden(true)
    }
}
