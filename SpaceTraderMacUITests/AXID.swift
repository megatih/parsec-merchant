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

    enum Sidebar {
        static let list = "sidebar.list"
    }

    enum Toolbar {
        static let target = "toolbar.target"
        static let warp = "toolbar.warp"
        static let inspector = "toolbar.inspector"
    }

    enum Status {
        static let feed = "status.feed"
        static let feedList = "status.feed.list"
        static let feedClose = "status.feed.close"
    }

    enum Inspector {
        static let root = "inspector.root"
    }

    enum Bridge {
        static let targetNext = "bridge.target.next"
        static let targetCard = "bridge.target"
    }

    enum Market {
        static let table = "market.table"
        static let items = ["water", "furs", "food", "ore", "games", "firearms", "medicine", "machines", "narcotics", "robots"]
        static func row(_ item: String) -> String { "market.row.\(item)" }
        static func buy(_ item: String) -> String { "market.row.\(item).buy" }
        static func held(_ item: String) -> String { "market.row.\(item).held" }
        static func buyPrice(_ item: String) -> String { "market.row.\(item).buyPrice" }
    }

    enum Files {
        static let list = "openSaved.list"
        static let open = "openSaved.open"
        static let cancel = "openSaved.cancel"
        static let rowPrefix = "openSaved.row."
    }

    enum Dialog {
        static let appConfirmationConfirm = "appConfirmation.confirm"
    }

    enum Options {
        static let sheet = "options.sheet"
        static let autoFuel = "options.autoFuel"
        static let autoRepair = "options.autoRepair"
        static let leaveEmpty = "options.leaveEmpty"
        static let alwaysIgnoreTraders = "options.alwaysIgnoreTraders"
        static let alwaysIgnoreTradeInOrbit = "options.alwaysIgnoreTradeInOrbit"
        static let ok = "options.ok"
        static let cancel = "options.cancel"
    }

    enum Settings {
        static let fastTravel = "settings.fastTravel"
    }

    enum Menu {
        static let save = "menu.file.save"
        static let saveAs = "menu.file.saveAs"
        static let revert = "menu.file.revert"
        static let options = "menu.game.options"
    }

    /// Section roots visited by ⌘1…⌘8.
    static let sections: [(key: String, root: String)] = [
        ("1", "bridge.root"), ("2", "market.root"), ("3", "shipyard.root"), ("4", "outfitter.root"),
        ("5", "crew.root"), ("6", "bank.root"), ("7", "galaxy.root"), ("8", "quests.root"),
    ]

    /// The galaxy chart (MAP §20), per scope prefix: `galaxy`, `galaxyWindow`, `bridge.miniChart`.
    struct Map {
        let p: String
        var map: String { "\(p).map" }
        func system(_ i: Int) -> String { "\(p).system.\(i)" }
        var hoverCard: String { "\(p).hoverCard" }
        var legend: String { "\(p).legend" }
        var legendToggle: String { "\(p).legend.toggle" }
        var zoomIn: String { "\(p).zoomIn" }
        var zoomOut: String { "\(p).zoomOut" }
        var fitGalaxy: String { "\(p).fitGalaxy" }
        var trackedRange: String { "\(p).trackedRange" }
        var plotRoute: String { "\(p).context.plotRoute" }
        var searchField: String { "\(p).search.field" }
        var searchResultPrefix: String { "\(p).search.result." }
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
        static let sidebarRow = "sidebar.galaxy"
    }
}
