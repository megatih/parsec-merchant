// SPDX-License-Identifier: GPL-2.0-or-later
import ParsecEngine
import SwiftUI

/// The playing window (UI-SHELL-034): sidebar, detail, inspector, toolbar and status bar.
struct MainShellView: View {
    @Environment(GameSession.self) private var session
    @SceneStorage("selectedSection") private var storedSection: String = Section.bridge.rawValue
    @SceneStorage("inspectorVisible") private var inspectorVisible = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        @Bindable var session = session
        NavigationSplitView {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 260)
        } detail: {
            VStack(spacing: 0) {
                detail
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                Divider()
                StatusBarView()
            }
        }
        .inspector(isPresented: $inspectorVisible) {
            ShipInspectorView()
                .inspectorColumnWidth(min: 260, ideal: 300, max: 380)
        }
        .toolbar { ShellToolbar(session: session, inspectorVisible: $inspectorVisible) }
        .onAppear {
            session.selectedSection = Section.restored(rawValue: storedSection, context: session.sectionContext)
            session.reduceMotion = reduceMotion
        }
        .onChange(of: reduceMotion) { _, new in session.reduceMotion = new }
        .onChange(of: session.selectedSection) { _, new in storedSection = new.rawValue }
    }

    /// UI-ENC-001: the detail mode decides the content (transit, encounter, game over or the selected section).
    @ViewBuilder
    private var detail: some View {
        if session.state != nil {
            switch DetailMode.derive(state: session.state, playback: session.transitPlayback, selected: session.selectedSection) {
            case let .transit(playback):
                TransitView(playback: playback)
            case .encounter:
                InterimEncounterPanel()
            case .gameOver:
                GameOverCard()
            case let .section(section):
                SectionDetailView(section: section)
            }
        }
    }
}

/// The selected section's content. Each section view is owned by its spec agent.
struct SectionDetailView: View {
    let section: Section

    var body: some View {
        switch section {
        case .bridge: BridgeSectionView()
        case .market: MarketSectionView()
        case .shipyard: ShipyardSectionView()
        case .outfitter: OutfitterSectionView()
        case .crew: CrewSectionView()
        case .bank: BankSectionView()
        case .galaxy: GalaxySectionView()
        case .quests: QuestsSectionView()
        }
    }
}
