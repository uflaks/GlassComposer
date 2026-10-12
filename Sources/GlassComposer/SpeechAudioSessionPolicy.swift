//
//  SpeechAudioSessionPolicy.swift
//  GlassComposer
//

import AVFoundation

/// Who configures the shared `AVAudioSession` while dictation runs. macOS
/// has no audio session, so the policy only matters on iOS.
public struct SpeechAudioSessionPolicy: Sendable, Equatable {
    let managesSession: Bool
    #if os(iOS)
    let category: AVAudioSession.Category
    let mode: AVAudioSession.Mode
    let options: AVAudioSession.CategoryOptions
    #endif

    /// The controller sets a record session while dictating, activates it,
    /// and on stop deactivates it and restores the category, mode and
    /// options it found. Suits hosts that do not play audio themselves.
    public static let managed = SpeechAudioSessionPolicy(managesSession: true)

    /// The controller never touches `AVAudioSession`; the host configures and
    /// activates a session that allows recording before starting dictation.
    public static let hostManaged = SpeechAudioSessionPolicy(managesSession: false)

    /// Session categories a host can ask for without importing iOS-only
    /// types; `managed(category:)` compiles in shared iOS/macOS code.
    public enum Category: Sendable, Equatable {
        /// Input only; other audio in the app stops. The default.
        case record
        /// Keeps the host's playback running (ducked) while dictating.
        case playAndRecord
    }

    /// Like `managed` but with `.playAndRecord` when the host plays audio.
    /// No-op on macOS, which has no audio session.
    public static func managed(category: Category) -> SpeechAudioSessionPolicy {
        #if os(iOS)
        switch category {
        case .record:
            return managed
        case .playAndRecord:
            // Qualified on purpose: an unqualified `.playAndRecord` resolves
            // to this enum and recurses.
            return managed(category: AVAudioSession.Category.playAndRecord)
        }
        #else
        return managed
        #endif
    }

    #if os(iOS)
    /// Full control on iOS: any `AVAudioSession` category, mode and options.
    public static func managed(
        category: AVAudioSession.Category,
        mode: AVAudioSession.Mode = .measurement,
        options: AVAudioSession.CategoryOptions = .duckOthers
    ) -> SpeechAudioSessionPolicy {
        SpeechAudioSessionPolicy(managesSession: true, category: category, mode: mode, options: options)
    }

    init(
        managesSession: Bool,
        category: AVAudioSession.Category = .record,
        mode: AVAudioSession.Mode = .measurement,
        options: AVAudioSession.CategoryOptions = .duckOthers
    ) {
        self.managesSession = managesSession
        self.category = category
        self.mode = mode
        self.options = options
    }
    #else
    init(managesSession: Bool) {
        self.managesSession = managesSession
    }
    #endif
}
