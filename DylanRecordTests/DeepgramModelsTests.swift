import Foundation
import Testing
@testable import DylanRecord

@Suite("DeepgramModels")
struct DeepgramModelsTests {
    @Test("Parse a real Deepgram streaming response")
    func parseResponse() throws {
        let json = """
        {
            "type": "Results",
            "channel_index": [0, 2],
            "duration": 1.5,
            "start": 3.2,
            "is_final": true,
            "speech_final": true,
            "channel": {
                "alternatives": [
                    {
                        "transcript": "hello world",
                        "confidence": 0.98,
                        "words": [
                            {
                                "word": "hello",
                                "start": 3.2,
                                "end": 3.5,
                                "confidence": 0.99,
                                "punctuated_word": "Hello"
                            },
                            {
                                "word": "world",
                                "start": 3.6,
                                "end": 4.0,
                                "confidence": 0.97,
                                "punctuated_word": "world"
                            }
                        ]
                    }
                ]
            }
        }
        """

        let data = json.data(using: .utf8)!
        let response = try JSONDecoder().decode(DeepgramResponse.self, from: data)

        #expect(response.type == "Results")
        #expect(response.channelIndex == [0, 2])
        #expect(response.isFinal == true)
        #expect(response.speechFinal == true)
        #expect(response.start == 3.2)
        #expect(response.duration == 1.5)
        #expect(response.channel.alternatives.count == 1)
        #expect(response.channel.alternatives[0].transcript == "hello world")
        #expect(response.channel.alternatives[0].words.count == 2)
        #expect(response.channel.alternatives[0].words[0].punctuatedWord == "Hello")
    }

    @Test("Parse response with empty transcript")
    func parseEmptyTranscript() throws {
        let json = """
        {
            "type": "Results",
            "channel_index": [1, 2],
            "duration": 0.5,
            "start": 10.0,
            "is_final": true,
            "speech_final": false,
            "channel": {
                "alternatives": [
                    {
                        "transcript": "",
                        "confidence": 0.0,
                        "words": []
                    }
                ]
            }
        }
        """

        let data = json.data(using: .utf8)!
        let response = try JSONDecoder().decode(DeepgramResponse.self, from: data)

        #expect(response.channel.alternatives[0].transcript == "")
        #expect(response.channel.alternatives[0].words.isEmpty)
    }

    @Test("Channel index 0 maps to Them, 1 maps to Me")
    func channelMapping() {
        let segment0 = TranscriptSegment(speaker: .them, text: "test", startTime: 0, endTime: 1)
        let segment1 = TranscriptSegment(speaker: .me, text: "test", startTime: 0, endTime: 1)

        #expect(segment0.speaker.rawValue == "Them")
        #expect(segment1.speaker.rawValue == "Me")
    }
}
