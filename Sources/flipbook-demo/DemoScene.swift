import Flipbook
import SwiftUI

/// SplitMix64: a tiny seedable generator, so "random" grain is a function of the frame number.
struct SplitMix64: RandomNumberGenerator {
    var state: UInt64
    init(seed: UInt64) { state = seed &+ 0x9E37_79B9_7F4A_7C15 }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

enum Grain {
    static let side = 512

    /// White noise with random alpha, generated once before rendering starts.
    static let tile: CGImage = {
        var generator = SplitMix64(seed: 0xF11B_B00C)
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        for i in 0..<(side * side) {
            let alpha = UInt8(truncatingIfNeeded: generator.next() % 40)
            pixels[i * 4 + 0] = alpha
            pixels[i * 4 + 1] = alpha
            pixels[i * 4 + 2] = alpha
            pixels[i * 4 + 3] = alpha
        }
        let provider = CGDataProvider(data: Data(pixels) as CFData)!
        return CGImage(
            width: side, height: side, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: side * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent
        )!
    }()

    /// Where the tile sits on a given frame.
    static func offset(frame: Int) -> CGPoint {
        var generator = SplitMix64(seed: UInt64(frame))
        return CGPoint(x: -Double(generator.next() % UInt64(side)), y: -Double(generator.next() % UInt64(side)))
    }
}

enum Palette {
    static let background = Color(red: 0.039, green: 0.039, blue: 0.059)
    static let pink = Color(red: 1.0, green: 0.31, blue: 0.64)
    static let dim = Color.white.opacity(0.55)
}

struct Backdrop: View {
    let frame: Frame

    var body: some View {
        ZStack {
            Palette.background
            RadialGradient(
                colors: [Palette.pink.opacity(0.22), .clear],
                center: UnitPoint(x: 0.85, y: 0.1), startRadius: 0, endRadius: 900
            )
            Canvas(rendersAsynchronously: false) { context, size in
                var lines = Path()
                let step = 54.0
                for x in stride(from: 0.0, through: size.width, by: step) {
                    lines.move(to: CGPoint(x: x, y: 0))
                    lines.addLine(to: CGPoint(x: x, y: size.height))
                }
                for y in stride(from: 0.0, through: size.height, by: step) {
                    lines.move(to: CGPoint(x: 0, y: y))
                    lines.addLine(to: CGPoint(x: size.width, y: y))
                }
                context.stroke(lines, with: .color(.white.opacity(0.06)), lineWidth: 1)
            }
            .opacity(frame.interpolate([0, 40], [0, 1], easing: .easeOut))
            Canvas(rendersAsynchronously: false) { context, size in
                context.fill(
                    Path(CGRect(origin: .zero, size: size)),
                    with: .tiledImage(Image(decorative: Grain.tile, scale: 1), origin: Grain.offset(frame: frame.index))
                )
            }
        }
    }
}

struct Headline: View {
    let title: String
    let accent: String
    let frame: Frame

    static let font = Font.system(size: 150, weight: .heavy)

    var body: some View {
        VStack(alignment: .leading, spacing: -18) {
            // "Make" rides a spring up into place.
            let rise = frame.spring(from: 30, stiffness: 120, damping: 14)
            Text(title)
                .foregroundStyle(.white)
                .offset(y: 90 * (1 - rise))
                .opacity(frame.interpolate([30, 48], [0, 1], easing: .easeOut))

            // "changelogs" is typed, one character every four frames.
            let typed = Int(frame.interpolate([70, 70 + Double(accent.count) * 4], [0, Double(accent.count)]))
            let typing = typed < accent.count
            let cursorOn = typing || frame.loop(duration: 60).index < 30
            typedText(accent, count: typed)
                .overlay(alignment: .bottomLeading) {
                    // Hidden copy of the typed prefix, so the cursor sits right after it.
                    Text(String(accent.prefix(typed)))
                        .hidden()
                        .overlay(alignment: .trailing) {
                            Rectangle()
                                .fill(Palette.pink)
                                .frame(width: 10, height: 132)
                                .offset(x: 18)
                                .opacity(frame.index >= 60 && cursorOn ? 1 : 0)
                        }
                }
        }
        .font(Headline.font)
        .tracking(-5)
    }

    private func typedText(_ text: String, count: Int) -> Text {
        var string = AttributedString(text)
        string.foregroundColor = Palette.pink
        if count < text.count {
            let cut = string.index(string.startIndex, offsetByCharacters: count)
            string[cut...].foregroundColor = .clear
        }
        return Text(string)
    }
}

struct Card: View {
    static func fade(_ frame: Frame) -> Double { frame.interpolate([0, 12], [0, 1], easing: .easeOut) }

    var title: String
    var accent: String
    var frame: Frame
    /// Off when a Metal backdrop is drawn underneath instead.
    var showsBackdrop = true

    var body: some View {
        ZStack(alignment: .leading) {
            if showsBackdrop { Backdrop(frame: frame) }

            VStack(alignment: .leading, spacing: 36) {
                Text("NEW · plugins/render")
                    .font(.system(size: 30, weight: .medium, design: .monospaced))
                    .tracking(3)
                    .foregroundStyle(Palette.dim)
                    .opacity(frame.interpolate([10, 30], [0, 1], easing: .easeOut))
                    .offset(x: frame.interpolate([10, 30], [-24, 0], easing: .easeOut))

                Headline(title: title, accent: accent, frame: frame)
            }
            .padding(.horizontal, 84)

            VStack(alignment: .leading, spacing: 18) {
                Spacer()
                Rectangle()
                    .fill(.white.opacity(0.12))
                    .frame(height: 2)
                    .overlay(alignment: .leading) {
                        Rectangle().fill(Palette.pink).frame(width: (1080 - 168) * frame.progress)
                    }
                Text("flipbook · frame \(String(format: "%03d", frame.index)) · \(String(format: "%.2f", frame.time))s")
                    .font(.system(size: 22, design: .monospaced))
                    .foregroundStyle(Palette.dim)
            }
            .padding(84)
            .opacity(frame.interpolate([20, 40], [0, 1]))
        }
        // Fade the whole card up from black.
        .opacity(Card.fade(frame))
        .background(showsBackdrop ? Color.black : .clear)
    }
}

/// The backdrop again, as a fragment shader: same colours, glow and grid, and hashed noise for grain.
let metalBackdrop = MetalBackdrop(
    source: """
    static float grain(uint2 p, uint frame) {
        uint h = p.x * 374761393u + p.y * 668265263u + frame * 2246822519u;
        h = (h ^ (h >> 13)) * 1274126177u;
        h ^= h >> 16;
        return float(h % 40u) / 255.0;
    }

    float4 backdrop(float2 point, Uniforms u) {
        float3 color = float3(0.039, 0.039, 0.059);
        float glow = 0.22 * saturate(1.0 - distance(point, float2(0.85, 0.1) * u.size) / 900.0);
        color = mix(color, float3(1.0, 0.31, 0.64), glow);
        float2 cell = fmod(point + 0.5, 54.0);
        float line = (cell.x < 1.0 || cell.y < 1.0) ? 0.06 * u.params[1] : 0.0;
        color = mix(color, float3(1.0), line);
        float noise = grain(uint2(point), uint(u.frame));
        color = color * (1.0 - noise) + noise;
        return float4(color * u.params[0], 1.0);
    }
    """,
    params: { frame in
        [Float(Card.fade(frame)), Float(frame.interpolate([0, 40], [0, 1], easing: .easeOut))]
    }
)

@MainActor
func demoComposition(scale: Int, frames: Int = 360, metalBackdrop useMetal: Bool = false) -> Composition<Card> {
    // Touch the grain before the first frame: nothing may be loaded lazily mid-render.
    _ = Grain.tile
    var composition = Composition(width: 1080, height: 1350, fps: 60, frames: frames, scale: scale) { frame in
        Card(title: "Make", accent: "changelogs", frame: frame, showsBackdrop: !useMetal)
    }
    if useMetal { composition.backdrop = metalBackdrop }
    return composition
}
