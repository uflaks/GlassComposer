import Testing
@testable import MaloryComposer

@Suite("Speech transcript assembly")
struct SpeechTranscriptAssemblerTests {
    @Test("Empty prefix returns spoken text")
    func emptyPrefix() {
        #expect(
            SpeechTranscriptAssembler.compose(
                prefix: "",
                finalized: "Hello ",
                volatile: "world"
            ) == "Hello world"
        )
    }

    @Test("Spoken text is appended to existing composer text")
    func appendsToPrefix() {
        #expect(
            SpeechTranscriptAssembler.compose(
                prefix: "Draft",
                finalized: "one ",
                volatile: "two"
            ) == "Draft one two"
        )
    }

    @Test("Prefix trailing whitespace is preserved without a second space")
    func prefixAlreadyHasSpace() {
        #expect(
            SpeechTranscriptAssembler.compose(
                prefix: "Draft ",
                finalized: "hello",
                volatile: ""
            ) == "Draft hello"
        )
    }

    @Test("Empty spoken text keeps the original prefix")
    func emptySpokenKeepsPrefix() {
        #expect(
            SpeechTranscriptAssembler.compose(
                prefix: "Keep me",
                finalized: "",
                volatile: ""
            ) == "Keep me"
        )
    }
}
