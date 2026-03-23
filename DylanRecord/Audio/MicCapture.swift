import AVFoundation
import Foundation

final class MicCapture {
    private let engine = AVAudioEngine()
    private var converter: AudioConverter?

    var onAudioData: ((Data) -> Void)?

    func start() throws {
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

    func stop() {
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
