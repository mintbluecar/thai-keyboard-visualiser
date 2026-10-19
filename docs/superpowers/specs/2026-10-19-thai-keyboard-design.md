# Thai Keyboard Overlay — Design

Date: 2026-10-19
Status: awaiting user approval

## Intent

The user is learning Thai and does not yet know where the Thai letters are on the keyboard. They want a small macOS app that shows an on-screen keyboard whenever the Thai input source is active, so they can glance at it while typing. It is a learning aid: first for finding letters at all, later as support while learning to touch-type. Over time they will need it less.

What makes it useful (and what existing options like macOS's Keyboard Viewer don't do well for them): it appears and disappears automatically with the input source, shows the English key alongside the Thai letter, lights up the key being pressed, and can be restyled (font, opacity, size, position) to suit how they are learning.

## Goals

1. When the active input source becomes Thai, show a floating on-screen keyboard. When it changes to anything else, hide it.
2. Draw a MacBook built-in keyboard (ANSI, the user's physical keyboard) with, on each character key:
   - the Thai character large and centred;
   - the English (US) key letter in the top-left corner, bold and blue (as in the approved mockup — e.g. `#7cc4ff` on a dark key).
3. While Shift is held, every character key shows its Shift character instead, and the Shift keys light up. Shift characters are not shown at any other time.
4. Light up each key while it is physically held down; release returns it to normal.
5. Thai vowel and tone marks (combining characters such as ั ิ ี ึ ื ุ ู ่ ้ ๊ ๋ ็ ์ ํ ฺ, and ำ) display on their own, cleanly — **no dotted-circle placeholder, no tofu boxes, no ghost base letter.** This is a hard requirement; the user rejected every mockup that showed one.
6. The characters shown come from the active macOS Thai input source itself, so the display matches what macOS actually types.
7. User-adjustable, all remembered between launches:
   - **Font** for the Thai characters (any installed font that can render Thai), so the user can practise reading a new typeface;
   - **Opacity** of the whole keyboard window;
   - **Size** — the window can be dragged to resize; the keyboard scales but always keeps its keyboard proportions (no stretching);
   - **Position** — the window can be dragged anywhere.
8. Global hotkeys (work regardless of input source and which app is focused):
   - snap the keyboard to the centre of a screen edge (top, bottom, left, right);
   - snap the keyboard to a screen corner (four corners);
   - make the keyboard bigger / smaller in steps, keeping proportions.
9. A menu bar icon (top-of-screen bar). Its menu includes:
   - Show/Hide keyboard — lets the user hide it while still typing in Thai, and bring it back;
   - Settings… (font, opacity, size, hotkeys, start at login);
   - Quit.
10. **Hiding while in Thai.** The keyboard can be hidden two ways: the menu's Hide keyboard item, or a small **×** close button on the keyboard window itself. Either one hides it only until the input source changes. Switching away from Thai and back shows it again. The hidden state is not saved: if the app launches while Thai is active, the keyboard shows. Choosing Show keyboard from the menu brings it back at any time. Users who don't want it at all can quit the app.
11. **Caps Lock in Thai.** By default the keyboard **hides while Caps Lock changes what the keys type**, and reappears when Caps Lock is turned off (unless the user had hidden it with Hide/×, which still lasts until the input source changes). A Settings toggle (off by default) changes this to **show what Caps Lock types** on each key: the big centre character comes from the layout's Caps Lock state, and the blue corner letter is left off if it would just repeat the centre one. Whether Caps Lock changes anything is read from the layout (see Goal 14), never assumed: if Caps Lock makes no difference in the active layout, the keyboard stays as normal. On the user's Mac today, Caps Lock in the Thai layout types plain English letters q w e a s d… (checked with `UCKeyTranslate`). If the user has macOS's "Use Caps Lock to switch to and from ABC" on, Caps Lock switches input source instead, and the hide-on-non-Thai rule covers it with no special case.
12. No Dock icon.
13. Starts automatically at login (user asked for this; on by default, can be turned off in Settings).
14. **Read the real behaviour, don't assume it** (user's requirement). Everything shown comes from what the user's Mac actually does, not from built-in expectations:
    - Each time the input source changes (and at launch), read the active layout's characters for every key in each state: plain, Shift, Caps Lock, Caps Lock + Shift. Shift and Caps Lock display use exactly these results. A key the layout gives no character for shows blank.
    - Caps Lock and Shift state come from the live modifier flags, not from counting presses.
    - The keyboard shape drawn matches the physical keyboard type macOS reports (ANSI / ISO / JIS). ANSI (the user's MacBook) is required. For ISO or JIS, still draw ANSI but say so in the check below.
    - **Compatibility check** in Settings: one plain-language line for each of these:
      - the active input source and whether it counts as Thai;
      - the keyboard type detected;
      - whether Input Monitoring is granted;
      - what Caps Lock does in this layout (types different characters / no effect).
      
      Items that need the user to act (no permission, keyboard type not matched) also show in the menu bar menu.

## Non-goals

- Typing practice, lessons, drills, scoring.
- Clicking on-screen keys to type.
- Layouts other than what the active Thai input source provides; non-MacBook keyboard shapes (ISO, numpad, external keyboards).
- Distribution to other people (App Store, notarisation). This is for the user's own Mac.

## Anti-goals (would make it a failure even if it "works")

- **Steals focus or interrupts typing.** The keyboard window must never become the key window or take keystrokes from the app the user is typing in.
- **Ugly mark rendering** — dotted circles or boxes on vowel/tone keys (see Goal 5).
- **Records or transmits keystrokes.** The app sees every key press; it may only use them to light up keys. Nothing logged, stored or sent anywhere.
- **Noticeable lag** between pressing a key and it lighting up.
- **Showing on the wrong layout** — e.g. visible while typing English.

## Constraints and environment

- User's machine: MacBook built-in keyboard, macOS 26.1 (Apple silicon).
- Thai input source in use: macOS built-in **"Thai"** keyboard layout (Kedmanee), `KeyboardLayout ID = -26624`. Detection should key off the input source's language being Thai (e.g. `kTISPropertyInputSourceLanguages` contains `th`) rather than this one ID, so "Thai – Pattachote" or another Thai source would also work.
- Toolchain: **latest Xcode and Swift** (user's decision: "let's use the latest software"). The user will install Xcode from the App Store before building; the machine currently has only old Command Line Tools (Swift 5.8, macOS 13 SDK), which are not to be used. Target the current macOS (26) and its SDK; newer APIs are fine.
- Signing: sign with the user's free Apple ID "Personal Team" development certificate in Xcode, so the code signature stays stable across rebuilds and macOS remembers the Input Monitoring permission.
- Reading global key presses requires the **Input Monitoring** permission. The app must handle not having it: still show the keyboard, and show a clear one-line notice (and a menu item) explaining how to grant it.

## Decided with the user

- Native macOS app (user agreed to this default), built with the latest Xcode.
- Key-face design: option "B" from the mockups — large Thai character + blue English letter top-left; Shift characters appear only while Shift is held.
- Visible only when input source is Thai; hidden otherwise.
- Font, opacity, size adjustable; keyboard keeps its shape when resized.
- Hotkeys for snapping to positions and resizing.
- Menu bar icon with show/hide toggle; no Dock icon.
- Hide (menu or × on the window) lasts until the input source changes; switching back to Thai shows it again. Quit is how to turn it off entirely.
- Start at login.
- Caps Lock on in Thai: hide by default; Settings toggle to show what Caps Lock types instead.
- The app reads real behaviour from the Mac (layout, modifiers, keyboard type) rather than assuming it, with a compatibility check the user can see.
- Project lives at `~/developer/personal/embn/thai-keyboard/`.

## Claude's calls (user can override)

- Language: Swift, AppKit for the window and menu bar; SwiftUI is fine for the Settings window if it builds cleanly with the SDK available.
- Character labels come from the live input source via `TISCopyCurrentKeyboardLayoutInputSource` + `UCKeyTranslate` (with and without Shift), per physical key code — not a hardcoded table. Re-read when the input source changes.
- Key presses observed with a listen-only `CGEventTap` (keyDown / keyUp / flagsChanged). Input source changes observed via `kTISNotifySelectedKeyboardInputSourceChanged` (distributed notification).
- Mark rendering: draw the mark's glyph directly from the font (e.g. Core Text `CTFontGetGlyphsForCharacters` + `CTFontDrawGlyphs`), which bypasses text shaping so no dotted circle is inserted; centre it on the key using the glyph's bounding box. Must be verified visually on every mark key with at least two fonts (system Thai font and one other). If a chosen font can't render a character, fall back to the system Thai font rather than show a box.
- Window: borderless, non-activating floating panel (`NSPanel` with `.nonactivatingPanel`), level above normal windows, joins all Spaces and shows over full-screen apps; resizable with fixed aspect ratio; draggable by its background.
- Default hotkeys (changeable in Settings because tools like Rectangle commonly use Ctrl+Option+arrows):
  - Ctrl+Option+← / → / ↑ / ↓ — snap to centre of that edge;
  - Ctrl+Option+U / I / J / K — top-left / top-right / bottom-left / bottom-right corner;
  - Ctrl+Option+= / − — bigger / smaller.
  Registered with Carbon `RegisterEventHotKey` (no extra permission needed).
- Snapping and sizing apply to the screen the keyboard is currently on, inside the visible area (not under the menu bar or Dock), with a small margin.
- Defaults: bottom-centre of the main screen, about 60% of screen width, opacity 90%, system Thai font, start at login on.
- Visual style follows the approved mockup, saved next to this doc as `2026-10-19-thai-keyboard-mockup.html` (open in a browser; ignore how it draws vowel marks — that's the browser problem Goal 5 exists to fix). Proportions at a 58 pt key: Thai character 28 pt, centred, nudged ~8 pt below centre to leave room for the English letter; English letter 14 pt bold, inset 6 pt left / 4 pt top; key corner radius 8; gap between keys 6; panel padding 12 with radius 14. Everything scales with the window.
- Visual style: dark keys on a dark rounded panel; held key turns amber (`#e8a23a`) with dark text; held Shift keys turn blue-violet (`#5a6cff`). Non-character keys (delete, tab, caps, return, shift, space, and the bottom row modifiers) are drawn with small grey English labels and no Thai.
- Option layer is ignored: in the Thai layout it types nothing.
- Settings persisted with `UserDefaults`. Start at login via `SMAppService.mainApp`.
- Menu bar icon: a simple template glyph (e.g. "ก" or a keyboard symbol).

## Left to the builder

- Exact key geometry for the MacBook layout (relative key widths, bottom row including fn/control/option/command and arrow keys).
- Hotkey-editing UI in Settings (a simple recorder field is enough).
- Step size for bigger/smaller hotkeys, minimum and maximum sizes.
- Project structure and tests: unit-test the pure parts (key-code → label mapping given a layout, snap-position maths, aspect-ratio sizing); the rest is verified by running the app.
