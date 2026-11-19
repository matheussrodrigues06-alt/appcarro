import Foundation
import Speech
import AVFoundation
import Observation

/// Transforma a fala em texto (reconhecimento de voz da Apple, em português, no próprio iPhone quando possível).
@MainActor
@Observable
final class SpeechTranscriber {
    private(set) var transcript = ""
    private(set) var isRecording = false
    private(set) var errorMessage: String?

    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "pt-BR"))
    private let audioEngine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?

    func start() async {
        errorMessage = nil
        guard await Self.authorize() else {
            errorMessage = "Para falar com o assistente, permita o microfone e o reconhecimento de fala em Ajustes → Auto Check."
            return
        }
        guard let recognizer, recognizer.isAvailable else {
            errorMessage = "O reconhecimento de voz não está disponível agora. Tente de novo em instantes."
            return
        }
        transcript = ""

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .measurement, options: .duckOthers)
            try session.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            errorMessage = "Não consegui usar o microfone."
            return
        }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        if recognizer.supportsOnDeviceRecognition { request.requiresOnDeviceRecognition = true }
        self.request = request

        Self.installTap(on: audioEngine.inputNode, request: request)
        audioEngine.prepare()
        do {
            try audioEngine.start()
        } catch {
            errorMessage = "Não consegui usar o microfone."
            cleanup()
            return
        }
        isRecording = true

        task = Self.startTask(recognizer: recognizer, request: request) { [weak self] text, finished in
            Task { @MainActor in
                guard let self else { return }
                if let text { self.transcript = text }
                if finished { self.cleanup() }
            }
        }
    }

    /// Para de ouvir; o texto final chega logo em seguida.
    func stop() {
        guard isRecording else { return }
        request?.endAudio()
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        isRecording = false
    }

    private func cleanup() {
        if audioEngine.isRunning { audioEngine.stop() }
        audioEngine.inputNode.removeTap(onBus: 0)
        request = nil
        task = nil
        isRecording = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    // Estes dois rodam fora da tela principal (o áudio chega em outra fila), por isso são "nonisolated".

    nonisolated private static func installTap(on input: AVAudioInputNode, request: SFSpeechAudioBufferRecognitionRequest) {
        let format = input.outputFormat(forBus: 0)
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            request.append(buffer)
        }
    }

    nonisolated private static func startTask(
        recognizer: SFSpeechRecognizer,
        request: SFSpeechAudioBufferRecognitionRequest,
        update: @escaping @Sendable (String?, Bool) -> Void
    ) -> SFSpeechRecognitionTask {
        recognizer.recognitionTask(with: request) { result, error in
            update(result?.bestTranscription.formattedString, error != nil || (result?.isFinal ?? false))
        }
    }

    nonisolated private static func authorize() async -> Bool {
        let speech = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0 == .authorized) }
        }
        guard speech else { return false }
        return await AVAudioApplication.requestRecordPermission()
    }
}
