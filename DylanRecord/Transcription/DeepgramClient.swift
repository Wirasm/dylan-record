import Foundation

final class DeepgramClient: NSObject, URLSessionWebSocketDelegate {
    enum ConnectionStatus {
        case connected
        case reconnecting(attempt: Int)
        case failed
    }

    nonisolated(unsafe) private var webSocket: URLSessionWebSocketTask?
    nonisolated(unsafe) private var session: URLSession?
    nonisolated(unsafe) private var keepaliveTimer: DispatchSourceTimer?
    private let apiKey: String
    private let channelCount: Int

    nonisolated(unsafe) var onTranscript: ((DeepgramResponse) -> Void)?
    nonisolated(unsafe) var onError: ((Error) -> Void)?
    nonisolated(unsafe) var onConnected: (() -> Void)?
    nonisolated(unsafe) var onStatusChange: ((ConnectionStatus) -> Void)?

    // Reconnect state — only touched on stateQueue.
    private let stateQueue = DispatchQueue(label: "com.rasmus.dylanrecord.deepgram")
    nonisolated(unsafe) private var isClosing = false
    nonisolated(unsafe) private var isReconnecting = false
    nonisolated(unsafe) private var reconnectAttempt = 0
    private let maxReconnectAttempts = 5

    // Deepgram stream time restarts at 0 per connection; this offset shifts
    // post-reconnect timestamps back onto the recording's timeline.
    nonisolated(unsafe) private var firstConnectDate: Date?
    nonisolated(unsafe) private var currentConnectDate: Date?

    init(apiKey: String, channelCount: Int = 1, language: String? = nil, keyterms: [String] = []) {
        self.apiKey = apiKey
        self.channelCount = channelCount
        self.language = language
        self.keyterms = keyterms
        super.init()
    }

    private let language: String?
    private let keyterms: [String]

    static func buildURL(channelCount: Int, language: String?, keyterms: [String]) -> URL? {
        var params = [
            "model=nova-3",
            "encoding=linear16",
            "sample_rate=16000",
            "channels=\(channelCount)",
            "interim_results=true",
            "smart_format=true",
            "punctuate=true"
        ]

        if channelCount > 1 {
            params.append("multichannel=true")
        }

        if let language {
            params.append("language=\(language)")
        } else {
            params.append("language=multi")
        }

        for term in keyterms {
            let encoded = term.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? term
            params.append("keyterm=\(encoded)")
        }

        let urlString = "wss://api.deepgram.com/v1/listen?" + params.joined(separator: "&")
        return URL(string: urlString)
    }

    func connect() {
        isClosing = false
        openSocket()
    }

    func sendAudio(_ data: Data) {
        webSocket?.send(.data(data)) { [weak self] error in
            if let error {
                print("[Deepgram] Send error: \(error.localizedDescription)")
                self?.scheduleReconnect(after: error)
            }
        }
    }

    func disconnect() {
        isClosing = true
        keepaliveTimer?.cancel()
        keepaliveTimer = nil

        guard webSocket != nil else {
            // Mid-reconnect: no socket to close gracefully
            session?.finishTasksAndInvalidate()
            session = nil
            return
        }

        let closeMessage = "{\"type\": \"CloseStream\"}"
        webSocket?.send(.string(closeMessage)) { [weak self] _ in
            // Give Deepgram a moment to flush trailing final transcripts.
            DispatchQueue.global().asyncAfter(deadline: .now() + 2) { [weak self] in
                guard let self else { return }
                self.webSocket?.cancel(with: .normalClosure, reason: nil)
                self.webSocket = nil
                // URLSession retains its delegate — invalidate to avoid leaking
                // one client per recording.
                self.session?.finishTasksAndInvalidate()
                self.session = nil
            }
        }
    }

    // MARK: - Private

    private func openSocket() {
        guard let url = Self.buildURL(channelCount: channelCount, language: language, keyterms: keyterms) else {
            print("[Deepgram] Invalid URL")
            return
        }
        print("[Deepgram] Connecting: \(url.absoluteString)")

        var request = URLRequest(url: url)
        request.setValue("Token \(apiKey)", forHTTPHeaderField: "Authorization")

        if session == nil {
            session = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
        }

        let now = Date()
        if firstConnectDate == nil { firstConnectDate = now }
        currentConnectDate = now

        webSocket = session?.webSocketTask(with: request)
        webSocket?.resume()

        startReceiving()
        if keepaliveTimer == nil {
            startKeepalive()
        }
    }

    private func scheduleReconnect(after error: Error) {
        stateQueue.async { [weak self] in
            guard let self, !self.isClosing, !self.isReconnecting else { return }
            self.isReconnecting = true
            self.reconnectAttempt += 1

            guard self.reconnectAttempt <= self.maxReconnectAttempts else {
                print("[Deepgram] Giving up after \(self.maxReconnectAttempts) reconnect attempts")
                self.onStatusChange?(.failed)
                return
            }

            let delay = pow(2.0, Double(self.reconnectAttempt - 1)) // 1, 2, 4, 8, 16s
            print("[Deepgram] Connection lost (\(error.localizedDescription)) — reconnecting in \(Int(delay))s (attempt \(self.reconnectAttempt))")
            self.onStatusChange?(.reconnecting(attempt: self.reconnectAttempt))

            self.webSocket?.cancel(with: .abnormalClosure, reason: nil)
            self.webSocket = nil

            self.stateQueue.asyncAfter(deadline: .now() + delay) { [weak self] in
                guard let self, !self.isClosing else { return }
                self.isReconnecting = false
                self.openSocket()
            }
        }
    }

    private func startReceiving() {
        webSocket?.receive { [weak self] result in
            switch result {
            case .success(let message):
                switch message {
                case .string(let text):
                    self?.handleMessage(text)
                case .data(let data):
                    if let text = String(data: data, encoding: .utf8) {
                        self?.handleMessage(text)
                    }
                @unknown default:
                    break
                }
                self?.startReceiving()

            case .failure(let error):
                print("[Deepgram] Receive error: \(error.localizedDescription)")
                self?.scheduleReconnect(after: error)
            }
        }
    }

    private func handleMessage(_ text: String) {
        guard let data = text.data(using: .utf8) else { return }

        // Log all messages for debugging
        print("[Deepgram] Received: \(String(text.prefix(200)))")

        do {
            var response = try JSONDecoder().decode(DeepgramResponse.self, from: data)
            guard let alt = response.channel.alternatives.first,
                  !alt.transcript.trimmingCharacters(in: .whitespaces).isEmpty else {
                return
            }
            if let first = firstConnectDate, let current = currentConnectDate {
                response.start += current.timeIntervalSince(first)
            }
            onTranscript?(response)
        } catch {
            // Check if it's an error message from Deepgram
            if text.contains("error") || text.contains("Error") {
                print("[Deepgram] ERROR response: \(text)")
                onError?(DeepgramClientError.serverError(text))
            }
        }
    }

    private func startKeepalive() {
        keepaliveTimer = DispatchSource.makeTimerSource(queue: .global(qos: .utility))
        keepaliveTimer?.schedule(deadline: .now() + 8, repeating: 8)
        keepaliveTimer?.setEventHandler { [weak self] in
            self?.webSocket?.send(.string("{\"type\": \"KeepAlive\"}")) { _ in }
        }
        keepaliveTimer?.resume()
    }

    enum DeepgramClientError: Error, LocalizedError {
        case serverError(String)
        var errorDescription: String? {
            switch self {
            case .serverError(let msg): return msg
            }
        }
    }

    // MARK: - URLSessionWebSocketDelegate

    func urlSession(
        _ session: URLSession,
        webSocketTask: URLSessionWebSocketTask,
        didOpenWithProtocol protocol: String?
    ) {
        print("[Deepgram] Connected")
        stateQueue.async { [weak self] in
            guard let self else { return }
            let wasReconnect = self.reconnectAttempt > 0
            self.reconnectAttempt = 0
            if wasReconnect {
                self.onStatusChange?(.connected)
            }
        }
        onConnected?()
    }

    func urlSession(
        _ session: URLSession,
        webSocketTask: URLSessionWebSocketTask,
        didCloseWith closeCode: URLSessionWebSocketTask.CloseCode,
        reason: Data?
    ) {
        print("[Deepgram] Disconnected: \(closeCode)")
    }
}
