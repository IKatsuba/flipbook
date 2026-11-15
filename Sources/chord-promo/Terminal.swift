import Flipbook
import SwiftUI

/// chord's dark theme, from its `src/ui/theme/theme.ts`.
enum Theme {
    static func hex(_ value: UInt32) -> Color {
        Color(red: Double((value >> 16) & 0xFF) / 255, green: Double((value >> 8) & 0xFF) / 255, blue: Double(value & 0xFF) / 255)
    }

    static let window = hex(0x16171B)
    static let text = hex(0xE6E6E6)
    static let dim = hex(0x8F96A0)
    static let accent = hex(0x47E7A5)
    static let permission = hex(0xB1B9F9)
    static let warning = hex(0xFFC107)
    static let success = hex(0x4EBA65)
    static let link = hex(0x8CC8FF)
    static let keyword = hex(0xD7A6FF)
    static let string = hex(0xF2D38A)
    static let title = hex(0x8CC8FF)
    static let type = hex(0x7FE0E8)
    static let added = hex(0x86E08A)
    static let removed = hex(0xFF8E8E)
    static let addedTint = hex(0x1F3B24)
    static let removedTint = hex(0x4A1F27)
    static let agents = [hex(0x6CB6FF), hex(0xC49CFF), hex(0x56D4DD), hex(0x7CCF7F)]
    static let markStops = [(0.0, 0xD2FFE4), (0.55, 0x3FDC9C), (1.0, 0x0A7470)] as [(Double, UInt32)]

    /// The mark's diagonal gradient, interpolated in sRGB as the terminal does.
    static func mark(_ t: Double) -> Color {
        let (a, b) = t < 0.55 ? (markStops[0], markStops[1]) : (markStops[1], markStops[2])
        let u = (t - a.0) / (b.0 - a.0)
        func channel(_ shift: UInt32) -> Double {
            let (x, y) = (Double((a.1 >> shift) & 0xFF), Double((b.1 >> shift) & 0xFF))
            return (x + (y - x) * u) / 255
        }
        return Color(red: channel(16), green: channel(8), blue: channel(0))
    }

    static let fontSize: CGFloat = 20
    static let lineHeight: CGFloat = 28
    static let mono = Font.custom("JetBrainsMono-Regular", fixedSize: fontSize)
    static let monoBold = Font.custom("JetBrainsMono-Bold", fixedSize: fontSize)
}

/// The shape of the video: 1920×1080, or 1080×1920 with a narrower terminal and the caption above it.
/// Set once, before the composition is made.
enum Stage {
    nonisolated(unsafe) static var vertical = false
    static var size: CGSize { vertical ? CGSize(width: 1080, height: 1920) : CGSize(width: 1920, height: 1080) }
    nonisolated(unsafe) static var scale = 1
    /// A length snapped to whole pixels. Text layers sit on whole pixels anyway; an offset that is
    /// not would make them round one way while moving and the other at rest.
    static func px(_ points: Double) -> CGFloat { CGFloat((points * Double(scale)).rounded() / Double(scale)) }
    /// Terminal columns inside the window.
    static var columns: Int { vertical ? 77 : 122 }
}

/// A run of terminal text in one style.
struct Seg {
    var text: String
    var color: Color = Theme.text
    var bold = false
}

func s(_ text: String, _ color: Color = Theme.text, bold: Bool = false) -> Seg { Seg(text: text, color: color, bold: bold) }
func dim(_ text: String) -> Seg { Seg(text: text, color: Theme.dim) }

/// One terminal row.
struct Line: Identifiable {
    var id: Int = 0
    var segs: [Seg]
    var tint: Color?
    var opacity: Double = 1

    init(_ segs: Seg..., tint: Color? = nil, opacity: Double = 1) {
        self.segs = segs
        self.tint = tint
        self.opacity = opacity
    }

    static let blank = Line(s(" "))
}

struct LineView: View {
    let line: Line

    var body: some View {
        Text(line.segs.reduce(into: AttributedString()) { result, seg in
            var run = AttributedString(seg.text)
            run.foregroundColor = seg.color
            run.font = seg.bold ? Theme.monoBold : Theme.mono
            result.append(run)
        })
        .lineLimit(1)
        .fixedSize()
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: Theme.lineHeight)
        .background(line.tint ?? .clear)
        .opacity(line.opacity)
    }
}

struct Lines: View {
    let lines: [Line]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in LineView(line: line) }
        }
    }
}

/// Characters of `text` typed by this frame, starting at `start`, one every `per` frames.
func typed(_ text: String, _ frame: Frame, from start: Int, per: Double = 1.4) -> String {
    let count = Int(frame.interpolate([Double(start), Double(start) + Double(text.count) * per], [0, Double(text.count)]))
    return String(text.prefix(count))
}

/// Breaks `text` into rows of at most `width` characters, at spaces.
func wrap(_ text: String, width: Int) -> [String] {
    var rows: [String] = []
    var row = ""
    for word in text.split(separator: " ") {
        if !row.isEmpty, row.count + 1 + word.count > width {
            rows.append(row)
            row = String(word)
        } else {
            row += (row.isEmpty ? "" : " ") + word
        }
    }
    if !row.isEmpty { rows.append(row) }
    return rows
}

/// The prompt box, with a block cursor after what has been typed.
struct PromptBox: View {
    var text = ""
    var cursor = true

    var body: some View {
        HStack(spacing: 0) {
            LineView(line: Line(dim("› "), s(text))).fixedSize()
            Rectangle().fill(Theme.text).frame(width: 11, height: 22).opacity(cursor ? 1 : 0)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .frame(height: 54)
        .overlay(RoundedRectangle(cornerRadius: 4).stroke(Theme.dim.opacity(0.8), lineWidth: 1.5))
    }
}

/// The status row under the prompt: a note on the left, the model on the right.
struct StatusRow: View {
    var left: [Seg] = [dim("? for shortcuts")]
    var right = "Claude Opus 5.5 · medium effort · ~1% context used"

    var body: some View {
        HStack(spacing: 0) {
            LineView(line: Line(segs: left)).fixedSize()
            Spacer(minLength: 0)
            LineView(line: Line(dim(right))).fixedSize()
        }
        .padding(.horizontal, 16)
    }
}

/// The window chord runs in.
struct TerminalWindow<Content: View>: View {
    @ViewBuilder var content: Content

    static var size: CGSize { Stage.vertical ? CGSize(width: 1000, height: 1180) : CGSize(width: 1560, height: 830) }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 9) {
                ForEach([0xFF5F57, 0xFEBC2E, 0x28C840] as [UInt32], id: \.self) { colour in
                    Circle().fill(Theme.hex(colour)).frame(width: 14, height: 14)
                }
                Text("chord")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.92))
                    .padding(.leading, 14)
                Spacer()
            }
            .padding(.horizontal, 26)
            .frame(height: 52)

            content
                .padding(.horizontal, 34)
                .padding(.bottom, 26)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .background(Theme.window, in: RoundedRectangle(cornerRadius: 26))
        .overlay(RoundedRectangle(cornerRadius: 29).strokeBorder(.white.opacity(0.22), lineWidth: 5).padding(-5))
        .shadow(color: .black.opacity(0.35), radius: 40, y: 24)
    }
}

extension Line {
    init(segs: [Seg]) {
        self.segs = segs
    }
}
