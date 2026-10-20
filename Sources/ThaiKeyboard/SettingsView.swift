import AppKit
import SwiftUI
import ThaiKeyboardCore

/// The Settings window's content: font, opacity, size, Caps Lock,
/// start-at-login, hotkeys and the compatibility check, in that order.
/// Every control applies through `SettingsModel` immediately.
struct SettingsView: View {
    let model: SettingsModel

    var body: some View {
        ScrollView {
            sections
        }
        .frame(width: 460, height: 560)
        .onAppear { model.refresh() }
    }

    /// Every section, top to bottom, without the scrolling container.
    /// `body` puts this in a `ScrollView`; the `--snapshot` debug tool
    /// renders it directly at full height instead, since `ImageRenderer`
    /// (unlike a real, on-screen window) never lays out a `ScrollView`'s
    /// offscreen content.
    var sections: some View {
        VStack(alignment: .leading, spacing: 20) {
            fontSection
            opacitySection
            sizeSection
            capsLockSection
            startAtLoginSection
            hotkeysSection
            compatibilitySection
        }
        .padding(20)
    }

    private var fontSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Font").font(.headline)
            Picker("Family", selection: Binding(
                get: { model.fontFamily },
                set: { model.setFontFamily($0) }
            )) {
                Text("System Thai").tag(String?.none)
                ForEach(model.thaiFamilies, id: \.self) { family in
                    Text(family).tag(String?.some(family))
                }
            }
            .labelsHidden()

            FontSampleView(family: model.fontFamily)
                .frame(height: 44)
        }
    }

    private var opacitySection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Opacity: \(Int(model.opacityPercent))%").font(.headline)
            Slider(
                value: Binding(get: { model.opacityPercent }, set: { model.setOpacityPercent($0) }),
                in: 20...100
            )
        }
    }

    private var sizeSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Size: \(Int(model.sizePercent))% of screen width").font(.headline)
            Slider(
                value: Binding(get: { model.sizePercent }, set: { model.setSizePercent($0) }),
                in: 25...100
            )
        }
    }

    private var capsLockSection: some View {
        Toggle(
            "Show what Caps Lock types instead of hiding",
            isOn: Binding(get: { model.showCapsOutput }, set: { model.setShowCapsOutput($0) })
        )
    }

    private var startAtLoginSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Toggle(
                "Start at login",
                isOn: Binding(get: { model.startAtLogin }, set: { model.setStartAtLogin($0) })
            )
            if let error = model.startAtLoginError {
                Text(error).font(.caption).foregroundStyle(.red)
            }
        }
    }

    private var hotkeysSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Hotkeys").font(.headline)
            ForEach(HotkeyAction.allCases, id: \.self) { action in
                HotkeyRow(action: action, model: model)
            }
            Button("Reset to defaults") { model.resetHotkeysToDefaults() }
        }
    }

    private var compatibilitySection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Compatibility check").font(.headline)
            ForEach(model.compatibilityLines, id: \.self) { line in
                Text(line).font(.system(.body, design: .monospaced))
            }
        }
    }
}

/// The font sample "ก ข ค ั ี ่ ้", drawn through `GlyphDrawing` (as the
/// keyboard itself is) so its marks are clean here too — no dotted circle.
private struct FontSampleView: View {
    var family: String?
    @Environment(\.colorScheme) private var colorScheme

    private static let items = ["ก", "ข", "ค", "ั", "ี", "่", "้"]
    private static let size: CGFloat = 28

    // A SwiftUI Canvas (not an NSView) so ImageRenderer can draw it too.
    // GlyphDrawing works in y-up coordinates; Canvas's are y-down.
    var body: some View {
        Canvas { context, size in
            context.withCGContext { cg in
                cg.translateBy(x: 0, y: size.height)
                cg.scaleBy(x: 1, y: -1)
                cg.setFillColor(colorScheme == .dark ? CGColor(gray: 1, alpha: 1) : CGColor(gray: 0, alpha: 1))
                let resolver = FontResolver(preferredFamily: family)
                let itemWidth = size.width / CGFloat(Self.items.count)
                for (index, item) in Self.items.enumerated() {
                    let rect = CGRect(x: CGFloat(index) * itemWidth, y: 0, width: itemWidth, height: size.height)
                    GlyphDrawing.drawCentred(item, font: resolver.font(for: item, size: Self.size), in: rect, context: cg)
                }
            }
        }
    }
}
