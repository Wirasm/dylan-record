import Testing
@testable import DylanRecord

@Suite("DeepgramClient URL Construction")
struct DeepgramClientTests {
    // We can't test the actual WebSocket connection, but we can verify
    // the URL is constructed correctly by making the connect method's
    // URL construction testable.

    @Test("URL includes multichannel for 2 channels")
    func multichannel() {
        let url = DeepgramClient.buildURL(channelCount: 2, language: nil, keyterms: [])
        #expect(url?.absoluteString.contains("multichannel=true") == true)
        #expect(url?.absoluteString.contains("channels=2") == true)
    }

    @Test("URL does not include multichannel for 1 channel")
    func singleChannel() {
        let url = DeepgramClient.buildURL(channelCount: 1, language: nil, keyterms: [])
        #expect(url?.absoluteString.contains("multichannel") == false)
        #expect(url?.absoluteString.contains("channels=1") == true)
    }

    @Test("URL includes specific language when set")
    func specificLanguage() {
        let url = DeepgramClient.buildURL(channelCount: 1, language: "sv", keyterms: [])
        #expect(url?.absoluteString.contains("language=sv") == true)
    }

    @Test("URL uses multi language when no language specified")
    func multiLanguage() {
        let url = DeepgramClient.buildURL(channelCount: 1, language: nil, keyterms: [])
        #expect(url?.absoluteString.contains("language=multi") == true)
    }

    @Test("URL includes keyterms")
    func keyterms() {
        let url = DeepgramClient.buildURL(channelCount: 1, language: nil, keyterms: ["Sasha", "Claude Code"])
        let urlStr = url?.absoluteString ?? ""
        #expect(urlStr.contains("keyterm=Sasha"))
        #expect(urlStr.contains("keyterm=Claude%20Code"))
    }

    @Test("URL does not include detect_language (not supported for streaming)")
    func noDetectLanguage() {
        let url = DeepgramClient.buildURL(channelCount: 2, language: nil, keyterms: [])
        #expect(url?.absoluteString.contains("detect_language") == false)
    }

    @Test("URL uses nova-3 model")
    func nova3Model() {
        let url = DeepgramClient.buildURL(channelCount: 1, language: nil, keyterms: [])
        #expect(url?.absoluteString.contains("model=nova-3") == true)
    }
}
