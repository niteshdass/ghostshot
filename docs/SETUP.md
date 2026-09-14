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
| Right ⌘ ⌘ (while quit) | Start Ghostshot again — the launcher answers this one |

Both taps must land within 300 ms (`doubleTapWindowMs`). Holding the key as
part of a real shortcut (⌘C, ⌘Tab) never triggers it — including Shift held for
a capital letter, so typing never quits the app.

Right ⌥ ⌥ only hides the panel; the app keeps running. Right ⇧ ⇧ exits for real —
the process is gone, which is why a second tiny process, GhostshotLauncher.app,
exists: it has no UI, watches for the same Right ⌘ ⌘, and starts Ghostshot back
up when Ghostshot is not running. While Ghostshot *is* running the launcher
ignores the gesture, so Right ⌘ ⌘ still means "capture".

## 1. Build

```bash
./build.sh          # produces Ghostshot.app and GhostshotLauncher.app
```

## 2. Configure

Everything lives in this folder. The first launch writes `config.json` next to
`Ghostshot.app` (mode 0600) — or copy the template:

```bash
cp config.example.json config.json && chmod 600 config.json
```

Edit it:

```json
{
  "geminiApiKey": "AIza...",
  "geminiApiKeys": ["AIza-second...", "AIza-third..."],
  "ntfyTopic": "ghostshot-<something-random-and-private>",
  "notifyPhone": true,
  "copyToClipboard": true
}
```

- **geminiApiKey / geminiApiKeys** — free from https://aistudio.google.com/apikey.
  Both fields are used: `geminiApiKey` first, then `geminiApiKeys` in order, with
  blanks and repeats dropped. Add a key by appending to the list. Leave them all
  empty and every request goes to Claude instead.
- **ntfyTopic** — any string. It is the *only* secret protecting the topic, so
  make it long and random. Install the ntfy app on your phone and subscribe to
  the same string to receive answers there. Set `notifyPhone: false` to skip.
- Anything you omit falls back to the built-in default, so a partial file is fine.

`config.json` and `state.json` are gitignored, so a real key never reaches git.
Set `GHOSTSHOT_CONFIG_DIR` to keep them somewhere else.

There is no key to set for Claude. That path shells out to the `claude` CLI and
uses whatever login the CLI already has.

## Which provider answers

Keys are tried in order, and the panel's status line names the one that answered
("gemini-2 · turn 3"). When a key reports its daily quota gone, that key alone is
parked until Google's next refill at midnight Pacific and the next key takes over;
`state.json` records which. Only when every key is out does Claude answer, on the
`claude` CLI — your subscription, no API billing.

A per-minute throttle or a rejected key is not sticky: that capture moves down the
list, and the next capture starts from the first key again.

## Sharing it with someone else

Send the source, not the built app. A macOS app bundle that arrives by AirDrop,
zip, or download is quarantined, and this one is signed by a certificate that
exists only in *your* login keychain — on their Mac that signature is worthless.
Building on their machine takes about a minute and avoids all of it.

They need macOS 14 or newer and the Xcode command line tools
(`xcode-select --install`; Swift 6 toolchain, i.e. Xcode 16 / CLT 16 or newer).

```bash
git clone <your repo> ghostshot && cd ghostshot
./setup-signing.sh                 # once: self-signed identity, so TCC grants stick
./build.sh
cp config.example.json config.json && chmod 600 config.json   # their own keys
./run.sh
./install-launcher.sh              # the Right ⌘ ⌘ reopen gesture
```

Then the per-machine bits, none of which can travel with the folder:

- **Accessibility** for *Ghostshot* and for *Ghostshot Launcher*, and **Screen &
  System Audio Recording** for *Ghostshot* (step 3). TCC grants are per Mac and
  per user, always.
- **Their own Gemini keys** in `config.json` — free from
  https://aistudio.google.com/apikey. Yours stay out of it: `config.json` is
  gitignored, so a clone never carries them.
- **The `claude` CLI**, logged in on their account, if they want the fallback
  (`claude` responds → it works). Without it, an exhausted key means no answer.

If you hand over a zip of the folder rather than a clone, delete `config.json`
and `state.json` from it first — a zip carries the files git would have skipped —
and tell them to run `xattr -dr com.apple.quarantine .` plus `./build.sh` before
anything else, so the bundles are rebuilt and signed locally.

[SHARING.md](SHARING.md) is the same thing written for the person receiving it:
requirements, install, the three permission grants, and what each failure means.
Send that one along.

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

The launcher is a separate bundle, so it needs its own **Accessibility** grant —
enable *Ghostshot Launcher* in the same list. Nothing else: it never captures,
never talks to the network, and only ever runs `open Ghostshot.app`.

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

## 4. Install the launcher

Right ⇧ ⇧ ends the process, so something else has to be alive to hear the gesture
that brings it back. `GhostshotLauncher.app` is that something: no UI, no network,
idle until the gesture arrives.

```bash
./install-launcher.sh              # runs it now and at every login
./install-launcher.sh --uninstall  # stops it and removes the login agent
```

It is a launchd agent (`~/Library/LaunchAgents/com.ghostshot.launcher.plist`) with
`KeepAlive`, so it survives a crash and a logout. Errors go to
`/tmp/ghostshot-launcher.log`. To check it without touching the keyboard:

```bash
./GhostshotLauncher.app/Contents/MacOS/GhostshotLauncher --launch-now
```

`./run.sh` restarts the agent on rebuild, so the running launcher is never a
stale binary.

## 5. Verify the stealth property

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

All of it lives in the checkout, next to the app bundles.

| Path | Purpose |
|---|---|
| `config.json` | your settings and keys, mode 0600, gitignored |
| `state.json` | Claude session id, per-key quota dates, panel position |
| `config.example.json` | the template to copy, committed, no keys |
| `Ghostshot.app` | the app itself |
| `GhostshotLauncher.app` | the stub that reopens it after a quit |
| `~/Library/LaunchAgents/com.ghostshot.launcher.plist` | keeps the launcher running |

Delete `state.json` to reset everything.

## Stopping it

Double-tap Right ⇧, or from a terminal:

```bash
pkill -f 'Ghostshot.app/Contents/MacOS/GhostshotApp'
```

That leaves the launcher running, so Right ⌘ ⌘ brings Ghostshot back. To stop
that too:

```bash
./install-launcher.sh --uninstall
```
