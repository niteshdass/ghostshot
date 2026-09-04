import Foundation
import Testing
@testable import GhostshotCore

@Suite struct ClaudeCodeProviderTests {
    private func makeProvider(_ runner: FakeProcessRunner) -> ClaudeCodeProvider {
        ClaudeCodeProvider(
            executablePath: "/usr/local/bin/claude",
            systemPrompt: "be terse",
            runner: runner,
            imageWriter: { _ in "/tmp/ghostshot/shot.png" }
        )
    }

    private func resultJSON(sessionID: String, answer: String, isError: Bool = false) -> ProcessResult {
        let json = #"{"session_id":"\#(sessionID)","is_error":\#(isError),"result":"\#(answer)"}"#
        return ProcessResult(exitCode: 0, stdout: json, stderr: "")
    }

    @Test func firstCallOmitsResumeAndSendsPromptOnStdin() async throws {
        let runner = FakeProcessRunner()
        runner.results = [resultJSON(sessionID: "s-1", answer: "the answer")]

        let answer = try await makeProvider(runner)
            .ask(history: [Message(role: .user, text: "what is this", imagePNG: Data([0x89]))])

        #expect(answer == "the answer")
        let call = try #require(runner.calls.last)
        #expect(call.executable == "/usr/local/bin/claude")
        #expect(!call.arguments.contains("--resume"))
        #expect(call.arguments == ["-p", "--output-format", "json", "--allowedTools", "Read"])
        // The prompt must be on stdin, never a positional argument:
        // --allowedTools is variadic and would swallow it.
        #expect(call.stdin.contains("/tmp/ghostshot/shot.png"))
        #expect(!call.arguments.contains(where: { $0.contains("/tmp/ghostshot/shot.png") }))
    }

    @Test func storesSessionIDAndResumesOnSecondCall() async throws {
        let runner = FakeProcessRunner()
        runner.results = [
            resultJSON(sessionID: "s-1", answer: "first"),
            resultJSON(sessionID: "s-1", answer: "second"),
        ]
        let provider = makeProvider(runner)

        _ = try await provider.ask(history: [Message(role: .user, text: "a", imagePNG: Data([0x89]))])
        #expect(provider.sessionID == "s-1")

        _ = try await provider.ask(history: [Message(role: .user, text: "b", imagePNG: Data([0x89]))])

        let call = try #require(runner.calls.last)
        #expect(call.arguments == ["-p", "--resume", "s-1", "--output-format", "json", "--allowedTools", "Read"])
    }

    @Test func firstPromptCarriesPriorHistoryAsText() async throws {
        let runner = FakeProcessRunner()
        runner.results = [resultJSON(sessionID: "s-1", answer: "ok")]
        let history = [
            Message(role: .user, text: "earlier question"),
            Message(role: .assistant, text: "earlier answer"),
            Message(role: .user, text: "current question", imagePNG: Data([0x89])),
        ]

        _ = try await makeProvider(runner).ask(history: history)

        let stdin = try #require(runner.calls.last?.stdin)
        #expect(stdin.contains("earlier question"))
        #expect(stdin.contains("earlier answer"))
        #expect(stdin.contains("be terse"))
    }

    @Test func resumedPromptDoesNotRepeatHistory() async throws {
        let runner = FakeProcessRunner()
        runner.results = [
            resultJSON(sessionID: "s-1", answer: "first"),
            resultJSON(sessionID: "s-1", answer: "second"),
        ]
        let provider = makeProvider(runner)

        _ = try await provider.ask(history: [Message(role: .user, text: "unique-earlier-text", imagePNG: Data([0x89]))])
        _ = try await provider.ask(history: [
            Message(role: .user, text: "unique-earlier-text", imagePNG: Data([0x89])),
            Message(role: .assistant, text: "first"),
            Message(role: .user, text: "now this", imagePNG: Data([0x89])),
        ])

        let stdin = try #require(runner.calls.last?.stdin)
        #expect(!stdin.contains("unique-earlier-text"))
        #expect(stdin.contains("now this"))
    }

    @Test func isErrorTrueThrowsBadResponse() async {
        let runner = FakeProcessRunner()
        runner.results = [resultJSON(sessionID: "s-1", answer: "went wrong", isError: true)]

        await expectAIError(makeProvider(runner)) { error in
            guard case .badResponse = error else {
                Issue.record("expected badResponse, got \(error)")
                return
            }
        }
    }

    @Test func nonZeroExitThrowsProviderUnavailable() async {
        let runner = FakeProcessRunner()
        runner.results = [ProcessResult(exitCode: 1, stdout: "", stderr: "command not found")]

        await expectAIError(makeProvider(runner)) { error in
            guard case .providerUnavailable = error else {
                Issue.record("expected providerUnavailable, got \(error)")
                return
            }
        }
    }

    @Test func unparseableStdoutThrowsBadResponse() async {
        let runner = FakeProcessRunner()
        runner.results = [ProcessResult(exitCode: 0, stdout: "not json", stderr: "")]

        await expectAIError(makeProvider(runner)) { error in
            guard case .badResponse = error else {
                Issue.record("expected badResponse, got \(error)")
                return
            }
        }
    }

    @Test func resetSessionClearsResume() async throws {
        let runner = FakeProcessRunner()
        runner.results = [
            resultJSON(sessionID: "s-1", answer: "first"),
            resultJSON(sessionID: "s-2", answer: "fresh"),
        ]
        let provider = makeProvider(runner)

        _ = try await provider.ask(history: [Message(role: .user, text: "a", imagePNG: Data([0x89]))])
        provider.sessionID = nil
        _ = try await provider.ask(history: [Message(role: .user, text: "b", imagePNG: Data([0x89]))])

        let call = try #require(runner.calls.last)
        #expect(!call.arguments.contains("--resume"))
        #expect(provider.sessionID == "s-2")
    }

    private func expectAIError(
        _ provider: ClaudeCodeProvider,
        check: (AIError) -> Void
    ) async {
        do {
            _ = try await provider.ask(history: [Message(role: .user, text: "q", imagePNG: Data([0x89]))])
            Issue.record("expected a throw")
        } catch let error as AIError {
            check(error)
        } catch {
            Issue.record("expected AIError, got \(error)")
        }
    }
}
