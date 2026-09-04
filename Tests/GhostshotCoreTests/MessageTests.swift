import Foundation
import Testing
@testable import GhostshotCore

@Suite struct MessageTests {
    @Test func userMessageCarriesTextAndImage() {
        let png = Data([0x89, 0x50, 0x4E, 0x47])
        let m = Message(role: .user, text: "what is this", imagePNG: png)
        #expect(m.role == .user)
        #expect(m.text == "what is this")
        #expect(m.imagePNG == png)
    }

    @Test func assistantMessageHasNoImageByDefault() {
        let m = Message(role: .assistant, text: "it is a terminal")
        #expect(m.imagePNG == nil)
    }

    @Test func quotaExhaustedIsDistinctFromOtherErrors() {
        #expect(AIError.quotaExhausted != AIError.network("offline"))
    }
}
