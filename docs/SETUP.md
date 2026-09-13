# Ghostshot — setup

A background utility. No Dock icon, no menu bar item, no Cmd-Tab entry.
Double-tap a right-hand modifier key and it captures the screen, asks an AI,
and shows the answer in a panel that screen sharing cannot see.

## Hotkeys

| Gesture | What happens |
|---|---|
| Right ⌘ ⌘ | Capture the screen and ask |
| Right ⌥ ⌥ | Show / hide the answer panel |
| Right ⌃ ⌃ | Start a fresh conversation |
| Right ⇧ ⇧ | Quit Ghostshot |

Both taps must land within 300 ms (`doubleTapWindowMs`). Holding the key as
part of a real shortcut (⌘C, ⌘Tab) never triggers it — including Shift held for
a capital letter, so typing never quits the app.

Right ⌥ ⌥ only hides the panel; the app keeps running. Right ⇧ ⇧ exits for real.

## 1. Build

```bash
./build.sh          # produces Ghostshot.app
```

## 2. Configure

The first launch writes `~/.config/ghostshot/config.json` (mode 0600). Edit it:

```json
{
  "geminiApiKey": "AIza...",
  "ntfyTopic": "ghostshot-<something-random-and-private>",
  "notifyPhone": true,
  "copyToClipboard": true
}
```

- **geminiApiKey** — free from https://aistudio.google.com/apikey. Used first,
  on the free tier. Leave it empty and every request goes to Claude instead.
- **ntfyTopic** — any string. It is the *only* secret protecting the topic, so
  make it long and random. Install the ntfy app on your phone and subscribe to
  the same string to receive answers there. Set `notifyPhone: false` to skip.
- Anything you omit falls back to the built-in default, so a partial file is fine.

When Gemini reports its quota exhausted, Ghostshot switches to the Claude Code
CLI for the rest of that calendar day and retries Gemini the next day. The CLI
path runs on your Claude subscription — no API billing.

## 3. Grant two permissions

Launch it once:

```bash
./run.sh
```

Then in **System Settings > Privacy & Security**:

1. **Accessibility** — enable Ghostshot. Needed to see the modifier taps. The
   tap is listen-only and can never swallow or alter a keystroke.
2. **Screen & System Audio Recording** — enable Ghostshot. Needed to capture.

macOS requires a relaunch after each grant. Run `./run.sh` again.

### Grant them only once

TCC records a *designated requirement*, not an app name. An ad-hoc signature
(`codesign --sign -`) produces a requirement of nothing but the cdhash, so every
code change is a new app to TCC: the switch still reads as on, but it no longer
matches the binary and the permission silently does not apply.

Run this once to get a stable identity:

```bash
./setup-signing.sh   # self-signed cert in your login keychain, asks for your password
```

`build.sh` then signs with it and the requirement becomes `identifier
"com.ghostshot.app" and certificate leaf = H"..."`, which survives every rebuild.
If you had already granted permissions under the ad-hoc signature, clear the
stale rows first:

```bash
tccutil reset Accessibility com.ghostshot.app
tccutil reset ScreenCapture com.ghostshot.app
```

To undo it all, delete "Ghostshot Local Signing" in Keychain Access.

## 4. Verify the stealth property

This is the check that matters. Do it once, yourself, before relying on it:

1. Start Ghostshot and press Right ⌥ ⌥ so the panel is visible.
2. Start a QuickTime screen recording (or a Zoom/Meet screen share) of that display.
3. Stop and play back the recording.

**The panel must be absent from the recording.** If you can see it, stop using
this for its purpose and tell me — the `sharingType = .none` guarantee failed.

## What this does not hide

Two honest limits:

- **A physical camera** pointed at your screen sees the panel. `sharingType`
  only affects software capture.
- **Local admin tooling** (MDM, EDR, a corporate monitoring agent installed on
  this Mac) can see the process, its network traffic, and its files. Ghostshot
  hides from screen capture, not from the operating system.

Screenshots leave your machine: to Google (Gemini) or to Anthropic (Claude
Code), and answer text to ntfy.sh if `notifyPhone` is on. Treat anything on
screen as shared with those services.

## Files

| Path | Purpose |
|---|---|
| `~/.config/ghostshot/config.json` | your settings, mode 0600 |
| `~/.config/ghostshot/state.json` | Claude session id, quota date, panel position |

Delete `state.json` to reset everything.

## Stopping it

Double-tap Right ⇧, or from a terminal:

```bash
pkill -f 'Ghostshot.app/Contents/MacOS/GhostshotApp'
```
