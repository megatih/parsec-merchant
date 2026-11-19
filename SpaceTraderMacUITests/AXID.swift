// SPDX-License-Identifier: GPL-2.0-or-later

/// The accessibility identifiers the UI flows use, mirrored from the app's `AXID` (UI-SHELL Conventions, §18).
/// The UI-test target cannot import the app, so these are literal copies; extend, never rename.
enum AXID {
    static let pattern = #"^[a-z][A-Za-z0-9]*(\.[A-Za-z0-9]+)+$"#

    enum Welcome {
        static let quickStart = "welcome.quickStart"
        static let newGame = "welcome.newGame"
    }

    enum NewGame {
        static let sheet = "newGame.sheet"
        static let name = "newGame.name"
        static let difficultyNormal = "newGame.difficulty.normal"
        static let rulesetModern = "newGame.ruleset.modern"
        static let balanced = "newGame.skills.balanced"
        static let galaxyCode = "newGame.galaxyCode"
        static let next = "newGame.next"
        static let cancel = "newGame.cancel"
        static let start = "newGame.start"
    }

    /// The dock bar (release 2.0; the sidebar's rows moved from `sidebar.` to `dock.`, the toolbar is gone).
    enum Dock {
        static let bar = "dock.bar"
        static let phaseLabel = "dock.phaseLabel"
        static let market = "dock.market"
        static let options = "dock.options"
        static func button(_ page: String) -> String { "dock.\(page)" }
    }

    enum Status {
        static let bar = "status.bar"
        static let cash = "status.cash"
        static let feed = "status.feed"
        static let feedList = "status.feed.list"
        static let feedClose = "status.feed.close"
    }

    enum Inspector {
        static let root = "inspector.root"
    }

    enum Bridge {
        static let root = "bridge.root"
        static let regions = ["bridge.system", "bridge.cargo", "bridge.chart", "bridge.target"]
        static let targetNext = "bridge.target.next"
        static let targetPrevious = "bridge.target.previous"
        static let targetCard = "bridge.target"
        static let targetName = "bridge.target.name"
        static let targetWarp = "bridge.target.warp"
        static let targetTrack = "bridge.target.track"
        static let targetFind = "bridge.target.find"
        static let fillTank = "bridge.system.fillTank"
        static let repairHull = "bridge.system.repairHull"
        static let news = "bridge.system.news"
        static let special = "bridge.system.special"
        static let hire = "bridge.system.hire"
        static let quest = "bridge.system.quest"
        static let chartOpen = "bridge.chart.open"
        static let system = ["bridge.system.planet", "bridge.system.name", "bridge.system.size", "bridge.system.tech", "bridge.system.government",
                             "bridge.system.resources", "bridge.system.status", "bridge.system.police", "bridge.system.pirates", "bridge.system.fuel",
                             "bridge.system.hull", fillTank, repairHull, news, special, hire, quest]
        static let target = [targetName, "bridge.target.distance", "bridge.target.badge", "bridge.target.note", "bridge.target.size",
                             "bridge.target.tech", "bridge.target.government", "bridge.target.resources", "bridge.target.police", "bridge.target.pirates",
                             "bridge.target.cost.mercenaries", "bridge.target.cost.insurance", "bridge.target.cost.interest",
                             "bridge.target.cost.wormholeTax", "bridge.target.cost.total", "bridge.target.fuelAfter", targetWarp, targetPrevious,
                             targetNext, targetTrack, targetFind]
        /// UI-BRG-031: every element of the Bridge (a literal copy of `BridgeManifest.all`).
        static var manifest: [String] {
            regions + system + [Cargo.bays, Cargo.holdLine, Cargo.sellAll] + Cargo.items.flatMap { Cargo.cells($0) + Cargo.controls($0) }
                + ["bridge.miniChart.map", chartOpen] + target
        }
        /// The elements that take clicks.
        static var buttons: [String] {
            [fillTank, repairHull, news, special, hire, quest, Cargo.sellAll, chartOpen, targetWarp, targetPrevious, targetNext, targetTrack, targetFind]
                + Cargo.items.flatMap { [Cargo.buy($0), Cargo.max($0), Cargo.sell($0), Cargo.all($0)] }
        }
    }

    /// The Bridge's Cargo region (UI-BRG-031): `bridge.cargo.<element>.<good>`.
    enum Cargo {
        static let panel = "bridge.cargo"
        static let rows = "bridge.cargo.rows"
        static let sellAll = "bridge.cargo.sellAll"
        static let bays = "bridge.cargo.summary.bays"
        static let holdLine = "bridge.cargo.summary.hold"
        static let items = ["water", "furs", "food", "ore", "games", "firearms", "medicine", "machines", "narcotics", "robots"]
        static func row(_ item: String) -> String { "bridge.cargo.row.\(item)" }
        static func good(_ item: String) -> String { "bridge.cargo.good.\(item)" }
        static func held(_ item: String) -> String { "bridge.cargo.hold.\(item)" }
        static func paid(_ item: String) -> String { "bridge.cargo.paid.\(item)" }
        static func sellPrice(_ item: String) -> String { "bridge.cargo.sellPrice.\(item)" }
        static func buyPrice(_ item: String) -> String { "bridge.cargo.buyPrice.\(item)" }
        static func stock(_ item: String) -> String { "bridge.cargo.stock.\(item)" }
        static func target(_ item: String) -> String { "bridge.cargo.target.\(item)" }
        static func delta(_ item: String) -> String { "bridge.cargo.delta.\(item)" }
        static func quantity(_ item: String) -> String { "bridge.cargo.quantity.\(item)" }
        static func buy(_ item: String) -> String { "bridge.cargo.buy.\(item)" }
        static func max(_ item: String) -> String { "bridge.cargo.max.\(item)" }
        static func sell(_ item: String) -> String { "bridge.cargo.sell.\(item)" }
        static func all(_ item: String) -> String { "bridge.cargo.all.\(item)" }
        static func cells(_ item: String) -> [String] {
            [row(item), good(item), held(item), paid(item), sellPrice(item), buyPrice(item), stock(item), target(item), delta(item)]
        }
        static func controls(_ item: String) -> [String] { [quantity(item), buy(item), max(item), sell(item), all(item)] }
    }

    enum Files {
        static let list = "openSaved.list"
        static let open = "openSaved.open"
        static let cancel = "openSaved.cancel"
        static let rowPrefix = "openSaved.row."
    }

    enum Dialog {
        static let appConfirmationConfirm = "appConfirmation.confirm"
        static let confirmationConfirm = "confirmation.confirm"
        static let retireSheet = "retire.sheet"
        static let retireConfirm = "retire.confirm"
    }

    enum Options {
        /// The Options page (release 2.0: a page whose changes apply at once; ⌥⌘O).
        static let root = "options.root"
        static let autoFuel = "options.autoFuel"
        static let autoRepair = "options.autoRepair"
        static let leaveEmpty = "options.leaveEmpty"
        static let alwaysIgnoreTraders = "options.alwaysIgnoreTraders"
        static let alwaysIgnoreTradeInOrbit = "options.alwaysIgnoreTradeInOrbit"
    }

    enum Settings {
        static let fastTravel = "settings.fastTravel"
    }

    enum Menu {
        static let save = "menu.file.save"
        static let saveAs = "menu.file.saveAs"
        static let revert = "menu.file.revert"
        static let options = "menu.view.options"
    }

    /// The Encounter view (UI-ENC §17).
    enum Encounter {
        static let view = "encounter.view"
        static let intro = "encounter.intro"
        static let badge = "encounter.badge"
        static let playerHull = "encounter.player.hull"
        static let opponentHull = "encounter.opponent.hull"
        static let log = "encounter.log"
        static func logRow(_ index: Int) -> String { "encounter.log.row.\(index)" }
        static let attack = "encounter.action.attack"
        static let flee = "encounter.action.flee"
        static let surrender = "encounter.action.surrender"
        static let resolve = "encounter.action.resolve"
        static let plunder = "encounter.action.plunder"
        static let trade = "encounter.action.trade"
        static let tactical = "encounter.tactical"
    }

    enum Transit {
        static let view = "transit.view"
    }

    enum Decision {
        static let plunderSheet = "decision.plunder.sheet"
        static let plunderDone = "decision.plunder.done"
        static let tradeSheet = "decision.trade.sheet"
        static let tradeDecline = "decision.trade.decline"
    }

    enum Report {
        static let sheet = "report.sheet"
        static let continueButton = "report.continue"
    }

    /// The arrival card on the Bridge (UI-ENC §17).
    enum Arrival {
        /// The arrival summary in the status bar's message slot (UI-BRG-042); a click on it opens the report sheet.
        static let card = "arrival.card"
        static func encounter(_ index: Int) -> String { "arrival.encounter.\(index)" }
        static let newsRead = "arrival.news.read"
    }

    enum Newspaper {
        static let sheet = "newspaper.sheet"
        static let close = "decision.newspaper.close"
        static let bridgeRead = "bridge.system.news"
    }

    enum Narrative {
        static let sheet = "narrative.sheet"
        static let decline = "narrative.decline"
        /// The Special notice on the Bridge; a click opens the offer.
        static let bridgeCard = "bridge.system.special"
        static let bridgeAccept = "bridge.system.special"
    }

    enum GameOver {
        static let card = "gameOver.card"
        static let highScores = "gameOver.highScores"
        static let mainMenu = "gameOver.mainMenu"
    }

    enum Scores {
        static let window = "scores.window"
    }

    /// Section roots visited by ⌘1…⌘8.
    static let sections: [(key: String, root: String)] = [
        ("1", "bridge.root"), ("2", "shipyard.root"), ("3", "outfitter.root"), ("4", "crew.root"),
        ("5", "bank.root"), ("6", "inspector.root"), ("7", "quests.root"), ("8", "galaxy.root"),
    ]

    /// The galaxy chart (MAP §20), per scope prefix: `galaxy`, `galaxyWindow`, `bridge.miniChart`.
    struct Map {
        let p: String
        var map: String { "\(p).map" }
        func system(_ i: Int) -> String { "\(p).system.\(i)" }
        var hoverCard: String { "\(p).hoverCard" }
        /// UI-PTR-011: the pinned selection card and its buttons.
        var selectionCard: String { "\(p).selectionCard" }
        var warp: String { "\(p).warp" }
        var selectionSetTarget: String { "\(p).selection.setTarget" }
        var selectionTrack: String { "\(p).selection.track" }
        var selectionPlotRoute: String { "\(p).selection.plotRoute" }
        var legend: String { "\(p).legend" }
        var legendToggle: String { "\(p).legend.toggle" }
        var zoomIn: String { "\(p).zoomIn" }
        var zoomOut: String { "\(p).zoomOut" }
        var fitGalaxy: String { "\(p).fitGalaxy" }
        var trackedRange: String { "\(p).trackedRange" }
        var plotRoute: String { "\(p).context.plotRoute" }
        var filterInRange: String { "\(p).search.filter.inRange" }
        var routePanel: String { "\(p).route.panel" }
        func routeHop(_ n: Int) -> String { "\(p).route.hop.\(n)" }
        var routeClear: String { "\(p).route.clear" }
    }

    enum Galaxy {
        static let root = "galaxy.root"
        static let windowRoot = "galaxyWindow.root"
        static let section = Map(p: "galaxy")
        static let window = Map(p: "galaxyWindow")
        static let mini = Map(p: "bridge.miniChart")
        static let sidebarRow = "dock.galaxy"
    }
}
