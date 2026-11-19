// SPDX-License-Identifier: GPL-2.0-or-later
import AppKit
import ParsecEngine
import SwiftUI

/// UI-NAV-001: the playing window: the dock bar, the status bar and the game area, top to bottom. Nothing is pinned to
/// the bottom edge. The game area shows exactly one of: a page, transit, an encounter or the game-over card.
struct GameShellView: View {
    @Environment(GameSession.self) private var session
    @SceneStorage("selectedSection") private var storedSection: String = Section.bridge.rawValue
    @Environment(\.accessibilityPreferences) private var prefs
    @AppStorage(AppSettingsKey.textSize) private var textSize = TextSizeSetting.standard.rawValue
    /// UI-KEYS-018: the Esc handlers of the pages, run by the window's one Esc router.
    @State private var escapes = EscapeRegistry()

    var body: some View {
        GeometryReader { geo in
            // UI-DS-002: one interface scale from the window's size, floored by the Text Size setting.
            let scale = PMScale.scale(for: geo.size, floor: Self.textFloor(textSize))
            VStack(spacing: 0) {
                DockBarView()
                    .focusSection()
                StatusBarView()
                detail
                    .frame(maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
                    .clipped()
                    .focusSection()
            }
            .environment(\.pmScale, scale)
            .environment(\.textScale, scale)
            .font(AppFontMetrics.font(.body, scale: scale))
        }
        // The game area is one dark console in both appearances (PRD §3.3).
        .environment(\.colorScheme, .dark)
        .background(PMColor.space)
        .frame(minWidth: Self.minimumSize(textSize).width, minHeight: Self.minimumSize(textSize).height)
        .modifier(WindowEscapeRouter(registry: escapes))
        .onAppear {
            session.selectedSection = Section.restored(rawValue: storedSection, context: session.sectionContext)
            session.reduceMotion = prefs.reduceMotion
            session.updateTips()
        }
        .onChange(of: prefs.reduceMotion) { _, new in session.reduceMotion = new }
        .onChange(of: session.selectedSection) { _, new in
            storedSection = new.rawValue
            session.updateTips()  // A11Y-044
        }
    }

    /// UI-DS-004: the lower clamp of the interface scale: the Text Size step, or the largest one whose minimum window
    /// fits the main screen.
    static func textFloor(_ rawValue: String) -> CGFloat {
        let wanted = (TextSizeSetting(rawValue: rawValue) ?? .standard).interfaceFloor
        let visible = NSScreen.main?.visibleFrame.size
        // The title bar is not content.
        return PMScale.effectiveFloor(wanted: wanted, available: visible.map { CGSize(width: $0.width, height: $0.height - 32) })
    }

    static func minimumSize(_ rawValue: String) -> CGSize { PMScale.minimumSize(floor: textFloor(rawValue)) }

    /// UI-ENC-001: the detail mode decides the content (transit, encounter, game over or the selected page).
    @ViewBuilder
    private var detail: some View {
        if session.state != nil {
            switch DetailMode.derive(state: session.state, playback: session.transitPlayback, selected: session.selectedSection) {
            case let .transit(playback):
                TransitView(playback: playback)
            case .encounter:
                EncounterView()
            case .gameOver:
                GameOverView()
            case let .section(section):
                SectionDetailView(section: section)
            }
        }
    }
}

/// The selected page's content.
struct SectionDetailView: View {
    let section: Section

    var body: some View {
        switch section {
        case .bridge: BridgeView()
        case .shipyard: ShipyardPage()
        case .outfitter: EquipmentPage()
        case .crew: PersonnelPage()
        case .bank: BankPage()
        case .galaxy: GalaxySectionView()
        case .quests: QuestsPage()
        case .logbook: LogbookView()
        case .status: StatusPage()
        case .options: OptionsPage()
        }
    }
}

extension TextSizeSetting {
    /// UI-DS-004: the interface-scale floor of a Text Size setting (Standard 1.0, Large 1.15, Larger 1.3, Extra Large 1.5,
    /// Largest 2.0); the nine stored values of 1.x map to the nearest step at or below them.
    var interfaceFloor: CGFloat {
        PMScale.textSteps.last { $0 <= scale + 1e-6 } ?? 1
    }
}
