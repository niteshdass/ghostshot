import Foundation

public struct RouterAnswer: Equatable, Sendable {
    public let text: String
    public let providerName: String

    public init(text: String, providerName: String) {
        self.text = text
        self.providerName = providerName
    }
}

public final class ProviderRouter {
    private let primary: AIProvider
    private let fallback: AIProvider
    private let loadState: () -> AppState
    private let saveState: (AppState) -> Void
    private let today: () -> String

    public init(
        primary: AIProvider,
        fallback: AIProvider,
        loadState: @escaping () -> AppState,
        saveState: @escaping (AppState) -> Void,
        today: @escaping () -> String = { ProviderRouter.todayString() }
    ) {
        self.primary = primary
        self.fallback = fallback
        self.loadState = loadState
        self.saveState = saveState
        self.today = today
    }

    public static func todayString() -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }

    public func ask(history: [Message]) async throws -> RouterAnswer {
        if loadState().geminiExhaustedOn != today() {
            do {
                let text = try await primary.ask(history: history)
                return RouterAnswer(text: text, providerName: primary.name)
            } catch AIError.quotaExhausted {
                var state = loadState()
                state.geminiExhaustedOn = today()
                saveState(state)
            }
        }

        let text = try await fallback.ask(history: history)
        return RouterAnswer(text: text, providerName: fallback.name)
    }
}
