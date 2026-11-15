import Flipbook
import SwiftUI

/// The gradient chord's own social card uses.
struct Backdrop: View {
    let frame: Frame

    var body: some View {
        // A slow drift, so the hold frames are not a still picture.
        let drift = 0.06 * sin(frame.time * 0.5)
        LinearGradient(
            stops: [
                .init(color: Theme.hex(0x2B3A8C), location: 0),
                .init(color: Theme.hex(0x6A4BC4), location: 0.38),
                .init(color: Theme.hex(0xC46AA8), location: 0.70),
                .init(color: Theme.hex(0xF2A17A), location: 1),
            ],
            startPoint: UnitPoint(x: 0 - drift, y: 0),
            endPoint: UnitPoint(x: 1 + drift, y: 1)
        )
    }
}

/// The line under the window that says what the scene shows.
struct Caption: View {
    let title: String
    let detail: String
    let frame: Frame

    var body: some View {
        let last = Double(frame.frames)
        VStack(spacing: Stage.vertical ? 22 : 10) {
            Text(title).font(.system(size: Stage.vertical ? 76 : 50, weight: .bold)).tracking(-0.5).foregroundStyle(.white)
            Text(detail).font(.system(size: Stage.vertical ? 36 : 26, weight: .medium)).foregroundStyle(.white.opacity(0.82))
        }
        .multilineTextAlignment(.center)
        .lineSpacing(4)
        .frame(width: Stage.vertical ? 920 : 1700)
        .shadow(color: .black.opacity(0.25), radius: 12, y: 4)
        .offset(y: Stage.px(26 * (1 - frame.spring(from: 6, stiffness: 160, damping: 20, settle: 40))))
        .opacity(min(frame.interpolate([6, 22], [0, 1]), frame.interpolate([last - 16, last - 2], [1, 0])))
    }
}

struct Intro: View {
    let frame: Frame

    var body: some View {
        let tagline = "One terminal for every coding agent."
        VStack(spacing: 64) {
            Lockup(unit: Stage.vertical ? 24 : 40, frame: frame)
            // Two rows where the card is narrow; the space typed after "for" becomes the break.
            Text(typed(Stage.vertical ? tagline.replacingOccurrences(of: "for every", with: "for\nevery") : tagline, frame, from: 92, per: 1.3) + " ")
                .font(.custom("JetBrainsMono-Regular", fixedSize: 46))
                .foregroundStyle(.white)
                .lineSpacing(10)
                .frame(width: Stage.vertical ? 540 : 1000, height: Stage.vertical ? 150 : 60, alignment: .topLeading)
        }
        .padding(.horizontal, Stage.vertical ? 60 : 110)
        .padding(.vertical, 90)
        .background(Theme.window.opacity(0.94), in: RoundedRectangle(cornerRadius: 36))
        .shadow(color: .black.opacity(0.3), radius: 40, y: 24)
        .scaleEffect(0.94 + 0.06 * frame.spring(stiffness: 120, damping: 18, settle: 50))
        .opacity(min(frame.interpolate([0, 14], [0, 1]), frame.interpolate([188, 206], [1, 0])))
        .offset(y: Stage.px(frame.interpolate([188, 206], [0, -40], easing: .easeIn)))
    }
}

struct Outro: View {
    let frame: Frame

    var body: some View {
        let command = "npm install -g @chorded/chord"
        VStack(spacing: 0) {
            Lockup(unit: Stage.vertical ? 24 : 26)
            Text(Stage.vertical ? "One terminal for\nevery coding agent." : "One terminal for every coding agent.")
                .font(.system(size: Stage.vertical ? 60 : 44, weight: .bold))
                .multilineTextAlignment(.center)
                .foregroundStyle(.white)
                .padding(.top, 54)
                .opacity(frame.interpolate([20, 40], [0, 1]))
            HStack(spacing: 0) {
                Text("$ ").foregroundStyle(Theme.dim)
                Text(typed(command, frame, from: 50, per: 1.5)).foregroundStyle(Theme.accent)
                Rectangle().fill(Theme.accent).frame(width: 18, height: 38).opacity(frame.loop(duration: 60).index < 36 ? 1 : 0)
                Spacer(minLength: 0)
            }
            .font(.custom("JetBrainsMono-Regular", fixedSize: 34))
            .padding(.horizontal, 34)
            .frame(width: 760, height: 84)
            .background(Theme.hex(0x0E0F12).opacity(0.7), in: RoundedRectangle(cornerRadius: 14))
            .padding(.top, 48)
            .opacity(frame.interpolate([36, 52], [0, 1]))
            Text(Stage.vertical ? "Open source · MIT · macOS and Linux\ngithub.com/IKatsuba/chord" : "Open source · MIT · macOS and Linux · github.com/IKatsuba/chord")
                .font(.custom("JetBrainsMono-Regular", fixedSize: Stage.vertical ? 28 : 24))
                .multilineTextAlignment(.center)
                .lineSpacing(12)
                .foregroundStyle(.white.opacity(0.8))
                .padding(.top, 44)
                .opacity(frame.interpolate([110, 130], [0, 1]))
        }
        .padding(.horizontal, Stage.vertical ? 70 : 120)
        .padding(.vertical, Stage.vertical ? 110 : 84)
        .background(Theme.window.opacity(0.94), in: RoundedRectangle(cornerRadius: 36))
        .shadow(color: .black.opacity(0.3), radius: 40, y: 24)
        .offset(y: Stage.px(50 * (1 - frame.spring(stiffness: 140, damping: 20, settle: 45))))
        .opacity(frame.interpolate([0, 16], [0, 1]))
    }
}

struct Promo: View {
    let frame: Frame

    var body: some View {
        ZStack {
            Backdrop(frame: frame)

            if let local = frame.sequence(from: Timeline.intro.from, duration: Timeline.intro.duration) {
                Intro(frame: local)
            }

            // One window for the four scenes in the middle; only what it shows changes.
            let first = Timeline.picker.from - 14
            let last = Timeline.outro.from + 14
            if let stage = frame.sequence(from: first, duration: last - first) {
                let rise = stage.spring(stiffness: 130, damping: 19, settle: 50)
                let leave = stage.interpolate([Double(stage.frames - 22), Double(stage.frames)], [0, 1], easing: .easeIn)
                TerminalWindow { scene }
                    .scaleEffect(0.95 + 0.05 * rise - 0.04 * leave)
                    .offset(y: Stage.px((Stage.vertical ? 170 : -86) + 120 * (1 - rise) - 30 * leave))
                    .opacity(min(stage.interpolate([0, 12], [0, 1]), 1 - leave))
            }

            caption.offset(y: Stage.vertical ? -660 : 432)

            if let local = frame.sequence(from: Timeline.outro.from, duration: Timeline.outro.duration) {
                Outro(frame: local)
            }
        }
    }

    /// What the window shows, cross-faded at the cuts.
    @ViewBuilder var scene: some View {
        if let local = frame.sequence(from: Timeline.picker.from - 14, duration: Timeline.picker.duration + 14) {
            PickerScene(frame: local.shift(by: 14)).opacity(cut(local))
        } else if let local = frame.sequence(from: Timeline.diff.from, duration: Timeline.diff.duration) {
            DiffScene(frame: local).opacity(cut(local))
        } else if let local = frame.sequence(from: Timeline.permission.from, duration: Timeline.permission.duration) {
            PermissionScene(frame: local).opacity(cut(local))
        } else if let local = frame.sequence(from: Timeline.team.from, duration: Timeline.team.duration + 14) {
            TeamScene(frame: local).opacity(local.interpolate([0, 8], [0, 1]))
        }
    }

    func cut(_ local: Frame) -> Double {
        min(local.interpolate([0, 8], [0, 1]), local.interpolate([Double(local.frames - 8), Double(local.frames)], [1, 0]))
    }

    @ViewBuilder var caption: some View {
        if let local = frame.sequence(from: Timeline.picker.from, duration: Timeline.picker.duration) {
            Caption(title: "Every coding agent. One terminal.", detail: "Claude Code, Codex, Gemini CLI, Cursor, OpenCode and 32 more.", frame: local)
        } else if let local = frame.sequence(from: Timeline.diff.from, duration: Timeline.diff.duration) {
            Caption(title: "Diffs you can read.", detail: "Whole, numbered and highlighted, whichever agent wrote them.", frame: local)
        } else if let local = frame.sequence(from: Timeline.permission.from, duration: Timeline.permission.duration) {
            Caption(title: "You stay in charge.", detail: "Every permission is a choice. Answer it with a number.", frame: local)
        } else if let local = frame.sequence(from: Timeline.team.from, duration: Timeline.team.duration) {
            Caption(title: "Agents that work as a team.", detail: "Codex writes the fix, Claude reviews it. Permissions still come to you.", frame: local)
        }
    }
}
