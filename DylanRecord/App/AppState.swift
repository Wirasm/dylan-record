import AVFoundation
import Foundation
import SwiftUI

@MainActor
@Observable
final class AppState {
    enum RecordingState: Equatable {
        case idle
        case recording(startDate: Date)
        case saving(segmentCount: Int)

        static func == (lhs: RecordingState, rhs: RecordingState) -> Bool {
            switch (lhs, rhs) {
            case (.idle, .idle): return true
            case (.recording, .recording): return true
            case (.saving, .saving): return true
            default: return false
            }
        }
    }

    var state: RecordingState = .idle
    var elapsedTime: TimeInterval = 0
    var lastError: String?

    var isRecording: Bool {
        if case .recording = state { return true }
        return false
    }

    var isSaving: Bool {
        if case .saving = state { return true }
        return false
    }

    var recordingStartDate: Date? {
        if case .recording(let date) = state { return date }
        return nil
    }

    // Settings
    var deepgramApiKey: String {
        get { UserDefaults.standard.string(forKey: "deepgramApiKey") ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: "deepgramApiKey") }
    }

    var obsidianVaultPath: String {
        get { UserDefaults.standard.string(forKey: "obsidianVaultPath") ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: "obsidianVaultPath") }
    }

    var language: String {
        get { UserDefaults.standard.string(forKey: "language") ?? "multi" }
        set { UserDefaults.standard.set(newValue, forKey: "language") }
    }

    var keywordsText: String {
        get { UserDefaults.standard.string(forKey: "keywords") ?? Self.defaultKeywords }
        set { UserDefaults.standard.set(newValue, forKey: "keywords") }
    }

    private static let defaultKeywords = """
    Sasha
    Archon
    Claude Code
    Claude
    Anthropic
    Cursor
    Obsidian
    Deepgram
    Rasmus
    Peter
    Tove
    push
    BTW
    PR
    deploy
    staging
    production
    API
    webhook
    """

    static let supportedLanguages: [(code: String, name: String)] = [
        ("multi", "Auto-detect (multilingual)"),
        ("sv", "Svenska"),
        ("en", "English"),
        ("da", "Dansk"),
        ("no", "Norsk"),
        ("de", "Deutsch"),
        ("fr", "Français"),
        ("es", "Español"),
        ("nl", "Nederlands"),
        ("ja", "日本語"),
    ]

    // Recording pipeline
    private var micCapture: MicCapture?
    private var systemCapture: SystemAudioCapture?
    private var combiner: AudioCombiner?
    private var deepgramClient: DeepgramClient?
    private(set) var transcriptManager = TranscriptManager()
    private var silenceDetector: SilenceDetector?
    private var elapsedTimer: Timer?
    private var hotkeyMonitor: Any?
    private let calendarService = CalendarService()

    func setupHotkey() {
        hotkeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.modifierFlags.contains([.command, .shift]) else { return }

            switch event.keyCode {
            case 15: // ⌘⇧R — toggle recording
                Task { @MainActor in self?.toggleRecording() }
            case 18: // ⌘⇧1 — Svenska
                Task { @MainActor in self?.language = "sv" }
            case 19: // ⌘⇧2 — English
                Task { @MainActor in self?.language = "en" }
            default:
                break
            }
        }
    }

    func toggleRecording() {
        if isRecording {
            stopRecording()
        } else {
            startRecording()
        }
    }

    func startRecording() {
        guard !deepgramApiKey.isEmpty else {
            lastError = "Set your Deepgram API key in Settings."
            return
        }

        lastError = nil
        let now = Date()
        state = .recording(startDate: now)
        elapsedTime = 0

        // Start elapsed timer
        elapsedTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self, let start = self.recordingStartDate else { return }
            self.elapsedTime = Date().timeIntervalSince(start)
        }

        // Clear previous transcript
        transcriptManager.clear()

        // Set up audio combiner
        let combiner = AudioCombiner()
        self.combiner = combiner

        // Set up Deepgram client (2-channel multichannel)
        let lang = language == "multi" ? nil : language
        let keyterms = loadKeywords()
        let client = DeepgramClient(apiKey: deepgramApiKey, channelCount: 2, language: lang, keyterms: keyterms)
        client.onTranscript = { response in
            Task { @MainActor [weak self] in
                self?.transcriptManager.handleResponse(response)
                // Notify silence detector that speech was detected
                if response.isFinal,
                   let transcript = response.channel.alternatives.first?.transcript,
                   !transcript.trimmingCharacters(in: .whitespaces).isEmpty {
                    self?.silenceDetector?.speechDetected()
                }
            }
        }
        client.onError = { error in
            print("[AppState] Deepgram error: \(error.localizedDescription)")
            Task { @MainActor [weak self] in
                self?.lastError = "Deepgram: \(error.localizedDescription)"
            }
        }
        self.deepgramClient = client

        // Wire combiner output to Deepgram
        combiner.onInterleavedData = { [weak client] data in
            client?.sendAudio(data)
        }

        // Start mic capture
        let mic = MicCapture()
        mic.onAudioData = { [weak combiner] data in
            combiner?.appendMicAudio(data)
        }
        self.micCapture = mic

        // Start system audio capture
        let sys = SystemAudioCapture()
        sys.onAudioData = { [weak combiner] data in
            combiner?.appendSystemAudio(data)
        }
        self.systemCapture = sys

        // Connect and start everything
        client.connect()
        combiner.start()

        do {
            try mic.start()
        } catch {
            print("[AppState] Mic start error: \(error)")
            lastError = "Mic: \(error.localizedDescription)"
        }

        do {
            try sys.start()
        } catch {
            print("[AppState] System audio error: \(error)")
            lastError = "System audio: \(error.localizedDescription)"
        }

        // Start silence detector with calendar awareness
        let detector = SilenceDetector()
        let calendarEnd = calendarService.currentMeetingEndDate(at: now)
        detector.onShouldAutoStop = { [weak self] reason in
            print("[AppState] \(reason)")
            self?.autoStopRecording()
        }
        detector.start(recordingStart: now, calendarEndDate: calendarEnd)
        self.silenceDetector = detector

        print("[AppState] Recording started — language: \(language), keyterms: \(keyterms.count), calendarEnd: \(calendarEnd?.description ?? "none")")
    }

    func autoStopRecording() {
        print("[AppState] Auto-stopping recording due to silence/calendar/max duration")
        stopRecording()
    }

    func stopRecording() {
        silenceDetector?.stop()
        silenceDetector = nil

        elapsedTimer?.invalidate()
        elapsedTimer = nil

        // Stop audio capture
        micCapture?.stop()
        micCapture = nil

        systemCapture?.stop()
        systemCapture = nil

        // Stop combiner
        combiner?.stop()
        combiner = nil

        // Disconnect Deepgram
        deepgramClient?.disconnect()
        deepgramClient = nil

        let count = transcriptManager.segments.count
        state = .saving(segmentCount: count)
        print("[AppState] Recording stopped, \(count) segments")
    }

    func finishSaving() {
        state = .idle
        elapsedTime = 0
    }

    func discardRecording() {
        transcriptManager.clear()
        state = .idle
        elapsedTime = 0
    }

    func formatElapsedTime() -> String {
        let minutes = Int(elapsedTime) / 60
        let seconds = Int(elapsedTime) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    func loadKeywords() -> [String] {
        keywordsText
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    nonisolated deinit {
    }
}
