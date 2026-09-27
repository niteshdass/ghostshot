import Foundation
import Testing
@testable import GhostshotCore

@Suite struct ConfigTests {
    /// Runs `body` with a private temp directory that is always cleaned up.
    private func withTempDir(_ body: (URL) throws -> Void) rethrows {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("ghostshot-tests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        try body(dir)
    }

    private func makeStore(_ dir: URL) -> ConfigStore {
        ConfigStore(
            configURL: dir.appendingPathComponent("config.json"),
            stateURL: dir.appendingPathComponent("state.json")
        )
    }

    @Test func partialConfigFileFillsMissingKeysWithDefaults() throws {
        try withTempDir { dir in
            let url = dir.appendingPathComponent("config.json")
            try #"{"geminiApiKey":"KEY123","ntfyTopic":"secret-topic"}"#
                .write(to: url, atomically: true, encoding: .utf8)

            let config = try makeStore(dir).loadConfig()

            #expect(config.geminiApiKey == "KEY123")
            #expect(config.ntfyTopic == "secret-topic")
            #expect(config.geminiModel == Config.defaults.geminiModel)
            #expect(config.doubleTapWindowMs == 300)
            #expect(config.notifyPhone)
        }
    }

    @Test func writeDefaultConfigCreatesFileWithMode600() throws {
        try withTempDir { dir in
            try makeStore(dir).writeDefaultConfigIfMissing()

            let url = dir.appendingPathComponent("config.json")
            let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
            let permissions = attrs[.posixPermissions] as? NSNumber

            #expect(permissions?.int16Value == 0o600)
        }
    }

    @Test func writeDefaultConfigDoesNotOverwriteExistingFile() throws {
        try withTempDir { dir in
            let url = dir.appendingPathComponent("config.json")
            try #"{"geminiApiKey":"MINE"}"#.write(to: url, atomically: true, encoding: .utf8)

            let store = makeStore(dir)
            try store.writeDefaultConfigIfMissing()

            #expect(try store.loadConfig().geminiApiKey == "MINE")
        }
    }

    @Test func stateRoundTrips() throws {
        try withTempDir { dir in
            let store = makeStore(dir)
            var state = store.loadState()
            state.claudeSessionID = "sess-9"
            state.exhaustedOn = ["gemini-1": "2026-09-04"]
            store.saveState(state)

            #expect(store.loadState() == state)
        }
    }

    @Test func keyListCombinesTheSingleKeyAndTheListInOrder() throws {
        try withTempDir { dir in
            let url = dir.appendingPathComponent("config.json")
            try #"{"geminiApiKey":"ONE","geminiApiKeys":["TWO","THREE"]}"#
                .write(to: url, atomically: true, encoding: .utf8)

            #expect(try makeStore(dir).loadConfig().allGeminiKeys == ["ONE", "TWO", "THREE"])
        }
    }

    @Test func keyListDropsBlanksAndRepeatsAndTrimsWhitespace() {
        let config = Config(
            geminiApiKey: "",
            geminiApiKeys: ["  ONE  ", "TWO", "ONE", "   "],
            ntfyTopic: "",
            geminiModel: "m",
            systemPrompt: "s",
            doubleTapWindowMs: 300,
            notifyPhone: false,
            copyToClipboard: false
        )

        #expect(config.allGeminiKeys == ["ONE", "TWO"])
    }

    @Test func aConfigWithOnlyTheOldSingleKeyStillWorks() throws {
        try withTempDir { dir in
            let url = dir.appendingPathComponent("config.json")
            try #"{"geminiApiKey":"ONLY"}"#.write(to: url, atomically: true, encoding: .utf8)

            #expect(try makeStore(dir).loadConfig().allGeminiKeys == ["ONLY"])
        }
    }

    @Test func defaultDirectoryIsTheCheckoutWhenItHoldsAConfig() {
        let dir = ConfigStore.defaultDirectory(
            environment: [:],
            bundleURL: URL(fileURLWithPath: "/Users/x/Projects/ghostshot/Ghostshot.app"),
            fileExists: { $0 == "/Users/x/Projects/ghostshot/config.json" }
        )

        #expect(dir.path == "/Users/x/Projects/ghostshot")
    }

    @Test func installedCopyUsesApplicationSupport() {
        let dir = ConfigStore.defaultDirectory(
            environment: [:],
            bundleURL: URL(fileURLWithPath: "/Users/x/Applications/Ghostshot.app"),
            homeDirectory: URL(fileURLWithPath: "/Users/x"),
            fileExists: { _ in false }
        )

        #expect(dir.path == "/Users/x/Library/Application Support/Ghostshot")
    }

    @Test func environmentOverridesTheDefaultDirectory() {
        let dir = ConfigStore.defaultDirectory(
            environment: ["GHOSTSHOT_CONFIG_DIR": "/tmp/elsewhere"],
            bundleURL: URL(fileURLWithPath: "/Users/x/Projects/ghostshot/Ghostshot.app")
        )

        #expect(dir.path == "/tmp/elsewhere")
    }

    @Test func emptyEnvironmentOverrideIsIgnored() {
        let dir = ConfigStore.defaultDirectory(
            environment: ["GHOSTSHOT_CONFIG_DIR": ""],
            bundleURL: URL(fileURLWithPath: "/Users/x/Projects/ghostshot/Ghostshot.app"),
            fileExists: { _ in true }
        )

        #expect(dir.path == "/Users/x/Projects/ghostshot")
    }

    @Test func missingStateFileReturnsEmptyState() throws {
        try withTempDir { dir in
            #expect(makeStore(dir).loadState() == AppState())
        }
    }
}
