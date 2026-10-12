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
    func attachmentStateMirrorsFailure() {
        let state = ComposerAttachmentState()
        #expect(state.errorMessage == nil)
        state.failure = .notAnImage
        #expect(state.errorMessage == ComposerAttachmentFailure.notAnImage.errorDescription)
        state.clear()
        #expect(state.failure == nil)
    }
}
