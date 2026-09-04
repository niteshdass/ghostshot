import Foundation
import Testing
@testable import GhostshotCore

@Suite struct ProcessRunnerTests {
    @Test func passesStdinAndCapturesStdout() async throws {
        let runner = SystemProcessRunner()
        let result = try await runner.run(executable: "/bin/cat", arguments: [], stdin: "hello ghostshot")

        #expect(result.exitCode == 0)
        #expect(result.stdout == "hello ghostshot")
    }

    @Test func capturesNonZeroExitAndStderr() async throws {
        let runner = SystemProcessRunner()
        let result = try await runner.run(
            executable: "/bin/sh",
            arguments: ["-c", "echo boom >&2; exit 3"],
            stdin: ""
        )

        #expect(result.exitCode == 3)
        #expect(result.stderr.contains("boom"))
    }

    @Test func handlesLargeStdinWithoutDeadlock() async throws {
        let runner = SystemProcessRunner()
        let big = String(repeating: "x", count: 200_000)
        let result = try await runner.run(executable: "/bin/cat", arguments: [], stdin: big)

        #expect(result.stdout.count == big.count)
    }
}
