import AppKit
import SwiftUI

/// Chivvy's design tokens: native materials and system grays, with brand orange as the only accent
enum Theme {
    static let brand = Color(red: 1, green: 138 / 255, blue: 31 / 255)
    /// Text and icons sitting on brand orange (white fails contrast there)
    static let onBrand = Color(red: 26 / 255, green: 13 / 255, blue: 0)
    /// Orange that stays readable as text on the window background
    static let brandText = dynamic(light: NSColor(red: 184 / 255, green: 84 / 255, blue: 0, alpha: 1),
                                   dark: NSColor(red: 1, green: 165 / 255, blue: 82 / 255, alpha: 1))
    static let brandSoft = dynamic(light: NSColor(red: 1, green: 138 / 255, blue: 31 / 255, alpha: 0.14),
                                   dark: NSColor(red: 1, green: 138 / 255, blue: 31 / 255, alpha: 0.20))
    static let success = dynamic(light: NSColor(red: 36 / 255, green: 138 / 255, blue: 61 / 255, alpha: 1),
                                 dark: NSColor(red: 50 / 255, green: 215 / 255, blue: 75 / 255, alpha: 1))
    static let danger = dynamic(light: NSColor(red: 215 / 255, green: 0, blue: 21 / 255, alpha: 1),
                                dark: NSColor(red: 1, green: 69 / 255, blue: 58 / 255, alpha: 1))

    /// Subtle fills over any background
    static let fill = dynamic(light: NSColor(white: 0, alpha: 0.05), dark: NSColor(white: 1, alpha: 0.06))
    static let fillStrong = dynamic(light: NSColor(white: 0, alpha: 0.07), dark: NSColor(white: 1, alpha: 0.10))
    static let hover = dynamic(light: NSColor(white: 0, alpha: 0.06), dark: NSColor(white: 1, alpha: 0.08))
    static let separator = Color(nsColor: .separatorColor)
    static let switchOff = dynamic(light: NSColor(white: 0, alpha: 0.14), dark: NSColor(white: 1, alpha: 0.18))
    /// Grouped-form cards in the main window
    static let card = dynamic(light: .white, dark: NSColor(white: 0.145, alpha: 1))
    static let content = Color(nsColor: .windowBackgroundColor)

    enum Space {
        static let xs: CGFloat = 4
        static let s: CGFloat = 8
        static let m: CGFloat = 12
        static let l: CGFloat = 16
        static let xl: CGFloat = 24
        static let xxl: CGFloat = 32
    }

    enum Radius {
        static let control: CGFloat = 6
        static let card: CGFloat = 10
        static let panel: CGFloat = 16
    }

    enum Font {
        static let display = SwiftUI.Font.system(size: 52, weight: .light).monospacedDigit()
        static let title = SwiftUI.Font.system(size: 22, weight: .semibold)
        static let headline = SwiftUI.Font.system(size: 15, weight: .semibold)
        static let body = SwiftUI.Font.system(size: 13)
        static let caption = SwiftUI.Font.system(size: 11)
    }

    private static func dynamic(light: NSColor, dark: NSColor) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .vibrantDark, .accessibilityHighContrastDarkAqua]) != nil ? dark : light
        })
    }
}

// MARK: - Buttons

/// One look for every button: a single orange primary per screen, grey secondary, and text buttons
struct ChivvyButtonStyle: ButtonStyle {
    enum Kind { case primary, secondary, text, danger }
    enum Size { case small, regular, large }

    var kind: Kind = .secondary
    var size: Size = .regular
    /// Stretch to the available width
    var fill = false

    func makeBody(configuration: Configuration) -> some View {
        StyledButton(configuration: configuration, kind: kind, size: size, fill: fill)
    }

    private struct StyledButton: View {
        let configuration: Configuration
        let kind: Kind
        let size: Size
        let fill: Bool
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            configuration.label
                .font(.system(size: fontSize, weight: kind == .primary ? .semibold : .medium))
                .lineLimit(1)
                .foregroundStyle(foreground)
                .padding(.horizontal, kind == .text || kind == .danger ? 6 : horizontalPadding)
                .frame(maxWidth: fill ? .infinity : nil)
                .frame(height: height)
                .background(background, in: RoundedRectangle(cornerRadius: radius))
                .contentShape(RoundedRectangle(cornerRadius: radius))
                .opacity(isEnabled ? (configuration.isPressed ? 0.75 : 1) : 0.4)
        }

        private var height: CGFloat {
            switch size {
            case .small: return 24
            case .regular: return 28
            case .large: return 36
            }
        }

        private var fontSize: CGFloat {
            switch size {
            case .small: return 12
            case .regular: return 13
            case .large: return 14
            }
        }

        private var horizontalPadding: CGFloat { size == .large ? 16 : 12 }
        private var radius: CGFloat { size == .large ? 8 : Theme.Radius.control }

        private var foreground: Color {
            switch kind {
            case .primary: return Theme.onBrand
            case .secondary: return .primary
            case .text: return Theme.brandText
            case .danger: return Theme.danger
            }
        }

        private var background: Color {
            switch kind {
            case .primary: return Theme.brand
            case .secondary: return Theme.fillStrong
            case .text, .danger: return .clear
            }
        }
    }
}

extension ButtonStyle where Self == ChivvyButtonStyle {
    static func chivvy(_ kind: ChivvyButtonStyle.Kind = .secondary, size: ChivvyButtonStyle.Size = .regular,
                       fill: Bool = false) -> ChivvyButtonStyle {
        ChivvyButtonStyle(kind: kind, size: size, fill: fill)
    }
}

/// A full-width list row that highlights under the pointer, like a menu item
struct HoverRowStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        HoverRow(isPressed: configuration.isPressed) { configuration.label }
    }
}

extension ButtonStyle where Self == HoverRowStyle {
    static var hoverRow: HoverRowStyle { HoverRowStyle() }
}

/// Row chrome shared by hover buttons and non-button rows (e.g. a row holding a switch)
struct HoverRow<Content: View>: View {
    var isPressed = false
    @ViewBuilder let content: () -> Content
    @State private var hovering = false

    var body: some View {
        content()
            .font(Theme.Font.body)
            .frame(maxWidth: .infinity, minHeight: 30, alignment: .leading)
            .padding(.horizontal, 10)
            .background(hovering || isPressed ? Theme.hover : .clear, in: RoundedRectangle(cornerRadius: Theme.Radius.control))
            .contentShape(Rectangle())
            .onHover { hovering = $0 }
    }
}

// MARK: - Switch

/// macOS 13's switch ignores `.tint`, so draw the brand-orange one ourselves
struct BrandSwitchStyle: ToggleStyle {
    var small = false

    func makeBody(configuration: Configuration) -> some View {
        let width: CGFloat = small ? 26 : 32
        let height: CGFloat = small ? 16 : 20
        let knob = height - 4
        return HStack(spacing: 0) {
            // Callers put the switch next to their own visible text; the label is only for VoiceOver.
            // (.labelsHidden() doesn't reach custom toggle styles.)
            configuration.label
                .frame(width: 0, height: 0)
                .clipped()
            Button {
                configuration.isOn.toggle()
            } label: {
                Capsule()
                    .fill(configuration.isOn ? Theme.brand : Theme.switchOff)
                    .frame(width: width, height: height)
                    .overlay(alignment: configuration.isOn ? .trailing : .leading) {
                        Circle()
                            .fill(.white)
                            .shadow(color: .black.opacity(0.3), radius: 1, y: 1)
                            .frame(width: knob, height: knob)
                            .padding(2)
                    }
                    .animation(.easeOut(duration: 0.15), value: configuration.isOn)
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
        }
        .accessibilityElement(children: .combine)
        .accessibilityValue(configuration.isOn ? L("开", "On") : L("关", "Off"))
    }
}

extension ToggleStyle where Self == BrandSwitchStyle {
    static var brandSwitch: BrandSwitchStyle { BrandSwitchStyle() }
    static var brandSwitchSmall: BrandSwitchStyle { BrandSwitchStyle(small: true) }
}

// MARK: - Segmented chips

/// A row of options in a grey track, the chosen one raised; used for presets and language
struct SegmentedChips<Item: Hashable>: View {
    let items: [Item]
    let selection: Item?
    let label: (Item) -> String
    let onSelect: (Item) -> Void
    var height: CGFloat = 26

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 2) {
            ForEach(items, id: \.self) { item in
                let isOn = item == selection
                Button {
                    onSelect(item)
                } label: {
                    Text(label(item))
                        .font(.system(size: 12, weight: isOn ? .semibold : .medium))
                        .foregroundStyle(isOn ? Color.primary : Color.secondary)
                        .padding(.horizontal, 12)
                        .frame(height: height)
                        .background {
                            if isOn {
                                RoundedRectangle(cornerRadius: Theme.Radius.control)
                                    .fill(colorScheme == .dark ? Color.white.opacity(0.16) : Color.white)
                                    .shadow(color: .black.opacity(colorScheme == .dark ? 0 : 0.15), radius: 1, y: 0.5)
                            }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isOn ? .isSelected : [])
            }
        }
        .padding(2)
        .background(Theme.fill, in: RoundedRectangle(cornerRadius: 8))
    }
}

// MARK: - Grouped form

/// A titled card of rows separated by hairlines, like System Settings
struct FormSection<Content: View>: View {
    let title: String
    var footer: String? = nil
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.leading, 4)
            VStack(spacing: 0) {
                content()
            }
            .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.Radius.card))
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.card).strokeBorder(Theme.separator.opacity(0.6)))
            if let footer {
                Text(footer)
                    .font(Theme.Font.caption)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 4)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

struct FormRow<Trailing: View>: View {
    let label: String
    var divider = true
    @ViewBuilder let trailing: () -> Trailing

    var body: some View {
        VStack(spacing: 0) {
            if divider {
                Rectangle().fill(Theme.separator.opacity(0.6)).frame(height: 1)
            }
            HStack(spacing: Theme.Space.s) {
                Text(label).font(Theme.Font.body)
                Spacer(minLength: Theme.Space.m)
                trailing()
            }
            .padding(.horizontal, Theme.Space.m)
            .frame(minHeight: 38)
        }
    }
}

// MARK: - Badges & keycaps

/// Round status icon used by the voice panel: filled for strong states, tinted for neutral ones
struct StatusBadge: View {
    enum Tone { case brand, brandSoft, success, neutral }
    let symbol: String
    let tone: Tone
    var size: CGFloat = 32

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.45, weight: .semibold))
            .foregroundStyle(foreground)
            .frame(width: size, height: size)
            .background(background, in: Circle())
            .padding(4)
            .background(ring, in: Circle())
    }

    private var foreground: Color {
        switch tone {
        case .brand: return Theme.onBrand
        case .brandSoft: return Theme.brandText
        case .success: return .white
        case .neutral: return .secondary
        }
    }

    private var background: Color {
        switch tone {
        case .brand: return Theme.brand
        case .brandSoft: return Theme.brandSoft
        case .success: return Theme.success
        case .neutral: return Theme.fillStrong
        }
    }

    private var ring: Color {
        switch tone {
        case .brand, .brandSoft: return Theme.brand.opacity(0.10)
        case .success: return Theme.success.opacity(0.14)
        case .neutral: return Theme.fill
        }
    }
}

struct Keycap: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.secondary)
    }
}

// MARK: - Materials

struct VisualEffectBackground: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .popover

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
    }
}

/// Floating panels (alert, voice) share one card look
struct PanelCard: ViewModifier {
    var radius: CGFloat = Theme.Radius.panel
    var glow = false

    func body(content: Content) -> some View {
        content
            .background(VisualEffectBackground(material: .popover).clipShape(RoundedRectangle(cornerRadius: radius)))
            .overlay(
                RoundedRectangle(cornerRadius: radius)
                    .strokeBorder(glow ? Theme.brand.opacity(0.35) : Theme.separator.opacity(0.5), lineWidth: 1)
            )
    }
}

extension View {
    func panelCard(radius: CGFloat = Theme.Radius.panel, glow: Bool = false) -> some View {
        modifier(PanelCard(radius: radius, glow: glow))
    }
}
