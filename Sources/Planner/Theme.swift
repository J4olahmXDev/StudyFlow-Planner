import SwiftUI
extension Color {
    static let daylight = Color(red:0.24,green:0.39,blue:0.33)
    static let paletteNames = ["Sage", "Blue", "Lavender", "Apricot", "Teal", "Rose", "Green", "Amber", "Slate", "Sky"]
    static let palette: [Color] = [
        Color(red: 0.34, green: 0.64, blue: 0.49), Color(red: 0.28, green: 0.65, blue: 0.94),
        Color(red: 0.57, green: 0.44, blue: 0.83), Color(red: 0.91, green: 0.59, blue: 0.29),
        Color(red: 0.25, green: 0.64, blue: 0.67), Color(red: 0.91, green: 0.35, blue: 0.53),
        Color(red: 0.36, green: 0.73, blue: 0.43), Color(red: 0.92, green: 0.68, blue: 0.26),
        Color(red: 0.46, green: 0.53, blue: 0.63), Color(red: 0.38, green: 0.73, blue: 0.88)
    ]
    static func subject(_ index: Int) -> Color { palette[Int(index.magnitude % UInt(palette.count))] }

}
struct Eyebrow: View { var text:String; var body:some View { Text(text.uppercased()).font(.system(size:10,weight:.semibold,design:.rounded)).tracking(1.7).foregroundStyle(.secondary) } }
struct EmptyState: View { var title:String; var detail:String; var body:some View { VStack(spacing:12) { Image(systemName:"sun.max").font(.largeTitle).foregroundStyle(Color.daylight); Text(title).font(.title3.weight(.semibold)); Text(detail).foregroundStyle(.secondary) }.frame(maxWidth:.infinity,maxHeight:.infinity).padding(36) } }
extension View { func card() -> some View { modifier(PlannerCard()) } }

extension View {
    @ViewBuilder func plannerHelp(_ text: String) -> some View {
        #if os(macOS)
        help(text)
        #else
        self
        #endif
    }
}

extension StudyTask {
    var displayColor: Color {
        Color.subject(color ?? (priority == .high ? 5 : priority == .medium ? 3 : 1))
    }
}

enum PlannerPalette: String, CaseIterable {
    case classic = "Classic"
    case retro = "Retro"
    case honey = "Soft Honey"
    case lilac = "White / Lilac"

    private static func color(_ hex: UInt32) -> Color {
        let red = Double((hex >> 16) & 0xff) / 255.0
        let green = Double((hex >> 8) & 0xff) / 255.0
        let blue = Double(hex & 0xff) / 255.0
        return Color(.sRGB, red: red, green: green, blue: blue)
    }

    func canvas(_ scheme: ColorScheme) -> Color {
        switch (self, scheme) {
        case (.classic, .dark): return Color(red: 0.12, green: 0.12, blue: 0.12)
        case (.classic, _): return Color(red: 0.975, green: 0.975, blue: 0.975)
        case (.retro, .dark): return Color(red: 0.18, green: 0.15, blue: 0.12)
        case (.retro, _): return Color(red: 0.96, green: 0.935, blue: 0.865)
        case (.honey, .dark): return Self.color(0x211f1a)
        case (.honey, _): return Self.color(0xfbfaf7)
        case (.lilac, .dark): return Self.color(0x211d27)
        case (.lilac, _): return Self.color(0xfaf9fc)
        }
    }

    func sidebar(_ scheme: ColorScheme) -> Color {
        switch (self, scheme) {
        case (.classic, .dark): return Color(red: 0.16, green: 0.16, blue: 0.16)
        case (.classic, _): return Color(red: 0.93, green: 0.93, blue: 0.93)
        case (.retro, .dark): return Color(red: 0.24, green: 0.20, blue: 0.15)
        case (.retro, _): return Color(red: 0.90, green: 0.85, blue: 0.74)
        case (.honey, .dark): return Self.color(0x2c2820)
        case (.honey, _): return Self.color(0xf4f0e5)
        case (.lilac, .dark): return Self.color(0x2d2637)
        case (.lilac, _): return Self.color(0xf2edf8)
        }
    }

    func paper(_ scheme: ColorScheme) -> Color {
        switch (self, scheme) {
        case (.classic, .dark): return Color(red: 0.15, green: 0.15, blue: 0.15)
        case (.classic, _): return .white
        case (.retro, .dark): return Color(red: 0.22, green: 0.18, blue: 0.14)
        case (.retro, _): return Color(red: 0.99, green: 0.97, blue: 0.91)
        case (.honey, .dark): return Self.color(0x28251f)
        case (.honey, _): return Self.color(0xffffff)
        case (.lilac, .dark): return Self.color(0x292431)
        case (.lilac, _): return Self.color(0xffffff)
        }
    }

    func accent(_ scheme: ColorScheme) -> Color {
        if self == .honey { return Self.color(scheme == .dark ? 0xefd78d : 0x715720) }
        if self == .lilac { return Self.color(scheme == .dark ? 0xcbb6f7 : 0x6745ad) }
        if self == .retro {
            return scheme == .dark ? Color(red: 0.91, green: 0.75, blue: 0.49)
                : Color(red: 0.38, green: 0.26, blue: 0.13)
        }
        return scheme == .dark ? .white : Color(red: 0.19, green: 0.19, blue: 0.19)
    }

    var button: Color {
        switch self {
        case .honey: return Self.color(0xefd78d)
        case .lilac: return Self.color(0x6745ad)
        case .retro: return Color(red: 0.38, green: 0.26, blue: 0.13)
        case .classic: return Color(red: 0.24, green: 0.24, blue: 0.24)
        }
    }

    var buttonText: Color { self == .honey ? Self.color(0x30230e) : .white }

    func selection(_ scheme: ColorScheme) -> Color {
        switch self {
        case .honey: return Self.color(scheme == .dark ? 0x51452a : 0xefd78d)
        case .lilac: return Self.color(scheme == .dark ? 0x493762 : 0xeae0ff)
        default: return accent(scheme).opacity(0.14)
        }
    }

    func popupTint(_ scheme: ColorScheme) -> Color {
        switch self {
        case .honey: return Self.color(scheme == .dark ? 0x39301f : 0xfcf4de)
        case .lilac: return Self.color(scheme == .dark ? 0x392d49 : 0xf1e9ff)
        default: return paper(scheme)
        }
    }

    var titleDesign: Font.Design { self == .retro ? .serif : .default }
}

private struct PlannerPaletteKey: EnvironmentKey {
    static let defaultValue = PlannerPalette.classic
}

extension EnvironmentValues {
    var plannerPalette: PlannerPalette {
        get { self[PlannerPaletteKey.self] }
        set { self[PlannerPaletteKey.self] = newValue }
    }
}

private struct PlannerCard: ViewModifier {
    @Environment(\.plannerPalette) private var palette
    @Environment(\.colorScheme) private var scheme

    func body(content: Content) -> some View {
        content.padding(18)
            .background(palette.paper(scheme), in: RoundedRectangle(cornerRadius: 16))
            .overlay { RoundedRectangle(cornerRadius: 16).strokeBorder(.primary.opacity(0.07)).allowsHitTesting(false) }
    }
}

struct PlannerPressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: configuration.isPressed)
    }
}
