import Foundation

struct DeepgramResponse: Decodable {
    let type: String
    let channelIndex: [Int]
    let duration: Double
    // Mutable: stream time restarts at 0 on reconnect, so the client shifts
    // it by the connection's offset into the recording.
    var start: Double
    let isFinal: Bool
    let speechFinal: Bool
    let channel: ChannelResult

    enum CodingKeys: String, CodingKey {
        case type
        case channelIndex = "channel_index"
        case duration, start
        case isFinal = "is_final"
        case speechFinal = "speech_final"
        case channel
    }
}

struct ChannelResult: Decodable {
    let alternatives: [Alternative]
}

struct Alternative: Decodable {
    let transcript: String
    let confidence: Double
    let words: [DeepgramWord]
}

struct DeepgramWord: Decodable {
    let word: String
    let start: Double
    let end: Double
    let confidence: Double
    let punctuatedWord: String?

    enum CodingKeys: String, CodingKey {
        case word, start, end, confidence
        case punctuatedWord = "punctuated_word"
    }
}

struct TranscriptSegment: Identifiable, Codable {
    var id = UUID()
    let speaker: Speaker
    let text: String
    let startTime: Double
    let endTime: Double

    enum Speaker: String, Codable {
        case me = "Me"
        case them = "Them"
    }
}
