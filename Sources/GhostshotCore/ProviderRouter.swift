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
        todayString(for: Date())
    }

    /// Gemini refills its requests-per-day quota at midnight Pacific, so the
    /// sticky flag has to use Pacific dates. On a local calendar the two
    /// boundaries drift apart by the UTC offset and Gemini sits unused for hours
    /// after Google has already refilled it.
    public static func todayString(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "America/Los_Angeles")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    public func ask(history: [Message]) async throws -> RouterAnswer {
        if loadState().geminiExhaustedOn != today() {
            do {
                let text = try await primary.ask(history: history)
                return RouterAnswer(text: text, providerName: primary.name)
            } catch AIError.quotaExhausted {
                // Sticky for the rest of the day: quota does not come back sooner.
                var state = loadState()
                state.geminiExhaustedOn = today()
                saveState(state)
            } catch AIError.rateLimited {
                // The per-minute window clears by itself, so the next capture
                // should try Gemini again rather than spend the day on Claude.
            } catch AIError.providerUnavailable {
                // Missing or rejected credentials. Fall back now, but do not mark
                // the day exhausted, so the next capture retries the primary.
            }
        }

        let text = try await fallback.ask(history: history)
        return RouterAnswer(text: text, providerName: fallback.name)
    }
}
