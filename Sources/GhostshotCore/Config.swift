import Foundation

public struct Config: Codable, Equatable, Sendable {
    public var geminiApiKey: String
    public var ntfyTopic: String
    public var geminiModel: String
    public var systemPrompt: String
    public var doubleTapWindowMs: Double
    public var notifyPhone: Bool
    public var copyToClipboard: Bool

    public static let defaults = Config(
        geminiApiKey: "",
        ntfyTopic: "",
        geminiModel: "gemini-2.5-flash",
        systemPrompt: """
        You answer questions that appear in screenshots taken during a live call. \
        Lead with the answer in one or two sentences. Then give at most two short lines of \
        reasoning. If the screenshot contains code, answer with code. Never describe the \
        screenshot itself unless asked.
        """,
        doubleTapWindowMs: 300,
        notifyPhone: true,
        copyToClipboard: true
    )

    public init(
        geminiApiKey: String,
        ntfyTopic: String,
        geminiModel: String,
        systemPrompt: String,
        doubleTapWindowMs: Double,
        notifyPhone: Bool,
        copyToClipboard: Bool
    ) {
        self.geminiApiKey = geminiApiKey
        self.ntfyTopic = ntfyTopic
        self.geminiModel = geminiModel
        self.systemPrompt = systemPrompt
        self.doubleTapWindowMs = doubleTapWindowMs
        self.notifyPhone = notifyPhone
        self.copyToClipboard = copyToClipboard
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Config.defaults
        geminiApiKey = try c.decodeIfPresent(String.self, forKey: .geminiApiKey) ?? d.geminiApiKey
        ntfyTopic = try c.decodeIfPresent(String.self, forKey: .ntfyTopic) ?? d.ntfyTopic
        geminiModel = try c.decodeIfPresent(String.self, forKey: .geminiModel) ?? d.geminiModel
        systemPrompt = try c.decodeIfPresent(String.self, forKey: .systemPrompt) ?? d.systemPrompt
        doubleTapWindowMs = try c.decodeIfPresent(Double.self, forKey: .doubleTapWindowMs) ?? d.doubleTapWindowMs
        notifyPhone = try c.decodeIfPresent(Bool.self, forKey: .notifyPhone) ?? d.notifyPhone
        copyToClipboard = try c.decodeIfPresent(Bool.self, forKey: .copyToClipboard) ?? d.copyToClipboard
    }
}

public struct AppState: Codable, Equatable, Sendable {
    public var claudeSessionID: String?
    /// "yyyy-MM-dd" on which Gemini reported its quota exhausted.
    public var geminiExhaustedOn: String?
    /// "x,y,w,h" of the overlay panel.
    public var panelFrame: String?

    public init(claudeSessionID: String? = nil, geminiExhaustedOn: String? = nil, panelFrame: String? = nil) {
        self.claudeSessionID = claudeSessionID
        self.geminiExhaustedOn = geminiExhaustedOn
        self.panelFrame = panelFrame
    }
}

public enum ConfigError: Error, Equatable {
    case unreadable(String)
}

public final class ConfigStore {
    public let configURL: URL
    public let stateURL: URL

    public init(configURL: URL, stateURL: URL) {
        self.configURL = configURL
        self.stateURL = stateURL
    }

    public static func defaultStore() -> ConfigStore {
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/ghostshot", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return ConfigStore(
            configURL: dir.appendingPathComponent("config.json"),
            stateURL: dir.appendingPathComponent("state.json")
        )
    }

    public func loadConfig() throws -> Config {
        guard let data = FileManager.default.contents(atPath: configURL.path) else {
            return .defaults
        }
        do {
            return try JSONDecoder().decode(Config.self, from: data)
        } catch {
            throw ConfigError.unreadable("\(configURL.path): \(error.localizedDescription)")
        }
    }

    public func writeDefaultConfigIfMissing() throws {
        guard !FileManager.default.fileExists(atPath: configURL.path) else { return }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(Config.defaults)
        FileManager.default.createFile(
            atPath: configURL.path,
            contents: data,
            attributes: [.posixPermissions: NSNumber(value: Int16(0o600))]
        )
    }

    public func loadState() -> AppState {
        guard let data = FileManager.default.contents(atPath: stateURL.path),
              let state = try? JSONDecoder().decode(AppState.self, from: data)
        else { return AppState() }
        return state
    }

    public func saveState(_ state: AppState) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(state) else { return }
        try? data.write(to: stateURL, options: .atomic)
    }
}
