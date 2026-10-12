import SwiftUI
import CoreText

/// Design tokens. Dark, glassy chrome over full-bleed artwork: surfaces are translucent, the
/// focused title lends its own colour to the glow around it, and one red accent marks the
/// primary action and progress.
enum Theme {
    static let bg0 = Color(hex: 0x07080B)
    static let bg1 = Color(hex: 0x0E1016)
    static let surface = Color(hex: 0x161922)
    static let surface2 = Color(hex: 0x20242F)
    static let line = Color.white.opacity(0.08)
    static let text1 = Color(hex: 0xF4F1EA)
    static let text2 = Color(hex: 0xF4F1EA).opacity(0.72)
    static let text3 = Color(hex: 0xF4F1EA).opacity(0.46)
    static let accent = Color(hex: 0xF0454A)
    static let good = Color(hex: 0x62D39B)
    static let focusInk = Color(hex: 0x0B0C10)

    /// Horizontal inset of content from the screen edge (title-safe area).
    static let edge: CGFloat = 80
    static let posterWidth: CGFloat = 200
    static let cardRadius: CGFloat = 20
    static let tileRadius: CGFloat = 24

    /// Focus changes: quick, with a little overshoot.
    static let focusSpring = Animation.spring(response: 0.34, dampingFraction: 0.72)
    /// Larger moves: rows, panels, the billboard.
    static let glide = Animation.spring(response: 0.5, dampingFraction: 0.86)
}

extension View {
    /// Translucent surface: Liquid Glass where the system has it, a thin material elsewhere.
    @ViewBuilder
    func glass<S: Shape>(_ shape: S) -> some View {
        if #available(tvOS 26.0, *) {
            glassEffect(.regular, in: shape)
        } else {
            background(.ultraThinMaterial, in: shape)
                .overlay(shape.stroke(Color.white.opacity(0.14), lineWidth: 1))
        }
    }
}

extension Post {
    /// A lively version of the poster's average colour, used for the glow around the title.
    var tint: Color {
        guard let c = poster.blurhash.flatMap(BlurHash.average) else { return Theme.accent }
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(red: c.red, green: c.green, blue: c.blue, alpha: 1).getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        // Greys have no meaningful hue; keep them as a cool white instead of a random colour.
        guard s > 0.1 else { return Color(hue: 0.62, saturation: 0.12, brightness: 0.95) }
        return Color(hue: h, saturation: min(0.95, max(0.55, s * 1.5)), brightness: min(1, max(0.8, b * 1.7)))
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}

/// Vazirmatn covers Persian and Latin in one family, so mixed strings stay visually consistent.
enum AppFont {
    static func register() {
        for url in Bundle.main.urls(forResourcesWithExtension: "ttf", subdirectory: nil) ?? [] {
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }

    static func name(_ weight: Font.Weight) -> String {
        switch weight {
        case .heavy, .black: return "Vazirmatn-ExtraBold"
        case .bold: return "Vazirmatn-Bold"
        case .semibold: return "Vazirmatn-SemiBold"
        case .medium: return "Vazirmatn-Medium"
        default: return "Vazirmatn-Regular"
        }
    }
}

extension Font {
    static func app(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .custom(AppFont.name(weight), fixedSize: size)
    }
}

// MARK: - Environment

private struct LocKey: EnvironmentKey {
    static let defaultValue = Loc(lang: .fa)
}

private struct CalmKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// Interface strings in the chosen language.
    var loc: Loc {
        get { self[LocKey.self] }
        set { self[LocKey.self] = newValue }
    }

    /// "Reduce motion" setting: no backdrop drift, no hero rotation.
    var calm: Bool {
        get { self[CalmKey.self] }
        set { self[CalmKey.self] = newValue }
    }
}
