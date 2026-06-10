import Foundation

/// Crash-safe draft of the in-progress transcript. One JSON line per final
/// segment (first line is a header), appended as segments arrive, so a crash
/// or reboot mid-meeting never loses the recording.
struct TranscriptDraftStore {
    struct Header: Codable {
        let startDate: Date
    }

    private let fileURL: URL

    init(directory: URL? = nil) {
        let dir = directory ?? FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("DylanRecord", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("draft-transcript.jsonl")
    }

    func begin(startDate: Date) {
        do {
            try Data().write(to: fileURL)
        } catch {
            print("[DraftStore] Failed to create draft file: \(error)")
        }
        appendLine(Header(startDate: startDate))
    }

    func append(_ segment: TranscriptSegment) {
        appendLine(segment)
    }

    /// Returns the unsaved draft, or nil if there is none worth recovering.
    func load() -> (startDate: Date, segments: [TranscriptSegment])? {
        guard let raw = try? String(contentsOf: fileURL, encoding: .utf8) else { return nil }
        let lines = raw.split(separator: "\n")
        guard let first = lines.first,
              let header = try? JSONDecoder().decode(Header.self, from: Data(first.utf8)) else {
            return nil
        }
        let segments = lines.dropFirst().compactMap {
            try? JSONDecoder().decode(TranscriptSegment.self, from: Data($0.utf8))
        }
        guard !segments.isEmpty else { return nil }
        return (header.startDate, segments)
    }

    func clear() {
        try? FileManager.default.removeItem(at: fileURL)
    }

    private func appendLine(_ value: some Encodable) {
        do {
            var data = try JSONEncoder().encode(value)
            data.append(0x0A)
            if let handle = FileHandle(forWritingAtPath: fileURL.path) {
                defer { try? handle.close() }
                try handle.seekToEnd()
                try handle.write(contentsOf: data)
            } else {
                try data.write(to: fileURL)
            }
        } catch {
            print("[DraftStore] Failed to append: \(error)")
        }
    }
}
