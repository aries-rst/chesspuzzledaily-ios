import Foundation

// Port of SoundManager.kt — stub for now: no audio assets are bundled yet. Call sites match
// the Kotlin original exactly so real AVAudioPlayer-backed sounds can drop in later without
// touching GameController.
final class SoundManager {
    var muted: Bool
    init(muted: Bool) { self.muted = muted }
    func click() {}
    func move() {}
    func capture() {}
    func check() {}
    func correct() {}
    func wrong() {}
    func solved() {}
    func failed() {}
}
