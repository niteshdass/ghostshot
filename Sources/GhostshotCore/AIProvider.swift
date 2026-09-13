import Foundation

public enum AIError: Error, Equatable {
    /// The provider's quota for the day is used up. Failover is sticky until it resets.
    case quotaExhausted
    /// A short-window throttle (Gemini's requests-per-minute). Failover for this
    /// request only: the window clears on its own within the minute.
    case rateLimited
    case network(String)
    case badResponse(String)
    case providerUnavailable(String)
}

public protocol AIProvider: AnyObject {
    var name: String { get }
    /// `history` is the whole conversation, oldest first. Images ride inside `Message.imagePNG`.
    func ask(history: [Message]) async throws -> String
}
