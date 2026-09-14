import Foundation

public final class GeminiProvider: AIProvider {
    /// One instance per API key, so the name carries which key answered ("gemini-2").
    public let name: String

    private let apiKey: String
    private let model: String
    private let systemPrompt: String
    private let client: HTTPClient

    public init(
        apiKey: String,
        model: String,
        systemPrompt: String,
        client: HTTPClient,
        name: String = "gemini"
    ) {
        self.name = name
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
            throw Self.classifyQuotaError(body: raw)
        }
        // A rejected credential is not a bad answer, it is an unusable provider:
        // surfacing it as .providerUnavailable lets the router move to the next key.
        // 404 lands here too: Google hides some models from newer projects, so one
        // key can be denied a model the others are served.
        if [401, 403, 404].contains(response.statusCode) {
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

    /// Google reports which window was exceeded in the QuotaFailure detail, as a
    /// `quotaId` such as `GenerateRequestsPerMinutePerProjectPerModel-FreeTier`.
    /// The distinction matters: the per-minute window clears within the minute,
    /// while the per-day one costs the rest of the day's allowance.
    ///
    /// An unrecognised body stays `.quotaExhausted`, the conservative reading —
    /// retrying a genuinely empty daily quota on every capture would put a failed
    /// round trip in front of every answer.
    static func classifyQuotaError(body: String) -> AIError {
        body.contains("PerMinute") ? .rateLimited : .quotaExhausted
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
