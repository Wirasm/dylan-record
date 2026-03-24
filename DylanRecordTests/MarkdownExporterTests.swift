import Testing
import Foundation
@testable import DylanRecord

@Suite("MarkdownExporter")
struct MarkdownExporterTests {
    @Test("Export creates valid markdown with frontmatter")
    func exportFormat() throws {
        let segments = [
            TranscriptSegment(speaker: .them, text: "Hello everyone", startTime: 3, endTime: 5),
            TranscriptSegment(speaker: .me, text: "Hi there", startTime: 6, endTime: 8),
        ]

        let tmpDir = FileManager.default.temporaryDirectory.path
        let exporter = MarkdownExporter()

        let date = ISO8601DateFormatter().date(from: "2026-03-24T14:30:00Z")!
        let path = try exporter.export(
            segments: segments,
            meetingName: "Test Meeting",
            startDate: date,
            duration: 300,
            vaultPath: tmpDir,
            calendarEvent: "Weekly Sync"
        )

        let content = try String(contentsOfFile: path, encoding: .utf8)

        // Check frontmatter
        #expect(content.contains("date: 2026-03-24"))
        #expect(content.contains("duration: \"5:00\""))
        #expect(content.contains("calendar_event: \"Weekly Sync\""))
        #expect(content.contains("tags:"))
        #expect(content.contains("- meeting"))
        #expect(content.contains("- transcript"))

        // Check title
        #expect(content.contains("# Test Meeting"))

        // Check transcript formatting
        #expect(content.contains("**Them** (0:03): Hello everyone"))
        #expect(content.contains("**Me** (0:06): Hi there"))

        // Cleanup
        try? FileManager.default.removeItem(atPath: path)
    }

    @Test("Export creates Meetings directory if missing")
    func createsMeetingsDir() throws {
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("dylan-test-\(UUID().uuidString)")
            .path

        let exporter = MarkdownExporter()
        let path = try exporter.export(
            segments: [],
            meetingName: "Empty",
            startDate: Date(),
            duration: 0,
            vaultPath: tmpDir,
            calendarEvent: nil
        )

        let meetingsDir = (tmpDir as NSString).appendingPathComponent("Meetings")
        #expect(FileManager.default.fileExists(atPath: meetingsDir))

        // Cleanup
        try? FileManager.default.removeItem(atPath: tmpDir)
    }

    @Test("Filename sanitizes slashes and colons")
    func sanitizedFilename() throws {
        let tmpDir = FileManager.default.temporaryDirectory.path
        let exporter = MarkdownExporter()

        let path = try exporter.export(
            segments: [],
            meetingName: "Q2/Q3 Review: Planning",
            startDate: Date(),
            duration: 0,
            vaultPath: tmpDir,
            calendarEvent: nil
        )

        #expect(!path.contains("Q2/Q3"))
        #expect(path.contains("Q2-Q3 Review- Planning"))

        try? FileManager.default.removeItem(atPath: path)
    }

    @Test("Segments sorted by time in output")
    func sortedOutput() throws {
        let segments = [
            TranscriptSegment(speaker: .me, text: "Second", startTime: 10, endTime: 12),
            TranscriptSegment(speaker: .them, text: "First", startTime: 2, endTime: 4),
            TranscriptSegment(speaker: .them, text: "Third", startTime: 20, endTime: 22),
        ]

        let tmpDir = FileManager.default.temporaryDirectory.path
        let exporter = MarkdownExporter()
        let path = try exporter.export(
            segments: segments,
            meetingName: "Sort Test",
            startDate: Date(),
            duration: 60,
            vaultPath: tmpDir,
            calendarEvent: nil
        )

        let content = try String(contentsOfFile: path, encoding: .utf8)
        let firstRange = content.range(of: "First")!
        let secondRange = content.range(of: "Second")!
        let thirdRange = content.range(of: "Third")!

        #expect(firstRange.lowerBound < secondRange.lowerBound)
        #expect(secondRange.lowerBound < thirdRange.lowerBound)

        try? FileManager.default.removeItem(atPath: path)
    }
}
