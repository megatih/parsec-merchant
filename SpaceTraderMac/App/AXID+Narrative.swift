// SPDX-License-Identifier: GPL-2.0-or-later

/// Narrative sheet identifiers (UI-ENC §17 "Narrative"; the Bridge card's `bridge.special.*` live in `AXID.Bridge`).
nonisolated extension AXID {
    enum Narrative {
        static let sheet = "narrative.sheet"
        static let title = "narrative.title"
        static let vignette = "narrative.vignette"
        static let story = "narrative.story"
        static let accept = "narrative.accept"
        static let decline = "narrative.decline"
        static let continueButton = "narrative.continue"

        static let all = [sheet, title, vignette, story, accept, decline, continueButton]
    }
}
