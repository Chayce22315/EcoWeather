import SwiftUI

/// Animated sky, clouds, optional rain streaks, and lightning for weather scenes.
struct WeatherSkyBackground: View {
    let scene: WeatherSceneKind
    @State private var rainSeed: CGFloat = 0
    @State private var lightningOpacity: Double = 0

    var body: some View {
        GeometryReader { geo in
            let scale = skyArtScale(for: geo.size)
            TimelineView(.animation(minimumInterval: 1 / 30, paused: false)) { timeline in
                let t = timeline.date.timeIntervalSinceReferenceDate
                Canvas { context, size in
                    drawSky(context: &context, size: size, t: t, scale: scale)
                    if scene.showsRain {
                        drawRain(context: &context, size: size, t: t, scale: scale)
                    }
                }
                .frame(width: geo.size.width, height: geo.size.height)
                .overlay {
                    if scene.showsThunder {
                        Color.white
                            .opacity(lightningOpacity * 0.38)
                            .allowsHitTesting(false)
                    }
                }
            }
        }
        .ignoresSafeArea()
        .onAppear {
            rainSeed = CGFloat.random(in: 0 ... 10_000)
        }
        .task(id: scene) {
            guard scene.showsThunder else {
                lightningOpacity = 0
                return
            }
            await runLightningLoop()
        }
    }

    /// Keeps clouds and rain feeling large on small phones; scales up a bit on Pro Max.
    private func skyArtScale(for size: CGSize) -> CGFloat {
        let ref: CGFloat = 375
        let m = max(size.width, size.height)
        return max(1.12, min(m / ref, 1.55))
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

    private func drawSky(context: inout GraphicsContext, size: CGSize, t: TimeInterval, scale: CGFloat) {
        let top = skyTopColor
        let mid = skyMidColor
        let bottom = skyBottomColor
        let rect = CGRect(origin: .zero, size: size)
        context.fill(
            Path(rect),
            with: .linearGradient(
                Gradient(stops: [
                    .init(color: top, location: 0),
                    .init(color: mid, location: 0.48),
                    .init(color: bottom, location: 1)
                ]),
                startPoint: CGPoint(x: size.width * 0.08, y: 0),
                endPoint: CGPoint(x: size.width * 0.42, y: size.height * 1.05)
            )
        )

        // Soft horizon haze
        let haze = Path(CGRect(x: 0, y: size.height * 0.55, width: size.width, height: size.height * 0.5))
        context.fill(haze, with: .color(bottom.opacity(scene.isNight ? 0.35 : 0.22)))

        if scene.isNight {
            drawMoon(context: &context, size: size, scale: scale)
            drawStars(context: &context, size: size, t: t)
        } else if sceneShowsSun(scene) {
            drawSun(context: &context, size: size, t: t, scale: scale)
        }

        let drift = CGFloat(t * 0.009) * scale
        drawCloudLayer(context: &context, size: size, drift: drift, opacity: scene.isNight ? 0.26 : 0.42, scale: 1 * scale, vertical: 0.14)
        drawCloudLayer(context: &context, size: size, drift: drift + 0.55, opacity: scene.isNight ? 0.18 : 0.32, scale: 0.92 * scale, vertical: 0.22)
        if cloudyAmount > 0.35 {
            drawCloudLayer(context: &context, size: size, drift: drift + 1.05, opacity: scene.isNight ? 0.24 : 0.36, scale: 0.78 * scale, vertical: 0.1)
        }
        if cloudyAmount > 0.75 {
            drawCloudLayer(context: &context, size: size, drift: drift + 1.6, opacity: scene.isNight ? 0.2 : 0.28, scale: 0.65 * scale, vertical: 0.32)
        }

        // Bottom depth vignette
        let vignetteRect = CGRect(x: 0, y: size.height * 0.35, width: size.width, height: size.height * 0.65)
        context.fill(
            Path(vignetteRect),
            with: .linearGradient(
                Gradient(colors: [Color.black.opacity(0), Color.black.opacity(scene.isNight ? 0.42 : 0.12)]),
                startPoint: CGPoint(x: size.width * 0.5, y: size.height * 0.35),
                endPoint: CGPoint(x: size.width * 0.5, y: size.height)
            )
        )
    }

    private func sceneShowsSun(_ scene: WeatherSceneKind) -> Bool {
        switch scene {
        case .sunny, .partlyCloudy, .live: return true
        default: return false
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
            return Color(red: 0.32, green: 0.62, blue: 0.98)
        case .cloudy:
            return Color(red: 0.48, green: 0.56, blue: 0.68)
        case .rain, .thunderstorm, .isolatedThunder:
            return Color(red: 0.22, green: 0.28, blue: 0.38)
        case .nightClear, .nightPartlyCloudy, .nightCloudy, .nightRain, .nightThunderstorm, .nightIsolatedThunder:
            return Color(red: 0.04, green: 0.06, blue: 0.18)
        case .live:
            return Color(red: 0.28, green: 0.55, blue: 0.94)
        }
    }

    private var skyMidColor: Color {
        switch scene {
        case .sunny, .partlyCloudy:
            return Color(red: 0.55, green: 0.78, blue: 0.99)
        case .cloudy:
            return Color(red: 0.58, green: 0.64, blue: 0.74)
        case .rain, .thunderstorm, .isolatedThunder:
            return Color(red: 0.34, green: 0.4, blue: 0.5)
        case .nightClear, .nightPartlyCloudy, .nightCloudy, .nightRain, .nightThunderstorm, .nightIsolatedThunder:
            return Color(red: 0.08, green: 0.1, blue: 0.26)
        case .live:
            return Color(red: 0.5, green: 0.72, blue: 0.96)
        }
    }

    private var skyBottomColor: Color {
        switch scene {
        case .sunny:
            return Color(red: 0.82, green: 0.92, blue: 0.99)
        case .partlyCloudy:
            return Color(red: 0.76, green: 0.86, blue: 0.97)
        case .cloudy:
            return Color(red: 0.72, green: 0.76, blue: 0.82)
        case .rain, .thunderstorm, .isolatedThunder:
            return Color(red: 0.42, green: 0.46, blue: 0.52)
        case .nightClear:
            return Color(red: 0.1, green: 0.12, blue: 0.32)
        case .nightPartlyCloudy, .nightCloudy:
            return Color(red: 0.08, green: 0.1, blue: 0.22)
        case .nightRain, .nightThunderstorm, .nightIsolatedThunder:
            return Color(red: 0.06, green: 0.08, blue: 0.16)
        case .live:
            return Color(red: 0.74, green: 0.86, blue: 0.96)
        }
    }

    private func drawSun(context: inout GraphicsContext, size: CGSize, t: TimeInterval, scale: CGFloat) {
        let cx = size.width * 0.78
        let cy = size.height * (0.12 / scale + 0.08)
        let r: CGFloat = 36 * scale
        let glow = Path(ellipseIn: CGRect(x: cx - r * 1.8, y: cy - r * 1.8, width: r * 3.6, height: r * 3.6))
        context.fill(
            glow,
            with: .radialGradient(
                Gradient(colors: [Color.yellow.opacity(0.45), Color.orange.opacity(0.08), Color.clear]),
                center: CGPoint(x: cx, y: cy),
                startRadius: r * 0.2,
                endRadius: r * 2.4
            )
        )
        let disc = Path(ellipseIn: CGRect(x: cx - r, y: cy - r, width: r * 2, height: r * 2))
        context.fill(
            disc,
            with: .radialGradient(
                Gradient(colors: [Color(red: 1, green: 0.98, blue: 0.85), Color(red: 1, green: 0.85, blue: 0.35)]),
                center: CGPoint(x: cx - r * 0.15, y: cy - r * 0.15),
                startRadius: 0,
                endRadius: r * 1.1
            )
        )
    }

    private func drawMoon(context: inout GraphicsContext, size: CGSize, scale: CGFloat) {
        let cx = size.width * 0.82
        let cy = size.height * 0.11
        let r: CGFloat = 30 * scale
        let glow = Path(ellipseIn: CGRect(x: cx - r * 1.5, y: cy - r * 1.5, width: r * 3, height: r * 3))
        context.fill(
            glow,
            with: .radialGradient(
                Gradient(colors: [Color.cyan.opacity(0.12), Color.blue.opacity(0.04), Color.clear]),
                center: CGPoint(x: cx, y: cy),
                startRadius: r * 0.2,
                endRadius: r * 2.2
            )
        )
        let disc = Path(ellipseIn: CGRect(x: cx - r, y: cy - r, width: r * 2, height: r * 2))
        context.fill(
            disc,
            with: .radialGradient(
                Gradient(colors: [Color(white: 0.98), Color(white: 0.88), Color(white: 0.72).opacity(0.85)]),
                center: CGPoint(x: cx - r * 0.12, y: cy - r * 0.1),
                startRadius: 0,
                endRadius: r * 1.08
            )
        )
    }

    private func drawStars(context: inout GraphicsContext, size: CGSize, t: TimeInterval) {
        for i in 0 ..< 42 {
            let u = hash01(UInt32(i * 2 + 1), seed: UInt32(scene.hashValue & 0xFFFF) &+ 9)
            let v = hash01(UInt32(i * 2 + 2), seed: UInt32(scene.hashValue & 0xFFFF) &+ 99)
            let sx = u * size.width
            let sy = v * size.height * 0.52
            let twinkle = 0.55 + 0.45 * sin(t * 1.4 + Double(i) * 0.7)
            let pr = CGFloat(hash01(UInt32(i + 50), seed: 3)) * 1.4 + 0.35
            context.fill(
                Path(ellipseIn: CGRect(x: sx, y: sy, width: pr, height: pr)),
                with: .color(Color.white.opacity(0.25 + twinkle * 0.45))
            )
        }
    }

    private func drawCloudLayer(
        context: inout GraphicsContext,
        size: CGSize,
        drift: CGFloat,
        opacity: CGFloat,
        scale: CGFloat,
        vertical: CGFloat
    ) {
        let baseY = size.height * vertical
        let h = size.height * 0.16 * scale
        let r = h * 0.58
        let strideX = r * 3.9
        let phase = (drift.truncatingRemainder(dividingBy: 1)) * strideX
        var x = -strideX * 3 + phase
        while x < size.width + strideX * 3 {
            let blob = Path { p in
                p.addEllipse(in: CGRect(x: x, y: baseY, width: r * 2.35, height: r * 1.65))
                p.addEllipse(in: CGRect(x: x + r * 1.35, y: baseY - r * 0.18, width: r * 2.55, height: r * 1.75))
                p.addEllipse(in: CGRect(x: x + r * 2.85, y: baseY, width: r * 2.2, height: r * 1.6))
            }
            context.fill(blob, with: .color(Color.white.opacity(Double(opacity))))
            x += strideX
        }
    }

    /// Wide-screen rain: x from scrambled hash (not linear index), slight wind angle.
    private func drawRain(context: inout GraphicsContext, size: CGSize, t: TimeInterval, scale: CGFloat) {
        let count = Int((size.width / 7 + size.height / 55) * scale) + 28
        let fall = size.height + 40
        let wind: CGFloat = 10 * scale
        let seedU = UInt32(rainSeed.rounded())
        for i in 0 ..< count {
            let u = hash01(UInt32(i &* 0x9E3779B9), seed: seedU &+ UInt32(i << 3))
            let x = u * (size.width + wind) - wind * 0.35
            let speed = 1.35 + hash01(UInt32(i &+ 17), seed: seedU) * 0.9
            let phase = hash01(UInt32(i &* 31), seed: seedU &+ 1)
            let offset = (t * speed + Double(phase) * 17 + Double(rainSeed) * 0.001).truncatingRemainder(dividingBy: 1)
            let y = CGFloat(offset) * fall - 20
            let len: CGFloat = (14 + CGFloat(i % 5) * 2) * scale
            var p = Path()
            p.move(to: CGPoint(x: x, y: y))
            p.addLine(to: CGPoint(x: x + wind * 0.08, y: y + len))
            let op = 0.08 + Double(i % 5) * 0.035
            context.stroke(p, with: .color(Color.white.opacity(op)), lineWidth: CGFloat(1 + (i % 3)) * 0.45 * scale)
        }
    }

    private func hash01(_ i: UInt32, seed: UInt32) -> CGFloat {
        var x = UInt64(i) &* 0x9E3779B97F4A7C15 &+ UInt64(seed)
        x ^= x >> 33
        x &*= 0xff51afd7ed558ccd
        x ^= x >> 33
        return CGFloat(Double(x & 0xFFFF_FFFF) / Double(0xFFFF_FFFF))
    }
}
