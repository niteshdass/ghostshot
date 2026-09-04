import Foundation

public final class Conversation {
    public static let earlierScreenshotPlaceholder = "[earlier screenshot]"

    public private(set) var messages: [Message] = []
    public private(set) var claudeSessionID: String?

    private let maxImages: Int

    public init(maxImages: Int = 2) {
        self.maxImages = maxImages
    }

    public func addUser(text: String, imagePNG: Data?) {
        messages.append(Message(role: .user, text: text, imagePNG: imagePNG))
        trimImages()
    }

    public func addAssistant(_ text: String) {
        messages.append(Message(role: .assistant, text: text))
    }

    public func setClaudeSessionID(_ id: String?) {
        claudeSessionID = id
    }

    public func reset() {
        messages.removeAll()
        claudeSessionID = nil
    }

    /// Walks newest to oldest, keeps `maxImages` images, strips the rest.
    private func trimImages() {
        var kept = 0
        for index in messages.indices.reversed() {
            guard messages[index].imagePNG != nil else { continue }
            if kept < maxImages {
                kept += 1
                continue
            }
            messages[index].imagePNG = nil
            let text = messages[index].text
            messages[index].text = text.isEmpty
                ? Self.earlierScreenshotPlaceholder
                : text + "\n" + Self.earlierScreenshotPlaceholder
        }
    }
}
