import Foundation

public struct Config: Codable, Equatable, Sendable {
    /// A single key. Kept so older config files keep working; `geminiApiKeys` is
    /// the one to grow.
    public var geminiApiKey: String
    /// Tried in order. When one reports its daily quota gone, the next one takes
    /// over; when they are all gone, Claude does.
    public var geminiApiKeys: [String]
    public var ntfyTopic: String
    public var geminiModel: String
    public var systemPrompt: String
    public var doubleTapWindowMs: Double
    public var notifyPhone: Bool
    public var copyToClipboard: Bool

    public static let defaults = Config(
        geminiApiKey: "",
        geminiApiKeys: [],
        ntfyTopic: "",
        geminiModel: "gemini-3.6-flash",
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

    /// `geminiApiKey` first, then `geminiApiKeys`, blanks and repeats removed.
    public var allGeminiKeys: [String] {
        var seen = Set<String>()
        return ([geminiApiKey] + geminiApiKeys)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && seen.insert($0).inserted }
    }

    public init(
        geminiApiKey: String,
        geminiApiKeys: [String] = [],
        ntfyTopic: String,
        geminiModel: String,
        systemPrompt: String,
        doubleTapWindowMs: Double,
        notifyPhone: Bool,
        copyToClipboard: Bool
    ) {
        self.geminiApiKey = geminiApiKey
        self.geminiApiKeys = geminiApiKeys
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
        geminiApiKeys = try c.decodeIfPresent([String].self, forKey: .geminiApiKeys) ?? d.geminiApiKeys
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
    /// Provider name -> "yyyy-MM-dd" (Pacific) on which it reported its quota gone.
    /// One entry per Gemini key, so a burnt key is skipped while the others are used.
    public var exhaustedOn: [String: String]
    /// "x,y,w,h" of the overlay panel.
    public var panelFrame: String?

    public init(
        claudeSessionID: String? = nil,
        exhaustedOn: [String: String] = [:],
        panelFrame: String? = nil
    ) {
        self.claudeSessionID = claudeSessionID
        self.exhaustedOn = exhaustedOn
        self.panelFrame = panelFrame
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        claudeSessionID = try c.decodeIfPresent(String.self, forKey: .claudeSessionID)
        exhaustedOn = try c.decodeIfPresent([String: String].self, forKey: .exhaustedOn) ?? [:]
        panelFrame = try c.decodeIfPresent(String.self, forKey: .panelFrame)
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

    /// Config and state live next to the app bundle. build.sh puts Ghostshot.app at
    /// the root of the checkout, so everything the app needs sits in one folder that
    /// can be copied around. `GHOSTSHOT_CONFIG_DIR` overrides the location.
    public static func defaultDirectory(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        bundleURL: URL = Bundle.main.bundleURL
    ) -> URL {
        if let override = environment["GHOSTSHOT_CONFIG_DIR"], !override.isEmpty {
            return URL(fileURLWithPath: (override as NSString).expandingTildeInPath, isDirectory: true)
        }
        return bundleURL.deletingLastPathComponent()
    }

    public static func defaultStore() -> ConfigStore {
        let dir = defaultDirectory()
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
