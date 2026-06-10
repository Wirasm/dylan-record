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
    var nextMeeting: CalendarService.UpcomingMeeting?
    /// Calendar event title overlapping the recording — save-dialog suggestion
    /// and `calendar_event` frontmatter.
    var suggestedMeetingName: String?
    private var nextMeetingTimer: Timer?
    // Export metadata survives past stopRecording so recovered drafts can be
    // saved with their original date and duration.
    private var pendingStartDate: Date?
    private var pendingDuration: TimeInterval = 0
    private let draftStore = TranscriptDraftStore()

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
    private var localHotkeyMonitor: Any?
    private let calendarService = CalendarService()

    func setupHotkey() {
        // Global monitors don't fire while our own app has focus (e.g. the
        // popover is open), so register a local monitor too.
        hotkeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            Task { @MainActor in
                self?.handleHotkey(event)
            }
        }
        localHotkeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if self?.handleHotkey(event) == true {
                return nil
            }
            return event
        }
    }

    @discardableResult
    private func handleHotkey(_ event: NSEvent) -> Bool {
        guard event.modifierFlags.contains([.command, .shift]) else { return false }

        switch event.keyCode {
        case 15: // ⌘⇧R — toggle recording
            toggleRecording()
            return true
        case 18: // ⌘⇧1 — Svenska
            language = "sv"
            return true
        case 19: // ⌘⇧2 — English
            language = "en"
            return true
        default:
            return false
        }
    }

    func startNextMeetingPolling(accessGranted: Bool) {
        print("[AppState] Calendar access: \(accessGranted)")
        guard accessGranted else { return }
        refreshNextMeeting()
        nextMeetingTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refreshNextMeeting()
            }
        }
    }

    /// Restores an unsaved transcript left behind by a crash or reboot.
    func recoverDraftIfNeeded() {
        guard case .idle = state, let draft = draftStore.load() else { return }

        transcriptManager.segments = draft.segments
        pendingStartDate = draft.startDate
        pendingDuration = draft.segments.map(\.endTime).max() ?? 0
        suggestedMeetingName = calendarService.meetingTitleOverlapping(
            start: draft.startDate,
            end: draft.startDate.addingTimeInterval(max(pendingDuration, 60))
        )
        state = .saving(segmentCount: draft.segments.count)
        print("[AppState] Recovered draft: \(draft.segments.count) segments from \(draft.startDate)")
        Notifier.send(
            title: "Recovered Transcript",
            body: "An unsaved recording was found — open Dylan Record to save it."
        )
    }

    private func refreshNextMeeting() {
        nextMeeting = calendarService.nextMeeting()
    }

    func toggleRecording() {
        if isRecording {
            stopRecording()
        } else {
            startRecording()
        }
    }

    func startRecording() {
        guard !isSaving else {
            lastError = "Save or discard the previous transcript first."
            return
        }
        guard !deepgramApiKey.isEmpty else {
            lastError = "Set your Deepgram API key in Settings."
            return
        }

        lastError = nil
        suggestedMeetingName = nil
        let now = Date()
        state = .recording(startDate: now)
        elapsedTime = 0
        draftStore.begin(startDate: now)

        // Start elapsed timer
        elapsedTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, let start = self.recordingStartDate else { return }
                self.elapsedTime = Date().timeIntervalSince(start)
            }
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
                guard let self else { return }
                if let segment = self.transcriptManager.handleResponse(response) {
                    // Persist immediately so a crash never loses the meeting
                    self.draftStore.append(segment)
                    self.silenceDetector?.speechDetected()
                }
            }
        }
        client.onError = { error in
            print("[AppState] Deepgram error: \(error.localizedDescription)")
            Task { @MainActor [weak self] in
                self?.lastError = "Deepgram: \(error.localizedDescription)"
            }
        }
        client.onStatusChange = { status in
            Task { @MainActor [weak self] in
                switch status {
                case .connected:
                    self?.lastError = nil
                    Notifier.send(title: "Transcription Restored", body: "Reconnected to Deepgram.")
                case .reconnecting(let attempt):
                    self?.lastError = "Transcription connection lost — reconnecting (attempt \(attempt))…"
                    if attempt == 1 {
                        Notifier.send(title: "Transcription Interrupted", body: "Connection to Deepgram lost — reconnecting…")
                    }
                case .failed:
                    self?.lastError = "Transcription connection failed. Stop recording to save what was captured."
                    Notifier.send(title: "Transcription Failed", body: "Could not reconnect to Deepgram. Stop recording to save what was captured.")
                }
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
            Notifier.send(title: "Mic Capture Failed", body: error.localizedDescription)
        }

        do {
            try sys.start()
        } catch {
            print("[AppState] System audio error: \(error)")
            lastError = "System audio: \(error.localizedDescription)"
            Notifier.send(title: "System Audio Capture Failed", body: error.localizedDescription)
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
        // Capture export metadata and the name suggestion on every stop path
        // (button, hotkey, auto-stop) before tearing the pipeline down.
        let stopDate = Date()
        if let start = recordingStartDate {
            pendingStartDate = start
            pendingDuration = stopDate.timeIntervalSince(start)
            suggestedMeetingName = calendarService.meetingTitleOverlapping(start: start, end: stopDate)
        }

        silenceDetector?.stop()
        silenceDetector = nil

        elapsedTimer?.invalidate()
        elapsedTimer = nil

        // Stop audio capture
        micCapture?.stop()
        micCapture = nil

        systemCapture?.stop()
        systemCapture = nil

        // Let the combiner drain its ring buffers and Deepgram deliver
        // trailing finals before tearing the connection down — otherwise the
        // last second of the meeting gets clipped.
        let combiner = self.combiner
        let client = self.deepgramClient
        self.combiner = nil
        self.deepgramClient = nil
        Task {
            try? await Task.sleep(for: .seconds(1))
            combiner?.stop()
            client?.disconnect()
        }

        let count = transcriptManager.segments.count
        state = .saving(segmentCount: count)
        print("[AppState] Recording stopped, \(count) segments")
    }

    func saveTranscript(name: String) {
        guard !obsidianVaultPath.isEmpty else {
            lastError = "Set vault path in Settings, then save again."
            return // stay in .saving — the transcript is kept for retry
        }

        do {
            let filePath = try MarkdownExporter().export(
                segments: transcriptManager.segments,
                meetingName: name,
                startDate: pendingStartDate ?? Date(),
                duration: pendingDuration > 0 ? pendingDuration : elapsedTime,
                vaultPath: obsidianVaultPath,
                calendarEvent: suggestedMeetingName
            )
            print("[AppState] Saved to: \(filePath)")
            draftStore.clear()
            finishSaving()
        } catch {
            // Stay in .saving — the transcript and draft survive for retry.
            lastError = "Save failed: \(error.localizedDescription)"
            Notifier.send(title: "Save Failed", body: error.localizedDescription)
        }
    }

    func finishSaving() {
        state = .idle
        elapsedTime = 0
        lastError = nil
        suggestedMeetingName = nil
        pendingStartDate = nil
        pendingDuration = 0
    }

    func discardRecording() {
        transcriptManager.clear()
        draftStore.clear()
        finishSaving()
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
