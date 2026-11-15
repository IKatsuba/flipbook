import Flipbook
import SwiftUI

/// The demo is a page of a flip book: ruled paper, ink, one red.
enum Palette {
    static let paper = Color(red: 0.949, green: 0.925, blue: 0.882)
    static let paperTop = Color(red: 0.965, green: 0.945, blue: 0.906)
    static let paperBottom = Color(red: 0.929, green: 0.902, blue: 0.847)
    static let ink = Color(red: 0.106, green: 0.098, blue: 0.082)
    static let red = Color(red: 0.898, green: 0.263, blue: 0.169)
    static let dim = ink.opacity(0.58)
}

struct Backdrop: View {
    let frame: Frame

    var body: some View {
        ZStack {
            LinearGradient(colors: [Palette.paperTop, Palette.paperBottom], startPoint: .top, endPoint: .bottom)
            // Ruled lines and a margin, as in an exercise book.
            Canvas(rendersAsynchronously: false) { context, size in
                var rules = Path()
                for y in stride(from: 54.0, through: size.height, by: 54) {
                    rules.move(to: CGPoint(x: 0, y: y))
                    rules.addLine(to: CGPoint(x: size.width, y: y))
                }
                context.stroke(rules, with: .color(Palette.ink.opacity(0.07)), lineWidth: 1)
                var margin = Path()
                margin.move(to: CGPoint(x: 60, y: 0))
                margin.addLine(to: CGPoint(x: 60, y: size.height))
                context.stroke(margin, with: .color(Palette.red.opacity(0.35)), lineWidth: 1.5)
            }
            .opacity(frame.interpolate([0, 40], [0, 1], easing: .easeOut))
        }
    }
}

struct Headline: View {
    let title: String
    let accent: String
    let frame: Frame

    static let font = Font.system(size: 132, weight: .bold, design: .serif)

    var body: some View {
        VStack(alignment: .leading, spacing: -10) {
            // The first line rides a spring up into place.
            let rise = frame.spring(from: 30, stiffness: 120, damping: 14, settle: 60)
            Text(title)
                .foregroundStyle(Palette.ink)
                .offset(y: frame.snap(90 * (1 - rise)))
                .opacity(frame.interpolate([30, 48], [0, 1], easing: .easeOut))

            // The second is typed, one character every four frames.
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
                                .fill(Palette.red)
                                .frame(width: 8, height: 118)
                                .offset(x: 16)
                                .opacity(frame.index >= 60 && cursorOn ? 1 : 0)
                        }
                }
        }
        .font(Headline.font)
        .tracking(-3)
    }

    private func typedText(_ text: String, count: Int) -> Text {
        var string = AttributedString(text)
        string.foregroundColor = Palette.red
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

            VStack(alignment: .leading, spacing: 30) {
                Text("FLIPBOOK · DEMO")
                    .font(.system(size: 28, weight: .semibold, design: .monospaced))
                    .tracking(5)
                    .foregroundStyle(Palette.red)
                    .opacity(frame.interpolate([10, 30], [0, 1], easing: .easeOut))
                    .offset(x: frame.snap(frame.interpolate([10, 30], [-24, 0], easing: .easeOut)))

                Headline(title: title, accent: accent, frame: frame)
            }
            .padding(.horizontal, 96)

            // The foot of the page: how far through, and the page number, which is the frame.
            VStack(alignment: .leading, spacing: 18) {
                Spacer()
                Rectangle()
                    .fill(Palette.ink.opacity(0.14))
                    .frame(height: 2)
                    .overlay(alignment: .leading) {
                        Rectangle().fill(Palette.red).frame(width: (1080 - 192) * frame.progress)
                    }
                HStack {
                    Text(String(format: "%.2f s", frame.time))
                    Spacer()
                    Text(String(format: "p. %03d", frame.index))
                }
                .font(.system(size: 22, weight: .medium, design: .monospaced))
                .foregroundStyle(Palette.dim)
            }
            .padding(.horizontal, 96)
            .padding(.vertical, 84)
            .opacity(frame.interpolate([20, 40], [0, 1]))
        }
        // Fade the whole page up from blank paper.
        .opacity(Card.fade(frame))
        .background(showsBackdrop ? Palette.paper : .clear)
    }
}

/// The backdrop again, as a fragment shader: the same paper, rules and margin.
let metalBackdrop = MetalBackdrop(
    source: """
    float4 backdrop(float2 point, Uniforms u) {
        float3 blank = float3(0.949, 0.925, 0.882);
        float3 color = mix(float3(0.965, 0.945, 0.906), float3(0.929, 0.902, 0.847), point.y / u.size.y);
        float rule = (point.y > 53.0 && fmod(point.y + 0.5, 54.0) < 1.0) ? 0.07 * u.params[1] : 0.0;
        color = mix(color, float3(0.106, 0.098, 0.082), rule);
        float margin = (fabs(point.x - 60.0) < 0.75) ? 0.35 * u.params[1] : 0.0;
        color = mix(color, float3(0.898, 0.263, 0.169), margin);
        return float4(mix(blank, color, u.params[0]), 1.0);
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
        Card(title: "Every frame", accent: "on its own.", frame: frame, showsBackdrop: !useMetal && !transparent)
    }
    composition.transparent = transparent
    if useMetal { composition.backdrop = metalBackdrop }
    return composition
}
