import Foundation

struct MarkdownExporter {
    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()

    /// Renders the full note (frontmatter + transcript). When `live` is true a
    /// `status: recording` marker is added to the frontmatter so an in-progress
    /// note is easy to tell apart from a finished one — both for you and for
    /// tools reading the vault while a meeting is happening.
    func render(
        segments: [TranscriptSegment],
        meetingName: String,
        startDate: Date,
        duration: TimeInterval,
        calendarEvent: String?,
        live: Bool = false
    ) -> String {
        let dateStr = Self.dateFormatter.string(from: startDate)
        let timeStr = Self.timeFormatter.string(from: startDate)

        let durationMinutes = Int(duration) / 60
        let durationSeconds = Int(duration) % 60
        let durationStr = String(format: "%d:%02d", durationMinutes, durationSeconds)

        // Build markdown
        var md = "---\n"
        md += "date: \(dateStr)\n"
        md += "time: \"\(timeStr)\"\n"
        md += "duration: \"\(durationStr)\"\n"
        if let event = calendarEvent {
            md += "calendar_event: \"\(event)\"\n"
        }
        if live {
            md += "status: recording\n"
        }
        md += "tags:\n  - meeting\n  - transcript\n"
        md += "---\n\n"
        md += "# \(meetingName)\n\n"

        // Format transcript segments
        let sorted = segments.sorted { $0.startTime < $1.startTime }
        for segment in sorted {
            let minutes = Int(segment.startTime) / 60
            let seconds = Int(segment.startTime) % 60
            let timestamp = String(format: "%d:%02d", minutes, seconds)
            md += "**\(segment.speaker.rawValue)** (\(timestamp)): \(segment.text)\n\n"
        }

        if live && sorted.isEmpty {
            md += "_Listening… transcript will appear here as people speak._\n"
        }

        return md
    }

    func fileName(meetingName: String, startDate: Date) -> String {
        let dateStr = Self.dateFormatter.string(from: startDate)
        let sanitizedName = meetingName
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .trimmingCharacters(in: .whitespaces)
        return "\(dateStr) \(sanitizedName).md"
    }

    func meetingsDirectory(vaultPath: String) -> String {
        (vaultPath as NSString).appendingPathComponent("Meetings")
    }

    /// Writes `content` to Meetings/<name>.md, creating the directory if needed.
    /// Returns the absolute file path.
    @discardableResult
    func write(content: String, meetingName: String, startDate: Date, vaultPath: String) throws -> String {
        let dir = meetingsDirectory(vaultPath: vaultPath)
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let filePath = (dir as NSString).appendingPathComponent(fileName(meetingName: meetingName, startDate: startDate))
        try content.write(toFile: filePath, atomically: true, encoding: .utf8)
        return filePath
    }

    /// Final export — render the finished note and write it to the vault.
    @discardableResult
    func export(
        segments: [TranscriptSegment],
        meetingName: String,
        startDate: Date,
        duration: TimeInterval,
        vaultPath: String,
        calendarEvent: String?
    ) throws -> String {
        let md = render(
            segments: segments,
            meetingName: meetingName,
            startDate: startDate,
            duration: duration,
            calendarEvent: calendarEvent,
            live: false
        )
        return try write(content: md, meetingName: meetingName, startDate: startDate, vaultPath: vaultPath)
    }
}
