import Foundation
import Testing
@testable import GhostshotCore

@Suite struct GeminiProviderTests {
    private func makeProvider(_ client: FakeHTTPClient) -> GeminiProvider {
        GeminiProvider(apiKey: "KEY123", model: "gemini-2.5-flash", systemPrompt: "be terse", client: client)
    }

    private func successBody(_ text: String) -> Data {
        Data(#"{"candidates":[{"content":{"parts":[{"text":"\#(text)"}],"role":"model"}}]}"#.utf8)
    }

    @Test func buildsCorrectURLAndAuthHeader() async throws {
        let client = FakeHTTPClient()
        client.responses = [(successBody("hi"), 200)]

        _ = try await makeProvider(client).ask(history: [Message(role: .user, text: "q")])

        let request = try #require(client.sentRequests.last)
        #expect(request.url?.absoluteString
            == "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent")
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "x-goog-api-key") == "KEY123")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
    }

    @Test func sendsSystemInstructionAndFullHistoryWithMappedRoles() async throws {
        let client = FakeHTTPClient()
        client.responses = [(successBody("ok"), 200)]
        let history = [
            Message(role: .user, text: "first"),
            Message(role: .assistant, text: "answer"),
            Message(role: .user, text: "second"),
        ]

        _ = try await makeProvider(client).ask(history: history)

        let json = client.lastBodyJSON
        let system = json["system_instruction"] as? [String: Any]
        let systemParts = system?["parts"] as? [[String: Any]]
        #expect(systemParts?.first?["text"] as? String == "be terse")

        let contents = try #require(json["contents"] as? [[String: Any]])
        #expect(contents.count == 3)
        #expect(contents[0]["role"] as? String == "user")
        #expect(contents[1]["role"] as? String == "model")
        #expect(contents[2]["role"] as? String == "user")
    }

    @Test func encodesImageAsBase64InlineData() async throws {
        let client = FakeHTTPClient()
        client.responses = [(successBody("ok"), 200)]
        let png = Data([0x89, 0x50, 0x4E, 0x47])

        _ = try await makeProvider(client).ask(history: [Message(role: .user, text: "q", imagePNG: png)])

        let contents = try #require(client.lastBodyJSON["contents"] as? [[String: Any]])
        let parts = try #require(contents[0]["parts"] as? [[String: Any]])
        let inline = try #require(parts.compactMap { $0["inline_data"] as? [String: Any] }.first)
        #expect(inline["mime_type"] as? String == "image/png")
        #expect(inline["data"] as? String == png.base64EncodedString())
    }

    @Test func joinsAllTextPartsOfTheAnswer() async throws {
        let client = FakeHTTPClient()
        client.responses = [(Data(#"{"candidates":[{"content":{"parts":[{"text":"one "},{"text":"two"}]}}]}"#.utf8), 200)]

        let answer = try await makeProvider(client).ask(history: [Message(role: .user, text: "q")])

        #expect(answer == "one two")
    }

    @Test func http429MapsToQuotaExhausted() async {
        let client = FakeHTTPClient()
        client.responses = [(Data(#"{"error":{"message":"rate limited"}}"#.utf8), 429)]

        await #expect(throws: AIError.quotaExhausted) {
            _ = try await makeProvider(client).ask(history: [Message(role: .user, text: "q")])
        }
    }

    @Test func resourceExhaustedInBodyMapsToQuotaExhausted() async {
        let client = FakeHTTPClient()
        client.responses = [(Data(#"{"error":{"status":"RESOURCE_EXHAUSTED"}}"#.utf8), 200)]

        await #expect(throws: AIError.quotaExhausted) {
            _ = try await makeProvider(client).ask(history: [Message(role: .user, text: "q")])
        }
    }

    @Test func unparseableBodyMapsToBadResponse() async {
        let client = FakeHTTPClient()
        client.responses = [(Data("<html>nope</html>".utf8), 200)]

        do {
            _ = try await makeProvider(client).ask(history: [Message(role: .user, text: "q")])
            Issue.record("expected a throw")
        } catch let error as AIError {
            guard case .badResponse = error else {
                Issue.record("expected badResponse, got \(error)")
                return
            }
        } catch {
            Issue.record("expected AIError, got \(error)")
        }
    }
}

@Suite struct GeminiProviderAvailabilityTests {
    private func message() -> [Message] {
        [Message(role: .user, text: "hi")]
    }

    @Test func emptyAPIKeyFailsWithoutTouchingTheNetwork() async {
        let client = FakeHTTPClient()
        let provider = GeminiProvider(apiKey: "", model: "gemini-2.5-flash", systemPrompt: "s", client: client)

        await #expect(throws: AIError.providerUnavailable("no Gemini API key configured")) {
            try await provider.ask(history: message())
        }
        #expect(client.sentRequests.isEmpty)
    }

    @Test func rejectedCredentialsAreProviderUnavailableSoTheRouterCanFallBack() async {
        for status in [401, 403] {
            let client = FakeHTTPClient()
            client.responses = [(Data(#"{"error":{"code":\#(status)}}"#.utf8), status)]
            let provider = GeminiProvider(apiKey: "k", model: "m", systemPrompt: "s", client: client)

            do {
                _ = try await provider.ask(history: message())
                Issue.record("expected HTTP \(status) to throw")
            } catch let error as AIError {
                guard case .providerUnavailable = error else {
                    Issue.record("HTTP \(status) gave \(error), wanted .providerUnavailable")
                    return
                }
            } catch {
                Issue.record("unexpected error \(error)")
            }
        }
    }
}
