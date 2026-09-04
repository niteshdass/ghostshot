# Ghostshot — Design Spec

Date: 2026-09-04
Status: Approved for planning

## 1. Purpose

A macOS background utility that, on a global hotkey, silently captures the
current screen, sends it to an AI model as part of one continuous
conversation, and delivers the answer to the operator without the answer
appearing in any screen share or recording.

Primary use: the operator is on a client call, a question appears on screen,
and they need a fast answer without switching apps or revealing tooling.

### Success criteria

- Hotkey to answer-on-screen in under 6 seconds on a typical connection.
- The overlay panel is absent from Zoom / Meet / Teams / QuickTime capture.
- Consecutive captures continue one conversation; the model can resolve
  references like "and the second one?" against earlier screenshots.
- Zero recurring cost under normal daily use.
- The app has no Dock icon, no menu bar item, and no Cmd-Tab entry.

### Non-goals

- No OCR, no local model, no clicking or typing on the operator's behalf.
- No browser automation and no interaction with claude.ai web UI.
- No multi-user, no sync, no history browser UI beyond the current answer.
- Not hardened against a determined forensic examiner. The app is listed in
  System Settings privacy panes; this is accepted.

## 2. Constraints

- macOS 14 (Sonoma), Apple Silicon. Deployment target `arm64-apple-macosx14.0`.
- Swift 6.0.3, Command Line Tools only. **No full Xcode.** Build must work
  with SwiftPM plus a shell script that assembles the `.app` bundle.
- Free at the margin. Gemini free tier is the default provider. The fallback
  is the `claude` CLI, which runs on the operator's existing Claude Max
  subscription. The paid Anthropic API is not used without explicit approval.
- Required permissions: Screen Recording, Accessibility. Both are one-time.

## 3. Architecture

Single native AppKit application. No helper daemon, no browser extension.

    Right Cmd x2
       |
       v
    HotkeyDetector --> ScreenCapturer --> Conversation --> AIProvider
     (CGEventTap)     (ScreenCaptureKit)   (history)        |
                                                            +-- GeminiProvider     (default)
                                                            +-- ClaudeCodeProvider (fallback)
                                                                  |
                                          +-----------------------+-----------------------+
                                          v                       v                       v
                                    OverlayPanel            NtfySender               Clipboard
                                 (sharingType .none)      (iPhone push)

### Rejected alternative

Hammerspoon or Keyboard Maestro scripting. Far faster to build, but neither
can set `NSWindow.sharingType = .none` on its canvases, so answers would be
visible in the shared stream. That defeats the primary requirement.

## 4. Components

Each unit below is independently testable except where marked as a thin shell
over a system API.

### 4.1 HotkeyDetector

Pure logic. Consumes a stream of `(key, timestamp)` modifier events and emits
actions. Clock is injected so tests do not sleep.

Bindings:

| Input | Action |
| --- | --- |
| Right Command, twice within 300 ms | `capture` |
| Right Option, twice within 300 ms | `togglePanel` |
| Right Control, twice within 300 ms | `resetConversation` |

Rules:

- A tap is a keyDown followed by keyUp of the same modifier with no other key
  pressed in between. Holding Right Command as part of a real shortcut such as
  Cmd+C must not count as a tap.
- A third tap within the window does not fire a second action. The sequence
  resets after a fire.
- Taps of different modifiers do not combine.

The CGEventTap that feeds this detector is **passive**: it observes and never
consumes events, so all normal modifier behaviour is preserved.

### 4.2 ScreenCapturer

Thin shell over ScreenCaptureKit. Uses `SCScreenshotManager.captureImage` on
the `SCDisplay` whose frame contains the current mouse location; falls back to
the main display if the cursor is off-screen. Encodes to PNG.

Silent by design: ScreenCaptureKit emits no shutter sound and no flash.

Writes the PNG to `/tmp/ghostshot/shot-<uuid>.png` for the Claude Code
provider, which needs a file path. Files older than one hour are deleted on
each capture.

### 4.3 Conversation

Holds the ordered message history and the provider session identifier.

- `append(user:image:)`, `append(assistant:)`, `reset()`.
- **Image trimming:** only the two most recent images are retained. Older
  entries keep their text and replace the image with the literal placeholder
  `[earlier screenshot]`. This keeps long calls inside free-tier token limits.
- `reset()` clears history and clears the stored Claude session id, so the
  next Claude call omits `--resume` and starts a new session.

### 4.4 AIProvider protocol

    protocol AIProvider {
        func ask(history: [Message], image: Data) async throws -> String
    }

Errors are typed. `AIError.quotaExhausted` is the signal the router uses to
fail over; all other errors surface to the operator without switching
providers.

### 4.5 GeminiProvider

- Endpoint: `https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent`
- Auth: API key from config, sent as the `x-goog-api-key` header.
- Body: `contents` array built from the full trimmed history; images as
  `inline_data` with `mime_type: image/png` and base64 payload.
- Continuity comes from resending the history array each turn.
- HTTP 429, or a body containing `RESOURCE_EXHAUSTED`, maps to
  `AIError.quotaExhausted`.

### 4.6 ClaudeCodeProvider

Spawns the `claude` CLI, which bills against the operator's Max subscription.

First turn:

    claude -p --output-format json --allowedTools Read \
      "Read <png path> and answer the question shown in it. \
       Answer first, then one or two lines of reasoning."

The `session_id` field is parsed from the JSON result and stored.

Every later turn:

    claude -p --resume <session_id> --output-format json --allowedTools Read "Read <png path> ..."

`--resume` is what makes this one continuous conversation rather than a fresh
chat per screenshot, matching the Gemini history array.

**Open risk, resolved before anything else is built.** It is not yet verified
that `claude -p` reliably reads an image from a path via the Read tool. The
first implementation task is a throwaway probe of exactly this. If the probe
fails, the fallback provider question returns to the operator for a decision
before any paid API is used. No paid API call is made without approval.

### 4.7 ProviderRouter

Tries Gemini. On `AIError.quotaExhausted`, switches to ClaudeCodeProvider for
the remainder of the day and records `{"exhaustedOn": "YYYY-MM-DD"}` in state.
On the next calendar day the router tries Gemini first again.

Switching providers does **not** clear history. Each provider maintains its
own continuity mechanism, so a mid-conversation switch means the Claude side
starts a new session; the router prepends a short text summary of the prior
turns to the first Claude prompt so context is not lost.

### 4.8 OverlayPanel

Thin shell over AppKit.

    NSPanel, style .nonactivatingPanel
    .level            = .floating
    .sharingType      = .none
    .collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
    .hidesOnDeactivate = false

`.nonactivatingPanel` means showing the panel never steals focus from the
client's application. `.sharingType = .none` is what makes the window blank in
screen-capture APIs.

Displays three states: `capturing`, `thinking`, and the answer. Answer text is
scrollable and rendered in a monospaced font so code stays readable. Position
is remembered between launches.

### 4.9 NtfySender

`POST https://ntfy.sh/<topic>` with the answer as the body. Topic is a secret
string from config. Answers are truncated to 3800 characters for the
notification; the full text remains in the panel and on the clipboard.

Errors are also pushed, so a failure is visible on the phone even when the
panel is hidden.

### 4.10 Config

`~/.config/ghostshot/config.json`, created with mode `0600`.

    {
      "geminiApiKey": "...",
      "ntfyTopic": "...",
      "geminiModel": "gemini-2.5-flash",
      "systemPrompt": "...",
      "doubleTapWindowMs": 300,
      "notifyPhone": true,
      "copyToClipboard": true
    }

The API key lives in this file rather than the Keychain. This is a
single-operator local tool and `0600` is proportionate. Documented as such so
the choice is deliberate rather than an oversight.

Runtime state, separate from config: `~/.config/ghostshot/state.json` holds
the Claude session id, the Gemini exhaustion date, and the panel position.

## 5. Answer delivery

Every answer goes to all three of: the overlay panel, the ntfy phone push, and
the clipboard. The last two are individually disableable in config.

## 6. Stealth properties and their limits

| Property | Mechanism |
| --- | --- |
| No Dock icon, no menu bar, no Cmd-Tab | `LSUIElement = 1` in Info.plist |
| Never steals focus | `.nonactivatingPanel` |
| Absent from screen share and recordings | `sharingType = .none` |
| No shutter sound or flash | ScreenCaptureKit |

Two limits are accepted and documented rather than engineered around:

1. A person physically looking at the operator's monitor sees the panel. The
   ntfy phone push exists to cover this case.
2. The app appears in System Settings, Privacy and Security, under both
   Accessibility and Screen Recording. Any app performing these functions must.

## 7. Error handling

| Condition | Behaviour |
| --- | --- |
| Screen Recording not granted | Panel shows the exact System Settings path to fix it. Capture is not attempted. |
| Accessibility not granted | Same, shown once at launch. Hotkeys cannot work until granted. |
| No network | Panel and ntfy report it. History is left untouched so a retry continues the same conversation. |
| Gemini quota exhausted | Silent failover to Claude. A one-line note appears in the panel so the operator knows which provider answered. |
| Both providers failed | Explicit failure message. Never a silent no-op. |
| `claude` CLI missing from PATH | Reported at launch, not at first failover. |

## 8. Testing

Test-driven. Real behavioural tests on the pure units:

- `HotkeyDetector`: double tap inside and outside the window; triple tap fires
  once; Cmd+C does not register as a tap; interleaved modifiers do not combine.
- `Conversation`: image trimming keeps exactly the last two; placeholder text
  substitution; `reset` clears both history and session id.
- `GeminiProvider`: request body shape against a golden fixture; success
  parsing; 429 and `RESOURCE_EXHAUSTED` both map to `quotaExhausted`.
- `ClaudeCodeProvider`: argument vector construction with and without a stored
  session id; `session_id` extraction from a JSON fixture; non-zero exit
  handling.
- `ProviderRouter`: failover on `quotaExhausted`; no failover on other errors;
  same-day stickiness; next-day retry of Gemini.
- `NtfySender`: URL construction, body truncation at 3800 characters.

Thin shells excluded from unit tests and verified by hand: the CGEventTap,
ScreenCaptureKit capture, and the NSPanel. The `sharingType = .none` guarantee
is verified manually by starting a Zoom or QuickTime screen recording with the
panel visible and confirming it does not appear in the output.

## 9. Build and distribution

- SwiftPM executable target plus a test target.
- `build.sh` compiles in release mode and assembles `Ghostshot.app` with a
  hand-written `Info.plist` carrying `LSUIElement`, `NSScreenCaptureUsageDescription`,
  and the bundle identifier.
- Signing: a self-signed code-signing certificate is generated once into the
  login Keychain and reused for every build. A stable signature means macOS
  keeps the granted permissions across rebuilds; ad-hoc signing would re-prompt
  after every compile.
- `run.sh` builds and launches.

## 10. First-run setup

1. Create a free Gemini API key in Google AI Studio, put it in the config file.
2. Choose a secret ntfy topic, install the ntfy iPhone app, subscribe to it.
3. Launch once and grant Screen Recording and Accessibility.
4. Double-tap Right Command to confirm end to end.
