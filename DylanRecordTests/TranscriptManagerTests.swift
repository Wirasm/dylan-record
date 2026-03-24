import Testing
@testable import DylanRecord

@Suite("TranscriptManager")
struct TranscriptManagerTests {
    private func makeResponse(
        channelIndex: Int,
        transcript: String,
        start: Double,
        duration: Double,
        isFinal: Bool = true
    ) -> DeepgramResponse {
        let word = DeepgramWord(word: transcript, start: start, end: start + duration, confidence: 0.99, punctuatedWord: transcript)
        let alt = Alternative(transcript: transcript, confidence: 0.99, words: [word])
        let channel = ChannelResult(alternatives: [alt])
        return DeepgramResponse(
            type: "Results",
            channelIndex: [channelIndex, 2],
            duration: duration,
            start: start,
            isFinal: isFinal,
            speechFinal: true,
            channel: channel
        )
    }

    @Test("Channel 0 becomes Them, channel 1 becomes Me")
    func speakerMapping() {
        let manager = TranscriptManager()

        manager.handleResponse(makeResponse(channelIndex: 0, transcript: "Hello from them", start: 0, duration: 1))
        manager.handleResponse(makeResponse(channelIndex: 1, transcript: "Hello from me", start: 0.5, duration: 1))

        #expect(manager.segments.count == 2)
        #expect(manager.segments[0].speaker == .them)
        #expect(manager.segments[0].text == "Hello from them")
        #expect(manager.segments[1].speaker == .me)
        #expect(manager.segments[1].text == "Hello from me")
    }

    @Test("Interim results are ignored")
    func interimIgnored() {
        let manager = TranscriptManager()

        manager.handleResponse(makeResponse(channelIndex: 0, transcript: "partial", start: 0, duration: 1, isFinal: false))

        #expect(manager.segments.count == 0)
    }

    @Test("Empty transcripts are ignored")
    func emptyIgnored() {
        let manager = TranscriptManager()

        manager.handleResponse(makeResponse(channelIndex: 0, transcript: "", start: 0, duration: 1))
        manager.handleResponse(makeResponse(channelIndex: 0, transcript: "   ", start: 1, duration: 1))

        #expect(manager.segments.count == 0)
    }

    @Test("Formatted transcript sorts by time and includes speaker labels")
    func formattedOutput() {
        let manager = TranscriptManager()

        manager.handleResponse(makeResponse(channelIndex: 1, transcript: "I said this", start: 5, duration: 2))
        manager.handleResponse(makeResponse(channelIndex: 0, transcript: "They said this first", start: 2, duration: 2))

        let formatted = manager.formattedTranscript()

        #expect(formatted.contains("**Them** (0:02): They said this first"))
        #expect(formatted.contains("**Me** (0:05): I said this"))

        // "Them" should come first since start=2 < start=5
        let themRange = formatted.range(of: "**Them**")!
        let meRange = formatted.range(of: "**Me**")!
        #expect(themRange.lowerBound < meRange.lowerBound)
    }

    @Test("Clear removes all segments")
    func clear() {
        let manager = TranscriptManager()

        manager.handleResponse(makeResponse(channelIndex: 0, transcript: "test", start: 0, duration: 1))
        #expect(manager.segments.count == 1)

        manager.clear()
        #expect(manager.segments.count == 0)
    }

    @Test("Timestamp formatting for minutes and seconds")
    func timestampFormatting() {
        let manager = TranscriptManager()

        manager.handleResponse(makeResponse(channelIndex: 0, transcript: "After one minute", start: 65, duration: 1))

        let formatted = manager.formattedTranscript()
        #expect(formatted.contains("(1:05)"))
    }
}
