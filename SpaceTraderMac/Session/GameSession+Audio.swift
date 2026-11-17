// SPDX-License-Identifier: GPL-2.0-or-later
import Foundation
import ParsecAudio

/// AUD-036 / AUD-038 / AUD-040: where the session reaches its audio and haptics services besides `apply`.
extension GameSession {
    /// AUD-038: the music mood follows the detail area.
    var musicMood: MusicMood {
        MusicMood.derive(detailMode: DetailMode.derive(state: state, playback: transitPlayback, selected: selectedSection))
    }

    func updateMusicMood() {
        audio.setMood(musicMood)
    }

    /// AUD-030: the newspaper rustles when its sheet appears.
    func presentationAudio(old: Presentation?) {
        guard case .sheet(.newspaper) = presentation else { return }
        if case .sheet(.newspaper) = old { return }
        audio.play(app: .newspaper)
    }

    /// AUD-030 / UI-ENC-026: a clicked tribble squeaks (its twin is the wiggle).
    func tribbleClicked() {
        audio.play(app: .tribble)
    }

    /// AUD-040: quantity snaps and full dock sliders.
    func performHaptic(_ haptic: AppHaptic) {
        haptics.perform(app: haptic)
    }

    /// AUD-042: Settings › Sound › Play Test Sound.
    func playTestSound() {
        audio.play(app: .testSound)
    }
}
