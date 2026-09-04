import Foundation
import Testing
@testable import GhostshotCore

@Suite struct ConversationTests {
    private func png(_ byte: UInt8) -> Data { Data([0x89, byte]) }

    @Test func keepsOnlyTwoMostRecentImages() {
        let c = Conversation(maxImages: 2)
        c.addUser(text: "one", imagePNG: png(1))
        c.addUser(text: "two", imagePNG: png(2))
        c.addUser(text: "three", imagePNG: png(3))

        #expect(c.messages[0].imagePNG == nil)
        #expect(c.messages[1].imagePNG == png(2))
        #expect(c.messages[2].imagePNG == png(3))
    }

    @Test func strippedMessageGainsPlaceholder() {
        let c = Conversation(maxImages: 1)
        c.addUser(text: "one", imagePNG: png(1))
        c.addUser(text: "two", imagePNG: png(2))

        #expect(c.messages[0].text.hasSuffix(Conversation.earlierScreenshotPlaceholder))
        #expect(c.messages[0].text.hasPrefix("one"))
    }

    @Test func placeholderIsNotAppendedTwice() {
        let c = Conversation(maxImages: 1)
        c.addUser(text: "one", imagePNG: png(1))
        c.addUser(text: "two", imagePNG: png(2))
        c.addUser(text: "three", imagePNG: png(3))

        let occurrences = c.messages[0].text
            .components(separatedBy: Conversation.earlierScreenshotPlaceholder)
            .count - 1
        #expect(occurrences == 1)
    }

    @Test func assistantMessagesAreNeverTrimmed() {
        let c = Conversation(maxImages: 1)
        c.addUser(text: "one", imagePNG: png(1))
        c.addAssistant("an answer")
        c.addUser(text: "two", imagePNG: png(2))

        #expect(c.messages[1].role == .assistant)
        #expect(c.messages[1].text == "an answer")
    }

    @Test func resetClearsMessagesAndSessionID() {
        let c = Conversation(maxImages: 2)
        c.addUser(text: "one", imagePNG: png(1))
        c.setClaudeSessionID("abc-123")

        c.reset()

        #expect(c.messages.isEmpty)
        #expect(c.claudeSessionID == nil)
    }
}
