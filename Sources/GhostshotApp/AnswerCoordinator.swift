import AppKit
import Foundation
import GhostshotCore

/// Owns the conversation and drives one capture -> ask -> deliver cycle.
@MainActor
final class AnswerCoordinator {
    private let config: Config
    private let store: ConfigStore
    private let conversation = Conversation()
    private let router: ProviderRouter
    private let claude: ClaudeCodeProvider
    private let ntfy: NtfySender
    private let panel: OverlayPanel

    /// Sent with every screenshot. The standing instructions live in the
    /// system prompt; this only points the model at the new image.
    static let turnPrompt = "Here is my current screen. Answer the question on it."

    private var inFlight = false
    private var turn = 0

    init(config: Config, store: ConfigStore, panel: OverlayPanel) {
        self.config = config
        self.store = store
        self.panel = panel

        let http = URLSessionHTTPClient()
        let gemini = GeminiProvider(
            apiKey: config.geminiApiKey,
            model: config.geminiModel,
            systemPrompt: config.systemPrompt,
            client: http
        )
        let claude = ClaudeCodeProvider(
            executablePath: AnswerCoordinator.resolveClaudePath(),
            systemPrompt: config.systemPrompt,
            runner: SystemProcessRunner(),
            imageWriter: AnswerCoordinator.writeTemporaryPNG
        )
        self.claude = claude
        self.ntfy = NtfySender(topic: config.notifyPhone ? config.ntfyTopic : "", client: http)

        // The router persists quota state; capture the store, not self.
        self.router = ProviderRouter(
            primary: gemini,
            fallback: claude,
            loadState: { store.loadState() },
            saveState: { store.saveState($0) }
        )

        // Resume the previous Claude Code session so the conversation survives relaunch.
        let state = store.loadState()
        claude.sessionID = state.claudeSessionID
        conversation.setClaudeSessionID(state.claudeSessionID)
    }

    // MARK: - Actions

    func handle(_ action: HotkeyAction) {
        switch action {
        case .capture:
            captureAndAsk()
        case .togglePanel:
            panel.toggleVisibility()
        case .resetConversation:
            resetConversation()
        case .quit:
            quit()
        }
    }

    /// The app has no Dock icon and no menu bar, so this hotkey is the only way
    /// to stop it from the keyboard.
    private func quit() {
        NSApp.terminate(nil)
    }

    private func resetConversation() {
        conversation.reset()
        claude.sessionID = nil
        var state = store.loadState()
        state.claudeSessionID = nil
        store.saveState(state)
        panel.setAnswer("", status: "conversation reset")
        panel.showWithoutFocus()
    }

    private func captureAndAsk() {
        guard !inFlight else {
            panel.setStatus("still working on the previous one…")
            return
        }
        inFlight = true
        turn += 1
        let thisTurn = turn

        panel.setStatus("capturing…")

        Task { @MainActor in
            defer { inFlight = false }

            let png: Data
            do {
                png = try await ScreenCapturer.capture(
                    excludingWindowNumbers: [panel.windowNumber]
                )
            } catch {
                panel.setAnswer(error.localizedDescription, status: "capture failed")
                panel.showWithoutFocus()
                return
            }

            panel.setStatus("thinking… (turn \(thisTurn))")

            conversation.addUser(text: Self.turnPrompt, imagePNG: png)
            let history = conversation.messages

            do {
                let answer = try await router.ask(history: history)
                conversation.addAssistant(answer.text)
                persistClaudeSession()
                deliver(answer)
            } catch {
                panel.setAnswer(
                    Self.describe(error),
                    status: "failed"
                )
                panel.showWithoutFocus()
            }
        }
    }

    private func deliver(_ answer: RouterAnswer) {
        panel.setAnswer(answer.text, status: "\(answer.providerName) · turn \(turn)")
        panel.showWithoutFocus()

        if config.copyToClipboard {
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(answer.text, forType: .string)
        }

        if config.notifyPhone {
            let body = answer.text
            Task { await ntfy.send(title: "Ghostshot", body: body) }
        }
    }

    private func persistClaudeSession() {
        guard let id = claude.sessionID else { return }
        var state = store.loadState()
        guard state.claudeSessionID != id else { return }
        state.claudeSessionID = id
        store.saveState(state)
        conversation.setClaudeSessionID(id)
    }

    private static func describe(_ error: Error) -> String {
        guard let aiError = error as? AIError else { return error.localizedDescription }
        switch aiError {
        case .quotaExhausted:
            return "Both providers are out of quota."
        case .rateLimited:
            return "Both providers are rate limited. Wait a minute and try again."
        case .network(let detail):
            return "Network error: \(detail)"
        case .badResponse(let detail):
            return "Unexpected response: \(detail)"
        case .providerUnavailable(let detail):
            return "Provider unavailable: \(detail)"
        }
    }

    // MARK: - Environment

    /// The app does not inherit a login shell's PATH, so look in the usual places.
    static func resolveClaudePath() -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let candidates = [
            "\(home)/.local/bin/claude",
            "\(home)/.claude/local/claude",
            "/opt/homebrew/bin/claude",
            "/usr/local/bin/claude",
        ]
        for path in candidates where FileManager.default.isExecutableFile(atPath: path) {
            return path
        }
        return "/usr/bin/env"
    }

    static func writeTemporaryPNG(_ data: Data) throws -> String {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ghostshot-\(UUID().uuidString).png")
        try data.write(to: url)
        return url.path
    }
}
