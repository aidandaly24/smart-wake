import SwiftUI

@main
struct SmartWakeApp: App {
    @StateObject private var store = AlarmStore.shared
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            HomeView(store: store)
                .preferredColorScheme(.dark)
                .tint(.mint)
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active { store.refresh() }
                }
        }
    }
}

/// A small, shared visual language inspired by the sunrise app icon. Keep text
/// on the dark surfaces; reserve the warm accent for actions and wayfinding.
enum WakePalette {
    static let background = Color(red: 0.035, green: 0.04, blue: 0.11)
    static let surface = Color(red: 0.095, green: 0.10, blue: 0.20)
    static let sunrise = Color(red: 1.0, green: 0.76, blue: 0.34)
    static let lavender = Color(red: 0.75, green: 0.68, blue: 1.0)
}

/// A quiet glow adds depth without competing with alarm status or game tiles.
struct WakeBackdrop: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ZStack(alignment: .topTrailing) {
            WakePalette.background
            RadialGradient(colors: [WakePalette.lavender.opacity(0.18), .clear],
                           center: .topTrailing, startRadius: 0, endRadius: 420)
            RadialGradient(colors: [WakePalette.sunrise.opacity(0.10), .clear],
                           center: .topLeading, startRadius: 0, endRadius: 340)
            TimelineView(.animation(minimumInterval: 1.0 / 20.0, paused: reduceMotion || scenePhase != .active || ProcessInfo.processInfo.isLowPowerModeEnabled)) { timeline in
                Canvas { context, size in
                    let t = reduceMotion ? 0 : timeline.date.timeIntervalSinceReferenceDate
                    drawSky(context: context, size: size, time: t)
                }
            }
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
        .allowsHitTesting(false)
    }

    private func drawSky(context: GraphicsContext, size: CGSize, time: TimeInterval) {
        // Slow layers create depth rather than requiring 3D assets or a network.
        for index in 0..<4 {
            let i = Double(index)
            let width = size.width * CGFloat(0.46 + 0.09 * i)
            let drift = CGFloat(sin(time / (24 + i * 5) + i) * 16)
            let x = size.width * CGFloat(index.isMultiple(of: 2) ? 0.0 : 0.58) + drift - width * 0.22
            let y = size.height * CGFloat(0.20 + i * 0.22)
            let color = (index.isMultiple(of: 2) ? WakePalette.lavender : Color.white).opacity(0.035)
            for puff in 0..<3 {
                let px = x + width * CGFloat(puff) * 0.25
                let py = y - CGFloat(puff == 1 ? 13 : 0)
                context.fill(Path(ellipseIn: CGRect(x: px, y: py, width: width * 0.5, height: 38)), with: .color(color))
            }
        }
        // Fine, drifting curves suggest a breeze without obscuring controls.
        for index in 0..<3 {
            let offset = CGFloat(sin(time / 15 + Double(index)) * 12)
            let x = size.width * CGFloat(index == 1 ? 0.48 : 0.05) + offset
            let y = size.height * CGFloat(0.30 + Double(index) * 0.23)
            var breeze = Path()
            breeze.move(to: CGPoint(x: x, y: y))
            breeze.addCurve(to: CGPoint(x: x + 90, y: y - 3),
                            control1: CGPoint(x: x + 25, y: y - 9),
                            control2: CGPoint(x: x + 55, y: y + 8))
            context.stroke(breeze, with: .color(.white.opacity(0.08)), style: StrokeStyle(lineWidth: 1, lineCap: .round))
        }
        for index in 0..<3 {
            let phase = (time / (34 + Double(index) * 5) + Double(index) * 0.31)
            let progress = phase - floor(phase)
            let x = size.width * CGFloat(progress * 1.3 - 0.15)
            let y = size.height * CGFloat(0.11 + Double(index) * 0.075) + CGFloat(sin(time / 5 + Double(index)) * 3)
            var bird = Path()
            bird.move(to: CGPoint(x: x - 7, y: y))
            bird.addQuadCurve(to: CGPoint(x: x, y: y + 3), control: CGPoint(x: x - 3, y: y - 3))
            bird.addQuadCurve(to: CGPoint(x: x + 7, y: y), control: CGPoint(x: x + 3, y: y - 3))
            context.stroke(bird, with: .color(.white.opacity(0.28)), style: StrokeStyle(lineWidth: 1.4, lineCap: .round))
        }
    }
}

struct WakeCard<Content: View>: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
            .background(WakePalette.surface.opacity(reduceTransparency ? 1 : 0.88), in: RoundedRectangle(cornerRadius: 22))
            .overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(.white.opacity(0.09)))
    }
}

struct WakePrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(isEnabled ? WakePalette.background : Color.white.opacity(0.72))
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(WakePalette.sunrise.opacity(isEnabled ? (configuration.isPressed ? 0.78 : 1) : 0.38),
                        in: RoundedRectangle(cornerRadius: 15))
            .opacity(isEnabled ? 1 : 0.8)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.98 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: configuration.isPressed)
    }
}

/// The approved sunrise artwork gives the greeting a tangible, friendly focal
/// point. It is decorative, so VoiceOver can focus on the alarm and its actions.
struct WakeSunrise: View {
    var size: CGFloat = 76

    var body: some View {
        Image("WakeSunrise")
            .resizable()
            .scaledToFill()
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: size * 0.29, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: size * 0.29, style: .continuous)
                .strokeBorder(.white.opacity(0.18), lineWidth: 1))
            .shadow(color: WakePalette.sunrise.opacity(0.20), radius: 18, y: 6)
            .accessibilityHidden(true)
    }
}
