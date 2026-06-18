import AVFoundation
import CoreGraphics
import Foundation
import ServiceManagement
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
    // Live note streamed into the vault while recording, so the meeting is
    // watchable (and readable by tools) in real time and survives a failed save.
    private var liveNoteName: String?
    private var liveFilePath: String?

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

    var anthropicApiKey: String {
        get { UserDefaults.standard.string(forKey: "anthropicApiKey") ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: "anthropicApiKey") }
    }

    var launchAtLogin = SMAppService.mainApp.status == .enabled {
        didSet {
            guard launchAtLogin != oldValue else { return }
            do {
                if launchAtLogin {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                print("[AppState] Launch at login failed: \(error)")
                lastError = "Launch at login: \(error.localizedDescription)"
            }
        }
    }

    var obsidianVaultPath: String {
        get { UserDefaults.standard.string(forKey: "obsidianVaultPath") ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: "obsidianVaultPath") }
    }

    // Stored (not computed) so SwiftUI observes changes — otherwise the menu's
    // language picker and the recording view don't refresh when ⌘⇧1/⌘⇧2 change
    // the language. didSet keeps it persisted to UserDefaults.
    var language: String = UserDefaults.standard.string(forKey: "language") ?? "multi" {
        didSet { UserDefaults.standard.set(language, forKey: "language") }
    }

    var keywordsText: String {
        get { UserDefaults.standard.string(forKey: "keywords") ?? Self.defaultKeywords }
        set { UserDefaults.standard.set(newValue, forKey: "keywords") }
    }

    private static let defaultKeywords = """
    Claude Code
    Claude
    Anthropic
    Cursor
    Obsidian
    Deepgram
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
    private var channelWatchdog: ChannelWatchdog?
    private var backupWriter: AudioBackupWriter?
    private var elapsedTimer: Timer?
    private var hotkeyMonitor: Any?
    private var localHotkeyMonitor: Any?
    private let calendarService = CalendarService()

    init() {
        migrateLegacyDefaultsIfNeeded()
        // Stored-property initializers run before this, so re-read after the
        // migration in case it just populated this domain.
        language = UserDefaults.standard.string(forKey: "language") ?? "multi"
    }

    /// Earlier builds shipped without a `CFBundleIdentifier`, so `UserDefaults`
    /// fell back to the executable-name domain ("DylanRecord"). Now that the
    /// bundle has a real identifier, standard defaults point at a fresh, empty
    /// domain — so copy the saved settings over once. No-op on installs that
    /// never ran the legacy build, or once the migration has already happened.
    private func migrateLegacyDefaultsIfNeeded() {
        let migratedFlag = "didMigrateLegacyDefaults"
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: migratedFlag) else { return }
        defaults.set(true, forKey: migratedFlag)

        guard let legacy = defaults.persistentDomain(forName: "DylanRecord") else { return }
        let keys = ["deepgramApiKey", "anthropicApiKey", "obsidianVaultPath", "language", "keywords"]
        var migrated = 0
        for key in keys where defaults.object(forKey: key) == nil {
            if let value = legacy[key] {
                defaults.set(value, forKey: key)
                migrated += 1
            }
        }
        if migrated > 0 {
            print("[AppState] Migrated \(migrated) legacy setting(s) from 'DylanRecord' domain")
        }
    }

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

        // Start streaming the note into the vault immediately. Provisional name
        // comes from the current calendar event; the save dialog lets you rename
        // it later. Created now so the file exists to watch from the first word.
        liveNoteName = calendarService.meetingTitleOverlapping(start: now, end: now) ?? "Untitled Recording"
        liveFilePath = nil
        writeLiveNote()

        // Set up audio combiner
        let combiner = AudioCombiner()
        self.combiner = combiner

        // Set up Deepgram client (2-channel multichannel).
        // Attendee names from the current calendar event boost name recognition.
        let lang = language == "multi" ? nil : language
        var keyterms = loadKeywords()
        for name in calendarService.currentMeetingAttendees(at: now) where !keyterms.contains(name) {
            keyterms.append(name)
        }
        let client = DeepgramClient(apiKey: deepgramApiKey, channelCount: 2, language: lang, keyterms: keyterms)
        client.onTranscript = { response in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if let segment = self.transcriptManager.handleResponse(response) {
                    // Persist immediately so a crash never loses the meeting
                    self.draftStore.append(segment)
                    self.silenceDetector?.speechDetected()
                    self.channelWatchdog?.segmentArrived(speaker: segment.speaker)
                    // Stream the new line into the vault note in real time
                    self.writeLiveNote()
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

        // Local WAV backup — re-transcribable if Deepgram fails entirely.
        // Deleted on successful save.
        let backup: AudioBackupWriter?
        do {
            backup = try AudioBackupWriter()
        } catch {
            print("[AppState] Audio backup unavailable: \(error)")
            backup = nil
        }
        self.backupWriter = backup

        // Wire combiner output to Deepgram and the backup file
        combiner.onInterleavedData = { [weak client, weak backup] data in
            client?.sendAudio(data)
            backup?.append(data)
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

        // System audio (the other side) is captured with a Core Audio process
        // tap, which macOS gates behind the "Screen & System Audio Recording"
        // permission. The tap API never triggers the prompt itself, so request
        // it explicitly — this also registers the app in the Privacy list so it
        // can be enabled by hand. Without it the tap runs but returns silence.
        if !CGPreflightScreenCaptureAccess() {
            let granted = CGRequestScreenCaptureAccess()
            if !granted {
                lastError = "Enable ‘Screen & System Audio Recording’ for DylanRecord in System Settings, then restart the recording to capture the other side."
                Notifier.send(
                    title: "Permission Needed",
                    body: "Allow Screen & System Audio Recording for DylanRecord, then restart the recording."
                )
            }
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

        // Watch for one-sided recordings (mic silently dead)
        let watchdog = ChannelWatchdog()
        watchdog.start(recordingStart: now)
        self.channelWatchdog = watchdog

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

        channelWatchdog?.stop()
        channelWatchdog = nil

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
        let backup = self.backupWriter
        self.combiner = nil
        self.deepgramClient = nil
        self.backupWriter = nil
        Task {
            try? await Task.sleep(for: .seconds(1))
            combiner?.stop()
            client?.disconnect()
            backup?.finish()
        }

        let count = transcriptManager.segments.count
        state = .saving(segmentCount: count)
        print("[AppState] Recording stopped, \(count) segments")
    }

    /// Streams the current transcript into the vault note as the meeting
    /// happens. Best-effort — a write failure must never interrupt recording.
    private func writeLiveNote() {
        guard let name = liveNoteName,
              !obsidianVaultPath.isEmpty,
              let start = recordingStartDate else { return }
        let exporter = MarkdownExporter()
        let md = exporter.render(
            segments: transcriptManager.segments,
            meetingName: name,
            startDate: start,
            duration: elapsedTime,
            calendarEvent: nil,
            live: true
        )
        do {
            liveFilePath = try exporter.write(
                content: md,
                meetingName: name,
                startDate: start,
                vaultPath: obsidianVaultPath
            )
        } catch {
            print("[AppState] Live note write failed: \(error)")
        }
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
            // If the final name differs from the in-progress note, remove the
            // stale live file so the vault doesn't end up with a duplicate.
            if let live = liveFilePath, live != filePath {
                try? FileManager.default.removeItem(atPath: live)
            }
            liveFilePath = nil
            liveNoteName = nil
            draftStore.clear()
            AudioBackupWriter.clear()
            let transcriptText = transcriptManager.formattedTranscript()
            finishSaving()
            openInObsidian(filePath: filePath)
            if !anthropicApiKey.isEmpty {
                Task {
                    await addSummary(toFileAt: filePath, transcript: transcriptText, meetingName: name)
                }
            }
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
        // Remove the in-progress note streamed to the vault.
        if let live = liveFilePath {
            try? FileManager.default.removeItem(atPath: live)
        }
        liveFilePath = nil
        liveNoteName = nil
        transcriptManager.clear()
        draftStore.clear()
        AudioBackupWriter.clear()
        finishSaving()
    }

    private func openInObsidian(filePath: String) {
        // The configured vault path may be a subfolder of the actual Obsidian
        // vault (e.g. ".../obsidian-vault/meeting recordings"). The deep-link
        // needs the real vault — the folder containing `.obsidian` — and a file
        // path relative to that root, so walk up from the file to find it.
        // Falls back to the configured path if no `.obsidian` is found.
        let fm = FileManager.default
        var vaultRoot = obsidianVaultPath
        var dir = (filePath as NSString).deletingLastPathComponent
        while !dir.isEmpty && dir != "/" {
            if fm.fileExists(atPath: (dir as NSString).appendingPathComponent(".obsidian")) {
                vaultRoot = dir
                break
            }
            dir = (dir as NSString).deletingLastPathComponent
        }

        let vaultName = (vaultRoot as NSString).lastPathComponent
        var relative = filePath
        if relative.hasPrefix(vaultRoot) {
            relative = String(relative.dropFirst(vaultRoot.count))
        }
        relative = relative.trimmingCharacters(in: CharacterSet(charactersIn: "/"))

        var components = URLComponents()
        components.scheme = "obsidian"
        components.host = "open"
        components.queryItems = [
            URLQueryItem(name: "vault", value: vaultName),
            URLQueryItem(name: "file", value: relative),
        ]
        if let url = components.url {
            NSWorkspace.shared.open(url)
        }
    }

    /// Generates an AI summary with action items and inserts it at the top of
    /// the saved note (after the title). Obsidian reloads the file on change.
    private func addSummary(toFileAt path: String, transcript: String, meetingName: String) async {
        do {
            let summary = try await MeetingSummarizer(apiKey: anthropicApiKey)
                .summarize(transcript: transcript, meetingName: meetingName)

            var contents = try String(contentsOfFile: path, encoding: .utf8)
            if let titleStart = contents.range(of: "\n# "),
               let titleEnd = contents.range(of: "\n", range: titleStart.upperBound..<contents.endIndex) {
                contents.insert(contentsOf: "\n\(summary)\n", at: titleEnd.upperBound)
            } else {
                contents += "\n\n\(summary)\n"
            }
            try contents.write(toFile: path, atomically: true, encoding: .utf8)
            print("[AppState] Summary added to \(path)")
            Notifier.send(title: "Summary Added", body: "AI summary added to \(meetingName).")
        } catch {
            print("[AppState] Summarization failed: \(error)")
            Notifier.send(title: "Summary Failed", body: error.localizedDescription)
        }
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
