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
        GeometryReader { geo in
            let w = max(geo.size.width, 1)
            let h = max(geo.size.height, 1)
            let seed32 = UInt32(truncatingIfNeeded: seed)
            TimelineView(.animation(minimumInterval: 1 / 24, paused: false)) { timeline in
                let t = timeline.date.timeIntervalSinceReferenceDate
                Canvas { context, size in
                    let count = max(6, Int(22 * intensity))
                    for i in 0 ..< count {
                        let u = hash01(UInt32(i &* 0x85EBCA6B), seed: seed32 &+ UInt32(i << 1))
                        let v = hash01(UInt32(i &* 0xC2B2AE35), seed: seed32 &+ UInt32(i &+ 999))
                        let x = u * size.width
                        let baseY = v * size.height
                        let speed = 0.65 + Double(hash01(UInt32(i), seed: seed32 &+ 7)) * 0.55
                        let drift = (t * speed * 18 + Double(hash01(UInt32(i &+ 3), seed: seed32)) * 20).truncatingRemainder(dividingBy: 1)
                        let y = (baseY + CGFloat(drift) * (size.height + 24)).truncatingRemainder(dividingBy: size.height + 24) - 8
                        let dropW = (1.2 + CGFloat(i % 4) * 0.35) * intensity
                        let dropH = (4 + CGFloat(i % 5)) * CGFloat(sqrt(Double(intensity)))
                        let rect = CGRect(x: x, y: y, width: max(dropW, 0.8), height: max(dropH, 2))
                        let path = Path(roundedRect: rect, cornerRadius: rect.width / 2)
                        let baseOp = (0.09 + Double(i % 4) * 0.028) * Double(intensity)
                        context.fill(path, with: .color(Color.white.opacity(baseOp)))
                        if i % 5 == 0 {
                            let blob = Path(ellipseIn: CGRect(x: x - 0.5, y: y - 2, width: dropW + 1.5, height: dropW + 1.2))
                            context.fill(blob, with: .color(Color.white.opacity(0.12 * Double(intensity))))
                        }
                    }
                }
                .frame(width: w, height: h)
            }
        }
        .allowsHitTesting(false)
    }

    private func hash01(_ i: UInt32, seed: UInt32) -> CGFloat {
        var x = UInt64(i) &* 0x9E3779B97F4A7C15 &+ UInt64(seed)
        x ^= x >> 33
        x &*= 0xff51afd7ed558ccd
        x ^= x >> 33
        return CGFloat(Double(x & 0xFFFF_FFFF) / Double(0xFFFF_FFFF))
    }
}
