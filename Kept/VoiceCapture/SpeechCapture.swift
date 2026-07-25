import AVFAudio
import Foundation
import Speech

// The walled voice module (C9/F9, M5-CONTRACTS §4): produces text, knows nothing else — no
// store, no network. On-device only, unconditionally: the request sets
// requiresOnDeviceRecognition = true and availability gates on supportsOnDeviceRecognition,
// so "voice never leaves your phone" is an architectural fact (source-scan never-test).

nonisolated struct SpeechAvailability: Equatable, Sendable {
    /// Locale + device support for STRICTLY on-device recognition (F9 gates the mic on this).
    let onDeviceSupported: Bool
    let permissionDenied: Bool

    static let unavailable = SpeechAvailability(onDeviceSupported: false, permissionDenied: false)
}

nonisolated protocol SpeechCapturing: Sendable {
    func availability(locale: Locale) async -> SpeechAvailability
    /// Requests mic + speech permission (system prompts). Returns whether both granted.
    func requestPermissions() async -> Bool
    /// Hold began: streams live partial transcripts until stop/cancel.
    func startCapture(partial: @escaping @Sendable (String) -> Void) async throws
    /// Hold released: returns the final transcript (stays editable in the composer — never auto-sends).
    func stopCapture() async -> String
    func cancelCapture() async
}

nonisolated enum SpeechCaptureError: Error {
    case unavailable
    case audioEngineFailed
}

/// Live implementation. Device-verified only (a real mic cannot be unit-tested) — tests drive
/// `FakeSpeechCapture`. API surface verified against the current Speech/AVFAudio headers.
actor OnDeviceSpeechCapture: SpeechCapturing {
    private var audioEngine: AVAudioEngine?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var latestTranscript = ""
    private var finalReceived = false

    func availability(locale: Locale) async -> SpeechAvailability {
        guard let recognizer = SFSpeechRecognizer(locale: locale), recognizer.supportsOnDeviceRecognition else {
            return .unavailable
        }
        let speechDenied = switch SFSpeechRecognizer.authorizationStatus() {
        case .denied, .restricted: true
        default: false
        }
        let micDenied = AVAudioApplication.shared.recordPermission == .denied
        return SpeechAvailability(onDeviceSupported: true, permissionDenied: speechDenied || micDenied)
    }

    func requestPermissions() async -> Bool {
        let speech = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
        guard speech else { return false }
        return await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
    }

    func startCapture(partial: @escaping @Sendable (String) -> Void) async throws {
        guard let recognizer = SFSpeechRecognizer(locale: .current), recognizer.supportsOnDeviceRecognition else {
            throw SpeechCaptureError.unavailable
        }
        latestTranscript = ""
        finalReceived = false

        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .measurement, options: .duckOthers)
        try session.setActive(true, options: .notifyOthersOnDeactivation)

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        // The F3/C2 line, in code: on-device or nothing — never network STT (F9).
        request.requiresOnDeviceRecognition = true
        self.request = request

        let engine = AVAudioEngine()
        let inputNode = engine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            request.append(buffer)
        }
        engine.prepare()
        do {
            try engine.start()
        } catch {
            inputNode.removeTap(onBus: 0)
            throw SpeechCaptureError.audioEngineFailed
        }
        audioEngine = engine

        task = recognizer.recognitionTask(with: request) { [weak self] result, _ in
            guard let result else { return }
            // Only Sendable values cross into the hop below (String + Bool, never the result).
            let text = result.bestTranscription.formattedString
            let isFinal = result.isFinal
            partial(text)
            Task { await self?.noteTranscript(text, isFinal: isFinal) }
        }
    }

    private func noteTranscript(_ text: String, isFinal: Bool) {
        latestTranscript = text
        if isFinal { finalReceived = true }
    }

    func stopCapture() async -> String {
        request?.endAudio()
        audioEngine?.stop()
        audioEngine?.inputNode.removeTap(onBus: 0)
        // Give the recognizer a short grace to deliver the final segment, then take the best we
        // have — the transcript stays editable in the composer either way.
        for _ in 0..<10 where !finalReceived {
            try? await Task.sleep(for: .milliseconds(100))
        }
        task?.cancel()
        tearDown()
        return latestTranscript
    }

    func cancelCapture() async {
        task?.cancel()
        request?.endAudio()
        audioEngine?.stop()
        audioEngine?.inputNode.removeTap(onBus: 0)
        latestTranscript = ""
        tearDown()
    }

    private func tearDown() {
        audioEngine = nil
        request = nil
        task = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}
