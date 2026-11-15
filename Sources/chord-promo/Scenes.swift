import Flipbook
import SwiftUI

/// Where each scene starts and how long it lasts, in frames at 60 fps.
enum Timeline {
    static let intro = (from: 0, duration: 210)
    static let picker = (from: 210, duration: 270)
    static let diff = (from: 480, duration: 320)
    static let permission = (from: 800, duration: 250)
    static let team = (from: 1050, duration: 420)
    static let outro = (from: 1470, duration: 270)
    static let frames = 1740
}

/// The header chord prints at the top of a session.
struct SessionHeader: View {
    var body: some View {
        HStack(alignment: .top, spacing: 30) {
            Mark(grid: MarkGrid.small, cell: CGSize(width: 12, height: 14))
            Lines(lines: [
                Line(s("chord", bold: true), dim(" v0.71.0")),
                Line(dim("claude · Claude Opus 5.5")),
                Line(dim("~/src/app")),
                Line(dim("? for shortcuts · /help")),
            ])
        }
    }
}

// MARK: Picker

struct PickerScene: View {
    let frame: Frame

    static let agents = [
        ("agoragentic-acp", "Agoragentic"), ("auggie", "Auggie CLI"), ("autohand", "Autohand Code"), ("bob", "Bob"),
        ("claude", "Claude Agent"), ("cline", "Cline"), ("codebuddy-code", "Codebuddy Code"), ("codex", "Codex"),
        ("deepagents", "DeepAgents"), ("dimcode", "DimCode"), ("dirac", "Dirac"), ("factory-droid", "Factory Droid"),
    ]

    /// The highlighted row: claude, down to codex, and back.
    var picked: Int {
        let steps: [(Int, Int)] = [(0, 4), (70, 5), (82, 6), (94, 7), (150, 6), (162, 5), (174, 4)]
        return steps.last { frame.index >= $0.0 }?.1 ?? 4
    }

    var body: some View {
        VStack(spacing: 0) {
            Lockup(unit: 15).padding(.top, 34).padding(.bottom, 26)
            LineView(line: Line(s("One terminal for every coding agent."))).fixedSize()
            LineView(line: Line(dim("v0.71.0 · ~/src/app"))).fixedSize()
            VStack(alignment: .leading, spacing: 0) {
                LineView(line: .blank)
                LineView(line: Line(s("Select agent")))
                LineView(line: .blank)
                ForEach(0..<Self.agents.count, id: \.self) { index in
                    let (name, title) = Self.agents[index]
                    let number = "\(index + 1).".padding(toLength: 4, withPad: " ", startingAt: 0)
                    if index == picked {
                        LineView(line: Line(s("❯   \(number)\(name) · \(title)", Theme.permission)))
                    } else {
                        LineView(line: Line(s("    \(number)\(name)"), dim(" · \(title)")))
                    }
                }
                LineView(line: Line(dim("    … +13 more")))
                LineView(line: .blank)
                LineView(line: Line(dim("↑↓ or j/k to move · Enter or 1-9 to select · Esc to cancel")))
            }
            .frame(width: 720)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: Diff

struct DiffScene: View {
    let frame: Frame

    static let prompt = "Greet people by name with a template literal"
    static let sent = 80

    var body: some View {
        let i = frame.index
        VStack(alignment: .leading, spacing: 0) {
            SessionHeader()
            Lines(lines: transcript(i))
            Spacer(minLength: 0)
            PromptBox(text: i < Self.sent ? typed(Self.prompt, frame, from: 12) : "", cursor: frame.loop(duration: 60).index < 36 || i < Self.sent)
            StatusRow().padding(.top, 8)
        }
    }

    func transcript(_ i: Int) -> [Line] {
        guard i >= Self.sent else { return [] }
        var lines: [Line] = [.blank, Line(dim("› "), s(Self.prompt)), .blank]
        guard i >= Self.sent + 24 else { return lines }
        let done = i >= Self.sent + 110
        lines.append(Line(s("● ", done ? Theme.success : Theme.dim), s("Edit", bold: true), s("(src/greeting.ts)")))
        guard i >= Self.sent + 44 else { return lines }
        lines.append(Line(dim("  └  Updated src/greeting.ts with 2 additions and 1 removal")))
        let code: [Line] = [
            Line(dim("     1 "), s("+ ", Theme.added), dim("/** Greets someone by name. */"), tint: Theme.addedTint),
            Line(dim("     2   "), s("export function ", Theme.keyword), s("greet", Theme.title), s("(name: "), s("string", Theme.type), s("): "), s("string", Theme.type), s(" {")),
            Line(dim("     2 "), s("- ", Theme.removed), s("  return ", Theme.keyword), s("\"hello \"", Theme.string), s(" + name;"), tint: Theme.removedTint),
            Line(dim("     3 "), s("+ ", Theme.added), s("  return ", Theme.keyword), s("`hello, ${name}`", Theme.string), s(";"), tint: Theme.addedTint),
            Line(dim("     4   "), s("}")),
        ]
        for (row, line) in code.enumerated() where i >= Self.sent + 52 + row * 9 {
            var line = line
            line.opacity = frame.interpolate([Double(Self.sent + 52 + row * 9), Double(Self.sent + 60 + row * 9)], [0, 1])
            lines.append(line)
        }
        if done { lines += [.blank, Line(s("● "), s("Edited."))] }
        return lines
    }
}

// MARK: Permission

struct PermissionScene: View {
    let frame: Frame

    static let prompt = "Write the release notes into notes.txt"
    static let sent = 62
    static let asked = 100
    static let answered = 190

    var body: some View {
        let i = frame.index
        let asking = i >= Self.asked && i < Self.answered + 10
        VStack(alignment: .leading, spacing: 0) {
            SessionHeader()
            Lines(lines: transcript(i))
            Spacer(minLength: 0)
            if asking {
                let seconds = (i - Self.asked) / 60
                LineView(line: Line(s("››› Waiting for permission… ", Theme.accent), dim("(\(seconds)s)")))
                    .padding(.bottom, 26)
                box(pressed: i >= Self.answered)
                    .offset(y: 30 * (1 - frame.spring(from: Self.asked, stiffness: 200, damping: 22)))
                    .opacity(frame.interpolate([Double(Self.asked), Double(Self.asked + 8)], [0, 1]))
                    .padding(.bottom, 26)
            }
            PromptBox(text: i < Self.sent ? typed(Self.prompt, frame, from: 8) : "", cursor: !asking)
            StatusRow(right: "Claude Opus 5.5 · medium effort").padding(.top, 8)
        }
    }

    func transcript(_ i: Int) -> [Line] {
        guard i >= Self.sent else { return [] }
        var lines: [Line] = [.blank, Line(dim("› "), s(Self.prompt)), .blank]
        guard i >= Self.sent + 20 else { return lines }
        let allowed = i >= Self.answered + 10
        lines.append(Line(s("● ", allowed ? Theme.success : Theme.dim), s("Write", bold: true), s("(notes.txt)")))
        if !allowed { lines.append(Line(dim("  └  Waiting…"))) }
        return lines
    }

    func box(pressed: Bool) -> some View {
        Lines(lines: [
            Line(s("Write notes.txt", Theme.permission, bold: true)),
            .blank,
            Line(s("Do you want to proceed?")),
            Line(s("❯ 1. Allow", Theme.permission, bold: pressed), tint: pressed ? Theme.permission.opacity(0.22) : nil),
            Line(s("  2. Always allow")),
            Line(s("  3. Deny")),
            .blank,
            Line(dim("Esc to reject")),
        ])
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .overlay(RoundedRectangle(cornerRadius: 4).stroke(Theme.permission, lineWidth: 1.5))
    }
}

// MARK: Team

struct TeamScene: View {
    let frame: Frame

    static let prompt = "Hand issue 214 to the bugfix team"
    static let sent = 62
    static let handed = 86
    static let started = 120
    static let reported = 215
    static let asked = 275

    static let job = "Issue 214: a string at the end of a line loses its closing quote. readString in src/parse/tokenize.ts stops at the newline before it consumes the quote. Add a test that fails for that reason, fix it, and have the diff reviewed. Report to me when it is done."
    static let report = "On it. tester is writing a failing test in tests/parse/tokenize_test.ts; coder waits for it and will edit src/parse/tokenize.ts only. I will report when the test fails for the bug's own reason."

    var body: some View {
        let i = frame.index
        VStack(alignment: .leading, spacing: 0) {
            Lines(lines: transcript(i))
            Spacer(minLength: 0)
            PromptBox(text: i < Self.sent ? typed(Self.prompt, frame, from: 8) : "", cursor: true)
            StatusRow(left: status(i), right: "Claude Opus 5.5 · medium · ~1% used").padding(.top, 8)
            Lines(lines: agents(i)).padding(.horizontal, 16)
        }
        .padding(.top, 8)
    }

    func transcript(_ i: Int) -> [Line] {
        guard i >= Self.sent else { return [] }
        var lines: [Line] = [Line(dim("› "), s(Self.prompt)), .blank]
        guard i >= Self.handed else { return lines }
        lines.append(Line(s("● ", Theme.success), s("Team", bold: true), s("(bugfix)"), dim(" · claude · claude-opus-5-5")))
        for (row, text) in wrap(Self.job, width: 112).enumerated() {
            lines.append(Line(dim((row == 0 ? "  └  " : "     ") + text)))
        }
        guard i >= Self.started else { return lines }
        lines += [.blank, Line(s("● "), s("bugfix has the job. Its lead will report here; you can look in with ↓."))]
        guard i >= Self.reported else { return lines }
        lines += [.blank, Line(s("← ", Theme.link), dim("from "), s("@bugfix", Theme.link, bold: true), dim(" · claude"))]
        for (row, text) in wrap(Self.report, width: 112).enumerated() {
            lines.append(Line(dim((row == 0 ? "  └  " : "     ") + text)))
        }
        return lines
    }

    func status(_ i: Int) -> [Seg] {
        guard i >= Self.asked else { return [dim("? for shortcuts")] }
        return [s("● tester needs your permission · ctrl+x a to go", Theme.warning), dim(" · ? for shortcuts")]
    }

    /// The agents list under the prompt: main, then the team and its members as they start.
    func agents(_ i: Int) -> [Line] {
        func seconds(since start: Int) -> String { "\(max(0, i - start) / 60)s" }
        func row(_ tree: String, _ name: String, _ colour: Color, _ what: String, _ state: Seg, _ news: String = "", bold: Bool = false) -> Line {
            let label = (tree + name).padding(toLength: 13, withPad: " ", startingAt: 0)
            return Line(
                dim(String(label.prefix(tree.count))), s(String(label.dropFirst(tree.count)), colour, bold: bold),
                dim(what.padding(toLength: 46, withPad: " ", startingAt: 0)),
                Seg(text: state.text.padding(toLength: 18, withPad: " ", startingAt: 0), color: state.color), dim(news)
            )
        }
        let working = { (start: Int) in s("✻ working \(seconds(since: start))", Theme.accent) }
        let idle = { (start: Int) in dim("◦ idle \(seconds(since: start))") }

        var lines = [row("", "main", Theme.text, "claude · Claude Opus 5.5 · medium", i >= Self.sent && i < Self.started ? working(Self.sent) : idle(i < Self.sent ? -480 : Self.started), bold: true)]
        guard i >= Self.started else { return lines }
        let claude = "claude · Claude Opus 5.5 · medium"
        lines.append(row("", "bugfix", Theme.agents[0], "team · " + claude, i < Self.reported ? working(Self.started) : idle(Self.reported), i >= Self.reported ? "✓ new reply" : ""))
        if i >= Self.started + 10 {
            let asking = i >= Self.asked
            lines.append(row("├─ ", "tester", Theme.agents[1], claude, asking ? s("● permission \(seconds(since: Self.asked))", Theme.warning) : working(Self.started + 10), asking ? "← new message" : ""))
        }
        if i >= Self.started + 18 { lines.append(row("├─ ", "coder", Theme.agents[2], "codex · GPT-6.1 Sol · medium", idle(Self.started + 18))) }
        if i >= Self.started + 26 { lines.append(row("└─ ", "reviewer", Theme.agents[3], claude, idle(Self.started + 26))) }
        return lines
    }
}
