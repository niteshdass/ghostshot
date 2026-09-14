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
        makeRouter(primaries: [primary], fallback: fallback, today: today)
    }

    private func makeRouter(
        primaries: [StubProvider],
        fallback: StubProvider,
        today: String = "2026-09-04"
    ) -> ProviderRouter {
        ProviderRouter(
            primaries: primaries,
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
        #expect(state.exhaustedOn["gemini"] == "2026-09-04")
    }

    @Test func sameDaySkipsPrimaryEntirely() async throws {
        state.exhaustedOn["gemini"] = "2026-09-04"
        let primary = StubProvider(name: "gemini", answer: "should not be used")
        let fallback = StubProvider(name: "claude-code", answer: "from claude")

        let answer = try await makeRouter(primary: primary, fallback: fallback).ask(history: history)

        #expect(primary.callCount == 0)
        #expect(answer.providerName == "claude-code")
    }

    @Test func nextDayRetriesPrimary() async throws {
        state.exhaustedOn["gemini"] = "2026-09-03"
        let primary = StubProvider(name: "gemini", answer: "gemini is back")
        let fallback = StubProvider(name: "claude-code")

        let answer = try await makeRouter(primary: primary, fallback: fallback, today: "2026-09-04")
            .ask(history: history)

        #expect(primary.callCount == 1)
        #expect(answer.text == "gemini is back")
    }

    @Test func rateLimitedFailsOverWithoutMarkingTheDayExhausted() async throws {
        let primary = StubProvider(name: "gemini", error: .rateLimited)
        let fallback = StubProvider(name: "claude-code", answer: "from claude")

        let answer = try await makeRouter(primary: primary, fallback: fallback).ask(history: history)

        #expect(answer.providerName == "claude-code")
        // A per-minute throttle clears within the minute. Marking the day exhausted
        // here would spend the rest of the daily allowance on the fallback.
        #expect(state.exhaustedOn["gemini"] == nil)
    }

    /// Google refills RPD at midnight Pacific, so the app's day has to flip there
    /// too — on a local clock the two boundaries drift by hours.
    @Test func todayStringUsesGooglesPacificResetBoundary() {
        // 2026-09-04 00:30 PDT
        #expect(ProviderRouter.todayString(for: Date(timeIntervalSince1970: 1_788_507_000)) == "2026-09-04")
        // 2026-09-03 23:30 PDT, one hour earlier
        #expect(ProviderRouter.todayString(for: Date(timeIntervalSince1970: 1_788_503_400)) == "2026-09-03")
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
        #expect(state.exhaustedOn["gemini"] == nil)
    }

    // MARK: - Several keys

    @Test func exhaustedKeyHandsOverToTheNextKeyNotToTheFallback() async throws {
        let first = StubProvider(name: "gemini-1", error: .quotaExhausted)
        let second = StubProvider(name: "gemini-2", answer: "from the second key")
        let fallback = StubProvider(name: "claude-code")

        let answer = try await makeRouter(primaries: [first, second], fallback: fallback)
            .ask(history: history)

        #expect(answer.text == "from the second key")
        #expect(answer.providerName == "gemini-2")
        #expect(fallback.callCount == 0)
        // Only the burnt key is recorded.
        #expect(state.exhaustedOn == ["gemini-1": "2026-09-04"])
    }

    @Test func fallbackOnlyAfterEveryKeyIsExhausted() async throws {
        let keys = (1...3).map { StubProvider(name: "gemini-\($0)", error: .quotaExhausted) }
        let fallback = StubProvider(name: "claude-code", answer: "from claude")

        let answer = try await makeRouter(primaries: keys, fallback: fallback).ask(history: history)

        #expect(answer.providerName == "claude-code")
        #expect(keys.allSatisfy { $0.callCount == 1 })
        #expect(state.exhaustedOn.count == 3)
    }

    @Test func sameDaySkipsTheBurntKeyAndStartsAtTheNextOne() async throws {
        state.exhaustedOn = ["gemini-1": "2026-09-04"]
        let first = StubProvider(name: "gemini-1", answer: "should not be used")
        let second = StubProvider(name: "gemini-2", answer: "from the second key")
        let fallback = StubProvider(name: "claude-code")

        let answer = try await makeRouter(primaries: [first, second], fallback: fallback)
            .ask(history: history)

        #expect(first.callCount == 0)
        #expect(answer.providerName == "gemini-2")
    }

    @Test func aKeyBurntYesterdayIsTriedAgainToday() async throws {
        state.exhaustedOn = ["gemini-1": "2026-09-03"]
        let first = StubProvider(name: "gemini-1", answer: "key one is back")
        let second = StubProvider(name: "gemini-2")

        let answer = try await makeRouter(
            primaries: [first, second],
            fallback: StubProvider(name: "claude-code"),
            today: "2026-09-04"
        ).ask(history: history)

        #expect(answer.providerName == "gemini-1")
        #expect(second.callCount == 0)
    }

    @Test func aRejectedKeyIsSkippedWithoutBeingMarkedExhausted() async throws {
        let first = StubProvider(name: "gemini-1", error: .providerUnavailable("bad key"))
        let second = StubProvider(name: "gemini-2", answer: "from the second key")

        let answer = try await makeRouter(
            primaries: [first, second],
            fallback: StubProvider(name: "claude-code")
        ).ask(history: history)

        #expect(answer.providerName == "gemini-2")
        #expect(state.exhaustedOn.isEmpty)
    }

    @Test func noKeysAtAllGoesStraightToTheFallback() async throws {
        let fallback = StubProvider(name: "claude-code", answer: "from claude")

        let answer = try await makeRouter(primaries: [], fallback: fallback).ask(history: history)

        #expect(answer.providerName == "claude-code")
    }
}
