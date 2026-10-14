//
//  SpeechInputController.swift
//  GlassComposer
//

import AVFoundation
import Observation
import Speech

/// On-device composer dictation via the iOS 26 / macOS 26 `SpeechAnalyzer`.
///
/// Hosts need `NSMicrophoneUsageDescription` and
/// `NSSpeechRecognitionUsageDescription` in their Info.plist. Dictation stops
/// by itself when the system interrupts audio (a call, Siri) or the audio
/// route changes under the engine, so `isRecording` never lies.
@MainActor
@Observable
public final class SpeechInputController {
    /// Where dictation is: `preparing` covers permission prompts, a model
    /// download and audio setup; `recording` means audio is flowing.
    public enum Phase: Sendable, Equatable {
        case idle
        case preparing
        case recording
    }

    public private(set) var phase: Phase = .idle

    /// Audio is flowing to the recognizer. False while `preparing`.
    public var isRecording: Bool { phase == .recording }

    /// Permissions, model download or audio setup are in progress.
    public var isPreparing: Bool { phase == .preparing }

    /// The language to transcribe. Read when dictation starts, so a host
    /// with a language picker can change it between recordings.
    public var locale: Locale

    /// Why the last start failed, or nil. Set it to nil to dismiss. Inspect
    /// the case to react (open Settings on `.microphoneDenied`, say).
    public var failure: SpeechInputFailure?

    /// `failure` as user-facing text.
    public var errorMessage: String? { failure?.errorDescription }

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
    private let audioSessionPolicy: SpeechAudioSessionPolicy
    private var systemObservers: [any NSObjectProtocol] = []
    #if os(iOS)
    private var restoredSessionConfiguration: AudioSessionConfiguration?
    #endif

    /// - Parameters:
    ///   - locale: The language to transcribe. Defaults to the device locale.
    ///   - audioSessionPolicy: Whether this controller or the host configures
    ///     `AVAudioSession` on iOS. Defaults to `.managed`.
    public init(locale: Locale = .current, audioSessionPolicy: SpeechAudioSessionPolicy = .managed) {
        self.locale = locale
        self.audioSessionPolicy = audioSessionPolicy
    }

    isolated deinit {
        // A host that drops the controller mid-recording (its view went away)
        // must not leave the microphone hot. Only synchronous teardown is
        // possible here; the analyzer is released without finalizing.
        for observer in systemObservers {
            NotificationCenter.default.removeObserver(observer)
        }
        if tapInstalled {
            audioEngine.inputNode.removeTap(onBus: 0)
        }
        if audioEngine.isRunning {
            audioEngine.stop()
        }
        inputBuilder?.finish()
        resultsTask?.cancel()
        deactivateAudioSession()
    }

    /// Starts dictation, or stops it if already preparing or recording. While
    /// recording, `onTranscript` receives `existingText` plus everything
    /// spoken so far, replacing the field's text each time; edits the user
    /// makes during dictation are overwritten by the next result.
    public func toggleRecording(existingText: String = "", onTranscript: @escaping (String) -> Void) {
        if phase == .idle {
            start(existingText: existingText, onTranscript: onTranscript)
        } else {
            stop()
        }
    }

    /// Starts dictation, superseding any start or recording in progress.
    public func start(existingText: String = "", onTranscript: @escaping (String) -> Void) {
        // Flip synchronously so a second tap before the Task runs sees the
        // start and stops it instead of starting again.
        phase = .preparing
        Task { await startRecording(existingText: existingText, onTranscript: onTranscript) }
    }

    /// Stops dictation if it is preparing or recording. Safe to call on
    /// send, on disappear, or when the scene goes to the background.
    public func stop() {
        guard phase != .idle else { return }
        Task { await stopRecording() }
    }

    private func startRecording(existingText: String, onTranscript: @escaping (String) -> Void) async {
        await stopRecording()

        // stopRecording bumps the generation, so a stop (or another start) that
        // interleaves with any await below makes checkStillCurrent throw and this
        // superseded start abandons the session instead of leaving the mic hot.
        let generation = startGeneration

        failure = nil
        draftPrefix = existingText
        finalizedText = ""
        volatileText = ""
        self.onTranscript = onTranscript
        phase = .preparing

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
            self.failure = failure
            await stopRecording()
        } catch {
            guard startGeneration == generation else { return }
            failure = .audioSetupFailed
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

        if let speechLocale = await SpeechTranscriber.supportedLocale(equivalentTo: locale) {
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
        } else if let dictationLocale = await DictationTranscriber.supportedLocale(equivalentTo: locale) {
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

        // ~5 s of 4096-frame buffers at 48 kHz; a stalled analyzer drops the
        // oldest audio instead of growing without bound.
        let (sequence, builder) = AsyncStream<AnalyzerInput>.makeStream(bufferingPolicy: .bufferingNewest(64))
        inputBuilder = builder
        try await analyzer.start(inputSequence: sequence)
        try checkStillCurrent(generation)

        try activateAudioSession()
        try installMicrophoneTap(targetFormat: analyzerFormat, builder: builder)
        audioEngine.prepare()
        try audioEngine.start()
        observeSystemAudioChanges()
        phase = .recording
    }

    /// Stops dictation when the system takes the audio away: an interruption
    /// (iOS) or a configuration change such as the input route disappearing
    /// (both platforms). The engine is already stopped by then; this resets
    /// state so the UI follows.
    private func observeSystemAudioChanges() {
        let center = NotificationCenter.default
        systemObservers.append(center.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: audioEngine, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in await self?.stopRecording() }
        })
        #if os(iOS)
        systemObservers.append(center.addObserver(
            forName: AVAudioSession.interruptionNotification, object: AVAudioSession.sharedInstance(), queue: .main
        ) { [weak self] notification in
            guard let raw = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                  AVAudioSession.InterruptionType(rawValue: raw) == .began else { return }
            Task { @MainActor in await self?.stopRecording() }
        })
        #endif
    }

    private func stopObservingSystemAudioChanges() {
        for observer in systemObservers {
            NotificationCenter.default.removeObserver(observer)
        }
        systemObservers.removeAll()
    }

    private func listenForResults<Results>(
        _ results: Results,
        generation: Int
    ) where Results: AsyncSequence, Results.Element: LiveSpeechResult {
        // Hold `self` only per result: a strong capture across the loop would
        // keep the controller (and the hot mic) alive after its host let go.
        resultsTask = Task { [weak self] in
            do {
                for try await result in results {
                    guard let self else { return }
                    self.apply(result: result)
                }
            } catch {
                guard let self, !Task.isCancelled, self.startGeneration == generation else { return }
                self.failure = .audioSetupFailed
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

        // A nil request means the assets are already installed; the call
        // throws when the module is unsupported or no locale slot is free.
        do {
            guard let request = try await AssetInventory.assetInstallationRequest(supporting: [module]) else {
                return
            }
            try await request.downloadAndInstall()
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw SpeechInputFailure.assetUnavailable
        }
    }

    /// iOS routes the mic through `AVAudioSession`; macOS has no session, the
    /// engine's input node is enough. Under `.hostManaged` the host has
    /// already set up a session that can record.
    private func activateAudioSession() throws {
        #if os(iOS)
        guard audioSessionPolicy.managesSession else { return }
        let session = AVAudioSession.sharedInstance()
        restoredSessionConfiguration = AudioSessionConfiguration(
            category: session.category, mode: session.mode, options: session.categoryOptions
        )
        try session.setCategory(audioSessionPolicy.category, mode: audioSessionPolicy.mode, options: audioSessionPolicy.options)
        try session.setActive(true, options: .notifyOthersOnDeactivation)
        #endif
    }

    /// Undoes `activateAudioSession`, and nothing else: a stop that never
    /// activated (permission denied, or the stop before every start) must not
    /// deactivate the host's session or tell other apps to resume.
    private func deactivateAudioSession() {
        #if os(iOS)
        guard audioSessionPolicy.managesSession, let previous = restoredSessionConfiguration else { return }
        restoredSessionConfiguration = nil
        let session = AVAudioSession.sharedInstance()
        try? session.setActive(false, options: .notifyOthersOnDeactivation)
        try? session.setCategory(previous.category, mode: previous.mode, options: previous.options)
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
        stopObservingSystemAudioChanges()

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
        phase = .idle

        deactivateAudioSession()
    }

    private func requestMicrophoneAuthorization() async -> Bool {
        let allowed = await AVAudioApplication.requestRecordPermission()
        guard allowed else {
            failure = .microphoneDenied
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
            failure = .speechDenied
            return false
        }
        return true
    }
}

private protocol LiveSpeechResult: SpeechModuleResult {
    var text: AttributedString { get }
}

extension SpeechTranscriber.Result: LiveSpeechResult {}

extension DictationTranscriber.Result: LiveSpeechResult {}

#if os(iOS)
/// What the host had on `AVAudioSession` before dictation, put back after.
private struct AudioSessionConfiguration {
    let category: AVAudioSession.Category
    let mode: AVAudioSession.Mode
    let options: AVAudioSession.CategoryOptions
}
#endif

/// Why dictation could not start or stopped on its own.
public enum SpeechInputFailure: Error, LocalizedError, Equatable, Sendable {
    /// The user declined microphone access.
    case microphoneDenied
    /// The user declined speech recognition.
    case speechDenied
    /// Neither `SpeechTranscriber` nor `DictationTranscriber` supports the
    /// requested locale.
    case localeNotSupported
    /// The on-device model for the locale is missing and could not be
    /// downloaded.
    case assetUnavailable
    /// The audio engine, session or analyzer failed to start, or the results
    /// stream ended with an error.
    case audioSetupFailed

    public var errorDescription: String? {
        switch self {
        case .microphoneDenied:
            return localized("Microphone permission is required.")
        case .speechDenied:
            return localized("Speech recognition permission is required.")
        case .localeNotSupported:
            return localized("Speech recognition is not available for this language.")
        case .assetUnavailable:
            return localized("Could not download the on-device speech model. Check your connection and try again.")
        case .audioSetupFailed:
            return localized("Could not start speech recognition.")
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
        // The input block is @Sendable, but AVAudioConverter calls it synchronously here.
        nonisolated(unsafe) var fed = false
        let status = converter.convert(to: output, error: &nsError) { _, statusPtr in
            defer { fed = true }
            statusPtr.pointee = fed ? .noDataNow : .haveData
            return fed ? nil : buffer
        }
        guard status != .error else { throw Failure.conversionFailed }
        return output
    }
}
