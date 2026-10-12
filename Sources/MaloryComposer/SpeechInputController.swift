//
//  SpeechInputController.swift
//  MaloryComposer
//

import AVFoundation
import Observation
import Speech

/// On-device composer dictation via the iOS 26 / macOS 26 `SpeechAnalyzer`.
///
/// Hosts need `NSMicrophoneUsageDescription` and
/// `NSSpeechRecognitionUsageDescription` in their Info.plist. The previous
/// `SFSpeechRecognizer` + `AVAudioEngine` path installed the mic tap before
/// activating the audio session (invalid 0 Hz format) and silently no-op'd
/// when `SFSpeechRecognizer()` was nil for the device locale.
@available(iOS 26.0, macOS 26.0, *)
@MainActor
@Observable
public final class SpeechInputController {
    public private(set) var isRecording = false
    public var errorMessage: String?

    private let audioEngine = AVAudioEngine()
    private var analyzer: SpeechAnalyzer?
    private var inputBuilder: AsyncStream<AnalyzerInput>.Continuation?
    private var resultsTask: Task<Void, Never>?
    private var tapInstalled = false
    private var startGeneration = 0
    private var draftPrefix = ""
    private var finalizedText = ""
    private var volatileText = ""
    private var onTranscript: ((String) -> Void)?

    public init() {}

    /// Starts dictation, or stops it if already recording. While recording,
    /// `onTranscript` receives `existingText` plus everything spoken so far.
    public func toggleRecording(existingText: String = "", onTranscript: @escaping (String) -> Void) {
        if isRecording {
            Task { await stopRecording() }
        } else {
            Task { await startRecording(existingText: existingText, onTranscript: onTranscript) }
        }
    }

    private func startRecording(existingText: String, onTranscript: @escaping (String) -> Void) async {
        await stopRecording()

        // stopRecording bumps the generation, so a stop (or another start) that
        // interleaves with any await below makes checkStillCurrent throw and this
        // superseded start abandons the session instead of leaving the mic hot.
        let generation = startGeneration

        errorMessage = nil
        draftPrefix = existingText
        finalizedText = ""
        volatileText = ""
        self.onTranscript = onTranscript
        isRecording = true

        do {
            let micAllowed = await requestMicrophoneAuthorization()
            try checkStillCurrent(generation)
            guard micAllowed else {
                await stopRecording()
                return
            }
            let speechAllowed = await requestSpeechAuthorization()
            try checkStillCurrent(generation)
            guard speechAllowed else {
                await stopRecording()
                return
            }
            try await startAnalyzerSession(generation: generation)
        } catch is CancellationError {
            // The superseding stopRecording already tore down everything this
            // start had registered; touching state here would clobber a newer
            // session.
        } catch let failure as SpeechInputFailure {
            guard startGeneration == generation else { return }
            errorMessage = failure.userMessage
            await stopRecording()
        } catch {
            guard startGeneration == generation else { return }
            errorMessage = SpeechInputFailure.audioSetupFailed.userMessage
            await stopRecording()
        }
    }

    /// Throws when a stop or newer start superseded the start that captured
    /// `generation`, so a resumed await must not touch shared session state.
    private func checkStillCurrent(_ generation: Int) throws {
        guard startGeneration == generation else { throw CancellationError() }
    }

    private func startAnalyzerSession(generation: Int) async throws {
        let module: any SpeechModule

        if let speechLocale = await SpeechTranscriber.supportedLocale(equivalentTo: .current) {
            let transcriber = SpeechTranscriber(
                locale: speechLocale,
                transcriptionOptions: [],
                reportingOptions: [.volatileResults],
                attributeOptions: []
            )
            try await ensureModelInstalled(
                for: transcriber,
                installedLocales: await SpeechTranscriber.installedLocales,
                locale: speechLocale
            )
            try checkStillCurrent(generation)
            listenForResults(transcriber.results, generation: generation)
            module = transcriber
        } else if let dictationLocale = await DictationTranscriber.supportedLocale(equivalentTo: .current) {
            let transcriber = DictationTranscriber(
                locale: dictationLocale,
                preset: .progressiveShortDictation
            )
            try await ensureModelInstalled(
                for: transcriber,
                installedLocales: await DictationTranscriber.installedLocales,
                locale: dictationLocale
            )
            try checkStillCurrent(generation)
            listenForResults(transcriber.results, generation: generation)
            module = transcriber
        } else {
            throw SpeechInputFailure.localeNotSupported
        }

        let analyzer = SpeechAnalyzer(modules: [module])
        self.analyzer = analyzer

        guard let analyzerFormat = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [module]) else {
            throw SpeechInputFailure.audioSetupFailed
        }
        try checkStillCurrent(generation)

        let (sequence, builder) = AsyncStream<AnalyzerInput>.makeStream()
        inputBuilder = builder
        try await analyzer.start(inputSequence: sequence)
        try checkStillCurrent(generation)

        try activateAudioSession()
        try installMicrophoneTap(targetFormat: analyzerFormat, builder: builder)
        audioEngine.prepare()
        try audioEngine.start()
    }

    private func listenForResults<Results>(
        _ results: Results,
        generation: Int
    ) where Results: AsyncSequence, Results.Element: LiveSpeechResult {
        resultsTask = Task { [weak self] in
            guard let self else { return }
            do {
                for try await result in results {
                    self.apply(result: result)
                }
            } catch {
                guard !Task.isCancelled, self.startGeneration == generation else { return }
                self.errorMessage = SpeechInputFailure.audioSetupFailed.userMessage
                await self.stopRecording()
            }
        }
    }

    private func apply(result: some LiveSpeechResult) {
        let piece = String(result.text.characters)
        if result.isFinal {
            finalizedText += piece
            volatileText = ""
        } else {
            volatileText = piece
        }
        onTranscript?(
            SpeechTranscriptAssembler.compose(
                prefix: draftPrefix,
                finalized: finalizedText,
                volatile: volatileText
            )
        )
    }

    private func ensureModelInstalled(
        for module: some SpeechModule,
        installedLocales: [Locale],
        locale: Locale
    ) async throws {
        let installed = Set(installedLocales.map { $0.identifier(.bcp47) })
        if installed.contains(locale.identifier(.bcp47)) {
            return
        }

        guard let request = try await AssetInventory.assetInstallationRequest(supporting: [module]) else {
            throw SpeechInputFailure.assetUnavailable
        }
        try await request.downloadAndInstall()
    }

    /// iOS routes the mic through `AVAudioSession`; macOS has no session, the
    /// engine's input node is enough.
    private func activateAudioSession() throws {
        #if os(iOS)
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .measurement, options: .duckOthers)
        try session.setActive(true, options: .notifyOthersOnDeactivation)
        #endif
    }

    private func deactivateAudioSession() {
        #if os(iOS)
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        #endif
    }

    private func installMicrophoneTap(
        targetFormat: AVAudioFormat,
        builder: AsyncStream<AnalyzerInput>.Continuation
    ) throws {
        let input = audioEngine.inputNode
        let micFormat = input.outputFormat(forBus: 0)
        guard micFormat.sampleRate > 0, micFormat.channelCount > 0 else {
            throw SpeechInputFailure.audioSetupFailed
        }

        let converter = SpeechAudioBufferConverter()
        input.installTap(onBus: 0, bufferSize: 4096, format: micFormat) { buffer, _ in
            guard let converted = try? converter.convert(buffer, to: targetFormat) else { return }
            builder.yield(AnalyzerInput(buffer: converted))
        }
        tapInstalled = true
    }

    private func stopRecording() async {
        startGeneration += 1

        if audioEngine.isRunning {
            audioEngine.stop()
        }
        if tapInstalled {
            audioEngine.inputNode.removeTap(onBus: 0)
            tapInstalled = false
        }

        inputBuilder?.finish()
        inputBuilder = nil

        try? await analyzer?.finalizeAndFinishThroughEndOfInput()
        analyzer = nil

        resultsTask?.cancel()
        resultsTask = nil
        onTranscript = nil
        isRecording = false

        deactivateAudioSession()
    }

    private func requestMicrophoneAuthorization() async -> Bool {
        let allowed = await AVAudioApplication.requestRecordPermission()
        guard allowed else {
            errorMessage = SpeechInputFailure.microphoneDenied.userMessage
            return false
        }
        return true
    }

    private func requestSpeechAuthorization() async -> Bool {
        let status = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
        guard status == .authorized else {
            errorMessage = SpeechInputFailure.speechDenied.userMessage
            return false
        }
        return true
    }
}

@available(iOS 26.0, macOS 26.0, *)
private protocol LiveSpeechResult: SpeechModuleResult {
    var text: AttributedString { get }
}

@available(iOS 26.0, macOS 26.0, *)
extension SpeechTranscriber.Result: LiveSpeechResult {}

@available(iOS 26.0, macOS 26.0, *)
extension DictationTranscriber.Result: LiveSpeechResult {}

private enum SpeechInputFailure: Error {
    case microphoneDenied
    case speechDenied
    case localeNotSupported
    case assetUnavailable
    case audioSetupFailed

    var userMessage: String {
        switch self {
        case .microphoneDenied:
            return "Microphone permission is required."
        case .speechDenied:
            return "Speech recognition permission is required."
        case .localeNotSupported:
            return "Speech recognition is not available for this language."
        case .assetUnavailable:
            return "Could not download the on-device speech model. Check your connection and try again."
        case .audioSetupFailed:
            return "Could not start speech recognition."
        }
    }
}

/// Converts mic buffers to the PCM format `SpeechAnalyzer` requested.
/// Create one per capture session and call only from the audio tap thread.
private final class SpeechAudioBufferConverter: @unchecked Sendable {
    enum Failure: Error {
        case cannotCreateConverter
        case cannotCreateBuffer
        case conversionFailed
    }

    private var converter: AVAudioConverter?

    func convert(_ buffer: AVAudioPCMBuffer, to format: AVAudioFormat) throws -> AVAudioPCMBuffer {
        let inputFormat = buffer.format
        guard inputFormat != format else { return buffer }

        if converter == nil || converter?.outputFormat != format {
            converter = AVAudioConverter(from: inputFormat, to: format)
            converter?.primeMethod = .none
        }
        guard let converter else { throw Failure.cannotCreateConverter }

        let ratio = converter.outputFormat.sampleRate / converter.inputFormat.sampleRate
        let capacity = AVAudioFrameCount((Double(buffer.frameLength) * ratio).rounded(.up))
        guard let output = AVAudioPCMBuffer(pcmFormat: converter.outputFormat, frameCapacity: capacity) else {
            throw Failure.cannotCreateBuffer
        }

        var nsError: NSError?
        var fed = false
        let status = converter.convert(to: output, error: &nsError) { _, statusPtr in
            defer { fed = true }
            statusPtr.pointee = fed ? .noDataNow : .haveData
            return fed ? nil : buffer
        }
        guard status != .error else { throw Failure.conversionFailed }
        return output
    }
}
