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

    // Recording pipeline
    private var micCapture: MicCapture?
    private var systemCapture: SystemAudioCapture?
    private var combiner: AudioCombiner?
    private var deepgramClient: DeepgramClient?
    private(set) var transcriptManager = TranscriptManager()
    private var elapsedTimer: Timer?
    private var hotkeyMonitor: Any?

    func setupHotkey() {
        hotkeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            // ⌘+Shift+R
            if event.modifierFlags.contains([.command, .shift]) && event.keyCode == 15 {
                DispatchQueue.main.async {
                    self?.toggleRecording()
                }
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
        let client = DeepgramClient(apiKey: deepgramApiKey, channelCount: 2)
        client.onTranscript = { response in
            Task { @MainActor [weak self] in
                self?.transcriptManager.handleResponse(response)
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

        print("[AppState] Recording started")
    }

    func stopRecording() {
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

    nonisolated deinit {
    }
}
