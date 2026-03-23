import Foundation

/// Combines two mono Int16 16kHz audio streams into interleaved stereo.
/// Channel 0 = system audio, Channel 1 = microphone.
final class AudioCombiner {
    private let systemBuffer: RingBuffer
    private let micBuffer: RingBuffer
    private let chunkSamples: Int  // samples per channel per chunk
    private var timer: DispatchSourceTimer?

    var onInterleavedData: ((Data) -> Void)?

    /// - Parameter chunkDuration: Duration of each interleaved chunk in seconds (default 0.1 = 100ms)
    init(chunkDuration: Double = 0.1) {
        let sampleRate = 16000
        self.chunkSamples = Int(Double(sampleRate) * chunkDuration)
        // 1 second capacity per buffer
        self.systemBuffer = RingBuffer(capacity: sampleRate)
        self.micBuffer = RingBuffer(capacity: sampleRate)
    }

    func appendSystemAudio(_ data: Data) {
        systemBuffer.write(data)
    }

    func appendMicAudio(_ data: Data) {
        micBuffer.write(data)
    }

    func start() {
        let queue = DispatchQueue(label: "com.rasmus.dylanrecord.combiner", qos: .userInteractive)
        timer = DispatchSource.makeTimerSource(queue: queue)
        timer?.schedule(deadline: .now(), repeating: .milliseconds(100))
        timer?.setEventHandler { [weak self] in
            self?.combineAndSend()
        }
        timer?.resume()
    }

    func stop() {
        timer?.cancel()
        timer = nil
    }

    private func combineAndSend() {
        var sysSamples = [Int16](repeating: 0, count: chunkSamples)
        var micSamples = [Int16](repeating: 0, count: chunkSamples)

        let sysCount = systemBuffer.read(into: &sysSamples, maxCount: chunkSamples)
        let micCount = micBuffer.read(into: &micSamples, maxCount: chunkSamples)

        // Only send if at least one source has data
        guard sysCount > 0 || micCount > 0 else { return }

        // Interleave: [sys0, mic0, sys1, mic1, ...]
        // 2 channels * 2 bytes per sample * chunkSamples
        var data = Data(capacity: chunkSamples * 4)
        for i in 0..<chunkSamples {
            withUnsafeBytes(of: sysSamples[i].littleEndian) { data.append(contentsOf: $0) }
            withUnsafeBytes(of: micSamples[i].littleEndian) { data.append(contentsOf: $0) }
        }

        onInterleavedData?(data)
    }
}
