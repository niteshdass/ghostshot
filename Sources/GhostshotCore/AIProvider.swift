import Foundation

public enum AIError: Error, Equatable {
    /// The provider's free quota is used up. This is the only error that triggers failover.
    case quotaExhausted
    case network(String)
    case badResponse(String)
    case providerUnavailable(String)
}

public protocol AIProvider: AnyObject {
    var name: String { get }
    /// `history` is the whole conversation, oldest first. Images ride inside `Message.imagePNG`.
    func ask(history: [Message]) async throws -> String
}
