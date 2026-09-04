import Foundation
import Testing
@testable import GhostshotCore

@Suite struct NtfySenderTests {
    @Test func postsToTopicURLWithTitleHeader() async {
        let client = FakeHTTPClient()
        await NtfySender(topic: "my-secret-topic", client: client).send(title: "Answer", body: "hello")

        let request = client.sentRequests.last
        #expect(request?.url?.absoluteString == "https://ntfy.sh/my-secret-topic")
        #expect(request?.httpMethod == "POST")
        #expect(request?.value(forHTTPHeaderField: "Title") == "Answer")
        #expect(request?.httpBody == Data("hello".utf8))
    }

    @Test func truncatesLongBodies() async {
        let client = FakeHTTPClient()
        let long = String(repeating: "x", count: 5000)

        await NtfySender(topic: "t", client: client).send(title: "Answer", body: long)

        let body = String(decoding: client.sentRequests.last?.httpBody ?? Data(), as: UTF8.self)
        #expect(body.count == NtfySender.maxBodyCharacters)
        #expect(body.hasSuffix("…"))
    }

    @Test func emptyTopicSendsNothing() async {
        let client = FakeHTTPClient()
        await NtfySender(topic: "", client: client).send(title: "Answer", body: "hello")

        #expect(client.sentRequests.isEmpty)
    }

    @Test func networkFailureIsSwallowed() async {
        let client = FakeHTTPClient()
        client.thrownError = AIError.network("offline")

        await NtfySender(topic: "t", client: client).send(title: "Answer", body: "hello")

        #expect(client.sentRequests.count == 1)
    }
}
