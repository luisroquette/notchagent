import AVFoundation
import AppKit
import Foundation

/// Synthesized tick layer + the accessibility gate. No audio files.
@MainActor
public final class DelightSounds {
    public struct Tone: Equatable {
        public let frequency: Double
        public let duration: Double
        public let volume: Float

        public init(frequency: Double, duration: Double, volume: Float) {
            self.frequency = frequency
            self.duration = duration
            self.volume = volume
        }
    }

    private let engine = AVAudioEngine()

    public init() {}

    /// Reduce Motion freezes the puppet; VoiceOver silences the sound.
    nonisolated public static func eligibility(enabled: Bool, reduceMotion: Bool, screenReader: Bool) -> Bool {
        enabled && !reduceMotion && !screenReader
    }

    /// Which gestures make noise — silent gestures (blink, lookAtCursor)
    /// stay silent: the sound layer is for confirmations, not chatter.
    nonisolated public static func tone(for gesture: MascotGesture) -> Tone? {
        switch gesture {
        case .nod: Tone(frequency: 880, duration: 0.18, volume: 0.15)
        case .hop: Tone(frequency: 660, duration: 0.14, volume: 0.13)
        case .stretch: Tone(frequency: 300, duration: 0.12, volume: 0.10)
        case .yawn: Tone(frequency: 240, duration: 0.20, volume: 0.09)
        default: nil
        }
    }

    public func play(_ gesture: MascotGesture) {
        guard let tone = Self.tone(for: gesture) else { return }
        playTone(tone)
    }

    /// One synthesized note: sine with soft attack and exponential decay,
    /// played on a throwaway player node and detached when done.
    private func playTone(_ tone: Tone) {
        let sampleRate = 44_100.0
        let frameCount = Int(tone.duration * sampleRate)
        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1) else { return }
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frameCount)) else { return }
        buffer.frameLength = AVAudioFrameCount(frameCount)
        let samples = buffer.floatChannelData![0]
        for i in 0..<frameCount {
            let t = Double(i) / sampleRate
            let env = Float(exp(-6.0 * t / tone.duration)) * Float(min(1, t / 0.01))
            samples[i] = Float(sin(2 * .pi * tone.frequency * t)) * env * tone.volume
        }
        let player = AVAudioPlayerNode()
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)
        player.scheduleBuffer(buffer, at: nil) { [weak self] in
            Task { @MainActor in self?.engine.detach(player) }
        }
        if !engine.isRunning {
            try? engine.start()
        }
        player.play()
    }
}
