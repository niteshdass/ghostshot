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
    /// Tried in order; each one is a separate Gemini key.
    private let primaries: [AIProvider]
    private let fallback: AIProvider
    private let loadState: () -> AppState
    private let saveState: (AppState) -> Void
    private let today: () -> String

    public init(
        primaries: [AIProvider],
        fallback: AIProvider,
        loadState: @escaping () -> AppState,
        saveState: @escaping (AppState) -> Void,
        today: @escaping () -> String = { ProviderRouter.todayString() }
    ) {
        self.primaries = primaries
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
        for primary in primaries {
            guard loadState().exhaustedOn[primary.name] != today() else { continue }
            do {
                let text = try await primary.ask(history: history)
                return RouterAnswer(text: text, providerName: primary.name)
            } catch AIError.quotaExhausted {
                // Sticky for the rest of the day: quota does not come back sooner.
                // Only this key is burnt, so the loop moves on to the next one.
                markExhausted(primary.name)
            } catch AIError.rateLimited {
                // The per-minute window clears by itself, so nothing is recorded
                // and the next capture starts from the top of the list again.
            } catch AIError.providerUnavailable {
                // Missing or rejected credentials. Skip this key for now, but do
                // not mark it exhausted: it may be fixed before the next capture.
            }
        }

        let text = try await fallback.ask(history: history)
        return RouterAnswer(text: text, providerName: fallback.name)
    }

    private func markExhausted(_ name: String) {
        var state = loadState()
        state.exhaustedOn[name] = today()
        saveState(state)
    }
}
