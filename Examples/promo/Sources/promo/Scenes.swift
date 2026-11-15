import Flipbook
import SwiftUI

/// Where each scene starts and how long it lasts, in frames at 60 fps.
enum Timeline {
    static let intro = (from: 0, duration: 210)
    static let code = (from: 210, duration: 450)
    static let motion = (from: 660, duration: 300)
    static let pure = (from: 960, duration: 270)
    static let speed = (from: 1230, duration: 270)
    static let outro = (from: 1500, duration: 240)
    static let frames = 1740
}

// MARK: Intro

/// Six pages fanned out, each a frame of a bouncing ball; they close into one book that plays.
struct Intro: View {
    let frame: Frame

    var body: some View {
        let closed = frame.spring(from: 70, stiffness: 90, damping: 16, settle: 60)
        let playing = frame.loop(duration: 48).progress
        VStack(spacing: 0) {
            ZStack {
                ForEach(0..<6, id: \.self) { index in
                    let spread = (Double(index) - 2.5) * (1 - closed)
                    let arrive = frame.spring(from: 6 + index * 5, stiffness: 180, damping: 17, settle: 40)
                    // Fanned out, each page is its own frame; closed, the top one plays them all.
                    let phase = closed < 1 ? Double(index) / 5 : playing
                    Page(phase: phase, label: closed < 0.5 ? String(format: "frame %03d", index * 8) : nil, size: CGSize(width: 230, height: 290))
                        .rotationEffect(.degrees(spread * 5))
                        .offset(x: frame.snap(spread * 262), y: frame.snap(abs(spread) * 14 + 60 * (1 - arrive)))
                        .opacity(frame.interpolate([Double(6 + index * 5), Double(16 + index * 5)], [0, 1]))
                }
            }
            .frame(height: 360)

            Text("Flipbook")
                .font(Look.serif(170, .black))
                .tracking(-4)
                .foregroundStyle(Look.ink)
                .padding(.top, 50)
                .offset(y: frame.snap(40 * (1 - frame.spring(from: 96, stiffness: 140, damping: 18, settle: 45))))
                .opacity(frame.interpolate([96, 114], [0, 1]))

            Text(frame.typed("Videos from SwiftUI views.", from: 126, per: 1.6) + " ")
                .font(Look.mono(40))
                .foregroundStyle(Look.dim)
                .frame(width: 660, alignment: .leading)
                .lineLimit(1)
                .padding(.top, 8)
        }
        .modifier(Flick(frame: frame))
    }
}

// MARK: Code and its result

struct CodeScene: View {
    let frame: Frame

    static let source: [[Code.Token]] = [
        [("let ", Look.keyword), ("comp = ", Look.ink), ("Composition", Look.type), ("(", Look.ink)],
        [("    width: ", Look.ink), ("1080", Look.number), (", height: ", Look.ink), ("1350", Look.number), (",", Look.ink)],
        [("    fps: ", Look.ink), ("60", Look.number), (", frames: ", Look.ink), ("120", Look.number)],
        [(") { frame ", Look.ink), ("in", Look.keyword)],
        [("    ", Look.ink), ("Text", Look.type), ("(", Look.ink), ("\"Hello\"", Look.string), (")", Look.ink)],
        [("        .", Look.ink), ("opacity", Look.call), ("(frame.", Look.ink), ("interpolate", Look.call), ("([", Look.ink), ("0", Look.number), (", ", Look.ink), ("20", Look.number), ("], [", Look.ink), ("0", Look.number), (", ", Look.ink), ("1", Look.number), ("]))", Look.ink)],
        [("        .", Look.ink), ("offset", Look.call), ("(y: ", Look.ink), ("60", Look.number), (" * (", Look.ink), ("1", Look.number), (" - frame.", Look.ink), ("spring", Look.call), ("()))", Look.ink)],
        [("}", Look.ink)],
        [("try await ", Look.keyword), ("comp.", Look.ink), ("video", Look.call), ("(to: url)", Look.ink)],
    ]

    /// The frame the little screen shows: played forward, then dragged back and forth,
    /// which only works because nothing in the view remembers anything.
    var shown: Frame {
        let index = frame.interpolate([250, 330, 362, 392, 422], [0, 119, 14, 70, 119], easing: .easeInOut)
        return Frame(index: Int(index.rounded()), fps: 60, frames: 120, scale: frame.scale)
    }

    var body: some View {
        let code = Code(rows: Self.source, count: frame.typed(String(repeating: " ", count: 400), from: 30, per: 0.55).count, size: 30)
        VStack(alignment: .leading, spacing: 56) {
            Heading(kicker: "ONE FUNCTION", title: "A video is a view of its frame number.", frame: frame)
            HStack(alignment: .top, spacing: 60) {
                Panel { code.padding(40).frame(width: 1060, height: 500, alignment: .topLeading) }
                screen
            }
        }
        .modifier(Flick(frame: frame))
    }

    var screen: some View {
        let shown = shown
        return VStack(spacing: 22) {
            Panel {
                Text("Hello")
                    .font(Look.serif(104, .bold))
                    .foregroundStyle(Look.ink)
                    .opacity(shown.interpolate([0, 20], [0, 1]))
                    .offset(y: frame.snap(60 * (1 - shown.spring())))
                    .frame(width: 560, height: 400)
            }
            // The scrubber: where on the timeline the screen is.
            VStack(alignment: .leading, spacing: 12) {
                ZStack(alignment: .leading) {
                    Capsule().fill(Look.faint).frame(width: 560, height: 6)
                    Capsule().fill(Look.accent).frame(width: 560 * shown.progress, height: 6)
                    Circle().fill(Look.ink).frame(width: 18, height: 18).offset(x: frame.snap(560 * shown.progress - 9))
                }
                Text(String(format: "frame %03d of 120", shown.index)).font(Look.mono(22)).foregroundStyle(Look.dim)
            }
        }
        .opacity(frame.interpolate([200, 230], [0, 1]))
    }
}

// MARK: Motion

/// A curve over one second with a dot riding it.
struct Curve: View {
    let label: String
    let value: (Double) -> Double
    /// 0 to 1 along the curve.
    let at: Double

    var body: some View {
        Panel {
            VStack(alignment: .leading, spacing: 18) {
                Text(label).font(Look.mono(21)).foregroundStyle(Look.dim)
                Canvas(rendersAsynchronously: false) { context, size in
                    // Leave headroom: a spring overshoots.
                    let point = { (t: Double) in CGPoint(x: t * size.width, y: size.height * (0.82 - 0.6 * value(t))) }
                    var guide = Path()
                    guide.move(to: CGPoint(x: 0, y: size.height * 0.22))
                    guide.addLine(to: CGPoint(x: size.width, y: size.height * 0.22))
                    context.stroke(guide, with: .color(Look.faint), style: StrokeStyle(lineWidth: 1.5, dash: [6, 8]))
                    var path = Path()
                    path.move(to: point(0))
                    for step in 1...120 where Double(step) / 120 <= at { path.addLine(to: point(Double(step) / 120)) }
                    context.stroke(path, with: .color(Look.ink), style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
                    let dot = point(at)
                    context.fill(Path(ellipseIn: CGRect(x: dot.x - 11, y: dot.y - 11, width: 22, height: 22)), with: .color(Look.accent))
                }
                .frame(height: 330)
            }
            .padding(30)
            .frame(width: 536)
        }
    }
}

struct MotionScene: View {
    let frame: Frame

    var body: some View {
        // The curves draw once, hold, and draw again.
        let at = frame.shift(by: 40).loop(duration: 130).interpolate([0, 90], [0, 1])
        VStack(alignment: .leading, spacing: 56) {
            Heading(kicker: "MOTION", title: "Springs and easing, solved per frame.", frame: frame)
            HStack(spacing: 36) {
                Curve(label: "interpolate(easing: .easeOut)", value: { Easing.easeOut.value($0) }, at: at)
                Curve(label: "spring(damping: 8)", value: { Frame.springValue(at: $0 * 1.5, damping: 8) }, at: at)
                Curve(label: "interpolate(easing: .easeInOut)", value: { Easing.easeInOut.value($0) }, at: at)
            }
            .opacity(frame.interpolate([24, 44], [0, 1]))
            Text("No clocks, no state: frame 90 is the same however you get there.")
                .font(Look.serif(32, .regular))
                .foregroundStyle(Look.dim)
                .opacity(frame.interpolate([60, 80], [0, 1]))
        }
        .modifier(Flick(frame: frame))
    }
}

// MARK: Determinism

struct PureScene: View {
    let frame: Frame

    /// SHA-256 of the first frames of flipbook-demo, as two separate runs printed them.
    static let hashes = [
        "ee32ddd5ef4d2adb", "ade61dd89e1ae591", "683ab3e3396231c2", "80625bd317173621",
        "cf2d7d70b70e628b", "29c9d2ff7fc31fe9", "7f953d343f5eb933",
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 50) {
            Heading(kicker: "DETERMINISTIC", title: "Render it twice. Get the same bytes.", frame: frame)
            HStack(alignment: .top, spacing: 70) {
                column("first render", start: 40)
                column("second render", start: 100)
                VStack(alignment: .leading, spacing: 0) {
                    Text(" ").font(Look.mono(24)).frame(height: 54)
                    ForEach(0..<Self.hashes.count, id: \.self) { row in
                        Text("=")
                            .font(Look.mono(36, .bold))
                            .foregroundStyle(Look.accent)
                            .frame(height: 60)
                            .opacity(frame.interpolate([Double(108 + row * 7), Double(114 + row * 7)], [0, 1]))
                    }
                }
            }
            Text("SHA-256 of every pixel buffer, frame by frame.")
                .font(Look.serif(32, .regular))
                .foregroundStyle(Look.dim)
                .opacity(frame.interpolate([150, 170], [0, 1]))
        }
        .modifier(Flick(frame: frame))
    }

    func column(_ title: String, start: Int) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title).font(Look.mono(24, .medium)).foregroundStyle(Look.dim).frame(height: 54, alignment: .top)
            ForEach(0..<Self.hashes.count, id: \.self) { row in
                HStack(spacing: 28) {
                    Text(String(format: "%03d", row)).foregroundStyle(Look.dim)
                    Text(Self.hashes[row] + "…").foregroundStyle(Look.ink)
                }
                .font(Look.mono(36))
                .frame(height: 60)
                .opacity(frame.interpolate([Double(start + row * 7), Double(start + 6 + row * 7)], [0, 1]))
            }
        }
    }
}

// MARK: Speed

struct SpeedScene: View {
    let frame: Frame

    var body: some View {
        let grow = frame.interpolate([40, 130], [0, 1], easing: .easeOut)
        VStack(alignment: .leading, spacing: 46) {
            Heading(kicker: "FAST", title: "Three times faster than it plays.", frame: frame)
            HStack(alignment: .lastTextBaseline, spacing: 20) {
                Text("\(Int((190 * grow).rounded()))")
                    .font(Look.serif(240, .black))
                    .tracking(-6)
                    .monospacedDigit()
                    .foregroundStyle(Look.ink)
                    .frame(width: 440, alignment: .trailing)
                VStack(alignment: .leading, spacing: 6) {
                    Text("frames per second").font(Look.serif(46, .bold)).foregroundStyle(Look.ink)
                    Text("1920×1080 · HEVC · Apple M3 Pro").font(Look.mono(26)).foregroundStyle(Look.dim)
                }
            }
            VStack(alignment: .leading, spacing: 16) {
                bar("playback", 60, width: 1500 * 60 / 190, color: Look.ink.opacity(0.28))
                bar("Flipbook", 190, width: 1500 * grow, color: Look.accent)
            }
            .opacity(frame.interpolate([30, 46], [0, 1]))
            Text("SwiftUI drawn by Core Animation on the GPU, straight into the hardware encoder.")
                .font(Look.serif(32, .regular))
                .foregroundStyle(Look.dim)
                .opacity(frame.interpolate([120, 140], [0, 1]))
        }
        .modifier(Flick(frame: frame))
    }

    func bar(_ label: String, _ value: Int, width: Double, color: Color) -> some View {
        HStack(spacing: 22) {
            Text(label).font(Look.mono(24)).foregroundStyle(Look.dim).frame(width: 150, alignment: .leading)
            RoundedRectangle(cornerRadius: 6).fill(color).frame(width: max(frame.snap(width), 2), height: 30)
        }
    }
}

// MARK: Outro

struct Outro: View {
    let frame: Frame

    static let features = ["HEVC · H.264 · ProRes", "alpha", "sound", "preview window", "stills"]

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 44) {
                Page(phase: frame.loop(duration: 48).progress, size: CGSize(width: 150, height: 190))
                Text("Flipbook").font(Look.serif(170, .black)).tracking(-4).foregroundStyle(Look.ink)
            }
            .offset(y: frame.snap(40 * (1 - frame.spring(stiffness: 140, damping: 18, settle: 45))))

            HStack(spacing: 14) {
                ForEach(0..<Self.features.count, id: \.self) { index in
                    Text(Self.features[index])
                        .font(Look.mono(24))
                        .foregroundStyle(Look.ink.opacity(0.85))
                        .padding(.horizontal, 20)
                        .padding(.vertical, 11)
                        .overlay(Capsule().strokeBorder(Look.faint, lineWidth: 1.5))
                        .opacity(frame.interpolate([Double(30 + index * 6), Double(42 + index * 6)], [0, 1]))
                }
            }
            .padding(.top, 54)

            Panel {
                Text(frame.typed(".package(url: \"https://github.com/IKatsuba/flipbook\", from: \"1.0.0\")", from: 70, per: 0.9) + " ")
                    .font(Look.mono(30))
                    .foregroundStyle(Look.accent)
                    .padding(.horizontal, 36)
                    .lineLimit(1)
                    .frame(width: 1400, height: 92, alignment: .leading)
            }
            .padding(.top, 54)
            .opacity(frame.interpolate([56, 72], [0, 1]))

            Text("MIT · macOS 15 · Apple Silicon")
                .font(Look.mono(26))
                .foregroundStyle(Look.dim)
                .padding(.top, 40)
                .opacity(frame.interpolate([150, 170], [0, 1]))
        }
        .opacity(frame.fade(in: 14))
    }
}

// MARK: The whole thing

struct Promo: View {
    let frame: Frame

    var body: some View {
        ZStack {
            Backdrop(frame: frame)
            if let local = frame.sequence(from: Timeline.intro.from, duration: Timeline.intro.duration) {
                Intro(frame: local)
            }
            if let local = frame.sequence(from: Timeline.outro.from, duration: Timeline.outro.duration) {
                Outro(frame: local)
            }
            // The four scenes in the middle share a page: heading top left, content under it.
            Group {
                if let local = frame.sequence(from: Timeline.code.from, duration: Timeline.code.duration) {
                    CodeScene(frame: local)
                } else if let local = frame.sequence(from: Timeline.motion.from, duration: Timeline.motion.duration) {
                    MotionScene(frame: local)
                } else if let local = frame.sequence(from: Timeline.pure.from, duration: Timeline.pure.duration) {
                    PureScene(frame: local)
                } else if let local = frame.sequence(from: Timeline.speed.from, duration: Timeline.speed.duration) {
                    SpeedScene(frame: local)
                }
            }
            .padding(.horizontal, 120)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
    }
}

/// How a scene leaves: flicked off to the left like a page, over its last frames.
struct Flick: ViewModifier {
    let frame: Frame

    func body(content: Content) -> some View {
        let last = Double(frame.frames - 1)
        let away = frame.interpolate([last - 14, last], [0, 1], easing: .easeIn)
        content
            .rotationEffect(.degrees(-2.5 * away), anchor: .bottomLeading)
            .offset(x: frame.snap(-140 * away))
            .opacity(1 - away)
    }
}

// MARK: Social card

/// The repository's social preview: 1280×640, the book, the name and what it does.
struct SocialCard: View {
    var body: some View {
        ZStack {
            Look.paper
            RoundedRectangle(cornerRadius: 6).strokeBorder(Look.faint, lineWidth: 1.5).padding(28)
            HStack(spacing: 64) {
                ZStack {
                    ForEach(0..<4, id: \.self) { index in
                        Page(phase: Double(index + 1) / 5, size: CGSize(width: 190, height: 240))
                            .rotationEffect(.degrees(Double(index - 3) * 7), anchor: .bottomLeading)
                            .offset(x: CGFloat(index - 3) * 16)
                    }
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text("Flipbook").font(Look.serif(132, .black)).tracking(-3).foregroundStyle(Look.ink)
                    Text("Videos from SwiftUI views.").font(Look.mono(34)).foregroundStyle(Look.dim)
                    Text("Every frame a pure function of its number.").font(Look.serif(30, .regular)).foregroundStyle(Look.accent).padding(.top, 14)
                }
            }
            .padding(.leading, 30)
        }
    }
}
