import SwiftUI

/// Animated sky, clouds, optional rain streaks, and lightning for weather scenes.
struct WeatherSkyBackground: View {
    let scene: WeatherSceneKind
    @State private var rainSeed: CGFloat = 0
    @State private var lightningOpacity: Double = 0

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: false)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            Canvas { context, size in
                drawSky(context: &context, size: size, t: t)
                if scene.showsRain {
                    drawRain(context: &context, size: size, t: t)
                }
            }
            .ignoresSafeArea()
            .overlay {
                if scene.showsThunder {
                    Color.white
                        .opacity(lightningOpacity * 0.35)
                        .ignoresSafeArea()
                        .allowsHitTesting(false)
                }
            }
        }
        .onAppear {
            rainSeed = CGFloat.random(in: 0 ... 1000)
        }
        .task(id: scene) {
            guard scene.showsThunder else {
                lightningOpacity = 0
                return
            }
            await runLightningLoop()
        }
    }

    private func runLightningLoop() async {
        while !Task.isCancelled {
            let wait = Double.random(in: 2.2 ... 5.5)
            try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000))
            guard scene.showsThunder else { break }
            withAnimation(.easeOut(duration: 0.06)) { lightningOpacity = 1 }
            try? await Task.sleep(nanoseconds: 45_000_000)
            withAnimation(.easeIn(duration: 0.12)) { lightningOpacity = 0.4 }
            try? await Task.sleep(nanoseconds: 80_000_000)
            withAnimation(.easeOut(duration: 0.25)) { lightningOpacity = 0 }
        }
    }

    private func drawSky(context: inout GraphicsContext, size: CGSize, t: TimeInterval) {
        let top = skyTopColor
        let bottom = skyBottomColor
        let rect = CGRect(origin: .zero, size: size)
        context.fill(
            Path(rect),
            with: .linearGradient(
                Gradient(colors: [top, bottom]),
                startPoint: CGPoint(x: 0, y: 0),
                endPoint: CGPoint(x: size.width * 0.2, y: size.height)
            )
        )

        let drift = CGFloat(t * 0.012)
        drawCloudLayer(context: &context, size: size, drift: drift, opacity: scene.isNight ? 0.22 : 0.38, scale: 1)
        drawCloudLayer(context: &context, size: size, drift: drift + 0.4, opacity: scene.isNight ? 0.16 : 0.28, scale: 0.85)
        if cloudyAmount > 0.35 {
            drawCloudLayer(context: &context, size: size, drift: drift + 0.75, opacity: scene.isNight ? 0.2 : 0.32, scale: 0.7)
        }

        if scene.isNight {
            for i in 0 ..< 18 {
                let sx = pseudoRandom01(Double(i) * 3.1 + 1) * size.width
                let sy = pseudoRandom01(Double(i) * 7.7 + 2) * size.height * 0.55
                let r: CGFloat = CGFloat(pseudoRandom01(Double(i) * 2.2)) * 1.2 + 0.4
                context.fill(
                    Path(ellipseIn: CGRect(x: sx, y: sy, width: r, height: r)),
                    with: .color(Color.white.opacity(0.35 + pseudoRandom01(Double(i)) * 0.35))
                )
            }
        }
    }

    private var cloudyAmount: Double {
        switch scene {
        case .partlyCloudy, .nightPartlyCloudy: return 0.45
        case .cloudy, .nightCloudy: return 0.95
        case .rain, .thunderstorm, .nightRain, .nightThunderstorm: return 0.9
        case .isolatedThunder, .nightIsolatedThunder: return 0.55
        case .sunny, .nightClear: return 0.12
        case .live: return 0.4
        }
    }

    private var skyTopColor: Color {
        switch scene {
        case .sunny, .partlyCloudy:
            return Color(red: 0.45, green: 0.72, blue: 0.98)
        case .cloudy:
            return Color(red: 0.55, green: 0.62, blue: 0.72)
        case .rain, .thunderstorm, .isolatedThunder:
            return Color(red: 0.32, green: 0.38, blue: 0.48)
        case .nightClear, .nightPartlyCloudy, .nightCloudy, .nightRain, .nightThunderstorm, .nightIsolatedThunder:
            return Color(red: 0.07, green: 0.09, blue: 0.22)
        case .live:
            return Color(red: 0.42, green: 0.65, blue: 0.92)
        }
    }

    private var skyBottomColor: Color {
        switch scene {
        case .sunny:
            return Color(red: 0.75, green: 0.88, blue: 0.98)
        case .partlyCloudy:
            return Color(red: 0.72, green: 0.82, blue: 0.95)
        case .cloudy:
            return Color(red: 0.68, green: 0.72, blue: 0.78)
        case .rain, .thunderstorm, .isolatedThunder:
            return Color(red: 0.48, green: 0.52, blue: 0.58)
        case .nightClear:
            return Color(red: 0.12, green: 0.14, blue: 0.28)
        case .nightPartlyCloudy, .nightCloudy:
            return Color(red: 0.1, green: 0.12, blue: 0.24)
        case .nightRain, .nightThunderstorm, .nightIsolatedThunder:
            return Color(red: 0.08, green: 0.1, blue: 0.18)
        case .live:
            return Color(red: 0.7, green: 0.82, blue: 0.94)
        }
    }

    private func drawCloudLayer(
        context: inout GraphicsContext,
        size: CGSize,
        drift: CGFloat,
        opacity: CGFloat,
        scale: CGFloat
    ) {
        let baseY = size.height * CGFloat(0.18 + Double(scale) * 0.1)
        let w = size.width * scale * 1.05
        let h = size.height * 0.13 * scale
        let r = h * 0.55
        let strideX = r * 4.2
        let phase = (drift.truncatingRemainder(dividingBy: 1)) * strideX
        var x = -strideX * 2 + phase
        while x < size.width + strideX * 2 {
            let blob = Path { p in
                p.addEllipse(in: CGRect(x: x, y: baseY, width: r * 2.2, height: r * 1.6))
                p.addEllipse(in: CGRect(x: x + r * 1.4, y: baseY - r * 0.15, width: r * 2.4, height: r * 1.7))
                p.addEllipse(in: CGRect(x: x + r * 2.9, y: baseY, width: r * 2.1, height: r * 1.55))
            }
            context.fill(blob, with: .color(Color.white.opacity(Double(opacity))))
            x += strideX
        }
    }

    private func drawRain(context: inout GraphicsContext, size: CGSize, t: TimeInterval) {
        let count = Int(size.width / 9) + 16
        let fall = size.height + 24
        for i in 0 ..< count {
            let col = CGFloat(i) / CGFloat(max(count - 1, 1))
            let x = col * size.width + rainSeed.truncatingRemainder(dividingBy: 24)
            let offset = (t * 1.8 + Double(i) * 0.09 + Double(rainSeed)).truncatingRemainder(dividingBy: 1)
            let y = CGFloat(offset) * fall - 12
            var p = Path()
            p.move(to: CGPoint(x: x, y: y))
            p.addLine(to: CGPoint(x: x + 1.4, y: y + 16))
            context.stroke(p, with: .color(Color.white.opacity(0.2)), lineWidth: 1.1)
        }
    }

    private func pseudoRandom01(_ x: Double) -> Double {
        let s = sin(x * 12.9898 + 78.233) * 43758.5453
        return s - floor(s)
    }
}
