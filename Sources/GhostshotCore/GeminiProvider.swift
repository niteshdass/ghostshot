import Foundation

public final class GeminiProvider: AIProvider {
    public let name = "gemini"

    private let apiKey: String
    private let model: String
    private let systemPrompt: String
    private let client: HTTPClient

    public init(apiKey: String, model: String, systemPrompt: String, client: HTTPClient) {
        self.apiKey = apiKey
        self.model = model
        self.systemPrompt = systemPrompt
        self.client = client
    }

    public func ask(history: [Message]) async throws -> String {
        guard !apiKey.isEmpty else {
            throw AIError.providerUnavailable("no Gemini API key configured")
        }
        let request = try buildRequest(history: history)

        let data: Data
        let response: HTTPURLResponse
        do {
            (data, response) = try await client.send(request)
        } catch let error as AIError {
            throw error
        } catch {
            throw AIError.network(error.localizedDescription)
        }

        let raw = String(decoding: data, as: UTF8.self)
        if response.statusCode == 429 || raw.contains("RESOURCE_EXHAUSTED") {
            throw AIError.quotaExhausted
        }
        // A rejected credential is not a bad answer, it is an unusable provider:
        // surfacing it as .providerUnavailable lets the router fall back to Claude.
        if response.statusCode == 401 || response.statusCode == 403 {
            throw AIError.providerUnavailable("HTTP \(response.statusCode): \(raw.prefix(300))")
        }
        guard (200..<300).contains(response.statusCode) else {
            throw AIError.badResponse("HTTP \(response.statusCode): \(raw.prefix(300))")
        }

        guard
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let candidates = json["candidates"] as? [[String: Any]],
            let content = candidates.first?["content"] as? [String: Any],
            let parts = content["parts"] as? [[String: Any]]
        else {
            throw AIError.badResponse("unexpected body: \(raw.prefix(300))")
        }

        let text = parts.compactMap { $0["text"] as? String }.joined()
        guard !text.isEmpty else { throw AIError.badResponse("empty answer") }
        return text
    }

    func buildRequest(history: [Message]) throws -> URLRequest {
        let urlString = "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent"
        guard let url = URL(string: urlString) else {
            throw AIError.badResponse("bad model name: \(model)")
        }

        let contents: [[String: Any]] = history.map { message in
            var parts: [[String: Any]] = []
            if !message.text.isEmpty {
                parts.append(["text": message.text])
            }
            if let png = message.imagePNG {
                parts.append(["inline_data": ["mime_type": "image/png", "data": png.base64EncodedString()]])
            }
            if parts.isEmpty { parts.append(["text": ""]) }
            return ["role": message.role == .user ? "user" : "model", "parts": parts]
        }

        let body: [String: Any] = [
            "system_instruction": ["parts": [["text": systemPrompt]]],
            "contents": contents,
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }
}
