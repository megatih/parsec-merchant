// SPDX-License-Identifier: GPL-2.0-or-later
import AppKit
import SwiftUI

/// A pull-down or pop-up menu button drawn by AppKit (`NSPopUpButton`). A11Y-029: SwiftUI's `Menu` and its menu-style
/// `Picker` outside a `Form` expose no press action on macOS 27 (`performAccessibilityAudit` reports "Action is missing"
/// for each), while `NSPopUpButton` supports AXPress and AXShowMenu, so VoiceOver can open it like a click does.
struct PopUpMenuButton: NSViewRepresentable {
    struct Item {
        var title: String
        var isOn = false
        var isEnabled = true
        var isSeparator = false
        var identifier: String?
        var action: () -> Void = {}

        static var separator: Item { Item(title: "", isSeparator: true) }
    }

    /// The button's text (pull-down) — a pop-up shows its selected item instead.
    var title: String
    var items: [Item]
    /// Pull-down (a command menu) or pop-up (a choice with `selectedIndex`).
    var pullsDown = true
    var selectedIndex: Int?
    var accessibilityLabel: String
    var identifier: String
    var help: String?
    var isEnabled = true
    var controlSize: NSControl.ControlSize = .regular
    var bezelStyle: NSButton.BezelStyle = .push

    final class Coordinator: NSObject {
        var items: [Item] = []
        @objc func choose(_ sender: NSMenuItem) {
            guard items.indices.contains(sender.tag) else { return }
            items[sender.tag].action()
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSPopUpButton {
        let button = NSPopUpButton(frame: .zero, pullsDown: pullsDown)
        button.setContentHuggingPriority(.required, for: .horizontal)
        update(button, context: context)
        return button
    }

    func updateNSView(_ button: NSPopUpButton, context: Context) {
        update(button, context: context)
    }

    private func update(_ button: NSPopUpButton, context: Context) {
        context.coordinator.items = items
        button.pullsDown = pullsDown
        button.controlSize = controlSize
        button.bezelStyle = bezelStyle
        button.isEnabled = isEnabled
        button.toolTip = help
        button.setAccessibilityLabel(accessibilityLabel)
        button.setAccessibilityIdentifier(identifier)
        let menu = NSMenu()
        if pullsDown {
            // A pull-down button shows its first item as the title.
            menu.addItem(NSMenuItem(title: title, action: nil, keyEquivalent: ""))
        }
        for (i, item) in items.enumerated() {
            if item.isSeparator {
                menu.addItem(.separator())
                continue
            }
            let m = NSMenuItem(title: item.title, action: #selector(Coordinator.choose(_:)), keyEquivalent: "")
            m.target = context.coordinator
            m.tag = i
            m.state = item.isOn ? .on : .off
            m.isEnabled = item.isEnabled
            if let id = item.identifier { m.setAccessibilityIdentifier(id) }
            menu.addItem(m)
        }
        menu.autoenablesItems = false
        button.menu = menu
        if !pullsDown, let selectedIndex, items.indices.contains(selectedIndex) {
            button.selectItem(withTag: selectedIndex)
        }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSPopUpButton, context: Context) -> CGSize? {
        nsView.intrinsicContentSize
    }
}
