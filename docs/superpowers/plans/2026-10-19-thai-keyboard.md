# Thai Keyboard Overlay Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A menu-bar-only macOS app that shows a floating MacBook keyboard with Thai labels whenever a Thai input source is active, lighting up held keys and switching labels with Shift / Caps Lock.

**Architecture:** One Swift package with two targets. `ThaiKeyboardCore` (library) holds everything that can be tested without a window: key geometry, label tables read from the live layout, the visibility state machine, placement maths, preferences, hotkey bindings, and the compatibility report. `ThaiKeyboard` (executable) holds the AppKit layer: the non-activating panel and its drawing, the event tap, the input-source observer, the menu bar item, hotkeys and the Settings window. A script assembles and signs the `.app` bundle.

**Tech Stack:** Swift 6 (latest Xcode toolchain), AppKit, SwiftUI (Settings window only), Carbon (TIS / `UCKeyTranslate` / `RegisterEventHotKey`), Core Text, CoreGraphics event taps, ServiceManagement (`SMAppService`), XCTest via `swift test`.

**Spec:** `docs/superpowers/specs/2026-10-19-thai-keyboard-design.md` (mockup: `docs/superpowers/specs/2026-10-19-thai-keyboard-mockup.html`)

## Global Constraints

- Built with the latest Xcode toolchain (Swift 6+, macOS 26 SDK). Never with the old Command Line Tools (Swift 5.8 / macOS 13 SDK).
- Deployment target: macOS 26.
- Signed with the user's "Apple Development" (Personal Team) identity, so the Input Monitoring permission survives rebuilds.
- `LSUIElement = true`: no Dock icon.
- Bundle identifier: `local.thaikeyboard.app`. App name: `ThaiKeyboard`. Installed to `/Applications/ThaiKeyboard.app`.
- Thai detection: the input source's `kTISPropertyInputSourceLanguages` contains a language starting with `th`. Never match on one source ID.
- Labels always come from the live layout via `UCKeyTranslate`, never from a hardcoded table (tests may use fakes).
- Keystrokes are never logged, stored or sent. No `print`/`os_log` of key codes or characters in shipped code.
- The keyboard panel must never become key or main window.
- Colours: English corner letter `#7cc4ff`; held key `#e8a23a` with dark text; held Shift `#5a6cff`.
- Proportions at a 58 pt key: Thai character 28 pt, centred, nudged ~8 pt below centre; English letter 14 pt bold, inset 6 pt left / 4 pt top; key corner radius 8; key gap 6; panel padding 12; panel corner radius 14. All scale with the window.
- Defaults: bottom-centre of the main screen, 60% of the visible screen width, opacity 0.9, system Thai font, start at login on, "show what Caps Lock types" off.
- Default hotkeys: Ctrl+Option+←/→/↑/↓ snap to that edge's centre; Ctrl+Option+U/I/J/K snap to top-left/top-right/bottom-left/bottom-right; Ctrl+Option+=/− bigger/smaller.
- Vowel and tone marks are drawn with no dotted circle, no box and no ghost base letter.

## Review Focus

1. **Input source switches, or the panel hides, while a key or Shift is held.** A key lit up from before the switch would stay lit forever. Expected: all pressed-key state clears on every input-source change and every show. Pinned in Task 6 (`test_resetClearsPressedKeys`).
2. **The saved frame is off-screen after a display change** (external monitor unplugged, resolution changed). Expected: the frame is clamped into the visible area at launch and on `NSApplication.didChangeScreenParametersNotification`. Pinned in Task 4 (`test_clampMovesOffscreenFrameIntoVisibleArea`).
3. **The saved font was uninstalled, or can't draw some Thai characters.** Expected: those characters fall back to the system Thai font, and no box is ever drawn. Pinned in Task 5 (`test_resolverFallsBackForMissingFont`, `test_resolverFallsBackForFontWithoutThai`).
4. **Input Monitoring is granted while the app is running.** Expected: keys start lighting up within a few seconds without a relaunch. The app retries creating the tap every 2 s until it succeeds. Pinned in Task 6 (manual verification step).
5. **A default hotkey is already taken by another app** (for example Rectangle owning Ctrl+Option+arrows), so `RegisterEventHotKey` fails. Expected: the Settings hotkey row says "In use by another app — choose another", and the other hotkeys still work. Pinned in Task 8 (`test_reportListsFailedHotkeys`) and the Task 9 Settings UI.

---

## File Structure

```
thai-keyboard/
  Package.swift
  Resources/Info.plist
  scripts/build-app.sh                       # build, bundle, sign, install, (re)launch
  Sources/ThaiKeyboardCore/
    KeyGeometry.swift                         # MacBook ANSI key rects + key kinds
    KeyLabels.swift                           # KeyState, KeyTranslator, LabelTable, display-state rules
    SystemLayout.swift                        # TIS: current source, isThai, UCKeyTranslate translator, keyboard type
    ThaiMarks.swift                           # combining-mark detection
    Visibility.swift                          # visibility state machine
    Placement.swift                           # snap / resize / clamp / default frame maths
    FontResolver.swift                        # pick font per character, fallback to system Thai
    PressedKeys.swift                         # held keys + modifier flags model
    Preferences.swift                         # UserDefaults-backed settings incl. hotkeys and frame
    Hotkeys.swift                             # HotkeyAction, HotkeyBinding, defaults
    Compatibility.swift                       # CompatibilityReport → plain-language lines
  Sources/ThaiKeyboard/
    main.swift                                # NSApplication bootstrap
    AppController.swift                       # wires everything together
    KeyboardPanel.swift                       # non-activating NSPanel, aspect ratio, × button
    KeyboardView.swift                        # draws keys
    GlyphDrawing.swift                        # Core Text drawing, marks via CTFontDrawGlyphs
    KeyEventMonitor.swift                     # listen-only CGEventTap + permission
    InputSourceObserver.swift                 # distributed notification → callback
    StatusMenu.swift                          # NSStatusItem + menu
    HotkeyCenter.swift                        # Carbon RegisterEventHotKey
    SettingsView.swift                        # SwiftUI settings + compatibility check
    LoginItem.swift                           # SMAppService wrapper
  Tests/ThaiKeyboardCoreTests/                # one test file per Core file
```

---

### Task 1: Toolchain, package skeleton, signed menu-bar app

**Files:**
- Create: `Package.swift`, `Resources/Info.plist`, `scripts/build-app.sh`, `Sources/ThaiKeyboard/main.swift`, `Sources/ThaiKeyboard/AppController.swift`, `Sources/ThaiKeyboard/StatusMenu.swift`, `Sources/ThaiKeyboardCore/ThaiMarks.swift`, `Tests/ThaiKeyboardCoreTests/ThaiMarksTests.swift`, `.gitignore` (`.build/`, `.superpowers/`, `*.app`)

**Interfaces:**
- Produces: `ThaiMarks.isCombiningMark(_ s: String) -> Bool`; `final class AppController` (`@MainActor`, owns `StatusMenu`); `final class StatusMenu` with `init(onQuit: @escaping () -> Void)`; `scripts/build-app.sh` (no args) builds release, writes `/Applications/ThaiKeyboard.app`, signs it, and relaunches it.

- [ ] **Step 1: Check the toolchain (user action if any check fails)**

Run: `xcode-select -p && swift --version && security find-identity -p codesigning -v | grep "Apple Development"`
Expected: the path is inside `/Applications/Xcode.app`, Swift 6 or newer, and one "Apple Development" identity.
If the path is wrong, the user runs `! sudo xcode-select -s /Applications/Xcode.app/Contents/Developer`. If there's no identity, the user goes to Xcode → Settings → Accounts, adds their Apple ID, then Manage Certificates → + → Apple Development. Stop until all three checks pass.

- [ ] **Step 2: Write the failing test**

```swift
func test_combiningMarksDetected() {
    for m in ["\u{0E31}", "\u{0E34}", "\u{0E35}", "\u{0E36}", "\u{0E37}", "\u{0E38}", "\u{0E39}", "\u{0E3A}",
              "\u{0E47}", "\u{0E48}", "\u{0E49}", "\u{0E4A}", "\u{0E4B}", "\u{0E4C}", "\u{0E4D}", "\u{0E4E}"] {
        XCTAssertTrue(ThaiMarks.isCombiningMark(m), m)
    }
}
func test_saraAmIsTreatedAsMark() { XCTAssertTrue(ThaiMarks.isCombiningMark("\u{0E33}")) }  // ำ needs a base too
func test_consonantsAndLatinAreNotMarks() {
    for s in ["ก", "ๆ", "ไ", "q", "", "%"] { XCTAssertFalse(ThaiMarks.isCombiningMark(s), s) }
}
```

- [ ] **Step 3: Run `swift test`.** Expected: FAIL (`ThaiMarks` not found).

- [ ] **Step 4: Implement**

- `Package.swift`: tools version 6.0, platform `.macOS("26.0")`, library target `ThaiKeyboardCore`, executable target `ThaiKeyboard` depending on it, test target.
- `ThaiMarks.isCombiningMark`: true when the string is a single scalar in U+0E31, U+0E33–U+0E3A or U+0E47–U+0E4E.
- `main.swift`: `NSApplication.shared`, `.accessory` activation policy, an `AppController` held strongly, `run()`.
- `StatusMenu`: an `NSStatusItem` titled "ก" with a Quit item.
- `Info.plist`: `CFBundleIdentifier local.thaikeyboard.app`, `CFBundleExecutable ThaiKeyboard`, `LSUIElement true`, `LSMinimumSystemVersion 26.0`.
- `build-app.sh` (`set -euo pipefail`):
  - `swift build -c release`;
  - assemble `ThaiKeyboard.app/Contents/{MacOS,Resources,Info.plist}` in `.build/`;
  - `codesign --force --options runtime --sign "Apple Development" ...`;
  - quit any running copy (`pkill -x ThaiKeyboard || true`), `ditto` the bundle to `/Applications/ThaiKeyboard.app`, then `open` it.

- [ ] **Step 5: Verify.** Run `swift test`. Expected: PASS. Run `scripts/build-app.sh && codesign -dv /Applications/ThaiKeyboard.app 2>&1 | grep Authority`. Expected: `Authority=Apple Development: …`, "ก" appears in the menu bar, there's no Dock icon, and Quit works.

- [ ] **Step 6: Commit** — `git add -A && git commit -m "feat: package skeleton and signed menu-bar app"`

---

### Task 2: MacBook ANSI key geometry

**Files:** Create `Sources/ThaiKeyboardCore/KeyGeometry.swift`, `Tests/ThaiKeyboardCoreTests/KeyGeometryTests.swift`

**Interfaces:**
- Produces:
  - `enum KeyKind: Equatable { case character; case modifier(String) }`. The `String` is the small grey label: "delete", "tab", "caps", "return", "shift", "fn", "control", "option", "command", "", "◀", "▲", "▼", "▶".
  - `struct KeySpec: Equatable { let keyCode: UInt16; let rect: CGRect; let kind: KeyKind }`. The rect is in key units: 1.0 = one standard key, y grows downward, and gaps are not included.
  - `enum MacBookANSI { static let keys: [KeySpec]; static let unitSize: CGSize; static var characterKeyCodes: [UInt16] }`.

Rows (top to bottom, widths in units, each row 14.5 wide):
- Row 0: `` ` `` 1–0 - = (13 × 1), delete 1.5.
- Row 1: tab 1.5, Q … \ (13 × 1).
- Row 2: caps 1.75, A … ' (11 × 1), return 1.75.
- Row 3: shift 2.25, Z … / (10 × 1), shift 2.25.
- Row 4: fn 1, control 1, option 1, command 1.25, space 5, command 1.25, option 1, ◀ 1, ▲ over ▼ (1 wide, 0.5 tall each), ▶ 1.

No function row. Key codes use Carbon's `kVK_*` constants: `kVK_ANSI_Q` etc., `kVK_Shift` / `kVK_RightShift`, `kVK_Space`.

- [ ] **Step 1: Write the failing tests**

```swift
func test_has47CharacterKeys() { XCTAssertEqual(MacBookANSI.characterKeyCodes.count, 47) }
func test_characterKeyCodesAreUnique() { XCTAssertEqual(Set(MacBookANSI.characterKeyCodes).count, 47) }
func test_everyRowIs14_5UnitsWide() {
    let rows = Dictionary(grouping: MacBookANSI.keys) { Int($0.rect.minY) }
    for (_, keys) in rows { XCTAssertEqual(keys.map(\.rect.maxX).max()!, 14.5, accuracy: 0.001) }
}
func test_noKeysOverlap() { /* for all pairs, a.rect.intersection(b.rect) has zero area */ }
func test_unitSizeIs14_5by5() { XCTAssertEqual(MacBookANSI.unitSize, CGSize(width: 14.5, height: 5)) }
func test_bothShiftKeysPresent() { XCTAssertNotNil(MacBookANSI.keys.first { $0.keyCode == UInt16(kVK_RightShift) }) }
```

- [ ] **Step 2: Run `swift test --filter KeyGeometryTests`.** Expected: FAIL.
- [ ] **Step 3: Implement `MacBookANSI` per the rows above.**
- [ ] **Step 4: Run `swift test --filter KeyGeometryTests`.** Expected: PASS.
- [ ] **Step 5: Commit** — `feat: MacBook ANSI key geometry`

---

### Task 3: Label table read from the live layout, plus keyboard type

**Files:** Create `Sources/ThaiKeyboardCore/KeyLabels.swift`, `Sources/ThaiKeyboardCore/SystemLayout.swift`, `Tests/ThaiKeyboardCoreTests/KeyLabelsTests.swift`, `Tests/ThaiKeyboardCoreTests/SystemLayoutTests.swift`

**Interfaces:**
- Consumes: `MacBookANSI.characterKeyCodes`
- Produces:
  - `enum KeyState: CaseIterable { case plain, shift, caps, capsShift }`
  - `protocol KeyTranslator { func characters(keyCode: UInt16, state: KeyState) -> String }`
  - `struct LabelTable`:
    - `init(translator: KeyTranslator, keyCodes: [UInt16])`
    - `func label(_ keyCode: UInt16, _ state: KeyState) -> String` (blank `""` when the layout gives nothing or only control characters)
    - `var capsChangesOutput: Bool` (true when any key's `.caps` label differs from `.plain`)
  - `enum DisplayMode: Equatable { case thai(KeyState), capsOutput(KeyState), hiddenForCaps }`
  - `func displayMode(shift: Bool, capsLock: Bool, capsChangesOutput: Bool, showCapsOutput: Bool) -> DisplayMode`
  - `struct InputSourceInfo { let id: String; let name: String; let isThai: Bool }`
  - `enum KeyboardType: Equatable { case ansi, iso, jis, unknown }`
  - `enum SystemLayout`:
    - `static func current() -> InputSourceInfo`
    - `static func translator(forSourceID: String) -> KeyTranslator?`
    - `static func currentTranslator() -> KeyTranslator?`
    - `static func keyboardType() -> KeyboardType`
    - `static func isThai(languages: [String]) -> Bool`

- [ ] **Step 1: Write failing tests (a fake translator for the rules, the real layout for the system)**

```swift
// KeyLabelsTests
struct Fake: KeyTranslator { let map: [UInt16: [KeyState: String]]
    func characters(keyCode: UInt16, state: KeyState) -> String { map[keyCode]?[state] ?? "" } }
func test_labelsComeFromTranslator() {
    let t = LabelTable(translator: Fake(map: [12: [.plain: "ๆ", .shift: "๐", .caps: "q", .capsShift: "Q"]]), keyCodes: [12])
    XCTAssertEqual(t.label(12, .plain), "ๆ"); XCTAssertEqual(t.label(12, .shift), "๐"); XCTAssertEqual(t.label(12, .caps), "q")
}
func test_controlCharactersBecomeBlank() { /* translator returns "\u{10}" → label is "" */ }
func test_capsChangesOutputFalseWhenCapsMatchesPlain() { /* .caps == .plain for all keys → false */ }
func test_displayModePlainAndShift() {
    XCTAssertEqual(displayMode(shift: false, capsLock: false, capsChangesOutput: true, showCapsOutput: false), .thai(.plain))
    XCTAssertEqual(displayMode(shift: true,  capsLock: false, capsChangesOutput: true, showCapsOutput: false), .thai(.shift))
}
func test_capsHidesByDefaultWhenItChangesOutput() {
    XCTAssertEqual(displayMode(shift: false, capsLock: true, capsChangesOutput: true, showCapsOutput: false), .hiddenForCaps)
}
func test_capsShowsOutputWhenToggleOn() {
    XCTAssertEqual(displayMode(shift: true, capsLock: true, capsChangesOutput: true, showCapsOutput: true), .capsOutput(.capsShift))
}
func test_capsIgnoredWhenItChangesNothing() {
    XCTAssertEqual(displayMode(shift: false, capsLock: true, capsChangesOutput: false, showCapsOutput: false), .thai(.plain))
}
// SystemLayoutTests
func test_isThai() { XCTAssertTrue(SystemLayout.isThai(languages: ["th"])); XCTAssertTrue(SystemLayout.isThai(languages: ["th-TH"]))
                     XCTAssertFalse(SystemLayout.isThai(languages: ["en", "zh-Hans"])) }
func test_realThaiLayoutMatchesUsersMac() throws {
    let t = try XCTUnwrap(SystemLayout.translator(forSourceID: "com.apple.keylayout.Thai"), "Thai layout not installed")
    XCTAssertEqual(t.characters(keyCode: UInt16(kVK_ANSI_Q), state: .plain), "ๆ")
    XCTAssertEqual(t.characters(keyCode: UInt16(kVK_ANSI_Q), state: .shift), "๐")
    XCTAssertEqual(t.characters(keyCode: UInt16(kVK_ANSI_Q), state: .caps), "q")
    XCTAssertEqual(t.characters(keyCode: UInt16(kVK_ANSI_Y), state: .plain), "\u{0E31}")
}
```

- [ ] **Step 2: Run `swift test --filter "KeyLabelsTests|SystemLayoutTests"`.** Expected: FAIL.
- [ ] **Step 3: Implement.**
  - The translator wraps `kTISPropertyUnicodeKeyLayoutData` and calls `UCKeyTranslate` with `kUCKeyActionDisplay` and `kUCKeyTranslateNoDeadKeysBit`. Modifier bytes are `(shiftKey | alphaLock) >> 8` per state, and keyboard type is `LMGetKbdType()`.
  - `keyboardType()` maps `KBGetLayoutType(LMGetKbdType())` (`kKeyboardANSI` / `kKeyboardISO` / `kKeyboardJIS`).
  - `isThai` checks whether any language `hasPrefix("th")`.
- [ ] **Step 4: Run the same filter.** Expected: PASS.
- [ ] **Step 5: Commit** — `feat: label table from live layout, display-mode rules`

---

### Task 4: Visibility state machine and placement maths

**Files:** Create `Sources/ThaiKeyboardCore/Visibility.swift`, `Sources/ThaiKeyboardCore/Placement.swift`, and tests for each.

**Interfaces:**
- Produces:
  - `struct Visibility`:
    - `init(isThai: Bool)`
    - `mutating func inputSourceChanged(isThai: Bool)`
    - `mutating func userHide()`
    - `mutating func userShow()`
    - `var userHidden: Bool`
    - `func isVisible(hiddenForCaps: Bool) -> Bool`
  - `enum SnapTarget: CaseIterable { case top, bottom, left, right, topLeft, topRight, bottomLeft, bottomRight }`
  - `enum Placement`:
    - `static let margin: CGFloat = 12`
    - `static func defaultFrame(visible: CGRect, aspect: CGFloat) -> CGRect` (60% of `visible.width`, bottom-centre)
    - `static func snapped(_ frame: CGRect, to: SnapTarget, in visible: CGRect) -> CGRect`
    - `static func resized(_ frame: CGRect, step: Int, aspect: CGFloat, in visible: CGRect) -> CGRect`. Each step changes the width by ±10%, keeping the centre. Width is clamped to `[360, visible.width - 2*margin]` and the result is then clamped into `visible`.
    - `static func clamped(_ frame: CGRect, in visible: CGRect) -> CGRect`

`aspect` is width/height and always comes from the panel's content: `MacBookANSI.unitSize` plus gaps and padding, computed in Task 5 and passed in.

- [ ] **Step 1: Write the failing tests**

```swift
func test_hiddenWhenNotThai() { XCTAssertFalse(Visibility(isThai: false).isVisible(hiddenForCaps: false)) }
func test_userHideLastsUntilSourceChanges() {
    var v = Visibility(isThai: true); v.userHide(); XCTAssertFalse(v.isVisible(hiddenForCaps: false))
    v.inputSourceChanged(isThai: false); v.inputSourceChanged(isThai: true); XCTAssertTrue(v.isVisible(hiddenForCaps: false))
}
func test_switchingBetweenTwoThaiSourcesAlsoClearsHide() {
    var v = Visibility(isThai: true); v.userHide(); v.inputSourceChanged(isThai: true); XCTAssertTrue(v.isVisible(hiddenForCaps: false))
}
func test_userShowOverridesHide() { var v = Visibility(isThai: true); v.userHide(); v.userShow(); XCTAssertTrue(v.isVisible(hiddenForCaps: false)) }
func test_capsHidesButUserHideStillWinsAfterCapsOff() {
    var v = Visibility(isThai: true); XCTAssertFalse(v.isVisible(hiddenForCaps: true))
    v.userHide(); XCTAssertFalse(v.isVisible(hiddenForCaps: false))
}
func test_newLaunchInThaiIsVisible() { XCTAssertTrue(Visibility(isThai: true).isVisible(hiddenForCaps: false)) }
func test_defaultFrameIs60PercentBottomCentre() {
    let vis = CGRect(x: 0, y: 0, width: 1000, height: 800)
    let f = Placement.defaultFrame(visible: vis, aspect: 3)
    XCTAssertEqual(f.width, 600, accuracy: 0.5); XCTAssertEqual(f.midX, 500, accuracy: 0.5); XCTAssertEqual(f.minY, 12, accuracy: 0.5)
}
func test_snapCorners() { /* topRight: maxX == vis.maxX-12, maxY == vis.maxY-12; same for each SnapTarget */ }
func test_resizeKeepsAspectAndCentre() { /* step +1: width ×1.1, height == width/aspect, centre unchanged */ }
func test_resizeClampsToMinAndScreen() { /* many -1 steps → width 360; many +1 → width vis.width-24 */ }
func test_clampMovesOffscreenFrameIntoVisibleArea() {
    let vis = CGRect(x: 0, y: 0, width: 1000, height: 800)
    let f = Placement.clamped(CGRect(x: 2500, y: -400, width: 600, height: 200), in: vis)
    XCTAssertTrue(vis.contains(f))
}
```

(Snap and resize use AppKit coordinates: the origin is bottom-left, and `visible` is `NSScreen.visibleFrame`.)

- [ ] **Step 2: Run `swift test --filter "VisibilityTests|PlacementTests"`.** Expected: FAIL.
- [ ] **Step 3: Implement both types.**
- [ ] **Step 4: Run the same filter.** Expected: PASS.
- [ ] **Step 5: Commit** — `feat: visibility rules and placement maths`

---

### Task 5: Keyboard panel and key drawing (static preview)

**Files:**
- Create: `Sources/ThaiKeyboardCore/FontResolver.swift`, `Tests/ThaiKeyboardCoreTests/FontResolverTests.swift`, `Sources/ThaiKeyboard/KeyboardPanel.swift`, `Sources/ThaiKeyboard/KeyboardView.swift`, `Sources/ThaiKeyboard/GlyphDrawing.swift`
- Modify: `Sources/ThaiKeyboard/AppController.swift`

**Interfaces:**
- Consumes: `MacBookANSI`, `LabelTable`, `DisplayMode`, `ThaiMarks`, `SystemLayout.currentTranslator()`, `Placement.defaultFrame`
- Produces:
  - `struct FontResolver`:
    - `init(preferredFamily: String?)`
    - `func font(for text: String, size: CGFloat) -> CTFont`. Uses the preferred family if it has glyphs for every scalar in `text`, otherwise the system Thai font.
    - `static func systemThaiFont(size: CGFloat) -> CTFont`. Built with `CTFontCreateForString` from the system UI font, using "ก".
    - `static func thaiCapableFamilies() -> [String]`. Families whose character set contains U+0E01.
  - `final class KeyboardPanel: NSPanel`:
    - `init(onClose: @escaping () -> Void)`
    - `canBecomeKey` and `canBecomeMain` both false
    - `static var aspect: CGFloat`
  - `final class KeyboardView: NSView`, with:
    - `var labels: LabelTable?`
    - `var mode: DisplayMode`
    - `var pressed: Set<UInt16>`
    - `var shiftHeld: Bool`
    - `var fontFamily: String?`

  Each property setter calls `needsDisplay = true`.

- [ ] **Step 1: Write the failing font tests**

```swift
func test_resolverUsesPreferredFamilyWhenItHasThai() {
    let f = FontResolver(preferredFamily: "Thonburi").font(for: "ก", size: 20)
    XCTAssertEqual(CTFontCopyFamilyName(f) as String, "Thonburi")
}
func test_resolverFallsBackForMissingFont() {
    let f = FontResolver(preferredFamily: "No Such Font 123").font(for: "ก", size: 20)
    XCTAssertEqual(CTFontCopyFamilyName(f) as String, CTFontCopyFamilyName(FontResolver.systemThaiFont(size: 20)) as String)
}
func test_resolverFallsBackForFontWithoutThai() {
    let f = FontResolver(preferredFamily: "Courier").font(for: "\u{0E31}", size: 20)
    XCTAssertNotEqual(CTFontCopyFamilyName(f) as String, "Courier")
}
func test_thaiCapableFamiliesIncludeThonburiExcludeCourier() { /* contains "Thonburi", not "Courier" */ }
```

- [ ] **Step 2: Run `swift test --filter FontResolverTests`.** Expected: FAIL. **Step 3:** implement `FontResolver`. **Step 4:** run again. Expected: PASS.

- [ ] **Step 5: Implement the panel and view**
  - Panel:
    - style `[.borderless, .nonactivatingPanel, .resizable]`
    - `level = .floating`
    - `collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]`
    - `isMovableByWindowBackground = true`, `hidesOnDeactivate = false`, `backgroundColor = .clear`
    - `contentAspectRatio` from `aspect`
    - a small × button in the top-right corner of the panel padding calls `onClose`
  - View: scale = `bounds.width / (unitSize.width × 58 + 13.5 × 6 + 2 × 12)`, so the Global Constraints proportions apply at scale 1. Draw the panel background, then each key (rect, gap, radius from Global Constraints) in this order:
    - **Fill:** amber if the key is in `pressed`; blue-violet for Shift keys when `shiftHeld`; dark otherwise.
    - **Centre text:** the label for the current mode (`.thai(s)` or `.capsOutput(s)`).
    - **Blue corner letter:** the US letter (uppercase for letters, the plain symbol otherwise, from a fixed US table, since it names the physical key). It is omitted in `.capsOutput` when it equals the centre text, case-insensitively.
    - **Modifier keys:** the grey `KeyKind.modifier` label.
  - `GlyphDrawing.drawCentred(_ text: String, font: CTFont, in rect: CGRect, context: CGContext)`:
    - When `ThaiMarks.isCombiningMark(text)`, get the glyph with `CTFontGetGlyphsForCharacters`, measure it with `CTFontGetBoundingRectsForGlyphs`, centre the glyph's bounding box in `rect`, and draw it with `CTFontDrawGlyphs`. This bypasses shaping, so there's no dotted circle.
    - Otherwise draw a `CTLine` centred on its typographic bounds.
  - Temporary wiring: `AppController` shows the panel at `Placement.defaultFrame` with `LabelTable` built from `SystemLayout.translator(forSourceID: "com.apple.keylayout.Thai")`, mode `.thai(.plain)`. Add a launch argument `--preview-mode shift|caps` so the other label sets can be screenshotted.

- [ ] **Step 6: Visual verification (required; the user rejected every mark rendering until now)**

Run: `scripts/build-app.sh`, then `screencapture -x /tmp/kb-plain.png`. Repeat with `--preview-mode shift`.
Repeat both with the font family temporarily set to a second Thai font (for example "Sukhumvit Set").
Expected in all four screenshots:
- Each mark appears alone and centred: Y ั, U ี, H ้, J ่, B ิ, N ื, 6 ุ, 7 ึ, E ำ, plus the Shift marks ํ ๊ ็ ๋ ฺ ์ ู.
- No dotted circle, box or ghost letter anywhere.
- The blue corner letter sits top-left, and the proportions match the mockup.

Attach the screenshots to the task report.

- [ ] **Step 7: Verify the panel never takes focus.** With TextEdit focused, click the panel and drag it, then type. Expected: the text still goes into TextEdit, and TextEdit's title bar stays active.

- [ ] **Step 8: Commit** — `feat: keyboard panel and glyph drawing`

---

### Task 6: Live key presses, input-source changes, visibility, menu

**Files:**
- Create: `Sources/ThaiKeyboardCore/PressedKeys.swift`, `Tests/ThaiKeyboardCoreTests/PressedKeysTests.swift`, `Sources/ThaiKeyboard/KeyEventMonitor.swift`, `Sources/ThaiKeyboard/InputSourceObserver.swift`
- Modify: `AppController.swift`, `StatusMenu.swift`

**Interfaces:**
- Consumes: `Visibility`, `displayMode`, `LabelTable`, `SystemLayout`, `KeyboardPanel` / `KeyboardView`
- Produces:
  - `struct PressedKeys`:
    - `mutating func keyDown(_ code: UInt16)`
    - `mutating func keyUp(_ code: UInt16)`
    - `mutating func flagsChanged(shift: Bool, capsLock: Bool)`
    - `mutating func reset()`
    - read-only `keys: Set<UInt16>`, `shift: Bool`, `capsLock: Bool`
  - `final class KeyEventMonitor`:
    - `init(onEvent: @escaping @MainActor (KeyEvent) -> Void)`
    - `func start()` (retries every 2 s until the tap is created)
    - `var hasPermission: Bool`
    - `enum KeyEvent { case down(UInt16), up(UInt16), flags(shift: Bool, capsLock: Bool) }`
  - `final class InputSourceObserver`, with `init(onChange: @escaping @MainActor () -> Void)`
  - `StatusMenu` gains:
    - `func update(isShown: Bool, actionItems: [String])`
    - callbacks `onToggleShow`, `onSettings`, `onQuit`
    - the Show/Hide title reflects the current state
    - action items appear as disabled lines above Settings

- [ ] **Step 1: Write failing tests**

```swift
func test_downUpTracksKeys() { var p = PressedKeys(); p.keyDown(12); XCTAssertEqual(p.keys, [12]); p.keyUp(12); XCTAssertEqual(p.keys, []) }
func test_flagsFromEventNotCounting() { var p = PressedKeys(); p.flagsChanged(shift: true, capsLock: false); p.flagsChanged(shift: true, capsLock: false); XCTAssertTrue(p.shift) }
func test_resetClearsPressedKeys() { var p = PressedKeys(); p.keyDown(12); p.flagsChanged(shift: true, capsLock: true); p.reset(); XCTAssertEqual(p.keys, []); XCTAssertFalse(p.shift) }
func test_resetKeepsCapsLockSinceItIsALatchedState() { /* after reset, capsLock unchanged */ }
```

(Caps Lock is a latched state: `reset()` clears held keys and Shift only. The next flags event resyncs Caps Lock anyway.)

- [ ] **Step 2: Run `swift test --filter PressedKeysTests`.** Expected: FAIL. **Step 3:** implement. **Step 4:** run again. Expected: PASS.

- [ ] **Step 5: Implement the monitors and wiring**
  - Event tap: `CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .listenOnly, eventsOfInterest: keyDown|keyUp|flagsChanged)`. Read the key code with `.keyboardEventKeycode`. Shift comes from `.maskShift`, Caps Lock from `.maskAlphaShift`.
    - On `.tapDisabledByTimeout` or `.tapDisabledByUserInput`, re-enable the tap.
    - Ignore auto-repeat (`.keyboardEventAutorepeat`), since it doesn't change state.
    - Permission: check with `CGPreflightListenEventAccess`, and call `CGRequestListenEventAccess` once on first launch.
  - Input source: observe `kTISNotifySelectedKeyboardInputSourceChanged` on `DistributedNotificationCenter`.
  - `AppController` on a source change:
    - rebuild `LabelTable` from `SystemLayout.currentTranslator()`;
    - call `visibility.inputSourceChanged(isThai:)` and `pressed.reset()`;
    - recompute.
  - Recompute:
    - `mode = displayMode(...)`;
    - show the panel with `orderFrontRegardless` if `visibility.isVisible(hiddenForCaps: mode == .hiddenForCaps)`, otherwise `orderOut`;
    - update the menu.

  The × button and the menu's Hide call `visibility.userHide()`; Show calls `userShow()`. Without permission, the menu shows "Allow key presses: System Settings → Privacy & Security → Input Monitoring" (clicking it opens that pane via `x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent`).

- [ ] **Step 6: Manual verification** (build with `scripts/build-app.sh` and grant Input Monitoring when asked). Expected:
  1. Switching to Thai shows the keyboard, and switching to ABC hides it.
  2. Held keys light amber with no visible lag, and go back on release.
  3. Holding Shift swaps the labels and lights both Shift keys.
  4. Caps Lock on (default setting) hides the keyboard, and Caps Lock off shows it again.
  5. × hides it. Switching to ABC and back to Thai shows it again.
  6. Menu Hide/Show works and its title is correct.
  7. Revoke Input Monitoring, then grant it while the app runs. Keys light up again within about 2 s, with no relaunch.
  8. Hold a key, switch input source with the Globe key, and release. No key stays lit.

- [ ] **Step 7: Commit** — `feat: live key highlighting, input-source visibility, menu`

---

### Task 7: Preferences and start at login

**Files:** Create `Sources/ThaiKeyboardCore/Preferences.swift`, `Sources/ThaiKeyboardCore/Hotkeys.swift`, `Tests/ThaiKeyboardCoreTests/PreferencesTests.swift`, `Sources/ThaiKeyboard/LoginItem.swift`; Modify `AppController.swift`

**Interfaces:**
- Produces:
  - `enum HotkeyAction: String, CaseIterable, Codable { case snapTop, snapBottom, snapLeft, snapRight, snapTopLeft, snapTopRight, snapBottomLeft, snapBottomRight, bigger, smaller }`
  - `struct HotkeyBinding: Codable, Equatable { var keyCode: UInt32; var carbonModifiers: UInt32 }`
  - `enum Hotkeys { static let defaults: [HotkeyAction: HotkeyBinding] }`. The values are the default hotkeys in Global Constraints, built from `controlKey | optionKey` and the keys `kVK_LeftArrow`, `kVK_RightArrow`, `kVK_UpArrow`, `kVK_DownArrow`, `kVK_ANSI_U`, `kVK_ANSI_I`, `kVK_ANSI_J`, `kVK_ANSI_K`, `kVK_ANSI_Equal` and `kVK_ANSI_Minus`.
  - `final class Preferences`:
    - `init(defaults: UserDefaults = .standard)`
    - properties:
      - `fontFamily: String?` (nil = system Thai)
      - `opacity: Double` (default 0.9, clamped to 0.2…1.0)
      - `frame: CGRect?`
      - `showCapsOutput: Bool` (default false)
      - `startAtLogin: Bool` (default true)
      - `hotkeys: [HotkeyAction: HotkeyBinding]` (default `Hotkeys.defaults`)
    - every property persists on set
  - `enum LoginItem { static func apply(_ on: Bool) throws; static var isEnabled: Bool }` (`SMAppService.mainApp`)

- [ ] **Step 1: Write failing tests** using a fresh `UserDefaults(suiteName: UUID().uuidString)!`:

```swift
func test_defaults() { let p = Preferences(defaults: d)
    XCTAssertNil(p.fontFamily); XCTAssertEqual(p.opacity, 0.9); XCTAssertNil(p.frame)
    XCTAssertFalse(p.showCapsOutput); XCTAssertTrue(p.startAtLogin); XCTAssertEqual(p.hotkeys, Hotkeys.defaults) }
func test_roundTrip() { /* set every property, new Preferences(defaults: d) reads same values */ }
func test_opacityClamped() { p.opacity = 0.0; XCTAssertEqual(p.opacity, 0.2); p.opacity = 3; XCTAssertEqual(p.opacity, 1.0) }
func test_defaultHotkeysCoverEveryActionOnce() { XCTAssertEqual(Set(Hotkeys.defaults.keys), Set(HotkeyAction.allCases)) }
```

- [ ] **Step 2: Run `swift test --filter PreferencesTests`.** Expected: FAIL. **Step 3:** implement. **Step 4:** run again. Expected: PASS.
- [ ] **Step 5: Wire it into `AppController`.**
  - Apply `opacity` (as `alphaValue`) and `fontFamily` at launch.
  - Save `frame` on `windowDidMove` / `windowDidResize`.
  - At launch and on `NSApplication.didChangeScreenParametersNotification`, restore the frame through `Placement.clamped`, falling back to `defaultFrame`.
  - On first launch, call `LoginItem.apply(prefs.startAtLogin)`.
- [ ] **Step 6: Manual verification.** Move and resize the keyboard, quit, and relaunch: it comes back where you left it. System Settings → General → Login Items lists ThaiKeyboard.
- [ ] **Step 7: Commit** — `feat: preferences persistence and start at login`

---

### Task 8: Global hotkeys and the compatibility report

**Files:** Create `Sources/ThaiKeyboard/HotkeyCenter.swift`, `Sources/ThaiKeyboardCore/Compatibility.swift`, `Tests/ThaiKeyboardCoreTests/CompatibilityTests.swift`; Modify `AppController.swift`, `StatusMenu.swift`

**Interfaces:**
- Consumes: `Preferences.hotkeys`, `HotkeyAction`, `Placement.snapped` / `resized`, `SystemLayout`, `LabelTable.capsChangesOutput`, `KeyEventMonitor.hasPermission`
- Produces:
  - `final class HotkeyCenter`:
    - `init(onAction: @escaping @MainActor (HotkeyAction) -> Void)`
    - `func register(_ bindings: [HotkeyAction: HotkeyBinding]) -> Set<HotkeyAction>` (returns the actions that failed to register; unregisters the previous set first)
  - `struct CompatibilityReport`:
    - fields `inputSource: InputSourceInfo`, `keyboardType: KeyboardType`, `inputMonitoring: Bool`, `capsChangesOutput: Bool`, `failedHotkeys: Set<HotkeyAction>`
    - `var lines: [String]`
    - `var actionItems: [String]`

Exact copy for `lines`, in order:
1. `"Input source: \(name) — counts as Thai"` or `"Input source: \(name) — not Thai, keyboard hidden"`
2. `"Keyboard: MacBook (ANSI) — matches"` or `"Keyboard: \(ISO|JIS|unknown) — drawn as MacBook ANSI, may not match your keys"`
3. `"Key presses: allowed"` or `"Key presses: not allowed — grant Input Monitoring in System Settings"`
4. `"Caps Lock: types different characters in this layout"` or `"Caps Lock: no effect in this layout"`
5. Only when some hotkeys failed: `"Hotkeys in use by another app: \(comma-separated action titles)"`

`actionItems` holds lines 2, 3 and 5, and only when each one needs the user to act (not ANSI, permission missing, a hotkey failed).

- [ ] **Step 1: Write failing tests**

```swift
func test_allGoodHasNoActionItems() { /* thai, .ansi, true, true, [] → 4 lines, actionItems empty, line[3] == "Caps Lock: types different characters in this layout" */ }
func test_missingPermissionIsActionItem() { /* inputMonitoring false → actionItems == ["Key presses: not allowed — grant Input Monitoring in System Settings"] */ }
func test_isoKeyboardIsActionItem() { /* .iso → actionItems contains "Keyboard: ISO — drawn as MacBook ANSI, may not match your keys" */ }
func test_reportListsFailedHotkeys() { /* failedHotkeys [.snapLeft] → 5 lines, last starts "Hotkeys in use by another app:", also in actionItems */ }
func test_notThaiLine() { /* isThai false → line[0] ends "— not Thai, keyboard hidden" */ }
```

- [ ] **Step 2: Run `swift test --filter CompatibilityTests`.** Expected: FAIL. **Step 3:** implement. **Step 4:** run again. Expected: PASS.
- [ ] **Step 5: Implement `HotkeyCenter` and wire it in.**
  - `HotkeyCenter` uses `InstallEventHandler` on `GetApplicationEventTarget()` for `kEventHotKeyPressed`, plus `RegisterEventHotKey` per binding. A failure status adds that action to the returned set.
  - Snap actions call `Placement.snapped`; bigger/smaller call `Placement.resized(step: ±1)`. Both act on the panel's current screen `visibleFrame` and save the frame.
  - `StatusMenu` action items come from `report.actionItems`.
- [ ] **Step 6: Manual verification.** Each default hotkey moves or resizes the keyboard on the screen it's on, works with both ABC and Thai active, and never pushes the keyboard under the menu bar or Dock. If Rectangle (or a test app) holds Ctrl+Option+←, the menu shows the "Hotkeys in use…" line.
- [ ] **Step 7: Commit** — `feat: global hotkeys and compatibility report`

---

### Task 9: Settings window

**Files:** Create `Sources/ThaiKeyboard/SettingsView.swift`; Modify `AppController.swift`, `StatusMenu.swift`

**Interfaces:**
- Consumes: `Preferences`, `FontResolver.thaiCapableFamilies()`, `CompatibilityReport`, `HotkeyCenter.register`, `LoginItem`, `HotkeyAction`
- Produces: `func showSettings()` on `AppController`. It opens one `NSWindow` hosting `SettingsView` and activates the app while that window is open. This is the only window allowed focus.

Sections, top to bottom:
1. **Font:** a picker of `thaiCapableFamilies()` plus "System Thai", with a live sample "ก ข ค ั ี ่ ้" drawn through `GlyphDrawing` (so the marks are clean here too).
2. **Opacity:** a slider from 20 to 100%.
3. **Size:** a slider for width as % of screen, which calls the same resize path.
4. **Caps Lock:** a toggle, "Show what Caps Lock types instead of hiding".
5. **Start at login:** a toggle that calls `LoginItem.apply` and shows the error inline if it throws.
6. **Hotkeys:** one row per `HotkeyAction`, each with a recorder that captures the next key + modifiers via a local `NSEvent` monitor (at least one of ⌃⌥⌘ is required), a "Reset to defaults" button, and failed rows marked "In use by another app — choose another".
7. **Compatibility check:** `report.lines` as plain text, refreshed when the window opens and when the input source changes.

Every change applies immediately and persists through `Preferences`.

- [ ] **Step 1: Implement `SettingsView` and wire Settings… in the menu.**
- [ ] **Step 2: Manual verification.**
  - Changing the font redraws the keyboard instantly and survives a relaunch.
  - Choose a decorative Thai font: any characters it lacks fall back, and no boxes appear.
  - The opacity and size sliders work.
  - The Caps Lock toggle switches between hiding and showing q w e…
  - Rebinding a hotkey works at once, and Reset restores the defaults.
  - The compatibility lines match reality (revoke Input Monitoring to see line 3 change).
- [ ] **Step 3: Commit** — `feat: settings window`

---

### Task 10: End-to-end check against the spec

**Files:** Create `README.md`: build steps, the permission note, how to quit, and that keystrokes are never stored.

- [ ] **Step 1: Run `swift test`.** Expected: all pass.
- [ ] **Step 2: Run `scripts/build-app.sh`, then walk through spec Goals 1–14 and every anti-goal on the real Mac, ticking each one in the task report.** Include the four mark screenshots from Task 5 retaken on the final build.
- [ ] **Step 3: Confirm no keystroke logging.** Run `grep -rnE "print\(|os_log|Logger\(" Sources/`. Expected: no hits that involve key codes or characters.
- [ ] **Step 4: Rebuild, then relaunch.** Expected: macOS does not ask for Input Monitoring again, which confirms the signature is stable.
- [ ] **Step 5: Commit** — `docs: README; verified against spec`
