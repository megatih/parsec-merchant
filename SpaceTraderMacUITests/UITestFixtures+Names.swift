// SPDX-License-Identifier: GPL-2.0-or-later

/// A11Y-041: the proper names the app shows as data (never localized, so never pseudo-localized): every system name
/// (`GameNames.systems`), every crew name (`GameNames.crew`), the commander names the flows use and the people credited
/// in About. The app test `LocalizationCatalogTests` checks these lists against the app's tables (the UI-test target
/// cannot import the engine).
extension UITestFixtures {
    static let systemNames: [String] = [
        "Acamar", "Adahn", "Aldea", "Andevian", "Antedi", "Balosnee", "Baratas", "Brax", "Bretel", "Calondia",
        "Campor", "Capelle", "Carzon", "Castor", "Cestus", "Cheron", "Courteney", "Daled", "Damast", "Davlos",
        "Deneb", "Deneva", "Devidia", "Draylon", "Drema", "Endor", "Esmee", "Exo", "Ferris", "Festen", "Fourmi",
        "Frolix", "Gemulon", "Guinifer", "Hades", "Hamlet", "Helena", "Hulst", "Iodine", "Iralius", "Janus",
        "Japori", "Jarada", "Jason", "Kaylon", "Khefka", "Kira", "Klaatu", "Klaestron", "Korma", "Kravat", "Krios",
        "Laertes", "Largo", "Lave", "Ligon", "Lowry", "Magrat", "Malcoria", "Melina", "Mentar", "Merik", "Mintaka",
        "Montor", "Mordan", "Myrthe", "Nelvana", "Nix", "Nyle", "Odet", "Og", "Omega", "Omphalos", "Orias",
        "Othello", "Parade", "Penthara", "Picard", "Pollux", "Quator", "Rakhar", "Ran", "Regulas", "Relva", "Rhymus",
        "Rochani", "Rubicum", "Rutia", "Sarpeidon", "Sefalla", "Seltrice", "Sigma", "Sol", "Somari", "Stakoron",
        "Styris", "Talani", "Tamus", "Tantalos", "Tanuga", "Tarchannen", "Terosa", "Thera", "Titan", "Torin",
        "Triacus", "Turkana", "Tyrus", "Umberlee", "Utopia", "Vadera", "Vagra", "Vandor", "Ventax", "Xenon",
        "Xerxes", "Yew", "Yojimbo", "Zalkon", "Zuul", "Centauri", "Galvon", "Inthara", "Meridian", "Qonos", "Rae",
        "Weytahn", "Zonama",
    ]

    static let crewNames: [String] = [
        "Commander", "Alyssa", "Armatur", "Bentos", "C2U2", "Chi'Ti", "Crystal", "Dane", "Deirdre", "Doc", "Draco",
        "Iranda", "Jeremiah", "Jujubal", "Krydon", "Luis", "Mercedez", "Milete", "Muri-L", "Mystyc", "Nandi",
        "Orestes", "Pancho", "PS37", "Quarck", "Sosumi", "Uma", "Wesley", "Wonton", "Yorvick", "Zeethibal",
        "Opponent", "Wild", "Jarek", "Captain", "Dragonfly", "Scarab", "SpaceMonster", "Aragorn", "Brady",
        "Eight of Nine", "Fangorn", "Gagarin", "Hoshi", "Jackson", "Kaylee", "Marcus", "O'Neill", "Ripley",
        "Stilgar", "Taggart", "Vansen", "Xizor", "Ziyal", "Scorpion",
    ]

    /// The Quick Start commander (`GameSession.defaultCommanderName`) and the wizard's flow commander.
    static let commanderNames = ["Jameson", commanderName]

    /// The people credited in the About window (`AboutContent.credits`).
    static let creditNames = ["Pieter Spronck", "Sam Anderson", "Samuel Goldstein", "Matt Lee", "Jay French", "David Pierron"]

    static var dataNames: [String] { systemNames + crewNames + commanderNames + creditNames }
}
