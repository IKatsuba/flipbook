import Flipbook
import SwiftUI

/// Flipbook's own look: a paper flip book. Warm paper, ink, one red, serif headlines,
/// and a page number in the corner that is the frame number.
enum Look {
    static func hex(_ value: UInt32) -> Color {
        Color(red: Double((value >> 16) & 0xFF) / 255, green: Double((value >> 8) & 0xFF) / 255, blue: Double(value & 0xFF) / 255)
    }

    static let paper = hex(0xF2ECE1)
    static let sheet = hex(0xFFFCF6)
    static let ink = hex(0x1B1915)
    static let accent = hex(0xE5432B)
    static let dim = ink.opacity(0.58)
    static let faint = ink.opacity(0.16)
    static let keyword = hex(0xC2331D)
    static let string = hex(0x7A5C00)
    static let number = hex(0xA94800)
    static let type = hex(0x0E7C86)
    static let call = hex(0x1F5FBF)

    static func mono(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }

    static func serif(_ size: CGFloat, _ weight: Font.Weight = .bold) -> Font {
        .system(size: size, weight: weight, design: .serif)
    }
}

/// The sheet everything is drawn on: paper, a hairline margin, and in the corner the page number,
/// which is the number of the frame being drawn.
struct Backdrop: View {
    let frame: Frame

    var body: some View {
        ZStack {
            Look.paper
            RoundedRectangle(cornerRadius: 6).strokeBorder(Look.faint, lineWidth: 1.5).padding(36)
            VStack {
                HStack {
                    Text("FLIPBOOK").tracking(5)
                    Spacer()
                    Text("1.2.0")
                }
                Spacer()
                HStack {
                    Text(String(format: "%.2f s", frame.time))
                    Spacer()
                    Text(String(format: "p. %04d", frame.index))
                }
            }
            .font(Look.mono(18, .medium))
            .foregroundStyle(Look.dim)
            .padding(.horizontal, 64)
            .padding(.vertical, 56)
        }
    }
}

/// A small monospace label over a large serif headline: the top of every scene.
struct Heading: View {
    let kicker: String
    let title: String
    let frame: Frame

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(kicker)
                .font(Look.mono(24, .semibold))
                .tracking(5)
                .foregroundStyle(Look.accent)
                .opacity(frame.interpolate([4, 18], [0, 1]))
            Text(title)
                .font(Look.serif(80, .bold))
                .tracking(-1.5)
                .foregroundStyle(Look.ink)
                .offset(y: frame.snap(30 * (1 - frame.spring(from: 8, stiffness: 150, damping: 20, settle: 40))))
                .opacity(frame.interpolate([8, 24], [0, 1]))
        }
    }
}

/// A sheet of paper lying on the page.
struct Panel<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            // The shadow belongs to the sheet alone: on the whole panel, every text layer in it gets one too.
            .background(RoundedRectangle(cornerRadius: 10).fill(Look.sheet).shadow(color: Look.ink.opacity(0.10), radius: 18, y: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Look.faint, lineWidth: 1.5))
    }
}

/// One page of the flip book: a ball somewhere on its arc.
struct Page: View {
    /// 0 to 1 along the bounce.
    let phase: Double
    var label: String?
    var size = CGSize(width: 190, height: 240)

    var body: some View {
        let x = (phase - 0.5) * size.width * 0.62
        let y = size.height * 0.24 - size.height * 0.52 * 4 * phase * (1 - phase)
        ZStack {
            RoundedRectangle(cornerRadius: 8).fill(Look.sheet).shadow(color: Look.ink.opacity(0.12), radius: 10, y: 6)
            RoundedRectangle(cornerRadius: 8).strokeBorder(Look.faint, lineWidth: 1.5)
            // The ground the ball bounces on.
            Rectangle().fill(Look.faint).frame(width: size.width * 0.72, height: 1.5).offset(y: size.height * 0.24 + size.width * 0.085)
            Circle().fill(Look.accent).frame(width: size.width * 0.17, height: size.width * 0.17).offset(x: x, y: y)
            if let label {
                Text(label).font(Look.mono(15)).foregroundStyle(Look.dim).offset(y: size.height / 2 - 24)
            }
        }
        .frame(width: size.width, height: size.height)
    }
}

/// Code with colours, typed in: as many characters as `count` allows, across the rows.
struct Code: View {
    typealias Token = (text: String, color: Color)
    let rows: [[Token]]
    var count = Int.max
    var size: CGFloat = 26

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(0..<rows.count, id: \.self) { index in
                Text(row(index))
                    .font(Look.mono(size))
                    .lineLimit(1)
                    .fixedSize()
                    .frame(height: size * 1.55, alignment: .leading)
            }
        }
    }

    private func row(_ index: Int) -> AttributedString {
        var left = count - rows[..<index].reduce(0) { $0 + $1.reduce(0) { $0 + $1.text.count } }
        var result = AttributedString(" ")
        for token in rows[index] where left > 0 {
            var run = AttributedString(String(token.text.prefix(left)))
            run.foregroundColor = token.color
            result.append(run)
            left -= token.text.count
        }
        return result
    }

    var length: Int { rows.reduce(0) { $0 + $1.reduce(0) { $0 + $1.text.count } } }
}
