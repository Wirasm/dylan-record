import Foundation

/// Writes the interleaved stereo 16kHz Int16 stream to a WAV file during
/// recording, as insurance against total transcription failure — the audio
/// can be re-transcribed later. Deleted once the transcript is saved.
final class AudioBackupWriter: @unchecked Sendable {
    static let sampleRate: UInt32 = 16000
    static let channels: UInt16 = 2

    static var defaultURL: URL {
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("DylanRecord", isDirectory: true)
            .appendingPathComponent("backup-audio.wav")
    }

    let url: URL
    private let handle: FileHandle
    private let lock = NSLock()
    private var dataBytes: UInt32 = 0
    private var finished = false

    init(url: URL = AudioBackupWriter.defaultURL) throws {
        self.url = url
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        FileManager.default.createFile(atPath: url.path, contents: nil)
        handle = try FileHandle(forWritingTo: url)
        try handle.write(contentsOf: Self.header(dataBytes: 0))
    }

    func append(_ data: Data) {
        lock.lock()
        defer { lock.unlock() }
        guard !finished else { return }
        do {
            try handle.write(contentsOf: data)
            dataBytes += UInt32(data.count)
        } catch {
            print("[AudioBackup] Write failed: \(error)")
        }
    }

    /// Patches the WAV header with the final sizes and closes the file.
    func finish() {
        lock.lock()
        defer { lock.unlock() }
        guard !finished else { return }
        finished = true
        do {
            try handle.seek(toOffset: 0)
            try handle.write(contentsOf: Self.header(dataBytes: dataBytes))
            try handle.close()
        } catch {
            print("[AudioBackup] Finalize failed: \(error)")
        }
    }

    static func clear() {
        try? FileManager.default.removeItem(at: defaultURL)
    }

    static func header(dataBytes: UInt32) -> Data {
        let byteRate = sampleRate * UInt32(channels) * 2
        let blockAlign = channels * 2
        var d = Data()
        d.append(contentsOf: Array("RIFF".utf8))
        d.appendLE(UInt32(36) + dataBytes)
        d.append(contentsOf: Array("WAVE".utf8))
        d.append(contentsOf: Array("fmt ".utf8))
        d.appendLE(UInt32(16))
        d.appendLE(UInt16(1)) // PCM
        d.appendLE(channels)
        d.appendLE(sampleRate)
        d.appendLE(byteRate)
        d.appendLE(blockAlign)
        d.appendLE(UInt16(16)) // bits per sample
        d.append(contentsOf: Array("data".utf8))
        d.appendLE(dataBytes)
        return d
    }
}

private extension Data {
    mutating func appendLE<T: FixedWidthInteger>(_ value: T) {
        Swift.withUnsafeBytes(of: value.littleEndian) { append(contentsOf: $0) }
    }
}
