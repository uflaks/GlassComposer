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

    #if os(iOS)
    /// Like `managed` but with the host's choice of session configuration,
    /// for example `.playAndRecord` so spoken replies keep playing.
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
