// SPDX-License-Identifier: GPL-2.0-or-later

/// Transit view identifiers (UI-ENC §17 "Transit") and the sidebar's phase label (UI-ENC-009, -015).
nonisolated extension AXID {
    enum Transit {
        static let view = "transit.view"
        static let progress = "transit.progress"
        static let skip = "transit.skip"
        static let fabricRip = "transit.fabricRip"
        /// `sidebar.phaseLabel`: "In transit" / "In encounter".

        static let all = [view, progress, skip, fabricRip]
    }

    /// The M9 encounter-area lists (UI-ENC-097). Later areas append their own `<Area>.all` here.
    static var encounterAreaAll: [String] { Encounter.all + Decision.all + Transit.all + Narrative.all + arrivalAreaAll }
}
