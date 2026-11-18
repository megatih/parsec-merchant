// SPDX-License-Identifier: GPL-2.0-or-later
import SwiftUI

/// ART-052: the clock of the slow ambient art on docked screens (Bridge planet, map vortices). Entries fall on whole
/// multiples of `interval` from the reference date, so every surface on this schedule updates on the same frames and the
/// window pays one update pass per frame. Paused (window inactive): one entry, a still frame.
struct AmbientSchedule: TimelineSchedule {
    static let interval: TimeInterval = 1.0 / 5

    var paused: Bool

    func entries(from startDate: Date, mode: TimelineScheduleMode) -> AnyIterator<Date> {
        if paused || mode == .lowFrequency {
            var done = false
            return AnyIterator {
                defer { done = true }
                return done ? nil : startDate
            }
        }
        let step = Self.interval
        var tick = (startDate.timeIntervalSinceReferenceDate / step).rounded(.up)
        return AnyIterator {
            defer { tick += 1 }
            return Date(timeIntervalSinceReferenceDate: tick * step)
        }
    }
}
