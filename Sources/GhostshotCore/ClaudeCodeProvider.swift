import Foundation

public final class ClaudeCodeProvider: AIProvider, @unchecked Sendable {
    public let name = "claude-code"

    /// Nil means the next call starts a fresh session. Persisted by the app across launches.
    public var sessionID: String?

    private let executablePath: String
    private let systemPrompt: String
    private let runner: ProcessRunner
    private let imageWriter: (Data) throws -> String

    public init(
        executablePath: String,
        systemPrompt: String,
        runner: ProcessRunner,
        imageWriter: @escaping (Data) throws -> String
    ) {
        self.executablePath = executablePath
        self.systemPrompt = systemPrompt
        self.runner = runner
        self.imageWriter = imageWriter
    }

    public func ask(history: [Message]) async throws -> String {
        guard let latest = history.last else {
            throw AIError.badResponse("empty history")
        }

        var imagePath: String?
        if let png = latest.imagePNG {
            do {
                imagePath = try imageWriter(png)
            } catch {
                throw AIError.providerUnavailable("could not write screenshot: \(error.localizedDescription)")
            }
        }

        let prompt = buildPrompt(history: history, imagePath: imagePath)
        let args = arguments(sessionID: sessionID)

        let result: ProcessResult
        do {
            result = try await runner.run(executable: executablePath, arguments: args, stdin: prompt)
        } catch {
            throw AIError.providerUnavailable(error.localizedDescription)
        }

        guard result.exitCode == 0 else {
            let detail = result.stderr.isEmpty ? result.stdout : result.stderr
            throw AIError.providerUnavailable("claude exited \(result.exitCode): \(detail.prefix(300))")
        }

        guard
            let data = result.stdout.data(using: .utf8),
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            throw AIError.badResponse("claude stdout was not JSON: \(result.stdout.prefix(300))")
        }

        if let newSession = json["session_id"] as? String {
            sessionID = newSession
        }

        let answer = json["result"] as? String ?? ""
        if (json["is_error"] as? Bool) == true {
            throw AIError.badResponse("claude reported an error: \(answer.prefix(300))")
        }
        guard !answer.isEmpty else { throw AIError.badResponse("claude returned an empty result") }
        return answer
    }

    /// The prompt is passed on stdin. `--allowedTools` is variadic and would eat a positional prompt.
    func arguments(sessionID: String?) -> [String] {
        var args = ["-p"]
        if let sessionID {
            args += ["--resume", sessionID]
        }
        args += ["--output-format", "json", "--allowedTools", "Read"]
        return args
    }

    func buildPrompt(history: [Message], imagePath: String?) -> String {
        var lines: [String] = []

        // A resumed session already holds the earlier turns, so replay them only on a fresh session.
        if sessionID == nil {
            lines.append(systemPrompt)
            let earlier = history.dropLast()
            if !earlier.isEmpty {
                lines.append("")
                lines.append("Earlier in this conversation:")
                for message in earlier {
                    let speaker = message.role == .user ? "Me" : "You"
                    lines.append("\(speaker): \(message.text)")
                }
            }
            lines.append("")
        }

        if let imagePath {
            lines.append("Read \(imagePath) and answer the question shown in it.")
        }
        if let latestText = history.last?.text, !latestText.isEmpty {
            lines.append(latestText)
        }

        return lines.joined(separator: "\n")
    }
}
