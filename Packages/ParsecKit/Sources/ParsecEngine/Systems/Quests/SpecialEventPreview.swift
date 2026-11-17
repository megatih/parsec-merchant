// SPDX-License-Identifier: GPL-2.0-or-later
// The special-event preview for the narrative sheet (docs/specs/UI-ENC.md §15, UI-ENC-105).

/// UI-ENC-105: what the narrative sheet needs to offer the current system's special event.
public struct SpecialEventPreview: Sendable, Equatable {
    public var type: SpecialEventType
    public var price: Int
    public var messageOnly: Bool
    /// The rejection that accepting would return now (nil when Accept can proceed, possibly to a follow-up consent).
    public var blocker: CommandError?
}

public extension GameEngine {
    /// UI-ENC-105: the preview of `state.specialEventAvailable`, or nil when none is offered. The blocker is computed by
    /// performing the accepted command on a copy; follow-up consents (Reactor, Wild) are not blockers.
    var specialEventPreview: SpecialEventPreview? {
        guard let type = state.specialEventAvailable, let spec = state.specialEventSpec(type) else { return nil }
        var probe = self
        let result = probe.perform(.specialEvent, acknowledging: [.acceptSpecialEvent])
        return SpecialEventPreview(type: type, price: spec.price, messageOnly: spec.messageOnly, blocker: result.rejection)
    }
}
