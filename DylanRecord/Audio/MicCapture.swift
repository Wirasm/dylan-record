import AVFoundation
import Foundation

// @unchecked Sendable: mutable state is only touched on the main thread;
// the tap callback only reads `converter` and `onAudioData`.
final class MicCapture: @unchecked Sendable {
    private let engine = AVAudioEngine()
    private var converter: AudioConverter?
    private var configChangeObserver: NSObjectProtocol?
    private var isRunning = false
    private var notifiedRestartFailure = false

    var onAudioData: ((Data) -> Void)?

    func start() throws {
        try startEngine()
        isRunning = true

        // The engine stops rendering when the input device changes mid-capture
        // (e.g. a headset reconnects), so restart the tap with the new format.
        configChangeObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange,
            object: engine,
            queue: .main
        ) { [weak self] _ in
            self?.restartAfterConfigurationChange()
        }
    }

    private func startEngine() throws {
        let inputNode = engine.inputNode
        let hwFormat = inputNode.outputFormat(forBus: 0)

        guard hwFormat.sampleRate > 0 else {
            throw MicCaptureError.noInputDevice
        }

        converter = try AudioConverter(inputFormat: hwFormat)

        // Buffer size: ~100ms of audio at hardware sample rate
        let bufferSize = AVAudioFrameCount(hwFormat.sampleRate * 0.1)

        inputNode.installTap(onBus: 0, bufferSize: bufferSize, format: hwFormat) { [weak self] buffer, _ in
            guard let self, let converter = self.converter else { return }
            do {
                let data = try converter.convert(buffer)
                self.onAudioData?(data)
            } catch {
                print("[MicCapture] Conversion error: \(error)")
            }
        }

        try engine.start()
    }

    private func restartAfterConfigurationChange() {
        guard isRunning else { return }

        engine.inputNode.removeTap(onBus: 0)
        engine.stop()

        do {
            try startEngine()
            print("[MicCapture] Restarted after audio configuration change")
            if notifiedRestartFailure {
                notifiedRestartFailure = false
                Notifier.send(title: "Microphone Restored", body: "Mic capture is running again.")
            }
        } catch {
            // Device may not be ready yet right after a reconnect — retry until
            // it comes back or the recording is stopped.
            print("[MicCapture] Restart failed: \(error) — retrying in 1s")
            if !notifiedRestartFailure {
                notifiedRestartFailure = true
                Notifier.send(title: "Microphone Interrupted", body: "Mic capture stopped after a device change — retrying…")
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
                self?.restartAfterConfigurationChange()
            }
        }
    }

    func stop() {
        isRunning = false
        if let configChangeObserver {
            NotificationCenter.default.removeObserver(configChangeObserver)
            self.configChangeObserver = nil
        }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        converter = nil
    }

    static func requestPermission() async -> Bool {
        await withCheckedContinuation { continuation in
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                continuation.resume(returning: granted)
            }
        }
    }
}

enum MicCaptureError: Error, LocalizedError {
    case noInputDevice

    var errorDescription: String? {
        switch self {
        case .noInputDevice:
            return "No microphone input device found."
        }
    }
}
