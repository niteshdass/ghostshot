import Foundation

public struct Message: Equatable, Sendable {
    public enum Role: String, Equatable, Sendable {
        case user
        case assistant
    }

    public var role: Role
    public var text: String
    public var imagePNG: Data?

    public init(role: Role, text: String, imagePNG: Data? = nil) {
        self.role = role
        self.text = text
        self.imagePNG = imagePNG
    }
}
