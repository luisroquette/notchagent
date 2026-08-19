import AVFoundation
import AppKit
import Foundation

/// Synthesized tick layer + the accessibility gate. No audio files.
@MainActor
public final class DelightSounds {
    public init() {}

    /// Reduce Motion freezes the puppet; VoiceOver silences the sound.
    nonisolated public static func eligibility(enabled: Bool, reduceMotion: Bool, screenReader: Bool) -> Bool {
        enabled && !reduceMotion && !screenReader
    }

    public func play(_ gesture: MascotGesture) {
        // Task 7 fills the synthesis; kept silent until then.
    }
}
