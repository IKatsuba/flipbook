import Flipbook
import SwiftUI

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
            let rise = frame.spring(from: 30, stiffness: 120, damping: 14, settle: 60)
            Text(title)
                .foregroundStyle(.white)
                .offset(y: frame.snap(90 * (1 - rise)))
                .opacity(frame.interpolate([30, 48], [0, 1], easing: .easeOut))

            // "changelogs" is typed, one character every four frames.
            let typed = frame.typed(accent, from: 70, per: 4).count
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
                    .offset(x: frame.snap(frame.interpolate([10, 30], [-24, 0], easing: .easeOut)))

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

/// The backdrop again, as a fragment shader: same colours, glow and grid.
let metalBackdrop = MetalBackdrop(
    source: """
    float4 backdrop(float2 point, Uniforms u) {
        float3 color = float3(0.039, 0.039, 0.059);
        float glow = 0.22 * saturate(1.0 - distance(point, float2(0.85, 0.1) * u.size) / 900.0);
        color = mix(color, float3(1.0, 0.31, 0.64), glow);
        float2 cell = fmod(point + 0.5, 54.0);
        float line = (cell.x < 1.0 || cell.y < 1.0) ? 0.06 * u.params[1] : 0.0;
        color = mix(color, float3(1.0), line);
        return float4(color * u.params[0], 1.0);
    }
    """,
    params: { frame in
        [Float(Card.fade(frame)), Float(frame.interpolate([0, 40], [0, 1], easing: .easeOut))]
    }
)

@MainActor
func demoComposition(
    width: Int = 1080, height: Int = 1350, scale: Int, frames: Int = 360, metalBackdrop useMetal: Bool = false,
    transparent: Bool = false
) -> Composition<Card> {
    var composition = Composition(width: width, height: height, fps: 60, frames: frames, scale: scale) { frame in
        Card(title: "Make", accent: "changelogs", frame: frame, showsBackdrop: !useMetal && !transparent)
    }
    composition.transparent = transparent
    if useMetal { composition.backdrop = metalBackdrop }
    return composition
}
