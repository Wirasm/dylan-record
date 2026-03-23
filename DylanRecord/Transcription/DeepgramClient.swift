import Foundation

final class DeepgramClient: NSObject, URLSessionWebSocketDelegate {
    private var webSocket: URLSessionWebSocketTask?
    private var session: URLSession?
    private var keepaliveTimer: DispatchSourceTimer?
    private let apiKey: String
    private let channelCount: Int

    var onTranscript: ((DeepgramResponse) -> Void)?
    var onError: ((Error) -> Void)?
    var onConnected: (() -> Void)?

    init(apiKey: String, channelCount: Int = 1) {
        self.apiKey = apiKey
        self.channelCount = channelCount
        super.init()
    }

    func connect() {
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

        let urlString = "wss://api.deepgram.com/v1/listen?" + params.joined(separator: "&")
        guard let url = URL(string: urlString) else { return }

        var request = URLRequest(url: url)
        request.setValue("Token \(apiKey)", forHTTPHeaderField: "Authorization")

        session = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
        webSocket = session?.webSocketTask(with: request)
        webSocket?.resume()

        startReceiving()
        startKeepalive()
    }

    func sendAudio(_ data: Data) {
        webSocket?.send(.data(data)) { [weak self] error in
            if let error {
                print("[Deepgram] Send error: \(error.localizedDescription)")
                self?.onError?(error)
            }
        }
    }

    func disconnect() {
        keepaliveTimer?.cancel()
        keepaliveTimer = nil

        let closeMessage = "{\"type\": \"CloseStream\"}"
        webSocket?.send(.string(closeMessage)) { [weak self] _ in
            self?.webSocket?.cancel(with: .normalClosure, reason: nil)
            self?.webSocket = nil
        }
    }

    // MARK: - Private

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
                self?.onError?(error)
            }
        }
    }

    private func handleMessage(_ text: String) {
        guard let data = text.data(using: .utf8) else { return }

        do {
            let response = try JSONDecoder().decode(DeepgramResponse.self, from: data)
            guard let alt = response.channel.alternatives.first,
                  !alt.transcript.trimmingCharacters(in: .whitespaces).isEmpty else {
                return
            }
            onTranscript?(response)
        } catch {
            // Not all messages are transcript results (e.g., metadata, errors)
            // Silently ignore parse failures for non-Results messages
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

    // MARK: - URLSessionWebSocketDelegate

    func urlSession(
        _ session: URLSession,
        webSocketTask: URLSessionWebSocketTask,
        didOpenWithProtocol protocol: String?
    ) {
        print("[Deepgram] Connected")
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
