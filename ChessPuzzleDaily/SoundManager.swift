import Foundation
import AVFoundation

/// Procedural sound (port of SoundManager.kt / js/sound.js): every effect is synthesized into
/// PCM at launch and played through AVAudioEngine — no bundled audio files, no licensing. Each
/// named effect is pre-rendered once into an AVAudioPCMBuffer and replayed on its own player
/// node, mirroring the Kotlin original's one-AudioTrack-per-effect, stop-and-restart approach.
final class SoundManager {
    var muted: Bool

    private let rate: Double = 22050
    private let engine = AVAudioEngine()
    private let format: AVAudioFormat
    private var buffers: [String: AVAudioPCMBuffer] = [:]
    private var players: [String: AVAudioPlayerNode] = [:]

    private enum Wave { case sine, triangle, sawtooth }

    /// Scratch PCM canvas for one effect; mirrors Kotlin's private `Mix` helper.
    private final class Mix {
        let rate: Double
        var buf: [Double]
        init(rate: Double, seconds: Double) {
            self.rate = rate
            buf = [Double](repeating: 0, count: max(1, Int(rate * seconds)))
        }

        func tone(_ freq: Double, _ dur: Double, _ type: Wave = .sine, _ vol: Double = 0.18, _ delay: Double = 0.0, _ glide: Double = 0.0) {
            let start = Int(delay * rate)
            let n = Int(dur * rate)
            var phase = 0.0
            for i in 0..<n {
                let idx = start + i
                if idx >= buf.count { break }
                let t = Double(i) / rate
                let f = glide > 0 ? freq * pow(glide, t / dur) : freq
                phase += 2 * Double.pi * f / rate
                let w: Double
                switch type {
                case .triangle: w = 2 / Double.pi * asin(sin(phase))
                case .sawtooth: w = ((phase / (2 * Double.pi)).truncatingRemainder(dividingBy: 1.0)) * 2 - 1
                case .sine: w = sin(phase)
                }
                let env = t < 0.008 ? t / 0.008 : exp(-6.0 * (t - 0.008) / dur)
                buf[idx] += w * env * vol
            }
        }

        func knock(_ vol: Double = 0.35, _ delay: Double = 0.0) {
            let start = Int(delay * rate)
            let n = Int(0.06 * rate)
            var y1 = 0.0, y2 = 0.0
            for i in 0..<n { // noise burst through a crude resonant filter (~1.1 kHz)
                let idx = start + i
                if idx >= buf.count { break }
                let x = Double.random(in: -1...1) * pow(1 - Double(i) / Double(n), 6)
                let y = x + 1.6 * y1 - 0.8 * y2
                y2 = y1; y1 = y
                buf[idx] += y * vol * 0.25
            }
            tone(180.0, 0.07, .sine, vol * 0.5, delay)
        }
    }

    init(muted: Bool) {
        self.muted = muted
        format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: rate, channels: 1, interleaved: false)!

        // Ambient: mixes with any other audio and respects the silent switch, same spirit as
        // Kotlin's USAGE_GAME/CONTENT_TYPE_SONIFICATION attributes.
        try? AVAudioSession.sharedInstance().setCategory(.ambient, options: [.mixWithOthers])
        try? AVAudioSession.sharedInstance().setActive(true)

        make("click", 0.08) { $0.tone(660, 0.05, .triangle, 0.08) }
        make("move", 0.12) { $0.knock(0.35) }
        make("capture", 0.16) { $0.knock(0.45); $0.knock(0.3, 0.05) }
        make("check", 0.25) { $0.knock(0.4); $0.tone(880, 0.18, .triangle, 0.1, 0.03) }
        make("correct", 0.3) { $0.tone(660, 0.12, .sine, 0.14); $0.tone(990, 0.18, .sine, 0.12, 0.08) }
        make("wrong", 0.3) { $0.tone(220, 0.25, .sawtooth, 0.07, 0.0, 0.7) }
        make("solved", 0.7) { m in
            for (i, f) in [523.0, 659.0, 784.0, 1047.0].enumerated() { m.tone(f, 0.35, .triangle, 0.13, Double(i) * 0.09) }
        }
        make("failed", 0.7) { m in
            for (i, f) in [392.0, 330.0, 262.0].enumerated() { m.tone(f, 0.3, .sine, 0.12, Double(i) * 0.12) }
        }

        for name in buffers.keys {
            let node = AVAudioPlayerNode()
            engine.attach(node)
            engine.connect(node, to: engine.mainMixerNode, format: format)
            players[name] = node
        }
        try? engine.start()
        for node in players.values { node.play() }
    }

    private func make(_ name: String, _ seconds: Double, _ block: (Mix) -> Void) {
        let m = Mix(rate: rate, seconds: seconds)
        block(m)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(m.buf.count)) else { return }
        buffer.frameLength = buffer.frameCapacity
        if let channel = buffer.floatChannelData {
            for i in 0..<m.buf.count { channel[0][i] = Float(max(-1.0, min(1.0, m.buf[i]))) }
        }
        buffers[name] = buffer
    }

    private func play(_ name: String) {
        if muted { return }
        guard let buffer = buffers[name], let node = players[name] else { return }
        if !engine.isRunning { try? engine.start() }
        node.stop()
        node.scheduleBuffer(buffer, at: nil, options: .interrupts, completionHandler: nil)
        node.play()
    }

    func click() { play("click") }
    func move() { play("move") }
    func capture() { play("capture") }
    func check() { play("check") }
    func correct() { play("correct") }
    func wrong() { play("wrong") }
    func solved() { play("solved") }
    func failed() { play("failed") }
}
