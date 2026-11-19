// SPDX-License-Identifier: GPL-2.0-or-later
import ParsecArt
import ParsecEngine
import SwiftUI

/// ART-077: a system as a hero card: the planet stage beside the facts when the card is wide enough, above them
/// otherwise. This was the 1.x Bridge's system card; release 2.0 shows the Bridge's planet in `BridgeSystemPanel`, and
/// this card presents a selected system on the Galactic Chart page. (The file keeps its 1.x name: the frozen planet
/// tests read the stage's layout from it.)
struct SystemHeroCard: View {
    let model: SystemCardModel
    let planet: PlanetArtInput

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: PlanetHero.spacing) {
                hero.frame(width: PlanetHero.besideSide, height: PlanetHero.besideSide)
                facts.frame(minWidth: PlanetHero.factsMinWidth, alignment: .leading)
            }
            VStack(alignment: .leading, spacing: 10) {
                hero.frame(maxWidth: .infinity).frame(height: PlanetHero.stackedHeight)
                facts
            }
        }
        .accessibilityElement(children: .contain)
    }

    private var hero: some View {
        PlanetHero(input: planet)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(SystemText.planetLabel(model)))
            .accessibilityAddTraits(.isImage)
    }

    private var facts: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(verbatim: model.name).pmFont(.title).foregroundStyle(PMColor.textPrimary).accessibilityAddTraits(.isHeader)
            fact("Size", Text(Names.size(model.size)))
            fact("Tech level", Text(SystemText.techLevel(model.techLevel)))
            fact("Government", Text(SystemText.government(model.government)))
            fact("Resources", Text(SystemText.resource(model.resource)))
            fact("Police", Text(SystemText.activity(model.police)))
            fact("Pirates", Text(SystemText.activity(model.pirates)))
        }
    }

    private func fact(_ label: LocalizedStringResource, _ value: Text) -> some View {
        HStack(spacing: 8) {
            Text(label).foregroundStyle(PMColor.textSecondary)
            value.foregroundStyle(PMColor.textPrimary)
        }
        .pmFont(.body)
        .accessibilityElement(children: .combine)
    }
}
