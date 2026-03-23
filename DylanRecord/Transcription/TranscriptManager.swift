import Foundation

@Observable
final class TranscriptManager {
    var segments: [TranscriptSegment] = []

    func handleResponse(_ response: DeepgramResponse) {
        let channelIndex = response.channelIndex.first ?? 0
        let speaker: TranscriptSegment.Speaker = channelIndex == 0 ? .them : .me

        guard let alt = response.channel.alternatives.first else { return }
        let text = alt.transcript.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }

        guard response.isFinal else { return }

        let segment = TranscriptSegment(
            speaker: speaker,
            text: text,
            startTime: response.start,
            endTime: response.start + response.duration
        )

        segments.append(segment)
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
