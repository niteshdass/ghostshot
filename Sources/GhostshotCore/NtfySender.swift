import Foundation

public struct NtfySender {
    public static let maxBodyCharacters = 3800

    private let topic: String
    private let client: HTTPClient

    public init(topic: String, client: HTTPClient) {
        self.topic = topic
        self.client = client
    }

    public func send(title: String, body: String) async {
        guard !topic.isEmpty,
              let url = URL(string: "https://ntfy.sh/\(topic)")
        else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(title, forHTTPHeaderField: "Title")
        request.httpBody = Data(Self.truncate(body).utf8)

        _ = try? await client.send(request)
    }

    static func truncate(_ text: String) -> String {
        guard text.count > maxBodyCharacters else { return text }
        return String(text.prefix(maxBodyCharacters - 1)) + "…"
    }
}
