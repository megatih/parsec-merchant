// SPDX-License-Identifier: GPL-2.0-or-later
import SwiftUI

/// UI-BRG-032: what a layout test learns about one identified element.
struct LayoutProbeRecord: Equatable, Sendable {
    /// In the probe root's coordinate space.
    var frame: CGRect
    var enabled: Bool
}

/// Collects the frames of identified elements for the layout tests. Nothing is measured unless an ancestor turns
/// probing on (`layoutProbeRoot`), so the game pays nothing for it.
struct LayoutProbeKey: PreferenceKey {
    static let defaultValue: [String: LayoutProbeRecord] = [:]

    static func reduce(value: inout [String: LayoutProbeRecord], nextValue: () -> [String: LayoutProbeRecord]) {
        value.merge(nextValue()) { first, _ in first }
    }
}

extension EnvironmentValues {
    /// True below a `layoutProbeRoot`.
    @Entry var layoutProbing = false
}

nonisolated enum LayoutProbe {
    static let space = "pm.layoutProbe"
}

private struct ProbedModifier: ViewModifier {
    let identifier: String
    @Environment(\.layoutProbing) private var probing
    @Environment(\.isEnabled) private var isEnabled

    func body(content: Content) -> some View {
        content
            .accessibilityIdentifier(identifier)
            .background {
                if probing {
                    GeometryReader { geo in
                        Color.clear.preference(key: LayoutProbeKey.self,
                                               value: [identifier: LayoutProbeRecord(frame: geo.frame(in: .named(LayoutProbe.space)), enabled: isEnabled)])
                    }
                }
            }
    }
}

extension View {
    /// The element's accessibility identifier, which is also its name in the layout tests.
    func probed(_ identifier: String) -> some View { modifier(ProbedModifier(identifier: identifier)) }

    /// Turns probing on below this view and reports every probed element's frame in this view's coordinates.
    func layoutProbeRoot(_ report: @escaping ([String: LayoutProbeRecord]) -> Void) -> some View {
        environment(\.layoutProbing, true)
            .coordinateSpace(.named(LayoutProbe.space))
            .onPreferenceChange(LayoutProbeKey.self) { value in MainActor.assumeIsolated { report(value) } }
    }
}
