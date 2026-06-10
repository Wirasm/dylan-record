import Foundation
import Testing
@testable import DylanRecord

@Suite("AudioBackupWriter")
struct AudioBackupWriterTests {
    private func tempURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("BackupWriterTests-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("backup.wav")
    }

    @Test("Writes a valid WAV file with correct header sizes")
    func validWav() throws {
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        let writer = try AudioBackupWriter(url: url)
        let samples = Data((0..<3200).map { UInt8($0 % 256) }) // 1600 Int16 samples
        writer.append(samples)
        writer.append(samples)
        writer.finish()

        let contents = try Data(contentsOf: url)
        #expect(contents.count == 44 + 6400)

        // RIFF header
        #expect(String(data: contents[0..<4], encoding: .ascii) == "RIFF")
        #expect(String(data: contents[8..<12], encoding: .ascii) == "WAVE")

        // RIFF chunk size = 36 + data bytes
        let riffSize = contents[4..<8].withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }
        #expect(riffSize == 36 + 6400)

        // data chunk size
        let dataSize = contents[40..<44].withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }
        #expect(dataSize == 6400)

        // Format fields: PCM, 2 channels, 16kHz, 16-bit
        let format = contents[20..<22].withUnsafeBytes { $0.loadUnaligned(as: UInt16.self) }
        let channels = contents[22..<24].withUnsafeBytes { $0.loadUnaligned(as: UInt16.self) }
        let rate = contents[24..<28].withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }
        let bits = contents[34..<36].withUnsafeBytes { $0.loadUnaligned(as: UInt16.self) }
        #expect(format == 1)
        #expect(channels == 2)
        #expect(rate == 16000)
        #expect(bits == 16)

        // Audio payload survives intact
        #expect(contents[44..<(44 + 3200)] == samples)
    }

    @Test("Append after finish is ignored")
    func appendAfterFinish() throws {
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        let writer = try AudioBackupWriter(url: url)
        writer.append(Data(repeating: 0, count: 100))
        writer.finish()
        writer.append(Data(repeating: 1, count: 100))
        writer.finish()

        let contents = try Data(contentsOf: url)
        #expect(contents.count == 44 + 100)
    }
}
