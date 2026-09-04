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
            state.geminiExhaustedOn = "2026-09-04"
            store.saveState(state)

            #expect(store.loadState() == state)
        }
    }

    @Test func missingStateFileReturnsEmptyState() throws {
        try withTempDir { dir in
            #expect(makeStore(dir).loadState() == AppState())
        }
    }
}
