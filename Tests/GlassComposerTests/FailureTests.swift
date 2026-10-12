import Testing
@testable import GlassComposer

@Suite("Failure descriptions")
struct FailureTests {
    @Test("Every speech failure has user-facing text")
    func speechFailuresDescribeThemselves() {
        let all: [SpeechInputFailure] = [.microphoneDenied, .speechDenied, .localeNotSupported, .assetUnavailable, .audioSetupFailed]
        for failure in all {
            #expect(failure.errorDescription?.isEmpty == false)
        }
    }

    @Test("Every attachment failure has user-facing text")
    func attachmentFailuresDescribeThemselves() {
        for failure in [ComposerAttachmentFailure.unavailable, .notAnImage] {
            #expect(failure.errorDescription?.isEmpty == false)
        }
    }

    @Test("errorMessage mirrors failure on the attachment state")
    @MainActor
    func attachmentStateMirrorsFailure() async {
        let state = ComposerAttachmentState()
        #expect(state.errorMessage == nil)
        #expect(!state.isLoading)
        state.failure = .notAnImage
        #expect(state.errorMessage == ComposerAttachmentFailure.notAnImage.errorDescription)
        // Deselecting clears the stale error as well as the attachment.
        await state.loadSelectedPhoto()
        #expect(state.failure == nil)
        state.clear()
        #expect(state.failure == nil)
        #expect(!state.isLoading)
    }
}

@Suite("Audio session policy")
struct SpeechAudioSessionPolicyTests {
    @Test("Presets differ in whether the controller owns the session")
    func presets() {
        #expect(SpeechAudioSessionPolicy.managed.managesSession)
        #expect(!SpeechAudioSessionPolicy.hostManaged.managesSession)
        #expect(SpeechAudioSessionPolicy.managed != .hostManaged)
        #expect(SpeechAudioSessionPolicy.managed(category: .playAndRecord).managesSession)
        #expect(SpeechAudioSessionPolicy.managed(category: .record) == .managed)
    }
}

@Suite("Localization")
struct LocalizationTests {
    @Test("Built-in strings resolve through the package catalog")
    func catalogResolves() {
        #expect(localized("Send") == "Send")
        #expect(SpeechInputFailure.microphoneDenied.errorDescription == "Microphone permission is required.")
    }
}
