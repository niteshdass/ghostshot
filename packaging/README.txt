Ghostshot for macOS (14 Sonoma or newer, Apple Silicon and Intel)

INSTALL
  Open Terminal and run:

    cd ~/Downloads/Ghostshot
    bash install.sh

  Do not double-click Ghostshot.app from this folder. The app is not signed by
  Apple, so macOS will say it "can't be opened" or "is damaged". install.sh
  copies it to ~/Applications and clears that block.

SETUP
  1. Add your Gemini API key (free: https://aistudio.google.com/apikey):
       open -e ~/Library/Application\ Support/Ghostshot/config.json
     Put it in "geminiApiKey". If you are logged in to the `claude` CLI,
     Ghostshot falls back to it when Gemini has no quota left.

  2. System Settings > Privacy & Security, turn on:
       Accessibility                   -> Ghostshot and Ghostshot Launcher
       Screen & System Audio Recording -> Ghostshot
     Then restart it:  open ~/Applications/Ghostshot.app

HOTKEYS (double-tap the RIGHT-side key)
  Right Cmd   Capture the screen and ask
  Right Opt   Show / hide the answer panel
  Right Ctrl  Start a fresh conversation
  Right Shift Quit (Right Cmd twice starts it again)

UPDATE
  Download the new zip and run  bash install.sh  again. Your config is kept.
  macOS may ask for the permissions again after an update.

UNINSTALL
    bash install.sh --uninstall
