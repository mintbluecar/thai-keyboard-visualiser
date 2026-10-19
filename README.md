# ThaiKeyboard

A small macOS menu-bar app that shows a floating on-screen keyboard whenever
the Thai input source is active, so you can see where the Thai letters are
while you type. It lights up each key as you press it. It's a personal
learning aid, built for one Mac — not distributed or notarised.

## Requirements

- The latest Xcode, installed from the App Store (not just the Command Line
  Tools).
- An Apple Development signing certificate for your Apple ID ("Personal
  Team" is fine). Xcode can create one automatically the first time you
  build or run from it.
- If Xcode or `codesign` reports your identity as invalid, you may need to
  install the Apple Worldwide Developer Relations (WWDR) G3 intermediate
  certificate. Download it from Apple's PKI page and double-click it to add
  it to Keychain Access.

## Build

```
scripts/build-app.sh
```

This builds a release binary, signs it with your Apple Development
identity, installs it to `/Applications/ThaiKeyboard.app`, and launches it.
Run it again any time you want to rebuild and relaunch.

## Tests

```
swift test
```

## Granting Input Monitoring

The app needs the Input Monitoring permission to see which key you're
pressing (only to light it up — see below). The first time it launches
without the permission, macOS prompts you; if you miss that, or need to
grant it later, go to **System Settings → Privacy & Security → Input
Monitoring** and turn ThaiKeyboard on. The app keeps working without it,
just without the key-press highlighting, and the menu bar menu tells you
when it's missing.

## Using it

A menu bar icon (ก) appears — no Dock icon. Its menu has:

- **Show/Hide keyboard** — hide it while still typing in Thai; it comes
  back when you switch input sources away from Thai and back.
- **Settings…** — font, opacity, size, hotkeys, start at login.
- **Quit** — the only way to turn the app off entirely.

### Default hotkeys

These work regardless of which app is focused:

- `Ctrl+Option+←/→/↑/↓` — snap the keyboard to that edge's centre.
- `Ctrl+Option+U/I/J/K` — snap to a corner (top-left/top-right/bottom-left/bottom-right).
- `Ctrl+Option+=/−` — bigger / smaller.

All of these can be changed in Settings.

### Settings

Settings lets you change the font used for the Thai characters, the
keyboard's opacity and size, how Caps Lock is shown, each hotkey, and
whether ThaiKeyboard starts automatically at login (on by default — turn it
off in Settings if you don't want that). Settings also shows a
compatibility check: your current input source, whether your keyboard
matches the layout being drawn, whether Input Monitoring is granted, and
what Caps Lock does in the active layout.

## Privacy

ThaiKeyboard watches your key presses only to light up the matching key on
screen. Nothing you type is ever logged, stored, or sent anywhere.
