import Foundation

struct MarkdownExporter {
    func export(
        segments: [TranscriptSegment],
        meetingName: String,
        startDate: Date,
        duration: TimeInterval,
        vaultPath: String,
        calendarEvent: String?
    ) throws -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let dateStr = dateFormatter.string(from: startDate)

        let timeFormatter = DateFormatter()
        timeFormatter.dateFormat = "HH:mm"
        let timeStr = timeFormatter.string(from: startDate)

        let durationMinutes = Int(duration) / 60
        let durationSeconds = Int(duration) % 60
        let durationStr = String(format: "%d:%02d", durationMinutes, durationSeconds)

        let sanitizedName = meetingName
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .trimmingCharacters(in: .whitespaces)

        // Build markdown
        var md = "---\n"
        md += "date: \(dateStr)\n"
        md += "time: \"\(timeStr)\"\n"
        md += "duration: \"\(durationStr)\"\n"
        if let event = calendarEvent {
            md += "calendar_event: \"\(event)\"\n"
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

        // Ensure Meetings directory exists
        let meetingsDir = (vaultPath as NSString).appendingPathComponent("Meetings")
        try FileManager.default.createDirectory(
            atPath: meetingsDir,
            withIntermediateDirectories: true
        )

        // Write file
        let fileName = "\(dateStr) \(sanitizedName).md"
        let filePath = (meetingsDir as NSString).appendingPathComponent(fileName)
        try md.write(toFile: filePath, atomically: true, encoding: .utf8)

        return filePath
    }
}
