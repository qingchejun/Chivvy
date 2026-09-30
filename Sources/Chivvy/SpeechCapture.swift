import AVFoundation
import Speech

/// Records from the microphone and transcribes Chinese speech live.
/// Ends by itself after a pause, or when `stop()` is called.
@MainActor
final class SpeechCapture {
    var onPartial: ((String) -> Void)?
    /// Final transcript (may be empty if nothing was heard)
    var onFinish: ((String) -> Void)?
    var onError: ((String) -> Void)?

    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "zh-CN"))
    /// A fresh engine per session: after the input device changes (e.g. AirPods connect),
    /// a long-lived engine keeps a stale format and installTap crashes on the mismatch
    private var engine: AVAudioEngine?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var silenceTimer: Timer?
    private var finalWaitTimer: Timer?
    private var transcript = ""
    private var finished = true
    /// Late callbacks from a cancelled task must not touch the next session
    private var session = 0

    /// Silence after speech that ends the recording
    private let pauseToFinish: TimeInterval = 2
    /// Give up if nothing at all is said
    private let initialTimeout: TimeInterval = 8
    /// After the audio ends, how long to wait for the recognizer's final (most complete) result
    private let finalResultWait: TimeInterval = 1

    var isRunning: Bool { !finished }

    /// Asks for speech recognition and microphone access; calls back with an error message or nil
    static func requestPermissions(_ completion: @escaping @MainActor (String?) -> Void) {
        SFSpeechRecognizer.requestAuthorization { status in
            guard status == .authorized else {
                Task { @MainActor in completion(L("没有语音识别权限，请在 系统设置 → 隐私与安全性 → 语音识别 中允许 Chivvy。", "Chivvy needs Speech Recognition access. Allow it in System Settings → Privacy & Security → Speech Recognition.")) }
                return
            }
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                Task { @MainActor in
                    completion(granted ? nil : L("没有麦克风权限，请在 系统设置 → 隐私与安全性 → 麦克风 中允许 Chivvy。", "Chivvy needs Microphone access. Allow it in System Settings → Privacy & Security → Microphone."))
                }
            }
        }
    }

    func start() {
        guard finished else { return }  // a second installTap on the same bus crashes

        guard let recognizer, recognizer.isAvailable else {
            onError?(L("语音识别暂时不可用，请检查网络或稍后再试。", "Speech recognition isn't available right now. Check your network or try again later."))
            return
        }

        let engine = AVAudioEngine()
        let format = engine.inputNode.outputFormat(forBus: 0)
        // No microphone (e.g. Mac mini with nothing attached) or input switching: installTap would crash
        guard format.sampleRate > 0, format.channelCount > 0 else {
            onError?(L("没有找到可用的麦克风。", "No microphone found."))
            return
        }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        // Stay on-device (offline, private) when the Chinese model is available
        if recognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true
        }

        engine.inputNode.installTap(onBus: 0, bufferSize: 1024, format: format, block: Self.appendBlock(request))
        do {
            engine.prepare()
            try engine.start()
        } catch {
            engine.inputNode.removeTap(onBus: 0)
            onError?(L("无法打开麦克风：", "Couldn't open the microphone: ") + error.localizedDescription)
            return
        }

        self.engine = engine
        self.request = request
        session += 1
        let current = session
        transcript = ""
        finished = false
        armSilenceTimer(initialTimeout)

        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            let text = result?.bestTranscription.formattedString
            let isFinal = result?.isFinal ?? false
            let message = error?.localizedDescription
            Task { @MainActor in
                guard let self, self.session == current, !self.finished else { return }
                // After endAudio the recognizer can send an empty final result; keep what was heard
                if let text, !text.isEmpty {
                    self.transcript = text
                    self.onPartial?(text)
                    if self.finalWaitTimer == nil {
                        self.armSilenceTimer(self.pauseToFinish)
                    }
                }
                if isFinal {
                    self.finish()
                } else if let message {
                    // Heard something: keep it. Heard nothing: say why (e.g. Siri/dictation turned off)
                    if self.transcript.isEmpty {
                        self.fail(L("语音识别出错：", "Speech recognition error: ") + message)
                    } else {
                        self.finish()
                    }
                }
            }
        }
    }

    /// The tap runs on the audio thread; build it outside the main actor so Swift 6 won't flag it
    private nonisolated static func appendBlock(_ request: SFSpeechAudioBufferRecognitionRequest) -> AVAudioNodeTapBlock {
        { buffer, _ in request.append(buffer) }
    }

    /// Stops listening, then waits briefly for the final result so the last word isn't cut off
    func stop() {
        guard !finished, finalWaitTimer == nil else { return }
        silenceTimer?.invalidate()
        silenceTimer = nil
        stopAudio()
        request?.endAudio()
        finalWaitTimer = Timer.scheduledTimer(withTimeInterval: finalResultWait, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.finish() }
        }
    }

    /// Ends the recording without delivering a result
    func cancel() {
        guard !finished else { return }
        finished = true
        tearDown()
    }

    private func armSilenceTimer(_ interval: TimeInterval) {
        silenceTimer?.invalidate()
        silenceTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.stop() }
        }
    }

    private func finish() {
        guard !finished else { return }
        finished = true
        tearDown()
        onFinish?(transcript)
    }

    private func fail(_ message: String) {
        guard !finished else { return }
        finished = true
        tearDown()
        onError?(message)
    }

    private func stopAudio() {
        guard let engine else { return }
        if engine.isRunning {
            engine.stop()
        }
        engine.inputNode.removeTap(onBus: 0)
        self.engine = nil
    }

    private func tearDown() {
        silenceTimer?.invalidate()
        silenceTimer = nil
        finalWaitTimer?.invalidate()
        finalWaitTimer = nil
        stopAudio()
        request?.endAudio()
        task?.cancel()
        request = nil
        task = nil
    }
}
