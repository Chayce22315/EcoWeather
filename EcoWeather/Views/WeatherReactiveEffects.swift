import SwiftUI

private struct WeatherSceneEnvironmentKey: EnvironmentKey {
    static let defaultValue: WeatherSceneKind = .live
}

extension EnvironmentValues {
    var weatherScene: WeatherSceneKind {
        get { self[WeatherSceneEnvironmentKey.self] }
        set { self[WeatherSceneEnvironmentKey.self] = newValue }
    }
}

extension View {
    func weatherSceneEnvironment(_ scene: WeatherSceneKind) -> some View {
        environment(\.weatherScene, scene)
    }

    /// Rain streaks / droplets on glass and thunder jolt (uses `\.weatherScene`).
    func weatherAtmosphere() -> some View {
        modifier(WeatherAtmosphereModifier())
    }
}

private struct WeatherAtmosphereModifier: ViewModifier {
    @Environment(\.weatherScene) private var scene
    @State private var shakeX: CGFloat = 0
    @State private var shakeY: CGFloat = 0
    @State private var shakeRotation: Double = 0

    func body(content: Content) -> some View {
        content
            .overlay {
                if scene.showsRain {
                    RainOnGlassOverlay(seed: scene.rawValue.hashValue, intensity: 1)
                } else if scene.showsMistOnGlass {
                    RainOnGlassOverlay(seed: scene.rawValue.hashValue &+ 17, intensity: 0.35)
                }
            }
            .offset(x: shakeX, y: shakeY)
            .rotationEffect(.degrees(shakeRotation))
            .animation(.interactiveSpring(response: 0.07, dampingFraction: 0.38), value: shakeX)
            .animation(.interactiveSpring(response: 0.07, dampingFraction: 0.38), value: shakeY)
            .animation(.interactiveSpring(response: 0.07, dampingFraction: 0.38), value: shakeRotation)
            .task(id: scene) {
                guard scene.showsThunder else {
                    shakeX = 0
                    shakeY = 0
                    shakeRotation = 0
                    return
                }
                await thunderShakeLoop()
            }
    }

    private func thunderShakeLoop() async {
        while !Task.isCancelled {
            let wait = Double.random(in: 1.8 ... 4.2)
            try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000))
            guard scene.showsThunder else { break }
            await MainActor.run {
                jolt(amplitude: 1)
            }
            try? await Task.sleep(nanoseconds: 55_000_000)
            await MainActor.run {
                jolt(amplitude: 0.55)
            }
            try? await Task.sleep(nanoseconds: 70_000_000)
            await MainActor.run {
                shakeX = 0
                shakeY = 0
                shakeRotation = 0
            }
        }
    }

    private func jolt(amplitude: CGFloat) {
        shakeX = CGFloat.random(in: -7 ... 7) * amplitude
        shakeY = CGFloat.random(in: -4 ... 4) * amplitude
        shakeRotation = Double.random(in: -1.2 ... 1.2) * Double(amplitude)
    }
}

/// Semi-transparent beads and streaks sliding down the glass (hit-testing off).
private struct RainOnGlassOverlay: View {
    let seed: Int
    /// 1 = heavy rain on glass, ~0.35 = occasional droplets.
    var intensity: CGFloat = 1

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 20, paused: false)) { timeline in
            Canvas { context, size in
                let t = timeline.date.timeIntervalSinceReferenceDate
                let count = max(4, Int(14 * intensity))
                for i in 0 ..< count {
                    let u = unitRandom(i * 3 + seed)
                    let v = unitRandom(i * 7 + seed &* 13)
                    let x = u * size.width
                    let baseY = v * size.height
                    let drift = (t * (22 + Double(i % 5)) + Double(seed % 17) * 0.1).truncatingRemainder(dividingBy: 1)
                    let y = (baseY + drift * (size.height + 20)).truncatingRemainder(dividingBy: size.height + 20) - 6
                    let w: CGFloat = (2 + CGFloat(i % 3) * 0.4) * intensity
                    let h: CGFloat = (5 + CGFloat(i % 4)) * CGFloat(sqrt(Double(intensity)))
                    let rect = CGRect(x: x, y: y, width: max(w, 1), height: max(h, 2))
                    let path = Path(roundedRect: rect, cornerRadius: rect.width / 2)
                    let baseOp = (0.1 + Double(i % 3) * 0.04) * Double(intensity)
                    context.fill(path, with: .color(Color.white.opacity(baseOp)))
                    if i % 4 == 0 {
                        let blob = Path(ellipseIn: CGRect(x: x - 1, y: y - 3, width: w + 2, height: w + 2))
                        context.fill(blob, with: .color(Color.white.opacity(0.14 * Double(intensity))))
                    }
                }
            }
            .allowsHitTesting(false)
        }
    }

    private func unitRandom(_ salt: Int) -> CGFloat {
        let x = sin(Double(salt) * 12.9898 + 78.233) * 43758.5453
        let f = x - floor(x)
        return CGFloat(f)
    }
}
