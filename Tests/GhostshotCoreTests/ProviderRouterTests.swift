import Foundation
import Testing
@testable import GhostshotCore

private final class StubProvider: AIProvider, @unchecked Sendable {
    let name: String
    var answer: String
    var error: AIError?
    private(set) var callCount = 0

    init(name: String, answer: String = "ok", error: AIError? = nil) {
        self.name = name
        self.answer = answer
        self.error = error
    }

    func ask(history: [Message]) async throws -> String {
        callCount += 1
        if let error { throw error }
        return answer
    }
}

/// A class suite: these tests mutate `state` across the router's callbacks.
@Suite final class ProviderRouterTests {
    private var state = AppState()
    private let history = [Message(role: .user, text: "q")]

    private func makeRouter(
        primary: StubProvider,
        fallback: StubProvider,
        today: String = "2026-09-04"
    ) -> ProviderRouter {
        ProviderRouter(
            primary: primary,
            fallback: fallback,
            loadState: { self.state },
            saveState: { self.state = $0 },
            today: { today }
        )
    }

    @Test func usesPrimaryWhenItWorks() async throws {
        let primary = StubProvider(name: "gemini", answer: "from gemini")
        let fallback = StubProvider(name: "claude-code")

        let answer = try await makeRouter(primary: primary, fallback: fallback).ask(history: history)

        #expect(answer.text == "from gemini")
        #expect(answer.providerName == "gemini")
        #expect(fallback.callCount == 0)
    }

    @Test func quotaExhaustedFailsOverAndRecordsTheDate() async throws {
        let primary = StubProvider(name: "gemini", error: .quotaExhausted)
        let fallback = StubProvider(name: "claude-code", answer: "from claude")

        let answer = try await makeRouter(primary: primary, fallback: fallback).ask(history: history)

        #expect(answer.text == "from claude")
        #expect(answer.providerName == "claude-code")
        #expect(state.geminiExhaustedOn == "2026-09-04")
    }

    @Test func sameDaySkipsPrimaryEntirely() async throws {
        state.geminiExhaustedOn = "2026-09-04"
        let primary = StubProvider(name: "gemini", answer: "should not be used")
        let fallback = StubProvider(name: "claude-code", answer: "from claude")

        let answer = try await makeRouter(primary: primary, fallback: fallback).ask(history: history)

        #expect(primary.callCount == 0)
        #expect(answer.providerName == "claude-code")
    }

    @Test func nextDayRetriesPrimary() async throws {
        state.geminiExhaustedOn = "2026-09-03"
        let primary = StubProvider(name: "gemini", answer: "gemini is back")
        let fallback = StubProvider(name: "claude-code")

        let answer = try await makeRouter(primary: primary, fallback: fallback, today: "2026-09-04")
            .ask(history: history)

        #expect(primary.callCount == 1)
        #expect(answer.text == "gemini is back")
    }

    @Test func nonQuotaErrorDoesNotFailOver() async {
        let primary = StubProvider(name: "gemini", error: .network("offline"))
        let fallback = StubProvider(name: "claude-code")

        do {
            _ = try await makeRouter(primary: primary, fallback: fallback).ask(history: history)
            Issue.record("expected a throw")
        } catch let error as AIError {
            #expect(error == .network("offline"))
            #expect(fallback.callCount == 0)
        } catch {
            Issue.record("expected AIError, got \(error)")
        }
    }

    @Test func bothProvidersFailSurfacesFallbackError() async {
        let primary = StubProvider(name: "gemini", error: .quotaExhausted)
        let fallback = StubProvider(name: "claude-code", error: .providerUnavailable("claude missing"))

        do {
            _ = try await makeRouter(primary: primary, fallback: fallback).ask(history: history)
            Issue.record("expected a throw")
        } catch let error as AIError {
            #expect(error == .providerUnavailable("claude missing"))
        } catch {
            Issue.record("expected AIError, got \(error)")
        }
    }

    @Test func unavailablePrimaryFailsOverWithoutMarkingTheDayExhausted() async throws {
        let primary = StubProvider(name: "gemini", error: .providerUnavailable("no Gemini API key configured"))
        let fallback = StubProvider(name: "claude-code", answer: "from claude")

        let answer = try await makeRouter(primary: primary, fallback: fallback).ask(history: history)

        #expect(answer.text == "from claude")
        #expect(answer.providerName == "claude-code")
        // Not sticky: a missing key or a bad credential may be fixed at any time,
        // so the next capture tries Gemini again.
        #expect(state.geminiExhaustedOn == nil)
    }
}
