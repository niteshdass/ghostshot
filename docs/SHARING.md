# Ghostshot — running it on another Mac

Written for the person receiving it. Ten minutes, most of it macOS asking for
permissions.

## Send the source, not the built app

`Ghostshot.app` does not survive the trip. Anything that arrives by AirDrop, zip,
or download is quarantined, and the bundle is signed by a self-signed certificate
that exists only in the sender's login keychain — on another Mac that signature
means nothing, and macOS treats the app as damaged. A build from source takes
about 70 seconds and sidesteps all of it.

Send a git clone, a repo URL, or a zip of the folder. If it is a zip, the sender
deletes `config.json` and `state.json` from it first: git skips those, a zip does
not, and they hold API keys.

## What the machine needs

| Requirement | Check | Fix |
|---|---|---|
| macOS 14 or newer | `sw_vers -productVersion` | — |
| Swift 6 toolchain (Xcode 16 / CLT 16+) | `swift --version` | `xcode-select --install` |
| A Gemini API key, or the `claude` CLI, or both | `claude -p hi` | https://aistudio.google.com/apikey |

Nothing else. No Homebrew packages, no Xcode project, no signing account.

## Install

```bash
git clone <repo> ghostshot && cd ghostshot

# Came as a zip instead of a clone? Strip the quarantine flag first:
#   xattr -dr com.apple.quarantine .

./setup-signing.sh     # once — self-signed identity, asks for your login password
./build.sh             # Ghostshot.app + GhostshotLauncher.app, ~70 s cold
cp config.example.json config.json && chmod 600 config.json
./run.sh               # starts it; macOS will now ask for permissions
./install-launcher.sh  # the Right ⌘ ⌘ gesture that reopens it after a quit
```

`setup-signing.sh` matters more than it looks. macOS records permission grants
against a *designated requirement*, not an app name. Ad-hoc signing makes every
rebuild look like a brand new app, so Accessibility and Screen Recording quietly
stop applying and the app goes deaf. The self-signed identity makes the grants
stick across rebuilds.

## Put your own keys in `config.json`

```json
{
  "geminiApiKey": "AIza...",
  "geminiApiKeys": ["AIza-second...", "AIza-third..."],
  "geminiModel": "gemini-3.6-flash",
  "ntfyTopic": "",
  "notifyPhone": true,
  "copyToClipboard": true
}
```

Use your own keys, not the sender's. A Gemini key carries a per-project daily
quota, so a shared key means two people draining one allowance — and a key that
gets flagged takes both of you down with it.

Keys are tried in order: `geminiApiKey` first, then `geminiApiKeys`. A key whose
daily quota runs out is parked until Google's refill at midnight Pacific and the
next key takes over. When every key is out, the `claude` CLI answers, on your own
subscription — no API billing, but it must be logged in (`claude -p hi` should
reply). With no keys at all and no CLI, nothing answers.

`config.json` and `state.json` are gitignored, so your keys never reach the repo.

## Grant three permissions

**System Settings > Privacy & Security**:

1. **Accessibility** → *Ghostshot* — to see the modifier taps. The tap is
   listen-only; it cannot swallow, delay, or alter a keystroke.
2. **Accessibility** → *Ghostshot Launcher* — a separate bundle, so a separate
   grant. It retries every 2 s, no relaunch needed.
3. **Screen & System Audio Recording** → *Ghostshot* — to capture.

macOS wants a relaunch after 1 and 3: `./run.sh` again.

These are per Mac and per user. They cannot be copied, exported, or inherited
from the sender's machine — every new machine grants them once.

## Hotkeys

| Gesture | What happens |
|---|---|
| Right ⌘ ⌘ | Capture the screen and ask |
| Right ⌥ ⌥ | Show / hide the answer panel |
| Right ⌃ ⌃ | Start a fresh conversation |
| Right ⇧ ⇧ | Quit Ghostshot |
| Right ⌘ ⌘ (while quit) | Start it again — the launcher answers this one |

Both taps within 300 ms (`doubleTapWindowMs`). Holding a modifier as part of a
real shortcut never triggers it.

## Check it works

```bash
swift test                                      # 69 tests, no network needed
pgrep -fl 'Ghostshot.app/Contents/MacOS/GhostshotApp'   # the app is up
pgrep -fl GhostshotLauncher                     # the launcher is up
tail -3 /tmp/ghostshot-launcher.log             # "listening for Right Command double taps"

# Does the launcher actually open the app, without touching the keyboard?
pkill -f 'Ghostshot.app/Contents/MacOS/GhostshotApp'
./GhostshotLauncher.app/Contents/MacOS/GhostshotLauncher --launch-now
```

Then the real test: double-tap Right ⌘ over a screen with a question on it.

## When something is wrong

| Symptom | Cause |
|---|---|
| Nothing happens on any gesture | Accessibility not granted, or granted before the last rebuild without `setup-signing.sh` |
| Gestures work, quitting works, Right ⌘ ⌘ never reopens it | *Ghostshot Launcher* missing its own Accessibility grant — check `/tmp/ghostshot-launcher.log` |
| Panel says a capture error | Screen & System Audio Recording not granted |
| "This model is no longer available to new users" | Google hides older models from new projects; use `gemini-3.6-flash` or newer in `geminiModel` |
| "Your project has been denied access" (403) | That key's project is blocked. The router skips it automatically; replace the key |
| Every answer comes from Claude | All Gemini keys are exhausted or rejected — `state.json` lists which, under `exhaustedOn` |
| `./build.sh` warns about no identity | `./setup-signing.sh` was skipped; the app still runs, but permissions are lost on every rebuild |

## Removing it

```bash
./install-launcher.sh --uninstall                        # stops the login agent
pkill -f 'Ghostshot.app/Contents/MacOS/GhostshotApp'     # stops the app
rm -rf ghostshot                                         # the whole thing
```

Then delete "Ghostshot Local Signing" in Keychain Access, and switch the two
Ghostshot entries off in Privacy & Security.
