import Foundation

@Observable
final class TranscriptManager {
    var segments: [TranscriptSegment] = []

    /// Appends a segment for a final, non-empty response. Returns it so the
    /// caller can persist it to the crash-safe draft.
    @discardableResult
    func handleResponse(_ response: DeepgramResponse) -> TranscriptSegment? {
        let channelIndex = response.channelIndex.first ?? 0
        let speaker: TranscriptSegment.Speaker = channelIndex == 0 ? .them : .me

        guard let alt = response.channel.alternatives.first else { return nil }
        let text = alt.transcript.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return nil }

        guard response.isFinal else { return nil }

        let segment = TranscriptSegment(
            speaker: speaker,
            text: text,
            startTime: response.start,
            endTime: response.start + response.duration
        )

        segments.append(segment)
        return segment
    }

    func clear() {
        segments.removeAll()
    }

    func formattedTranscript() -> String {
        segments
            .sorted { $0.startTime < $1.startTime }
            .map { segment in
                let minutes = Int(segment.startTime) / 60
                let seconds = Int(segment.startTime) % 60
                let timestamp = String(format: "%d:%02d", minutes, seconds)
                return "**\(segment.speaker.rawValue)** (\(timestamp)): \(segment.text)"
            }
            .joined(separator: "\n\n")
    }
}
