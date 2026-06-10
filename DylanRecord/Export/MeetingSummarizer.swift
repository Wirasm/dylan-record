import Foundation

/// Summarizes a meeting transcript with the Claude API. Returns markdown
/// sections (summary, decisions, action items) in the transcript's language.
struct MeetingSummarizer {
    static let model = "claude-opus-4-8"
    private let apiKey: String

    init(apiKey: String) {
        self.apiKey = apiKey
    }

    func summarize(transcript: String, meetingName: String) async throws -> String {
        var request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 300
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")

        let system = """
        You summarize meeting transcripts. "Me" is Rasmus (the app's owner); \
        "Them" is the other participant(s). Write in the dominant language of \
        the transcript (usually Swedish or English). Return exactly these \
        markdown sections:

        ## Summary
        3-6 sentences on what the meeting was about and what was concluded.

        ## Decisions
        Bullet list of decisions that were made. Omit this section if there were none.

        ## Action items
        - [ ] One checkbox per action item, prefixed with the owner's name. Omit this section if there were none.

        Return only the markdown sections — no preamble, no code fences.
        """

        let body: [String: Any] = [
            "model": Self.model,
            "max_tokens": 16000,
            "thinking": ["type": "adaptive"],
            "system": system,
            "messages": [
                ["role": "user", "content": "Meeting: \(meetingName)\n\nTranscript:\n\(transcript)"]
            ],
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw SummarizerError.invalidResponse
        }
        guard http.statusCode == 200 else {
            let text = String(data: data, encoding: .utf8) ?? ""
            throw SummarizerError.apiError(status: http.statusCode, body: String(text.prefix(300)))
        }

        // Content is an array of blocks; adaptive thinking may prepend
        // thinking blocks, so take the first text block.
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let content = json["content"] as? [[String: Any]],
              let text = content.first(where: { $0["type"] as? String == "text" })?["text"] as? String
        else {
            throw SummarizerError.invalidResponse
        }

        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    enum SummarizerError: Error, LocalizedError {
        case invalidResponse
        case apiError(status: Int, body: String)

        var errorDescription: String? {
            switch self {
            case .invalidResponse:
                return "Unexpected response from the Claude API."
            case .apiError(let status, let body):
                return "Claude API error \(status): \(body)"
            }
        }
    }
}
