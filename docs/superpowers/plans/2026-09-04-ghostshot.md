# Ghostshot Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A macOS background app where double-tapping Right Command silently captures the screen, sends it to an AI as part of one continuous conversation, and shows the answer in an overlay window that is invisible to screen sharing.

**Architecture:** One SwiftPM package with two targets. `GhostshotCore` is a plain library holding every piece of real logic behind injected protocols, so all of it is unit tested without touching the system. `GhostshotApp` is a thin AppKit executable that wires Core to the four system APIs it needs: a passive CGEventTap, ScreenCaptureKit, an NSPanel, and NSPasteboard. A shell script assembles the `.app` bundle because there is no Xcode on this machine.

**Tech Stack:** Swift 6.0.3 (language mode 5), SwiftPM, XCTest, AppKit, ScreenCaptureKit, Carbon key codes, URLSession, Foundation.Process.

**Spec:** `docs/superpowers/specs/2026-09-04-ghostshot-design.md`

## Verified Facts

These were probed on this machine before planning. Do not re-litigate them; do not "fix" code that depends on them.

1. `screencapture -x` captures silently. Retina displays return 2x pixel dimensions (1800x1000 for a 900x500 region).
2. `claude -p --output-format json --allowedTools Read` **does** read a PNG from a path and answer about it. Measured 8.2s first turn.
3. `claude -p --resume <session_id>` continues the same conversation, including recall of a previously read image, and returns the same `session_id`. Measured 2.9s.
4. **`--allowedTools` is a variadic flag.** If the prompt is passed as a positional argument after it, the CLI consumes the prompt as another tool name and fails with `Error: Input must be provided either through stdin or as a prompt argument when using --print`. **The prompt MUST be written to the process's stdin.** Every `ClaudeCodeProvider` test and implementation depends on this.

## Global Constraints

- Platform floor: macOS 14. `platforms: [.macOS(.v14)]`, target triple `arm64-apple-macosx14.0`.
- Swift 6.0.3 toolchain, but **language mode 5** (`.swiftLanguageMode(.v5)`) on every target. Swift 6 strict concurrency is not worth fighting here.
- **swift-testing (`import Testing`), not XCTest.** See "Test framework" below.
- No Xcode. No `.xcodeproj`. Build is `swift build` plus `build.sh`.
- No third-party dependencies. Foundation, AppKit, ScreenCaptureKit only.
- Free at the margin: Gemini free tier primary, `claude` CLI fallback. **Never** call the paid Anthropic API.
- Every unit in `GhostshotCore` takes its collaborators by protocol so tests never hit the network, the filesystem outside a temp dir, or a real process.
- Secrets live in `~/.config/ghostshot/config.json` at mode `0600`. Never commit it; never log the API key.

## Test framework

**Corrected during execution.** The plan was first written assuming XCTest.
That is wrong on this machine and the tasks below still show XCTest code.

Discovered facts:

- Xcode 15.4 *is* installed at `/Applications/Xcode.app`, but it carries
  Swift **5.10**, which cannot build a `swift-tools-version: 6.0` package.
- The active toolchain is Command Line Tools with Swift **6.0.3**. It has no
  `XCTest` module, so `import XCTest` fails to compile.
- The Command Line Tools **do** ship swift-testing
  (`/Library/Developer/CommandLineTools/Library/Developer/Frameworks/Testing.framework`).
  Verified working: `swift test` runs `@Test` functions on Swift 6.0.3 with no
  Xcode involved.

So: keep Swift 6.0.3 and CLT, and write every test with swift-testing.
`DEVELOPER_DIR` must NOT be pointed at Xcode.

**Translate each task's test code mechanically using this table.** The
assertions and the behaviour under test do not change; only the syntax does.

| XCTest (as written in the tasks) | swift-testing (what to actually write) |
| --- | --- |
| `import XCTest` | `import Testing` plus `import Foundation` |
| `final class FooTests: XCTestCase` | `@Suite struct FooTests` |
| `func test_someBehavior()` | `@Test func someBehavior()` |
| `XCTAssertEqual(a, b)` | `#expect(a == b)` |
| `XCTAssertNotEqual(a, b)` | `#expect(a != b)` |
| `XCTAssertNil(a)` | `#expect(a == nil)` |
| `XCTAssertTrue(a)` / `XCTAssertFalse(a)` | `#expect(a)` / `#expect(!a)` |
| `try XCTUnwrap(a)` | `try #require(a)` |
| `XCTFail("msg")` | `Issue.record("msg")` |
| `setUpWithError` / `tearDownWithError` | per-test temp directory helper with `defer` |

Two suites need a `final class` rather than a `struct`, because their tests
mutate suite-level state: `ProviderRouterTests` (mutates `state`) and any
suite holding a fake across calls. A `@Suite final class` still gets a fresh
instance per test.

Run a single suite with `swift test --filter FooTests`; run everything with
`swift test`.

## Deviation from the spec

The spec sketches `AIProvider.ask(history:image:)` with the image as a separate parameter. This plan instead carries images **inside** `Message.imagePNG`, and the protocol is `ask(history:) async throws -> String`. Reason: history must carry older images too, so a separate parameter would need a parallel array. Single source of truth is better. Everything else follows the spec as written.

## File Structure

```
ghostshot/
  Package.swift
  Sources/
    GhostshotCore/
      Message.swift             Message, Role
      AIProvider.swift          AIProvider protocol, AIError
      Clock.swift               Clock protocol, SystemClock, FakeClock
      HotkeyDetector.swift      double-tap state machine (pure)
      Conversation.swift        history + image trimming + session id
      Config.swift              Config, AppState, ConfigStore (paths injected)
      HTTPClient.swift          HTTPClient protocol + URLSessionHTTPClient
      ProcessRunner.swift       ProcessRunner protocol + SystemProcessRunner
      GeminiProvider.swift      free-tier primary
      ClaudeCodeProvider.swift  claude CLI fallback
      ProviderRouter.swift      failover + same-day stickiness
      NtfySender.swift          phone push
    GhostshotApp/
      main.swift                NSApplication bootstrap
      AppDelegate.swift         wiring, permission checks
      EventTapController.swift  CGEventTap -> HotkeyDetector
      ScreenCapturer.swift      ScreenCaptureKit -> PNG Data
      OverlayPanel.swift        NSPanel, sharingType .none
      AnswerCoordinator.swift   capture -> ask -> deliver
  Tests/
    GhostshotCoreTests/
      HotkeyDetectorTests.swift
      ConversationTests.swift
      ConfigTests.swift
      GeminiProviderTests.swift
      ClaudeCodeProviderTests.swift
      ProviderRouterTests.swift
      NtfySenderTests.swift
      Fakes.swift               FakeHTTPClient, FakeProcessRunner, FakeClock
  Resources/Info.plist
  build.sh
  run.sh
  docs/SETUP.md
```

---

### Task 1: Package skeleton and core value types

**Files:**
- Create: `Package.swift`
- Create: `Sources/GhostshotCore/Message.swift`
- Create: `Sources/GhostshotCore/AIProvider.swift`
- Test: `Tests/GhostshotCoreTests/MessageTests.swift`

**Interfaces:**
- Consumes: nothing.
- Produces: `Message` (with `Message.Role`), `AIProvider` protocol, `AIError`. Every later task uses these.

- [ ] **Step 1: Write the failing test**

`Tests/GhostshotCoreTests/MessageTests.swift`:

```swift
import XCTest
@testable import GhostshotCore

final class MessageTests: XCTestCase {
    func test_userMessage_carriesTextAndImage() {
        let png = Data([0x89, 0x50, 0x4E, 0x47])
        let m = Message(role: .user, text: "what is this", imagePNG: png)
        XCTAssertEqual(m.role, .user)
        XCTAssertEqual(m.text, "what is this")
        XCTAssertEqual(m.imagePNG, png)
    }

    func test_assistantMessage_hasNoImageByDefault() {
        let m = Message(role: .assistant, text: "it is a terminal")
        XCTAssertNil(m.imagePNG)
    }

    func test_quotaExhausted_isDistinctFromOtherErrors() {
        XCTAssertNotEqual(AIError.quotaExhausted, AIError.network("offline"))
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter MessageTests`
Expected: FAIL — the package does not exist yet, so this is a build error, not an assertion failure. That is the correct starting state.

- [ ] **Step 3: Write minimal implementation**

`Package.swift`:

```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Ghostshot",
    platforms: [.macOS(.v14)],
    targets: [
        .target(
            name: "GhostshotCore",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "GhostshotApp",
            dependencies: ["GhostshotCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "GhostshotCoreTests",
            dependencies: ["GhostshotCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
```

`Sources/GhostshotCore/Message.swift`:

```swift
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
```

`Sources/GhostshotCore/AIProvider.swift`:

```swift
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
```

Create a placeholder so the executable target compiles — `Sources/GhostshotApp/main.swift`:

```swift
// Replaced in Task 12.
print("ghostshot: not wired yet")
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter MessageTests`
Expected: PASS, 3 tests.

- [ ] **Step 5: Commit**

```bash
git add Package.swift Sources Tests
git commit -m "feat: package skeleton with Message and AIProvider types"
```

---

### Task 2: HotkeyDetector double-tap state machine

**Files:**
- Create: `Sources/GhostshotCore/HotkeyDetector.swift`
- Test: `Tests/GhostshotCoreTests/HotkeyDetectorTests.swift`

**Interfaces:**
- Consumes: nothing from earlier tasks.
- Produces: `ModifierKey` (`.rightCommand`, `.rightOption`, `.rightControl`), `HotkeyEvent` (`.modifierDown(ModifierKey)`, `.modifierUp(ModifierKey)`, `.otherKeyDown`), `HotkeyAction` (`.capture`, `.togglePanel`, `.resetConversation`), and `HotkeyDetector.handle(_ event: HotkeyEvent, at now: TimeInterval) -> HotkeyAction?`. Task 11 feeds this from a CGEventTap.

Timestamps are seconds as `TimeInterval`. The detector never reads a clock itself — the caller passes `now`. That is what makes it testable without sleeping.

- [ ] **Step 1: Write the failing test**

`Tests/GhostshotCoreTests/HotkeyDetectorTests.swift`:

```swift
import XCTest
@testable import GhostshotCore

final class HotkeyDetectorTests: XCTestCase {
    private func tap(_ d: HotkeyDetector, _ key: ModifierKey, at t: TimeInterval) -> HotkeyAction? {
        _ = d.handle(.modifierDown(key), at: t)
        return d.handle(.modifierUp(key), at: t + 0.01)
    }

    func test_twoTapsInsideWindow_fireCapture() {
        let d = HotkeyDetector(doubleTapWindowMs: 300)
        XCTAssertNil(tap(d, .rightCommand, at: 0.0))
        XCTAssertEqual(tap(d, .rightCommand, at: 0.2), .capture)
    }

    func test_twoTapsOutsideWindow_fireNothing() {
        let d = HotkeyDetector(doubleTapWindowMs: 300)
        XCTAssertNil(tap(d, .rightCommand, at: 0.0))
        XCTAssertNil(tap(d, .rightCommand, at: 0.6))
    }

    func test_thirdTap_doesNotFireAgain() {
        let d = HotkeyDetector(doubleTapWindowMs: 300)
        XCTAssertNil(tap(d, .rightCommand, at: 0.0))
        XCTAssertEqual(tap(d, .rightCommand, at: 0.1), .capture)
        XCTAssertNil(tap(d, .rightCommand, at: 0.2))
    }

    func test_rightOption_togglesPanel_andRightControl_resets() {
        let d = HotkeyDetector(doubleTapWindowMs: 300)
        XCTAssertNil(tap(d, .rightOption, at: 0.0))
        XCTAssertEqual(tap(d, .rightOption, at: 0.1), .togglePanel)

        XCTAssertNil(tap(d, .rightControl, at: 1.0))
        XCTAssertEqual(tap(d, .rightControl, at: 1.1), .resetConversation)
    }

    func test_differentModifiers_doNotCombine() {
        let d = HotkeyDetector(doubleTapWindowMs: 300)
        XCTAssertNil(tap(d, .rightCommand, at: 0.0))
        XCTAssertNil(tap(d, .rightOption, at: 0.1))
    }

    func test_realShortcutIsNotATap() {
        // Cmd+C: hold right command, press C, release right command.
        let d = HotkeyDetector(doubleTapWindowMs: 300)
        _ = d.handle(.modifierDown(.rightCommand), at: 0.0)
        _ = d.handle(.otherKeyDown, at: 0.05)
        XCTAssertNil(d.handle(.modifierUp(.rightCommand), at: 0.1))
        // A genuine tap right after must still count as only the FIRST tap.
        XCTAssertNil(tap(d, .rightCommand, at: 0.2))
    }

    func test_upWithoutDown_isIgnored() {
        let d = HotkeyDetector(doubleTapWindowMs: 300)
        XCTAssertNil(d.handle(.modifierUp(.rightCommand), at: 0.0))
        XCTAssertNil(tap(d, .rightCommand, at: 0.1))
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter HotkeyDetectorTests`
Expected: FAIL — `cannot find 'HotkeyDetector' in scope`.

- [ ] **Step 3: Write minimal implementation**

`Sources/GhostshotCore/HotkeyDetector.swift`:

```swift
import Foundation

public enum ModifierKey: Equatable, Hashable, Sendable {
    case rightCommand
    case rightOption
    case rightControl
}

public enum HotkeyEvent: Equatable, Sendable {
    case modifierDown(ModifierKey)
    case modifierUp(ModifierKey)
    /// Any non-modifier key going down. Used to disqualify real shortcuts like Cmd+C.
    case otherKeyDown
}

public enum HotkeyAction: Equatable, Sendable {
    case capture
    case togglePanel
    case resetConversation
}

public final class HotkeyDetector {
    private let window: TimeInterval
    private var heldSince: [ModifierKey: TimeInterval] = [:]
    private var contaminated: Set<ModifierKey> = []
    private var lastTapKey: ModifierKey?
    private var lastTapAt: TimeInterval?

    public init(doubleTapWindowMs: Double = 300) {
        self.window = doubleTapWindowMs / 1000.0
    }

    public func handle(_ event: HotkeyEvent, at now: TimeInterval) -> HotkeyAction? {
        switch event {
        case .modifierDown(let key):
            heldSince[key] = now
            contaminated.remove(key)
            return nil

        case .otherKeyDown:
            // Every modifier currently held was part of a real shortcut, not a tap.
            for key in heldSince.keys { contaminated.insert(key) }
            return nil

        case .modifierUp(let key):
            guard heldSince.removeValue(forKey: key) != nil else { return nil }

            if contaminated.remove(key) != nil {
                lastTapKey = nil
                lastTapAt = nil
                return nil
            }

            if lastTapKey == key, let previous = lastTapAt, now - previous <= window {
                lastTapKey = nil
                lastTapAt = nil
                return Self.action(for: key)
            }

            lastTapKey = key
            lastTapAt = now
            return nil
        }
    }

    private static func action(for key: ModifierKey) -> HotkeyAction {
        switch key {
        case .rightCommand: return .capture
        case .rightOption: return .togglePanel
        case .rightControl: return .resetConversation
        }
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter HotkeyDetectorTests`
Expected: PASS, 7 tests.

- [ ] **Step 5: Commit**

```bash
git add Sources/GhostshotCore/HotkeyDetector.swift Tests/GhostshotCoreTests/HotkeyDetectorTests.swift
git commit -m "feat: double-tap hotkey detector with shortcut disqualification"
```

---

### Task 3: Conversation history with image trimming

**Files:**
- Create: `Sources/GhostshotCore/Conversation.swift`
- Test: `Tests/GhostshotCoreTests/ConversationTests.swift`

**Interfaces:**
- Consumes: `Message` from Task 1.
- Produces: `Conversation` with `messages: [Message]`, `claudeSessionID: String?`, `addUser(text:imagePNG:)`, `addAssistant(_:)`, `setClaudeSessionID(_:)`, `reset()`, and `static let earlierScreenshotPlaceholder`. Tasks 5, 6, 7 and 12 read `messages`.

Only the two most recent images are kept. Older ones are dropped and their message text gains the placeholder, exactly once.

- [ ] **Step 1: Write the failing test**

`Tests/GhostshotCoreTests/ConversationTests.swift`:

```swift
import XCTest
@testable import GhostshotCore

final class ConversationTests: XCTestCase {
    private func png(_ byte: UInt8) -> Data { Data([0x89, byte]) }

    func test_keepsOnlyTwoMostRecentImages() {
        let c = Conversation(maxImages: 2)
        c.addUser(text: "one", imagePNG: png(1))
        c.addUser(text: "two", imagePNG: png(2))
        c.addUser(text: "three", imagePNG: png(3))

        XCTAssertNil(c.messages[0].imagePNG)
        XCTAssertEqual(c.messages[1].imagePNG, png(2))
        XCTAssertEqual(c.messages[2].imagePNG, png(3))
    }

    func test_strippedMessageGainsPlaceholder() {
        let c = Conversation(maxImages: 1)
        c.addUser(text: "one", imagePNG: png(1))
        c.addUser(text: "two", imagePNG: png(2))

        XCTAssertTrue(c.messages[0].text.hasSuffix(Conversation.earlierScreenshotPlaceholder))
        XCTAssertTrue(c.messages[0].text.hasPrefix("one"))
    }

    func test_placeholderIsNotAppendedTwice() {
        let c = Conversation(maxImages: 1)
        c.addUser(text: "one", imagePNG: png(1))
        c.addUser(text: "two", imagePNG: png(2))
        c.addUser(text: "three", imagePNG: png(3))

        let occurrences = c.messages[0].text
            .components(separatedBy: Conversation.earlierScreenshotPlaceholder)
            .count - 1
        XCTAssertEqual(occurrences, 1)
    }

    func test_assistantMessagesAreNeverTrimmed() {
        let c = Conversation(maxImages: 1)
        c.addUser(text: "one", imagePNG: png(1))
        c.addAssistant("an answer")
        c.addUser(text: "two", imagePNG: png(2))

        XCTAssertEqual(c.messages[1].role, .assistant)
        XCTAssertEqual(c.messages[1].text, "an answer")
    }

    func test_resetClearsMessagesAndSessionID() {
        let c = Conversation(maxImages: 2)
        c.addUser(text: "one", imagePNG: png(1))
        c.setClaudeSessionID("abc-123")

        c.reset()

        XCTAssertTrue(c.messages.isEmpty)
        XCTAssertNil(c.claudeSessionID)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter ConversationTests`
Expected: FAIL — `cannot find 'Conversation' in scope`.

- [ ] **Step 3: Write minimal implementation**

`Sources/GhostshotCore/Conversation.swift`:

```swift
import Foundation

public final class Conversation {
    public static let earlierScreenshotPlaceholder = "[earlier screenshot]"

    public private(set) var messages: [Message] = []
    public private(set) var claudeSessionID: String?

    private let maxImages: Int

    public init(maxImages: Int = 2) {
        self.maxImages = maxImages
    }

    public func addUser(text: String, imagePNG: Data?) {
        messages.append(Message(role: .user, text: text, imagePNG: imagePNG))
        trimImages()
    }

    public func addAssistant(_ text: String) {
        messages.append(Message(role: .assistant, text: text))
    }

    public func setClaudeSessionID(_ id: String?) {
        claudeSessionID = id
    }

    public func reset() {
        messages.removeAll()
        claudeSessionID = nil
    }

    /// Walks newest to oldest, keeps `maxImages` images, strips the rest.
    private func trimImages() {
        var kept = 0
        for index in messages.indices.reversed() {
            guard messages[index].imagePNG != nil else { continue }
            if kept < maxImages {
                kept += 1
                continue
            }
            messages[index].imagePNG = nil
            let text = messages[index].text
            messages[index].text = text.isEmpty
                ? Self.earlierScreenshotPlaceholder
                : text + "\n" + Self.earlierScreenshotPlaceholder
        }
    }
}
```

The placeholder cannot be appended twice because the loop only touches messages that still hold an image, and stripping removes it.

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter ConversationTests`
Expected: PASS, 5 tests.

- [ ] **Step 5: Commit**

```bash
git add Sources/GhostshotCore/Conversation.swift Tests/GhostshotCoreTests/ConversationTests.swift
git commit -m "feat: conversation history with sliding image window"
```

---

### Task 4: Config and state persistence

**Files:**
- Create: `Sources/GhostshotCore/Config.swift`
- Test: `Tests/GhostshotCoreTests/ConfigTests.swift`

**Interfaces:**
- Consumes: nothing.
- Produces: `Config` (fields `geminiApiKey`, `ntfyTopic`, `geminiModel`, `systemPrompt`, `doubleTapWindowMs`, `notifyPhone`, `copyToClipboard`), `AppState` (fields `claudeSessionID`, `geminiExhaustedOn`, `panelFrame`), and `ConfigStore(configURL:stateURL:)` with `loadConfig() throws -> Config`, `writeDefaultConfigIfMissing() throws`, `loadState() -> AppState`, `saveState(_:)`. Task 7 uses `AppState.geminiExhaustedOn`. Task 12 uses everything.

Missing keys in an existing config file fall back to defaults rather than failing to decode, so adding a field later never breaks a user's file.

- [ ] **Step 1: Write the failing test**

`Tests/GhostshotCoreTests/ConfigTests.swift`:

```swift
import XCTest
@testable import GhostshotCore

final class ConfigTests: XCTestCase {
    private var dir: URL!

    override func setUpWithError() throws {
        dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("ghostshot-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    private func makeStore() -> ConfigStore {
        ConfigStore(
            configURL: dir.appendingPathComponent("config.json"),
            stateURL: dir.appendingPathComponent("state.json")
        )
    }

    func test_partialConfigFile_fillsMissingKeysWithDefaults() throws {
        let url = dir.appendingPathComponent("config.json")
        try #"{"geminiApiKey":"KEY123","ntfyTopic":"secret-topic"}"#
            .write(to: url, atomically: true, encoding: .utf8)

        let config = try makeStore().loadConfig()

        XCTAssertEqual(config.geminiApiKey, "KEY123")
        XCTAssertEqual(config.ntfyTopic, "secret-topic")
        XCTAssertEqual(config.geminiModel, Config.defaults.geminiModel)
        XCTAssertEqual(config.doubleTapWindowMs, 300)
        XCTAssertTrue(config.notifyPhone)
    }

    func test_writeDefaultConfig_createsFileWithMode600() throws {
        let store = makeStore()
        try store.writeDefaultConfigIfMissing()

        let url = dir.appendingPathComponent("config.json")
        let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
        let permissions = attrs[.posixPermissions] as? NSNumber

        XCTAssertEqual(permissions?.int16Value, 0o600)
    }

    func test_writeDefaultConfig_doesNotOverwriteExistingFile() throws {
        let url = dir.appendingPathComponent("config.json")
        try #"{"geminiApiKey":"MINE"}"#.write(to: url, atomically: true, encoding: .utf8)

        let store = makeStore()
        try store.writeDefaultConfigIfMissing()

        XCTAssertEqual(try store.loadConfig().geminiApiKey, "MINE")
    }

    func test_stateRoundTrips() throws {
        let store = makeStore()
        var state = store.loadState()
        state.claudeSessionID = "sess-9"
        state.geminiExhaustedOn = "2026-09-04"
        store.saveState(state)

        XCTAssertEqual(store.loadState(), state)
    }

    func test_missingStateFile_returnsEmptyState() {
        XCTAssertEqual(makeStore().loadState(), AppState())
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter ConfigTests`
Expected: FAIL — `cannot find 'ConfigStore' in scope`.

- [ ] **Step 3: Write minimal implementation**

`Sources/GhostshotCore/Config.swift`:

```swift
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
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter ConfigTests`
Expected: PASS, 5 tests.

- [ ] **Step 5: Commit**

```bash
git add Sources/GhostshotCore/Config.swift Tests/GhostshotCoreTests/ConfigTests.swift
git commit -m "feat: config and state persistence with 0600 permissions"
```

---

### Task 5: Injection seams — HTTPClient, ProcessRunner, and test fakes

**Files:**
- Create: `Sources/GhostshotCore/HTTPClient.swift`
- Create: `Sources/GhostshotCore/ProcessRunner.swift`
- Test: `Tests/GhostshotCoreTests/Fakes.swift`
- Test: `Tests/GhostshotCoreTests/ProcessRunnerTests.swift`

**Interfaces:**
- Consumes: nothing.
- Produces: `HTTPClient` protocol with `send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)`, `URLSessionHTTPClient`; `ProcessResult` (`exitCode: Int32`, `stdout: String`, `stderr: String`), `ProcessRunner` protocol with `run(executable:arguments:stdin:) async throws -> ProcessResult`, `SystemProcessRunner`. Test-only `FakeHTTPClient` and `FakeProcessRunner` are used by Tasks 6, 7, 8, 9.

`SystemProcessRunner` gets a real test because writing to a child's stdin and reading both pipes without deadlocking is the exact thing that breaks in production.

- [ ] **Step 1: Write the failing test**

`Tests/GhostshotCoreTests/Fakes.swift`:

```swift
import Foundation
@testable import GhostshotCore

final class FakeHTTPClient: HTTPClient, @unchecked Sendable {
    var responses: [(Data, Int)] = []
    var thrownError: Error?
    private(set) var sentRequests: [URLRequest] = []

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        sentRequests.append(request)
        if let thrownError { throw thrownError }
        guard !responses.isEmpty else {
            return (Data(), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
        let (data, status) = responses.removeFirst()
        return (data, HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!)
    }

    var lastBodyJSON: [String: Any] {
        guard let body = sentRequests.last?.httpBody,
              let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any]
        else { return [:] }
        return json
    }
}

final class FakeProcessRunner: ProcessRunner, @unchecked Sendable {
    var results: [ProcessResult] = []
    var thrownError: Error?
    private(set) var calls: [(executable: String, arguments: [String], stdin: String)] = []

    func run(executable: String, arguments: [String], stdin: String) async throws -> ProcessResult {
        calls.append((executable, arguments, stdin))
        if let thrownError { throw thrownError }
        guard !results.isEmpty else { return ProcessResult(exitCode: 0, stdout: "", stderr: "") }
        return results.removeFirst()
    }
}
```

`Tests/GhostshotCoreTests/ProcessRunnerTests.swift`:

```swift
import XCTest
@testable import GhostshotCore

final class ProcessRunnerTests: XCTestCase {
    func test_passesStdinAndCapturesStdout() async throws {
        let runner = SystemProcessRunner()
        let result = try await runner.run(executable: "/bin/cat", arguments: [], stdin: "hello ghostshot")

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertEqual(result.stdout, "hello ghostshot")
    }

    func test_capturesNonZeroExitAndStderr() async throws {
        let runner = SystemProcessRunner()
        let result = try await runner.run(
            executable: "/bin/sh",
            arguments: ["-c", "echo boom >&2; exit 3"],
            stdin: ""
        )

        XCTAssertEqual(result.exitCode, 3)
        XCTAssertTrue(result.stderr.contains("boom"))
    }

    func test_handlesLargeStdinWithoutDeadlock() async throws {
        let runner = SystemProcessRunner()
        let big = String(repeating: "x", count: 200_000)
        let result = try await runner.run(executable: "/bin/cat", arguments: [], stdin: big)

        XCTAssertEqual(result.stdout.count, big.count)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter ProcessRunnerTests`
Expected: FAIL — `cannot find 'SystemProcessRunner' in scope`.

- [ ] **Step 3: Write minimal implementation**

`Sources/GhostshotCore/HTTPClient.swift`:

```swift
import Foundation

public protocol HTTPClient: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

public struct URLSessionHTTPClient: HTTPClient {
    private let session: URLSession

    public init(timeout: TimeInterval = 45) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = timeout
        self.session = URLSession(configuration: configuration)
    }

    public func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw AIError.badResponse("not an HTTP response")
        }
        return (data, http)
    }
}
```

`Sources/GhostshotCore/ProcessRunner.swift`:

```swift
import Foundation

public struct ProcessResult: Equatable, Sendable {
    public let exitCode: Int32
    public let stdout: String
    public let stderr: String

    public init(exitCode: Int32, stdout: String, stderr: String) {
        self.exitCode = exitCode
        self.stdout = stdout
        self.stderr = stderr
    }
}

public protocol ProcessRunner: Sendable {
    func run(executable: String, arguments: [String], stdin: String) async throws -> ProcessResult
}

public struct SystemProcessRunner: ProcessRunner {
    public init() {}

    public func run(executable: String, arguments: [String], stdin: String) async throws -> ProcessResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments

        let inPipe = Pipe(), outPipe = Pipe(), errPipe = Pipe()
        process.standardInput = inPipe
        process.standardOutput = outPipe
        process.standardError = errPipe

        try process.run()

        // Drain both output pipes on background queues BEFORE writing stdin.
        // A child that fills its stdout pipe while we are still writing stdin deadlocks otherwise.
        let outBox = DataBox(), errBox = DataBox()
        let group = DispatchGroup()
        let queue = DispatchQueue(label: "ghostshot.process", attributes: .concurrent)

        group.enter()
        queue.async { outBox.data = outPipe.fileHandleForReading.readDataToEndOfFile(); group.leave() }
        group.enter()
        queue.async { errBox.data = errPipe.fileHandleForReading.readDataToEndOfFile(); group.leave() }

        if !stdin.isEmpty {
            inPipe.fileHandleForWriting.write(Data(stdin.utf8))
        }
        try? inPipe.fileHandleForWriting.close()

        process.waitUntilExit()
        group.wait()

        return ProcessResult(
            exitCode: process.terminationStatus,
            stdout: String(decoding: outBox.data, as: UTF8.self),
            stderr: String(decoding: errBox.data, as: UTF8.self)
        )
    }
}

private final class DataBox: @unchecked Sendable {
    var data = Data()
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter ProcessRunnerTests`
Expected: PASS, 3 tests. The large-stdin test is the one that proves the pipe draining is correct.

- [ ] **Step 5: Commit**

```bash
git add Sources/GhostshotCore/HTTPClient.swift Sources/GhostshotCore/ProcessRunner.swift Tests/GhostshotCoreTests/Fakes.swift Tests/GhostshotCoreTests/ProcessRunnerTests.swift
git commit -m "feat: HTTP and process injection seams with deadlock-free pipe draining"
```

---

### Task 6: GeminiProvider

**Files:**
- Create: `Sources/GhostshotCore/GeminiProvider.swift`
- Test: `Tests/GhostshotCoreTests/GeminiProviderTests.swift`

**Interfaces:**
- Consumes: `Message`, `AIProvider`, `AIError` (Task 1); `HTTPClient` and `FakeHTTPClient` (Task 5).
- Produces: `GeminiProvider(apiKey:model:systemPrompt:client:)` conforming to `AIProvider`, with `name == "gemini"`. Task 7 uses it as the primary provider.

Continuity comes from resending the whole history each turn. Gemini uses role `"model"` for assistant turns, not `"assistant"`.

- [ ] **Step 1: Write the failing test**

`Tests/GhostshotCoreTests/GeminiProviderTests.swift`:

```swift
import XCTest
@testable import GhostshotCore

final class GeminiProviderTests: XCTestCase {
    private func makeProvider(_ client: FakeHTTPClient) -> GeminiProvider {
        GeminiProvider(apiKey: "KEY123", model: "gemini-2.5-flash", systemPrompt: "be terse", client: client)
    }

    private func successBody(_ text: String) -> Data {
        Data(#"{"candidates":[{"content":{"parts":[{"text":"\#(text)"}],"role":"model"}}]}"#.utf8)
    }

    func test_buildsCorrectURLAndAuthHeader() async throws {
        let client = FakeHTTPClient()
        client.responses = [(successBody("hi"), 200)]

        _ = try await makeProvider(client).ask(history: [Message(role: .user, text: "q")])

        let request = try XCTUnwrap(client.sentRequests.last)
        XCTAssertEqual(
            request.url?.absoluteString,
            "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent"
        )
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "x-goog-api-key"), "KEY123")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
    }

    func test_sendsSystemInstructionAndFullHistoryWithMappedRoles() async throws {
        let client = FakeHTTPClient()
        client.responses = [(successBody("ok"), 200)]
        let history = [
            Message(role: .user, text: "first"),
            Message(role: .assistant, text: "answer"),
            Message(role: .user, text: "second"),
        ]

        _ = try await makeProvider(client).ask(history: history)

        let json = client.lastBodyJSON
        let system = json["system_instruction"] as? [String: Any]
        let systemParts = system?["parts"] as? [[String: Any]]
        XCTAssertEqual(systemParts?.first?["text"] as? String, "be terse")

        let contents = try XCTUnwrap(json["contents"] as? [[String: Any]])
        XCTAssertEqual(contents.count, 3)
        XCTAssertEqual(contents[0]["role"] as? String, "user")
        XCTAssertEqual(contents[1]["role"] as? String, "model")
        XCTAssertEqual(contents[2]["role"] as? String, "user")
    }

    func test_encodesImageAsBase64InlineData() async throws {
        let client = FakeHTTPClient()
        client.responses = [(successBody("ok"), 200)]
        let png = Data([0x89, 0x50, 0x4E, 0x47])

        _ = try await makeProvider(client).ask(history: [Message(role: .user, text: "q", imagePNG: png)])

        let contents = try XCTUnwrap(client.lastBodyJSON["contents"] as? [[String: Any]])
        let parts = try XCTUnwrap(contents[0]["parts"] as? [[String: Any]])
        let inline = try XCTUnwrap(parts.compactMap { $0["inline_data"] as? [String: Any] }.first)
        XCTAssertEqual(inline["mime_type"] as? String, "image/png")
        XCTAssertEqual(inline["data"] as? String, png.base64EncodedString())
    }

    func test_joinsAllTextPartsOfTheAnswer() async throws {
        let client = FakeHTTPClient()
        client.responses = [(Data(#"{"candidates":[{"content":{"parts":[{"text":"one "},{"text":"two"}]}}]}"#.utf8), 200)]

        let answer = try await makeProvider(client).ask(history: [Message(role: .user, text: "q")])

        XCTAssertEqual(answer, "one two")
    }

    func test_http429_mapsToQuotaExhausted() async {
        let client = FakeHTTPClient()
        client.responses = [(Data(#"{"error":{"message":"rate limited"}}"#.utf8), 429)]

        await assertThrows(.quotaExhausted, from: makeProvider(client))
    }

    func test_resourceExhaustedInBody_mapsToQuotaExhausted() async {
        let client = FakeHTTPClient()
        client.responses = [(Data(#"{"error":{"status":"RESOURCE_EXHAUSTED"}}"#.utf8), 200)]

        await assertThrows(.quotaExhausted, from: makeProvider(client))
    }

    func test_unparseableBody_mapsToBadResponse() async {
        let client = FakeHTTPClient()
        client.responses = [(Data("<html>nope</html>".utf8), 200)]

        do {
            _ = try await makeProvider(client).ask(history: [Message(role: .user, text: "q")])
            XCTFail("expected throw")
        } catch let error as AIError {
            guard case .badResponse = error else { return XCTFail("expected badResponse, got \(error)") }
        } catch {
            XCTFail("expected AIError, got \(error)")
        }
    }

    private func assertThrows(_ expected: AIError, from provider: GeminiProvider,
                              file: StaticString = #filePath, line: UInt = #line) async {
        do {
            _ = try await provider.ask(history: [Message(role: .user, text: "q")])
            XCTFail("expected throw", file: file, line: line)
        } catch let error as AIError {
            XCTAssertEqual(error, expected, file: file, line: line)
        } catch {
            XCTFail("expected AIError, got \(error)", file: file, line: line)
        }
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter GeminiProviderTests`
Expected: FAIL — `cannot find 'GeminiProvider' in scope`.

- [ ] **Step 3: Write minimal implementation**

`Sources/GhostshotCore/GeminiProvider.swift`:

```swift
import Foundation

public final class GeminiProvider: AIProvider {
    public let name = "gemini"

    private let apiKey: String
    private let model: String
    private let systemPrompt: String
    private let client: HTTPClient

    public init(apiKey: String, model: String, systemPrompt: String, client: HTTPClient) {
        self.apiKey = apiKey
        self.model = model
        self.systemPrompt = systemPrompt
        self.client = client
    }

    public func ask(history: [Message]) async throws -> String {
        let request = try buildRequest(history: history)

        let data: Data
        let response: HTTPURLResponse
        do {
            (data, response) = try await client.send(request)
        } catch let error as AIError {
            throw error
        } catch {
            throw AIError.network(error.localizedDescription)
        }

        let raw = String(decoding: data, as: UTF8.self)
        if response.statusCode == 429 || raw.contains("RESOURCE_EXHAUSTED") {
            throw AIError.quotaExhausted
        }
        guard (200..<300).contains(response.statusCode) else {
            throw AIError.badResponse("HTTP \(response.statusCode): \(raw.prefix(300))")
        }

        guard
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let candidates = json["candidates"] as? [[String: Any]],
            let content = candidates.first?["content"] as? [String: Any],
            let parts = content["parts"] as? [[String: Any]]
        else {
            throw AIError.badResponse("unexpected body: \(raw.prefix(300))")
        }

        let text = parts.compactMap { $0["text"] as? String }.joined()
        guard !text.isEmpty else { throw AIError.badResponse("empty answer") }
        return text
    }

    func buildRequest(history: [Message]) throws -> URLRequest {
        let urlString = "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent"
        guard let url = URL(string: urlString) else {
            throw AIError.badResponse("bad model name: \(model)")
        }

        let contents: [[String: Any]] = history.map { message in
            var parts: [[String: Any]] = []
            if !message.text.isEmpty {
                parts.append(["text": message.text])
            }
            if let png = message.imagePNG {
                parts.append(["inline_data": ["mime_type": "image/png", "data": png.base64EncodedString()]])
            }
            if parts.isEmpty { parts.append(["text": ""]) }
            return ["role": message.role == .user ? "user" : "model", "parts": parts]
        }

        let body: [String: Any] = [
            "system_instruction": ["parts": [["text": systemPrompt]]],
            "contents": contents,
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter GeminiProviderTests`
Expected: PASS, 7 tests.

- [ ] **Step 5: Commit**

```bash
git add Sources/GhostshotCore/GeminiProvider.swift Tests/GhostshotCoreTests/GeminiProviderTests.swift
git commit -m "feat: Gemini provider with history replay and quota detection"
```

---

### Task 7: ClaudeCodeProvider

**Files:**
- Create: `Sources/GhostshotCore/ClaudeCodeProvider.swift`
- Test: `Tests/GhostshotCoreTests/ClaudeCodeProviderTests.swift`

**Interfaces:**
- Consumes: `Message`, `AIProvider`, `AIError` (Task 1); `ProcessRunner`, `ProcessResult`, `FakeProcessRunner` (Task 5); `Conversation.earlierScreenshotPlaceholder` (Task 3).
- Produces: `ClaudeCodeProvider(executablePath:systemPrompt:runner:imageWriter:)` conforming to `AIProvider` with `name == "claude-code"`, plus `var sessionID: String?` (readable and settable, so Task 12 can persist it across launches). Task 8 uses this as the fallback provider.

**Critical, verified on this machine:** the prompt goes on **stdin**, never as a positional argument, because `--allowedTools` is variadic and swallows it.

`imageWriter` is a closure `(Data) throws -> String` returning the path the PNG was written to. Injected so tests never touch the disk.

- [ ] **Step 1: Write the failing test**

`Tests/GhostshotCoreTests/ClaudeCodeProviderTests.swift`:

```swift
import XCTest
@testable import GhostshotCore

final class ClaudeCodeProviderTests: XCTestCase {
    private func makeProvider(_ runner: FakeProcessRunner) -> ClaudeCodeProvider {
        ClaudeCodeProvider(
            executablePath: "/usr/local/bin/claude",
            systemPrompt: "be terse",
            runner: runner,
            imageWriter: { _ in "/tmp/ghostshot/shot.png" }
        )
    }

    private func resultJSON(sessionID: String, answer: String, isError: Bool = false) -> ProcessResult {
        let json = #"{"session_id":"\#(sessionID)","is_error":\#(isError),"result":"\#(answer)"}"#
        return ProcessResult(exitCode: 0, stdout: json, stderr: "")
    }

    func test_firstCall_omitsResumeAndSendsPromptOnStdin() async throws {
        let runner = FakeProcessRunner()
        runner.results = [resultJSON(sessionID: "s-1", answer: "the answer")]

        let answer = try await makeProvider(runner)
            .ask(history: [Message(role: .user, text: "what is this", imagePNG: Data([0x89]))])

        XCTAssertEqual(answer, "the answer")
        let call = try XCTUnwrap(runner.calls.last)
        XCTAssertEqual(call.executable, "/usr/local/bin/claude")
        XCTAssertFalse(call.arguments.contains("--resume"))
        XCTAssertEqual(call.arguments, ["-p", "--output-format", "json", "--allowedTools", "Read"])
        // The prompt must be on stdin, never a positional argument.
        XCTAssertTrue(call.stdin.contains("/tmp/ghostshot/shot.png"))
        XCTAssertFalse(call.arguments.contains(where: { $0.contains("/tmp/ghostshot/shot.png") }))
    }

    func test_storesSessionIDAndResumesOnSecondCall() async throws {
        let runner = FakeProcessRunner()
        runner.results = [
            resultJSON(sessionID: "s-1", answer: "first"),
            resultJSON(sessionID: "s-1", answer: "second"),
        ]
        let provider = makeProvider(runner)

        _ = try await provider.ask(history: [Message(role: .user, text: "a", imagePNG: Data([0x89]))])
        XCTAssertEqual(provider.sessionID, "s-1")

        _ = try await provider.ask(history: [Message(role: .user, text: "b", imagePNG: Data([0x89]))])

        let call = try XCTUnwrap(runner.calls.last)
        XCTAssertEqual(call.arguments, ["-p", "--resume", "s-1", "--output-format", "json", "--allowedTools", "Read"])
    }

    func test_firstPromptCarriesPriorHistoryAsText() async throws {
        let runner = FakeProcessRunner()
        runner.results = [resultJSON(sessionID: "s-1", answer: "ok")]
        let history = [
            Message(role: .user, text: "earlier question"),
            Message(role: .assistant, text: "earlier answer"),
            Message(role: .user, text: "current question", imagePNG: Data([0x89])),
        ]

        _ = try await makeProvider(runner).ask(history: history)

        let stdin = try XCTUnwrap(runner.calls.last?.stdin)
        XCTAssertTrue(stdin.contains("earlier question"))
        XCTAssertTrue(stdin.contains("earlier answer"))
        XCTAssertTrue(stdin.contains("be terse"))
    }

    func test_resumedPromptDoesNotRepeatHistory() async throws {
        let runner = FakeProcessRunner()
        runner.results = [
            resultJSON(sessionID: "s-1", answer: "first"),
            resultJSON(sessionID: "s-1", answer: "second"),
        ]
        let provider = makeProvider(runner)

        _ = try await provider.ask(history: [Message(role: .user, text: "unique-earlier-text", imagePNG: Data([0x89]))])
        _ = try await provider.ask(history: [
            Message(role: .user, text: "unique-earlier-text", imagePNG: Data([0x89])),
            Message(role: .assistant, text: "first"),
            Message(role: .user, text: "now this", imagePNG: Data([0x89])),
        ])

        let stdin = try XCTUnwrap(runner.calls.last?.stdin)
        XCTAssertFalse(stdin.contains("unique-earlier-text"))
        XCTAssertTrue(stdin.contains("now this"))
    }

    func test_isErrorTrue_throwsBadResponse() async {
        let runner = FakeProcessRunner()
        runner.results = [resultJSON(sessionID: "s-1", answer: "went wrong", isError: true)]

        await assertThrowsAIError(makeProvider(runner)) { error in
            guard case .badResponse = error else { return XCTFail("expected badResponse, got \(error)") }
        }
    }

    func test_nonZeroExit_throwsProviderUnavailable() async {
        let runner = FakeProcessRunner()
        runner.results = [ProcessResult(exitCode: 1, stdout: "", stderr: "command not found")]

        await assertThrowsAIError(makeProvider(runner)) { error in
            guard case .providerUnavailable = error else { return XCTFail("expected providerUnavailable, got \(error)") }
        }
    }

    func test_unparseableStdout_throwsBadResponse() async {
        let runner = FakeProcessRunner()
        runner.results = [ProcessResult(exitCode: 0, stdout: "not json", stderr: "")]

        await assertThrowsAIError(makeProvider(runner)) { error in
            guard case .badResponse = error else { return XCTFail("expected badResponse, got \(error)") }
        }
    }

    func test_resetSessionClearsResume() async throws {
        let runner = FakeProcessRunner()
        runner.results = [
            resultJSON(sessionID: "s-1", answer: "first"),
            resultJSON(sessionID: "s-2", answer: "fresh"),
        ]
        let provider = makeProvider(runner)

        _ = try await provider.ask(history: [Message(role: .user, text: "a", imagePNG: Data([0x89]))])
        provider.sessionID = nil
        _ = try await provider.ask(history: [Message(role: .user, text: "b", imagePNG: Data([0x89]))])

        XCTAssertFalse(try XCTUnwrap(runner.calls.last).arguments.contains("--resume"))
        XCTAssertEqual(provider.sessionID, "s-2")
    }

    private func assertThrowsAIError(
        _ provider: ClaudeCodeProvider,
        file: StaticString = #filePath,
        line: UInt = #line,
        check: (AIError) -> Void
    ) async {
        do {
            _ = try await provider.ask(history: [Message(role: .user, text: "q", imagePNG: Data([0x89]))])
            XCTFail("expected throw", file: file, line: line)
        } catch let error as AIError {
            check(error)
        } catch {
            XCTFail("expected AIError, got \(error)", file: file, line: line)
        }
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter ClaudeCodeProviderTests`
Expected: FAIL — `cannot find 'ClaudeCodeProvider' in scope`.

- [ ] **Step 3: Write minimal implementation**

`Sources/GhostshotCore/ClaudeCodeProvider.swift`:

```swift
import Foundation

public final class ClaudeCodeProvider: AIProvider, @unchecked Sendable {
    public let name = "claude-code"

    /// Nil means the next call starts a fresh session. Persisted by the app across launches.
    public var sessionID: String?

    private let executablePath: String
    private let systemPrompt: String
    private let runner: ProcessRunner
    private let imageWriter: (Data) throws -> String

    public init(
        executablePath: String,
        systemPrompt: String,
        runner: ProcessRunner,
        imageWriter: @escaping (Data) throws -> String
    ) {
        self.executablePath = executablePath
        self.systemPrompt = systemPrompt
        self.runner = runner
        self.imageWriter = imageWriter
    }

    public func ask(history: [Message]) async throws -> String {
        guard let latest = history.last else {
            throw AIError.badResponse("empty history")
        }

        var imagePath: String?
        if let png = latest.imagePNG {
            do {
                imagePath = try imageWriter(png)
            } catch {
                throw AIError.providerUnavailable("could not write screenshot: \(error.localizedDescription)")
            }
        }

        let prompt = buildPrompt(history: history, imagePath: imagePath)
        let args = arguments(sessionID: sessionID)

        let result: ProcessResult
        do {
            result = try await runner.run(executable: executablePath, arguments: args, stdin: prompt)
        } catch {
            throw AIError.providerUnavailable(error.localizedDescription)
        }

        guard result.exitCode == 0 else {
            let detail = result.stderr.isEmpty ? result.stdout : result.stderr
            throw AIError.providerUnavailable("claude exited \(result.exitCode): \(detail.prefix(300))")
        }

        guard
            let data = result.stdout.data(using: .utf8),
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            throw AIError.badResponse("claude stdout was not JSON: \(result.stdout.prefix(300))")
        }

        if let newSession = json["session_id"] as? String {
            sessionID = newSession
        }

        let answer = json["result"] as? String ?? ""
        if (json["is_error"] as? Bool) == true {
            throw AIError.badResponse("claude reported an error: \(answer.prefix(300))")
        }
        guard !answer.isEmpty else { throw AIError.badResponse("claude returned an empty result") }
        return answer
    }

    /// The prompt is passed on stdin. `--allowedTools` is variadic and would eat a positional prompt.
    func arguments(sessionID: String?) -> [String] {
        var args = ["-p"]
        if let sessionID {
            args += ["--resume", sessionID]
        }
        args += ["--output-format", "json", "--allowedTools", "Read"]
        return args
    }

    func buildPrompt(history: [Message], imagePath: String?) -> String {
        var lines: [String] = []

        // A resumed session already holds the earlier turns, so replay them only on a fresh session.
        if sessionID == nil {
            lines.append(systemPrompt)
            let earlier = history.dropLast()
            if !earlier.isEmpty {
                lines.append("")
                lines.append("Earlier in this conversation:")
                for message in earlier {
                    let speaker = message.role == .user ? "Me" : "You"
                    lines.append("\(speaker): \(message.text)")
                }
            }
            lines.append("")
        }

        if let imagePath {
            lines.append("Read \(imagePath) and answer the question shown in it.")
        }
        if let latestText = history.last?.text, !latestText.isEmpty {
            lines.append(latestText)
        }

        return lines.joined(separator: "\n")
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter ClaudeCodeProviderTests`
Expected: PASS, 8 tests.

- [ ] **Step 5: Commit**

```bash
git add Sources/GhostshotCore/ClaudeCodeProvider.swift Tests/GhostshotCoreTests/ClaudeCodeProviderTests.swift
git commit -m "feat: claude CLI provider with stdin prompt and session resume"
```

---

### Task 8: ProviderRouter failover

**Files:**
- Create: `Sources/GhostshotCore/ProviderRouter.swift`
- Test: `Tests/GhostshotCoreTests/ProviderRouterTests.swift`

**Interfaces:**
- Consumes: `AIProvider`, `AIError`, `Message` (Task 1); `AppState`, `ConfigStore` (Task 4).
- Produces: `ProviderRouter(primary:fallback:loadState:saveState:today:)` with `ask(history:) async throws -> RouterAnswer`, where `RouterAnswer` has `text: String` and `providerName: String`. Task 12 calls this.

`loadState`/`saveState`/`today` are closures so the router is tested without a filesystem or a real calendar.

- [ ] **Step 1: Write the failing test**

`Tests/GhostshotCoreTests/ProviderRouterTests.swift`:

```swift
import XCTest
@testable import GhostshotCore

private final class StubProvider: AIProvider, @unchecked Sendable {
    let name: String
    var answer: String
    var error: AIError?
    private(set) var callCount = 0

    init(name: String, answer: String = "ok", error: AIError? = nil) {
        self.name = name
        self.answer = answer
        self.error = error
    }

    func ask(history: [Message]) async throws -> String {
        callCount += 1
        if let error { throw error }
        return answer
    }
}

final class ProviderRouterTests: XCTestCase {
    private var state = AppState()

    private func makeRouter(
        primary: StubProvider,
        fallback: StubProvider,
        today: String = "2026-09-04"
    ) -> ProviderRouter {
        ProviderRouter(
            primary: primary,
            fallback: fallback,
            loadState: { self.state },
            saveState: { self.state = $0 },
            today: { today }
        )
    }

    private let history = [Message(role: .user, text: "q")]

    func test_usesPrimaryWhenItWorks() async throws {
        let primary = StubProvider(name: "gemini", answer: "from gemini")
        let fallback = StubProvider(name: "claude-code")

        let answer = try await makeRouter(primary: primary, fallback: fallback).ask(history: history)

        XCTAssertEqual(answer.text, "from gemini")
        XCTAssertEqual(answer.providerName, "gemini")
        XCTAssertEqual(fallback.callCount, 0)
    }

    func test_quotaExhausted_failsOverAndRecordsTheDate() async throws {
        let primary = StubProvider(name: "gemini", error: .quotaExhausted)
        let fallback = StubProvider(name: "claude-code", answer: "from claude")

        let answer = try await makeRouter(primary: primary, fallback: fallback).ask(history: history)

        XCTAssertEqual(answer.text, "from claude")
        XCTAssertEqual(answer.providerName, "claude-code")
        XCTAssertEqual(state.geminiExhaustedOn, "2026-09-04")
    }

    func test_sameDay_skipsPrimaryEntirely() async throws {
        state.geminiExhaustedOn = "2026-09-04"
        let primary = StubProvider(name: "gemini", answer: "should not be used")
        let fallback = StubProvider(name: "claude-code", answer: "from claude")

        let answer = try await makeRouter(primary: primary, fallback: fallback).ask(history: history)

        XCTAssertEqual(primary.callCount, 0)
        XCTAssertEqual(answer.providerName, "claude-code")
    }

    func test_nextDay_retriesPrimary() async throws {
        state.geminiExhaustedOn = "2026-09-03"
        let primary = StubProvider(name: "gemini", answer: "gemini is back")
        let fallback = StubProvider(name: "claude-code")

        let answer = try await makeRouter(primary: primary, fallback: fallback, today: "2026-09-04").ask(history: history)

        XCTAssertEqual(primary.callCount, 1)
        XCTAssertEqual(answer.text, "gemini is back")
    }

    func test_nonQuotaError_doesNotFailOver() async {
        let primary = StubProvider(name: "gemini", error: .network("offline"))
        let fallback = StubProvider(name: "claude-code")

        do {
            _ = try await makeRouter(primary: primary, fallback: fallback).ask(history: history)
            XCTFail("expected throw")
        } catch let error as AIError {
            XCTAssertEqual(error, .network("offline"))
            XCTAssertEqual(fallback.callCount, 0)
        } catch {
            XCTFail("expected AIError, got \(error)")
        }
    }

    func test_bothProvidersFail_surfacesFallbackError() async {
        let primary = StubProvider(name: "gemini", error: .quotaExhausted)
        let fallback = StubProvider(name: "claude-code", error: .providerUnavailable("claude missing"))

        do {
            _ = try await makeRouter(primary: primary, fallback: fallback).ask(history: history)
            XCTFail("expected throw")
        } catch let error as AIError {
            XCTAssertEqual(error, .providerUnavailable("claude missing"))
        } catch {
            XCTFail("expected AIError, got \(error)")
        }
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter ProviderRouterTests`
Expected: FAIL — `cannot find 'ProviderRouter' in scope`.

- [ ] **Step 3: Write minimal implementation**

`Sources/GhostshotCore/ProviderRouter.swift`:

```swift
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
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter ProviderRouterTests`
Expected: PASS, 6 tests.

- [ ] **Step 5: Commit**

```bash
git add Sources/GhostshotCore/ProviderRouter.swift Tests/GhostshotCoreTests/ProviderRouterTests.swift
git commit -m "feat: provider router with same-day quota stickiness"
```

---

### Task 9: NtfySender phone push

**Files:**
- Create: `Sources/GhostshotCore/NtfySender.swift`
- Test: `Tests/GhostshotCoreTests/NtfySenderTests.swift`

**Interfaces:**
- Consumes: `HTTPClient`, `FakeHTTPClient` (Task 5).
- Produces: `NtfySender(topic:client:)` with `send(title:body:) async` and `static let maxBodyCharacters = 3800`. Task 12 calls it.

`send` never throws. A failed push must not break the answer that already reached the panel.

- [ ] **Step 1: Write the failing test**

`Tests/GhostshotCoreTests/NtfySenderTests.swift`:

```swift
import XCTest
@testable import GhostshotCore

final class NtfySenderTests: XCTestCase {
    func test_postsToTopicURLWithTitleHeader() async {
        let client = FakeHTTPClient()
        await NtfySender(topic: "my-secret-topic", client: client).send(title: "Answer", body: "hello")

        let request = client.sentRequests.last
        XCTAssertEqual(request?.url?.absoluteString, "https://ntfy.sh/my-secret-topic")
        XCTAssertEqual(request?.httpMethod, "POST")
        XCTAssertEqual(request?.value(forHTTPHeaderField: "Title"), "Answer")
        XCTAssertEqual(request?.httpBody, Data("hello".utf8))
    }

    func test_truncatesLongBodies() async {
        let client = FakeHTTPClient()
        let long = String(repeating: "x", count: 5000)

        await NtfySender(topic: "t", client: client).send(title: "Answer", body: long)

        let body = String(decoding: client.sentRequests.last?.httpBody ?? Data(), as: UTF8.self)
        XCTAssertEqual(body.count, NtfySender.maxBodyCharacters)
        XCTAssertTrue(body.hasSuffix("…"))
    }

    func test_emptyTopic_sendsNothing() async {
        let client = FakeHTTPClient()
        await NtfySender(topic: "", client: client).send(title: "Answer", body: "hello")

        XCTAssertTrue(client.sentRequests.isEmpty)
    }

    func test_networkFailure_isSwallowed() async {
        let client = FakeHTTPClient()
        client.thrownError = AIError.network("offline")

        await NtfySender(topic: "t", client: client).send(title: "Answer", body: "hello")

        XCTAssertEqual(client.sentRequests.count, 1)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter NtfySenderTests`
Expected: FAIL — `cannot find 'NtfySender' in scope`.

- [ ] **Step 3: Write minimal implementation**

`Sources/GhostshotCore/NtfySender.swift`:

```swift
import Foundation

public struct NtfySender {
    public static let maxBodyCharacters = 3800

    private let topic: String
    private let client: HTTPClient

    public init(topic: String, client: HTTPClient) {
        self.topic = topic
        self.client = client
    }

    public func send(title: String, body: String) async {
        guard !topic.isEmpty,
              let url = URL(string: "https://ntfy.sh/\(topic)")
        else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(title, forHTTPHeaderField: "Title")
        request.httpBody = Data(Self.truncate(body).utf8)

        _ = try? await client.send(request)
    }

    static func truncate(_ text: String) -> String {
        guard text.count > maxBodyCharacters else { return text }
        return String(text.prefix(maxBodyCharacters - 1)) + "…"
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter NtfySenderTests`
Expected: PASS, 4 tests.

- [ ] **Step 5: Commit**

```bash
git add Sources/GhostshotCore/NtfySender.swift Tests/GhostshotCoreTests/NtfySenderTests.swift
git commit -m "feat: ntfy phone push with truncation and silent failure"
```

---

### Task 10: ScreenCapturer

**Files:**
- Create: `Sources/GhostshotApp/ScreenCapturer.swift`
- Modify: `Sources/GhostshotApp/main.swift` (temporary manual harness, replaced in Task 13)

**Interfaces:**
- Consumes: nothing from Core.
- Produces: `ScreenCapturer` with `static func capture(excludingWindowNumbers: [Int]) async throws -> Data` returning PNG bytes, and `enum CaptureError: Error { case permissionDenied(String), noDisplay, encodingFailed }`. Task 12 calls it with the overlay panel's window number.

**Excluding the overlay panel matters.** Without it, a capture taken while the panel is visible includes the previous answer, and the model starts answering its own output.

There is no unit test here — this is a thin shell over ScreenCaptureKit that needs a real display and a granted permission. It is verified by hand in this task's Step 4.

- [ ] **Step 1: Write the implementation**

`Sources/GhostshotApp/ScreenCapturer.swift`:

```swift
import AppKit
import Foundation
import ScreenCaptureKit

enum CaptureError: LocalizedError {
    case permissionDenied(String)
    case noDisplay
    case encodingFailed

    var errorDescription: String? {
        switch self {
        case .permissionDenied(let detail):
            return """
            Screen Recording permission is not granted.

            System Settings > Privacy & Security > Screen & System Audio Recording
            Enable Ghostshot, then quit and relaunch the app.

            (\(detail))
            """
        case .noDisplay:
            return "No display found to capture."
        case .encodingFailed:
            return "Could not encode the screenshot as PNG."
        }
    }
}

enum ScreenCapturer {
    /// Captures the display under the mouse pointer, omitting our own windows.
    static func capture(excludingWindowNumbers: [Int]) async throws -> Data {
        let content: SCShareableContent
        do {
            content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        } catch {
            throw CaptureError.permissionDenied(error.localizedDescription)
        }

        guard let display = displayUnderCursor(in: content.displays) else {
            throw CaptureError.noDisplay
        }

        let excluded = content.windows.filter { excludingWindowNumbers.contains(Int($0.windowID)) }
        let filter = SCContentFilter(display: display, excludingWindows: excluded)

        let configuration = SCStreamConfiguration()
        configuration.width = display.width
        configuration.height = display.height
        configuration.showsCursor = false
        configuration.capturesAudio = false

        let image = try await SCScreenshotManager.captureImage(
            contentFilter: filter,
            configuration: configuration
        )

        let bitmap = NSBitmapImageRep(cgImage: image)
        guard let png = bitmap.representation(using: .png, properties: [:]) else {
            throw CaptureError.encodingFailed
        }
        return png
    }

    private static func displayUnderCursor(in displays: [SCDisplay]) -> SCDisplay? {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main

        if let screenNumber = screen?.deviceDescription[
            NSDeviceDescriptionKey("NSScreenNumber")
        ] as? NSNumber {
            if let match = displays.first(where: { $0.displayID == screenNumber.uint32Value }) {
                return match
            }
        }
        return displays.first
    }
}
```

- [ ] **Step 2: Write a temporary manual harness**

Replace `Sources/GhostshotApp/main.swift`:

```swift
import AppKit
import Foundation

// Temporary harness for Task 10. Replaced by the real app bootstrap in Task 13.
let app = NSApplication.shared
app.setActivationPolicy(.accessory)

Task {
    do {
        let png = try await ScreenCapturer.capture(excludingWindowNumbers: [])
        let url = URL(fileURLWithPath: "/tmp/ghostshot-manual-capture.png")
        try png.write(to: url)
        print("captured \(png.count) bytes to \(url.path)")
    } catch {
        print("capture failed: \(error.localizedDescription)")
    }
    exit(0)
}

app.run()
```

- [ ] **Step 3: Build**

Run: `swift build`
Expected: builds with no errors.

- [ ] **Step 4: Verify by hand**

Run: `swift run GhostshotApp`

Expected on first run: macOS prompts for Screen Recording permission, or the app prints the `permissionDenied` message with the exact System Settings path. Grant it, then run again.

Expected on success: `captured NNNNNN bytes to /tmp/ghostshot-manual-capture.png`.

Then confirm the file is a real screenshot:

```bash
file /tmp/ghostshot-manual-capture.png
open /tmp/ghostshot-manual-capture.png
```

Expected: `PNG image data`, and the image shows your current screen with no mouse cursor drawn.

- [ ] **Step 5: Commit**

```bash
git add Sources/GhostshotApp/ScreenCapturer.swift Sources/GhostshotApp/main.swift
git commit -m "feat: ScreenCaptureKit capture of the display under the cursor"
```

---

### Task 11: OverlayPanel

**Files:**
- Create: `Sources/GhostshotApp/OverlayPanel.swift`
- Modify: `Sources/GhostshotApp/main.swift` (harness updated, replaced in Task 13)

**Interfaces:**
- Consumes: nothing from Core.
- Produces: `PanelState` (`.capturing`, `.thinking(provider: String)`, `.answer(text: String, provider: String)`, `.error(String)`), and `OverlayPanel` (an `NSPanel` subclass) with `render(_ state: PanelState)`, `toggleVisibility()`, `showPanel()`, `var frameString: String`, `func restoreFrame(from: String?)`. Task 12 owns one and passes `windowNumber` to `ScreenCapturer`.

- [ ] **Step 1: Write the implementation**

`Sources/GhostshotApp/OverlayPanel.swift`:

```swift
import AppKit

enum PanelState {
    case capturing
    case thinking(provider: String)
    case answer(text: String, provider: String)
    case error(String)
}

final class OverlayPanel: NSPanel {
    private let textView = NSTextView()
    private let statusLabel = NSTextField(labelWithString: "")

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 420),
            styleMask: [.borderless, .nonactivatingPanel, .resizable],
            backing: .buffered,
            defer: false
        )

        // The whole point: absent from screen shares and recordings.
        sharingType = .none

        level = .floating
        isFloatingPanel = true
        becomesKeyOnlyIfNeeded = true
        hidesOnDeactivate = false
        isMovableByWindowBackground = true
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        backgroundColor = NSColor.black.withAlphaComponent(0.92)
        hasShadow = true
        isOpaque = false

        buildContent()
    }

    private func buildContent() {
        let container = NSView(frame: contentRect(forFrameRect: frame))
        container.wantsLayer = true
        container.layer?.cornerRadius = 10
        container.layer?.masksToBounds = true

        statusLabel.font = .monospacedSystemFont(ofSize: 10, weight: .regular)
        statusLabel.textColor = NSColor.systemGreen
        statusLabel.translatesAutoresizingMaskIntoConstraints = false

        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.textColor = NSColor.white
        textView.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        textView.textContainerInset = NSSize(width: 4, height: 4)

        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        scrollView.documentView = textView
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        container.addSubview(statusLabel)
        container.addSubview(scrollView)

        NSLayoutConstraint.activate([
            statusLabel.topAnchor.constraint(equalTo: container.topAnchor, constant: 8),
            statusLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 12),
            statusLabel.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -12),

            scrollView.topAnchor.constraint(equalTo: statusLabel.bottomAnchor, constant: 6),
            scrollView.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 8),
            scrollView.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -8),
            scrollView.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -8),
        ])

        contentView = container
    }

    func render(_ state: PanelState) {
        switch state {
        case .capturing:
            statusLabel.stringValue = "capturing…"
            statusLabel.textColor = .systemGray
        case .thinking(let provider):
            statusLabel.stringValue = "thinking… (\(provider))"
            statusLabel.textColor = .systemYellow
        case .answer(let text, let provider):
            statusLabel.stringValue = "answer · \(provider)"
            statusLabel.textColor = .systemGreen
            textView.string = text
            textView.scroll(NSPoint(x: 0, y: 0))
        case .error(let message):
            statusLabel.stringValue = "error"
            statusLabel.textColor = .systemRed
            textView.string = message
        }
        showPanel()
    }

    func showPanel() {
        // orderFrontRegardless, never makeKeyAndOrderFront: focus must stay with the client's app.
        orderFrontRegardless()
    }

    func toggleVisibility() {
        if isVisible { orderOut(nil) } else { showPanel() }
    }

    var frameString: String {
        let f = frame
        return "\(f.origin.x),\(f.origin.y),\(f.size.width),\(f.size.height)"
    }

    func restoreFrame(from string: String?) {
        guard let parts = string?.split(separator: ","), parts.count == 4,
              let x = Double(parts[0]), let y = Double(parts[1]),
              let w = Double(parts[2]), let h = Double(parts[3])
        else {
            center()
            return
        }
        setFrame(NSRect(x: x, y: y, width: w, height: h), display: false)
    }
}
```

- [ ] **Step 2: Update the manual harness**

Replace `Sources/GhostshotApp/main.swift`:

```swift
import AppKit
import Foundation

// Temporary harness for Task 11. Replaced by the real app bootstrap in Task 13.
let app = NSApplication.shared
app.setActivationPolicy(.accessory)

let panel = OverlayPanel()
panel.restoreFrame(from: nil)
panel.render(.answer(text: """
If you can read this in a screen recording, sharingType is not working.
Line two, to confirm scrolling and monospace rendering.
""", provider: "manual-test"))

app.run()
```

- [ ] **Step 3: Build**

Run: `swift build`
Expected: builds with no errors.

- [ ] **Step 4: Verify the stealth property by hand**

This is the single most important manual check in the plan. If it fails, the app has no reason to exist.

```bash
swift run GhostshotApp
```

The panel appears, floating, dark, with the test text. It should not appear in the Dock and should not take focus from your current app.

Now, with the panel visible on screen:

1. Start a screen recording: press Cmd+Shift+5, choose "Record Entire Screen", click Record.
2. Wait three seconds, then stop the recording from the menu bar.
3. Open the resulting movie.

Expected: **the panel is absent from the recording** while everything else on the desktop is present.

Also confirm with a second method:

```bash
/usr/sbin/screencapture -x /tmp/ghostshot-sharing-check.png
open /tmp/ghostshot-sharing-check.png
```

Expected: the panel does not appear in that PNG either.

If the panel *does* appear, stop and fix `sharingType` before continuing. Nothing downstream matters until this passes.

Quit the harness with Ctrl+C.

- [ ] **Step 5: Commit**

```bash
git add Sources/GhostshotApp/OverlayPanel.swift Sources/GhostshotApp/main.swift
git commit -m "feat: floating overlay panel excluded from screen capture"
```

---

### Task 12: EventTapController

**Files:**
- Create: `Sources/GhostshotApp/EventTapController.swift`
- Modify: `Sources/GhostshotApp/main.swift` (harness updated, replaced in Task 13)

**Interfaces:**
- Consumes: `HotkeyDetector`, `HotkeyEvent`, `HotkeyAction`, `ModifierKey` (Task 2).
- Produces: `EventTapController(detector:onAction:)` with `func start() throws` and `static func hasAccessibilityPermission(prompt: Bool) -> Bool`, plus `enum EventTapError: LocalizedError { case accessibilityDenied, tapCreationFailed }`. Task 13 wires it.

The tap is created with `.listenOnly` so it observes without consuming. Right-modifier key codes: Right Command `54`, Right Option `61`, Right Control `62`.

- [ ] **Step 1: Write the implementation**

`Sources/GhostshotApp/EventTapController.swift`:

```swift
import AppKit
import ApplicationServices
import CoreGraphics
import GhostshotCore

enum EventTapError: LocalizedError {
    case accessibilityDenied
    case tapCreationFailed

    var errorDescription: String? {
        switch self {
        case .accessibilityDenied:
            return """
            Accessibility permission is not granted, so the hotkeys cannot work.

            System Settings > Privacy & Security > Accessibility
            Enable Ghostshot, then quit and relaunch the app.
            """
        case .tapCreationFailed:
            return "Could not create the keyboard event tap."
        }
    }
}

final class EventTapController {
    private let detector: HotkeyDetector
    private let onAction: (HotkeyAction) -> Void
    private var tap: CFMachPort?

    // Carbon virtual key codes for the right-hand modifiers.
    private static let rightCommandKeyCode: Int64 = 54
    private static let rightOptionKeyCode: Int64 = 61
    private static let rightControlKeyCode: Int64 = 62

    // Device-dependent flag bits that distinguish right modifiers from left.
    private static let rightCommandMask: UInt64 = 0x0000_0010
    private static let rightOptionMask: UInt64 = 0x0000_0040
    private static let rightControlMask: UInt64 = 0x0000_2000

    init(detector: HotkeyDetector, onAction: @escaping (HotkeyAction) -> Void) {
        self.detector = detector
        self.onAction = onAction
    }

    static func hasAccessibilityPermission(prompt: Bool) -> Bool {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue()
        return AXIsProcessTrustedWithOptions([key: prompt] as CFDictionary)
    }

    func start() throws {
        guard Self.hasAccessibilityPermission(prompt: true) else {
            throw EventTapError.accessibilityDenied
        }

        let mask = (1 << CGEventType.flagsChanged.rawValue) | (1 << CGEventType.keyDown.rawValue)
        let context = Unmanaged.passUnretained(self).toOpaque()

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            // listenOnly: observe without consuming, so normal typing is untouched.
            options: .listenOnly,
            eventsOfInterest: CGEventMask(mask),
            callback: { _, type, event, refcon in
                guard let refcon else { return Unmanaged.passUnretained(event) }
                let controller = Unmanaged<EventTapController>.fromOpaque(refcon).takeUnretainedValue()
                controller.handle(type: type, event: event)
                return Unmanaged.passUnretained(event)
            },
            userInfo: context
        ) else {
            throw EventTapError.tapCreationFailed
        }

        self.tap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    private func handle(type: CGEventType, event: CGEvent) {
        // macOS disables a tap that times out; re-enable it rather than dying silently.
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return
        }

        let now = ProcessInfo.processInfo.systemUptime
        var hotkeyEvent: HotkeyEvent?

        switch type {
        case .keyDown:
            hotkeyEvent = .otherKeyDown

        case .flagsChanged:
            let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
            let flags = event.flags.rawValue

            let mapping: (ModifierKey, UInt64)?
            switch keyCode {
            case Self.rightCommandKeyCode: mapping = (.rightCommand, Self.rightCommandMask)
            case Self.rightOptionKeyCode: mapping = (.rightOption, Self.rightOptionMask)
            case Self.rightControlKeyCode: mapping = (.rightControl, Self.rightControlMask)
            default: mapping = nil
            }

            if let (key, mask) = mapping {
                hotkeyEvent = (flags & mask) != 0 ? .modifierDown(key) : .modifierUp(key)
            }

        default:
            break
        }

        guard let hotkeyEvent, let action = detector.handle(hotkeyEvent, at: now) else { return }
        DispatchQueue.main.async { self.onAction(action) }
    }
}
```

- [ ] **Step 2: Update the manual harness**

Replace `Sources/GhostshotApp/main.swift`:

```swift
import AppKit
import Foundation
import GhostshotCore

// Temporary harness for Task 12. Replaced by the real app bootstrap in Task 13.
let app = NSApplication.shared
app.setActivationPolicy(.accessory)

let detector = HotkeyDetector(doubleTapWindowMs: 300)
let controller = EventTapController(detector: detector) { action in
    print("ACTION: \(action)")
}

do {
    try controller.start()
    print("listening. double-tap right cmd / right option / right control. ctrl-c to quit.")
} catch {
    print("failed: \(error.localizedDescription)")
    exit(1)
}

app.run()
```

- [ ] **Step 3: Build**

Run: `swift build`
Expected: builds with no errors.

- [ ] **Step 4: Verify by hand**

Run: `swift run GhostshotApp`

On first run macOS prompts for Accessibility. Grant it to the terminal running the binary, then rerun.

Check each of these:

| Do this | Expect |
| --- | --- |
| Double-tap Right Command quickly | `ACTION: capture` |
| Double-tap Right Option quickly | `ACTION: togglePanel` |
| Double-tap Right Control quickly | `ACTION: resetConversation` |
| Tap Right Command twice slowly (over a second apart) | nothing printed |
| Press Cmd+C in another app | nothing printed |
| Type a paragraph normally | nothing printed, and **all typing works normally** |

The last row is the one that proves `.listenOnly` is correct. If any keystrokes go missing, the tap is consuming events and must be fixed.

Quit with Ctrl+C.

- [ ] **Step 5: Commit**

```bash
git add Sources/GhostshotApp/EventTapController.swift Sources/GhostshotApp/main.swift
git commit -m "feat: passive event tap driving the double-tap detector"
```

---

### Task 13: AnswerCoordinator and app bootstrap

**Files:**
- Create: `Sources/GhostshotApp/AnswerCoordinator.swift`
- Create: `Sources/GhostshotApp/AppDelegate.swift`
- Modify: `Sources/GhostshotApp/main.swift` (final version)

**Interfaces:**
- Consumes: everything. `Conversation` (Task 3), `ConfigStore`/`Config`/`AppState` (Task 4), `URLSessionHTTPClient`/`SystemProcessRunner` (Task 5), `GeminiProvider` (Task 6), `ClaudeCodeProvider` (Task 7), `ProviderRouter`/`RouterAnswer` (Task 8), `NtfySender` (Task 9), `ScreenCapturer` (Task 10), `OverlayPanel`/`PanelState` (Task 11), `EventTapController`/`HotkeyDetector` (Task 12).
- Produces: the running app.

- [ ] **Step 1: Write the coordinator**

`Sources/GhostshotApp/AnswerCoordinator.swift`:

```swift
import AppKit
import Foundation
import GhostshotCore

@MainActor
final class AnswerCoordinator {
    private let config: Config
    private let store: ConfigStore
    private let conversation: Conversation
    private let router: ProviderRouter
    private let claude: ClaudeCodeProvider
    private let ntfy: NtfySender
    private let panel: OverlayPanel
    private var isBusy = false

    init(
        config: Config,
        store: ConfigStore,
        conversation: Conversation,
        router: ProviderRouter,
        claude: ClaudeCodeProvider,
        ntfy: NtfySender,
        panel: OverlayPanel
    ) {
        self.config = config
        self.store = store
        self.conversation = conversation
        self.router = router
        self.claude = claude
        self.ntfy = ntfy
        self.panel = panel
    }

    func handle(_ action: HotkeyAction) {
        switch action {
        case .capture: capture()
        case .togglePanel: panel.toggleVisibility()
        case .resetConversation: reset()
        }
    }

    private func reset() {
        conversation.reset()
        claude.sessionID = nil
        var state = store.loadState()
        state.claudeSessionID = nil
        store.saveState(state)
        panel.render(.answer(text: "New conversation started.", provider: "ghostshot"))
    }

    private func capture() {
        // Ignore a second trigger while one request is in flight.
        guard !isBusy else { return }
        isBusy = true
        panel.render(.capturing)

        Task {
            defer { isBusy = false }
            do {
                let png = try await ScreenCapturer.capture(
                    excludingWindowNumbers: [panel.windowNumber]
                )
                panel.render(.thinking(provider: "…"))

                conversation.addUser(text: "", imagePNG: png)
                let answer = try await router.ask(history: conversation.messages)
                conversation.addAssistant(answer.text)

                persistSession()
                deliver(answer)
            } catch {
                let message = error.localizedDescription
                panel.render(.error(message))
                if config.notifyPhone {
                    await ntfy.send(title: "Ghostshot error", body: message)
                }
            }
        }
    }

    private func persistSession() {
        var state = store.loadState()
        state.claudeSessionID = claude.sessionID
        state.panelFrame = panel.frameString
        store.saveState(state)
    }

    private func deliver(_ answer: RouterAnswer) {
        panel.render(.answer(text: answer.text, provider: answer.providerName))

        if config.copyToClipboard {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(answer.text, forType: .string)
        }

        if config.notifyPhone {
            Task { await ntfy.send(title: "Ghostshot", body: answer.text) }
        }
    }
}
```

- [ ] **Step 2: Write the app delegate**

`Sources/GhostshotApp/AppDelegate.swift`:

```swift
import AppKit
import Foundation
import GhostshotCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var panel: OverlayPanel!
    private var eventTap: EventTapController!
    private var coordinator: AnswerCoordinator!
    private let store = ConfigStore.defaultStore()

    func applicationDidFinishLaunching(_ notification: Notification) {
        try? store.writeDefaultConfigIfMissing()

        let config: Config
        do {
            config = try store.loadConfig()
        } catch {
            fatalError("could not read config: \(error)")
        }

        let state = store.loadState()

        panel = OverlayPanel()
        panel.restoreFrame(from: state.panelFrame)

        let http = URLSessionHTTPClient()

        let gemini = GeminiProvider(
            apiKey: config.geminiApiKey,
            model: config.geminiModel,
            systemPrompt: config.systemPrompt,
            client: http
        )

        let claude = ClaudeCodeProvider(
            executablePath: Self.findClaudeExecutable(),
            systemPrompt: config.systemPrompt,
            runner: SystemProcessRunner(),
            imageWriter: Self.writeTempPNG
        )
        claude.sessionID = state.claudeSessionID

        let router = ProviderRouter(
            primary: gemini,
            fallback: claude,
            loadState: { [store] in store.loadState() },
            saveState: { [store] in store.saveState($0) }
        )

        let conversation = Conversation(maxImages: 2)
        let ntfy = NtfySender(topic: config.ntfyTopic, client: http)

        coordinator = AnswerCoordinator(
            config: config,
            store: store,
            conversation: conversation,
            router: router,
            claude: claude,
            ntfy: ntfy,
            panel: panel
        )

        let detector = HotkeyDetector(doubleTapWindowMs: config.doubleTapWindowMs)
        eventTap = EventTapController(detector: detector) { [weak self] action in
            self?.coordinator.handle(action)
        }

        do {
            try eventTap.start()
        } catch {
            panel.render(.error(error.localizedDescription))
            return
        }

        var startupProblems: [String] = []
        if config.geminiApiKey.isEmpty {
            startupProblems.append("No Gemini API key in \(store.configURL.path) — every request will use the claude CLI fallback.")
        }
        if !FileManager.default.isExecutableFile(atPath: Self.findClaudeExecutable()) {
            startupProblems.append("The `claude` CLI was not found — there is no fallback if Gemini's quota runs out.")
        }

        let banner = startupProblems.isEmpty
            ? "Ready.\n\nRight ⌘ ⌘ — capture and ask\nRight ⌥ ⌥ — show/hide this panel\nRight ⌃ ⌃ — start a new conversation"
            : startupProblems.joined(separator: "\n\n")

        panel.render(.answer(text: banner, provider: "ghostshot"))
    }

    private static func findClaudeExecutable() -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let candidates = [
            "\(home)/.local/bin/claude",
            "/opt/homebrew/bin/claude",
            "/usr/local/bin/claude",
        ]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
            ?? candidates[0]
    }

    private static func writeTempPNG(_ data: Data) throws -> String {
        let dir = URL(fileURLWithPath: "/tmp/ghostshot", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        // Sweep anything older than an hour so screenshots do not pile up on disk.
        let cutoff = Date().addingTimeInterval(-3600)
        let contents = try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: [.contentModificationDateKey]
        )
        for url in contents ?? [] {
            let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
            if let modified, modified < cutoff {
                try? FileManager.default.removeItem(at: url)
            }
        }

        let url = dir.appendingPathComponent("shot-\(UUID().uuidString).png")
        try data.write(to: url)
        return url.path
    }
}
```

- [ ] **Step 3: Write the final main.swift**

Replace `Sources/GhostshotApp/main.swift`:

```swift
import AppKit

let application = NSApplication.shared
// .accessory keeps the app out of the Dock and the Cmd-Tab switcher.
application.setActivationPolicy(.accessory)

let delegate = AppDelegate()
application.delegate = delegate
application.run()
```

- [ ] **Step 4: Build and run the whole test suite**

Run: `swift build && swift test`
Expected: builds clean; all tests from Tasks 1 through 9 pass (45 tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/GhostshotApp
git commit -m "feat: wire capture, providers, panel, ntfy and clipboard together"
```

---

### Task 14: App bundle, signing, setup docs, and end-to-end verification

**Files:**
- Create: `Resources/Info.plist`
- Create: `build.sh`
- Create: `run.sh`
- Create: `docs/SETUP.md`
- Modify: `.gitignore`

**Interfaces:**
- Consumes: the built `GhostshotApp` executable from Task 13.
- Produces: `Ghostshot.app`, and the documented setup procedure.

A stable code signature matters: with ad-hoc signing the signature changes on every build and macOS re-asks for Screen Recording and Accessibility each time. `build.sh` therefore honours `GHOSTSHOT_SIGN_ID`, and `docs/SETUP.md` explains creating a reusable self-signed certificate once.

- [ ] **Step 1: Write the Info.plist**

`Resources/Info.plist`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>Ghostshot</string>
    <key>CFBundleDisplayName</key>
    <string>Ghostshot</string>
    <key>CFBundleIdentifier</key>
    <string>com.niteshdas.ghostshot</string>
    <key>CFBundleExecutable</key>
    <string>GhostshotApp</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
```

- [ ] **Step 2: Write the build and run scripts**

`build.sh`:

```bash
#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")"

APP_NAME="Ghostshot"
BUNDLE="build/${APP_NAME}.app"
SIGN_ID="${GHOSTSHOT_SIGN_ID:--}"

echo "==> compiling"
swift build -c release

echo "==> assembling ${BUNDLE}"
rm -rf "${BUNDLE}"
mkdir -p "${BUNDLE}/Contents/MacOS"
mkdir -p "${BUNDLE}/Contents/Resources"

cp Resources/Info.plist "${BUNDLE}/Contents/Info.plist"
cp "$(swift build -c release --show-bin-path)/GhostshotApp" "${BUNDLE}/Contents/MacOS/GhostshotApp"

echo "==> signing with identity: ${SIGN_ID}"
codesign --force --deep --sign "${SIGN_ID}" "${BUNDLE}"
codesign --verify --verbose "${BUNDLE}"

if [ "${SIGN_ID}" = "-" ]; then
  cat <<'WARN'

NOTE: signed ad-hoc. The signature changes on every build, so macOS will
re-ask for Screen Recording and Accessibility after each rebuild.
See docs/SETUP.md to create a stable self-signed certificate once.

WARN
fi

echo "==> built ${BUNDLE}"
```

`run.sh`:

```bash
#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")"
./build.sh

pkill -f "Ghostshot.app/Contents/MacOS/GhostshotApp" 2>/dev/null || true
open build/Ghostshot.app

echo "running. right cmd x2 to capture."
```

Make both executable:

```bash
chmod +x build.sh run.sh
```

- [ ] **Step 3: Write the setup documentation**

`docs/SETUP.md`:

```markdown
# Ghostshot setup

## 1. Stable code-signing certificate (once, optional but recommended)

Without this the app is ad-hoc signed, and macOS re-asks for permissions on
every rebuild.

1. Open Keychain Access.
2. Menu: Keychain Access > Certificate Assistant > Create a Certificate…
3. Name: `Ghostshot Self Signed`
4. Identity Type: Self Signed Root
5. Certificate Type: **Code Signing**
6. Create, then Done.

Then build with it:

    export GHOSTSHOT_SIGN_ID="Ghostshot Self Signed"
    ./build.sh

Put that `export` line in `~/.zshrc` so every build reuses it.

## 2. Gemini API key (free)

1. Go to Google AI Studio and create an API key. The free tier needs no billing.
2. Put it in `~/.config/ghostshot/config.json` under `geminiApiKey`.

The config file is created automatically on first launch with mode 0600. Never
commit it.

## 3. Phone notifications (free)

1. Install the "ntfy" app on the iPhone.
2. Invent a topic name that nobody would guess, e.g. `gs-4f9a2c7e-notes`.
   Anyone who knows the topic can read your answers, so treat it as a secret.
3. Subscribe to that topic in the app.
4. Put the same string in `config.json` under `ntfyTopic`.

## 4. Permissions

Launch once with `./run.sh`, then grant both:

- System Settings > Privacy & Security > **Screen & System Audio Recording** > Ghostshot
- System Settings > Privacy & Security > **Accessibility** > Ghostshot

Quit and relaunch after granting.

## 5. Hotkeys

| Keys | Action |
| --- | --- |
| Right Command, twice fast | capture the screen and ask |
| Right Option, twice fast | show or hide the answer panel |
| Right Control, twice fast | start a new conversation |

## 6. Which model answered

The panel's status line shows `gemini` or `claude-code`. Ghostshot uses the
Gemini free tier until its quota is exhausted, then switches to the `claude`
CLI for the rest of the day and retries Gemini the next day.
```

- [ ] **Step 4: Verify end to end**

```bash
./run.sh
```

Grant both permissions when prompted, then relaunch. Work through this checklist:

| Check | Expected |
| --- | --- |
| App is running | No Dock icon, no menu bar item, not in Cmd-Tab |
| Panel shows the ready banner | Lists the three hotkeys |
| Open a page with a question on it, double-tap Right Command | Panel goes `capturing…` then `thinking…` then shows an answer within ~10s |
| Status line | Reads `answer · gemini` (or `claude-code` if no Gemini key is set) |
| iPhone | ntfy notification arrives with the same answer |
| Clipboard | Cmd+V pastes the answer |
| Second question, different screen, double-tap Right Command | Answer arrives, and asking "what did I show you before?" is answered correctly — proving one continuous session |
| Double-tap Right Option | Panel hides; again, it reappears |
| Double-tap Right Control | Panel says "New conversation started."; the model no longer recalls earlier screenshots |
| **Start a Cmd+Shift+5 full-screen recording, ask a question, stop** | The recording shows the desktop but **not** the panel |
| Type normally in any app | Nothing is captured, no keystrokes lost |

- [ ] **Step 5: Commit**

```bash
git add Resources build.sh run.sh docs/SETUP.md .gitignore
git commit -m "feat: app bundle assembly, signing, and setup documentation"
```

---

## Notes for the implementer

- **Never** pass the prompt as a positional argument to `claude`. It goes on stdin. This is verified, not theoretical.
- The overlay panel must be excluded from capture (`excludingWindowNumbers: [panel.windowNumber]`), or the model ends up reading its own previous answer off the screen.
- `orderFrontRegardless()`, never `makeKeyAndOrderFront(_:)`. The panel must never steal focus.
- The event tap is `.listenOnly`. If you ever change it to `.defaultTap`, you must return the event from the callback or you will swallow the user's keystrokes system-wide.
- Do not log `config.geminiApiKey`.
