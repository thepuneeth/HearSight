import SwiftUI
import UIKit

enum HearSightThemeMode {
    case cinematicDark
    case warmLight
}

struct HearSightTheme {
    var mode: HearSightThemeMode
    var background: Color
    var surface: Color
    var surfaceElevated: Color
    var surfaceGlass: Color
    var field: Color
    var primaryText: Color
    var secondaryText: Color
    var accent: Color
    var secondaryAccent: Color
    var warning: Color
    var stroke: Color
    var glow: Color
    var buttonForeground: Color

    static func current(for colorScheme: ColorScheme) -> HearSightTheme {
        colorScheme == .dark ? .cinematicDark : .warmLight
    }

    static let cinematicDark = HearSightTheme(
        mode: .cinematicDark,
        background: Color(hex: 0x050505),
        surface: Color(hex: 0x121212),
        surfaceElevated: Color(hex: 0x201F1F),
        surfaceGlass: Color.white.opacity(0.075),
        field: Color(hex: 0x1C1B1B),
        primaryText: Color(hex: 0xF5F7F8),
        secondaryText: Color(hex: 0xBBC9CF),
        accent: Color(hex: 0x00D1FF),
        secondaryAccent: Color(hex: 0xBB86FC),
        warning: Color(hex: 0xFFB4AB),
        stroke: Color.white.opacity(0.12),
        glow: Color(hex: 0x00D1FF).opacity(0.36),
        buttonForeground: Color(hex: 0x001F28)
    )

    static let warmLight = HearSightTheme(
        mode: .warmLight,
        background: Color(hex: 0xFDFCFB),
        surface: Color(hex: 0xFFFFFF),
        surfaceElevated: Color(hex: 0xF6F3F2),
        surfaceGlass: Color.white.opacity(0.54),
        field: Color(hex: 0xF5E1CE),
        primaryText: Color(hex: 0x1B1C1C),
        secondaryText: Color(hex: 0x564334),
        accent: Color(hex: 0xFF8C00),
        secondaryAccent: Color(hex: 0xE27D60),
        warning: Color(hex: 0xBA1A1A),
        stroke: Color(hex: 0xDDC1AE).opacity(0.7),
        glow: Color(hex: 0xE27D60).opacity(0.28),
        buttonForeground: Color.white
    )
}

enum HearSightSpacing {
    static let unit: CGFloat = 8
    static let pageMargin: CGFloat = 24
    static let sectionGap: CGFloat = 32
    static let cardPadding: CGFloat = 24
    static let touchTarget: CGFloat = 64
    static let compactGap: CGFloat = 16
}

enum HearSightRadius {
    static let control: CGFloat = 18
    static let card: CGFloat = 28
    static let hud: CGFloat = 32
    static let pill: CGFloat = 999
}

enum HearSightType {
    static func display() -> Font {
        .system(size: 44, weight: .bold, design: .rounded)
    }

    static func headline() -> Font {
        .system(size: 32, weight: .bold, design: .rounded)
    }

    static func title() -> Font {
        .system(size: 28, weight: .semibold, design: .rounded)
    }

    static func bodyLarge() -> Font {
        .system(size: 22, weight: .medium, design: .rounded)
    }

    static func body() -> Font {
        .system(size: 18, weight: .medium, design: .rounded)
    }

    static func label() -> Font {
        .system(size: 15, weight: .semibold, design: .rounded)
    }
}

struct HearSightAmbientBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let theme = HearSightTheme.current(for: colorScheme)

        ZStack {
            theme.background

            RadialGradient(
                colors: [
                    theme.accent.opacity(theme.mode == .cinematicDark ? 0.24 : 0.18),
                    .clear
                ],
                center: .topLeading,
                startRadius: 20,
                endRadius: 360
            )

            RadialGradient(
                colors: [
                    theme.secondaryAccent.opacity(theme.mode == .cinematicDark ? 0.22 : 0.14),
                    .clear
                ],
                center: .bottomTrailing,
                startRadius: 30,
                endRadius: 420
            )
        }
        .ignoresSafeArea()
    }
}

struct HearSightGlassSurface<Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme
    var radius: CGFloat = HearSightRadius.card
    var padding: CGFloat = HearSightSpacing.cardPadding
    @ViewBuilder let content: () -> Content

    var body: some View {
        let theme = HearSightTheme.current(for: colorScheme)

        content()
            .padding(padding)
            .background(.ultraThinMaterial)
            .background(theme.surfaceGlass)
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: [
                                theme.accent.opacity(0.38),
                                theme.stroke,
                                Color.clear
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            )
            .shadow(color: theme.glow.opacity(0.35), radius: 28, x: 0, y: 16)
    }
}

struct HearSightSoftGlow: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    var active = true
    var radius: CGFloat = 40

    func body(content: Content) -> some View {
        let theme = HearSightTheme.current(for: colorScheme)

        content
            .shadow(color: active ? theme.glow : .clear, radius: radius, x: 0, y: 0)
    }
}

extension View {
    func hearSightGlow(active: Bool = true, radius: CGFloat = 40) -> some View {
        modifier(HearSightSoftGlow(active: active, radius: radius))
    }
}

struct HearSightOrbMicrophone: View {
    @Environment(\.colorScheme) private var colorScheme
    var isListening: Bool
    var diameter: CGFloat = 190

    var body: some View {
        let theme = HearSightTheme.current(for: colorScheme)

        ZStack {
            HearSightRadarRings(
                isActive: isListening,
                color: theme.accent,
                ringCount: 3
            )
            .frame(width: diameter * 1.28, height: diameter * 1.28)
            .accessibilityHidden(true)

            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            theme.accent.opacity(theme.mode == .cinematicDark ? 0.42 : 0.85),
                            theme.secondaryAccent.opacity(theme.mode == .cinematicDark ? 0.28 : 0.75),
                            theme.surfaceGlass
                        ],
                        center: .topLeading,
                        startRadius: 12,
                        endRadius: diameter
                    )
                )
                .frame(width: diameter, height: diameter)
                .overlay(
                    Circle()
                        .stroke(theme.stroke, lineWidth: 1)
                )
                .hearSightGlow(active: isListening, radius: 54)

            Circle()
                .fill(theme.primaryText)
                .frame(width: diameter * 0.62, height: diameter * 0.62)
                .opacity(theme.mode == .cinematicDark ? 0.98 : 0.92)

            Image(systemName: isListening ? "waveform" : "mic.fill")
                .font(.system(size: diameter * 0.24, weight: .bold))
                .foregroundStyle(theme.background)
                .scaleEffect(isListening ? 1.05 : 1)
        }
        .animation(.easeInOut(duration: 0.28), value: isListening)
        .accessibilityElement(children: .ignore)
    }
}

struct HearSightRadarRings: View {
    var isActive: Bool
    var color: Color
    var ringCount = 4

    var body: some View {
        TimelineView(.animation) { timeline in
            let phase = isActive ? timeline.date.timeIntervalSinceReferenceDate : 0

            ZStack {
                ForEach(rings) { ring in
                    let index = ring.index
                    let progress = isActive ? CGFloat((phase * 0.35 + Double(index) / Double(ringCount)).truncatingRemainder(dividingBy: 1)) : CGFloat(index + 1) / CGFloat(ringCount + 1)
                    Circle()
                        .stroke(color.opacity(isActive ? 0.34 * (1 - progress) : 0.12), lineWidth: 1.2)
                        .scaleEffect(0.32 + progress * 0.72)
                }
            }
        }
        .drawingGroup()
    }

    private var rings: [HearSightRingIndex] {
        Array(0..<ringCount).map { HearSightRingIndex(index: $0) }
    }
}

private struct HearSightRingIndex: Identifiable {
    let index: Int
    var id: Int { index }
}

struct HearSightNavigationHUDCard<Content: View>: View {
    var title: String?
    var symbol: String?
    @ViewBuilder let content: () -> Content

    var body: some View {
        HearSightGlassSurface(radius: HearSightRadius.hud) {
            VStack(alignment: .leading, spacing: HearSightSpacing.compactGap) {
                if title != nil || symbol != nil {
                    HStack(spacing: 10) {
                        if let symbol {
                            Image(systemName: symbol)
                                .font(.headline.weight(.semibold))
                        }
                        if let title {
                            Text(title)
                                .font(HearSightType.label())
                                .textCase(.uppercase)
                        }
                    }
                    .foregroundStyle(.secondary)
                }

                content()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct HearSightFloatingBottomNavigation: View {
    @Environment(\.colorScheme) private var colorScheme
    let items: [HearSightBottomNavItem]
    let activeID: String
    let select: (HearSightBottomNavItem) -> Void

    var body: some View {
        let theme = HearSightTheme.current(for: colorScheme)

        HStack(spacing: 12) {
            ForEach(items) { item in
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    select(item)
                } label: {
                    Image(systemName: item.systemImage)
                        .font(.title3.weight(.semibold))
                        .frame(width: HearSightSpacing.touchTarget, height: HearSightSpacing.touchTarget)
                        .foregroundStyle(item.id == activeID ? theme.buttonForeground : theme.secondaryText)
                        .background(item.id == activeID ? theme.accent : Color.clear)
                        .clipShape(Circle())
                }
                .buttonStyle(HearSightHapticButtonStyle())
                .accessibilityLabel(item.accessibilityLabel)
                .accessibilityHint(item.accessibilityHint)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
        .background(theme.surfaceGlass)
        .clipShape(Capsule())
        .overlay(Capsule().stroke(theme.stroke, lineWidth: 1))
        .hearSightGlow(active: true, radius: 24)
    }
}

struct HearSightBottomNavItem: Identifiable {
    let id: String
    let systemImage: String
    let accessibilityLabel: String
    let accessibilityHint: String
}

struct HearSightPrimaryButton: View {
    @Environment(\.colorScheme) private var colorScheme
    let title: String
    let systemImage: String
    let accessibilityHint: String
    let action: () -> Void

    var body: some View {
        let theme = HearSightTheme.current(for: colorScheme)

        Button {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            action()
        } label: {
            Label(title, systemImage: systemImage)
                .font(HearSightType.label())
                .foregroundStyle(theme.buttonForeground)
                .frame(maxWidth: .infinity)
                .frame(minHeight: HearSightSpacing.touchTarget)
                .background(
                    LinearGradient(
                        colors: [
                            theme.accent,
                            theme.mode == .cinematicDark ? theme.accent.opacity(0.72) : theme.secondaryAccent
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .clipShape(Capsule())
                .overlay(
                    Capsule()
                        .stroke(Color.white.opacity(theme.mode == .cinematicDark ? 0.16 : 0.42), lineWidth: 1)
                )
                .hearSightGlow(active: true, radius: 24)
        }
        .buttonStyle(HearSightHapticButtonStyle())
        .accessibilityLabel(title)
        .accessibilityHint(accessibilityHint)
    }
}

struct HearSightSecondaryButton: View {
    @Environment(\.colorScheme) private var colorScheme
    let title: String
    let systemImage: String
    let accessibilityHint: String
    let action: () -> Void

    var body: some View {
        let theme = HearSightTheme.current(for: colorScheme)

        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            action()
        } label: {
            Label(title, systemImage: systemImage)
                .font(HearSightType.label())
                .foregroundStyle(theme.primaryText)
                .frame(minHeight: 52)
                .padding(.horizontal, 18)
                .background(theme.surfaceGlass)
                .background(.ultraThinMaterial)
                .clipShape(Capsule())
                .overlay(Capsule().stroke(theme.stroke, lineWidth: 1))
        }
        .buttonStyle(HearSightHapticButtonStyle())
        .accessibilityLabel(title)
        .accessibilityHint(accessibilityHint)
    }
}

struct HearSightHapticButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .opacity(configuration.isPressed ? 0.86 : 1)
            .animation(.spring(response: 0.24, dampingFraction: 0.72), value: configuration.isPressed)
    }
}

extension Color {
    init(hex: UInt, alpha: Double = 1) {
        self.init(
            red: Double((hex >> 16) & 0xff) / 255,
            green: Double((hex >> 8) & 0xff) / 255,
            blue: Double(hex & 0xff) / 255,
            opacity: alpha
        )
    }
}
