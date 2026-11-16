/// The scene `flipbook new` writes, and the one `flipbook doctor --deep` renders.
let starter = #"""
import Flipbook
import SwiftUI

// A scene is a Composition: a size in points, a frame rate, a length in frames,
// and a view of the frame. Look at it with `flipbook preview`, encode it with `flipbook render`.

let composition = Composition(width: 1920, height: 1080, fps: 60, frames: 180) { frame in
    ZStack {
        Color(red: 0.95, green: 0.93, blue: 0.88)
        VStack(spacing: 24) {
            Text("Hello")
                .font(.system(size: 160, weight: .bold, design: .serif))
                .offset(y: frame.snap(60 * (1 - frame.spring(from: 10, settle: 45))))
                .opacity(frame.interpolate([10, 30], [0, 1]))
            Text(frame.typed("made with Flipbook", from: 50, per: 2) + " ")
                .font(.system(size: 40, design: .monospaced))
                .opacity(0.6)
        }
        .foregroundStyle(Color(red: 0.1, green: 0.1, blue: 0.08))
    }
    .opacity(frame.fade(out: 20))
}

try await composition.run()

"""#

/// What `flipbook skill` prints: everything needed to go from "make a video" to a file.
let skill = #"""
# Making a video with flipbook

flipbook turns a SwiftUI view into a video on a Mac. You write one Swift file, the scene;
`flipbook render scene.swift` compiles it and encodes the video. Every frame is drawn from
its number alone, so a scene has no timers and no state.

## Before anything

```sh
flipbook doctor --json      # {"ok": true|false, "checks": [{"name", "ok", "required", "detail", "fix"}]}
```

If `ok` is false, stop and tell the person each failed check's `fix`. What is missing is
theirs to install (Xcode, a macOS update); do not try to work around it. `flipbook doctor
--deep` also builds and renders a tiny scene, which takes about a minute the first time.

## The flow

```sh
flipbook new promo.swift                          # a working scene to start from
flipbook still promo.swift --frame 60 --out /tmp/check.png   # then look at the image
flipbook render promo.swift --out videos/promo.mp4 --json
```

1. Write the scene (or `new` and edit it).
2. Render stills at a few frames and look at them. A scene that compiles can still be wrong:
   text off the edge, a line that wraps, an animation that has not started.
3. Render. `--out` is any path, relative to where you run the command; folders are created.
   Without it the video goes to `out/<scene name>.mp4` in the current directory.

The first build compiles the library and takes about a minute; after that a changed scene
builds in a few seconds. Builds live in `~/Library/Caches/flipbook`, never beside the scene.

## A scene file

```swift
import Flipbook
import SwiftUI

let composition = Composition(width: 1920, height: 1080, fps: 60, frames: 300, scale: 1) { frame in
    ZStack {
        Color.black
        Text("Hello")
            .font(.system(size: 120, weight: .bold))
            .foregroundStyle(.white)
            .opacity(frame.interpolate([0, 20], [0, 1]))
    }
}

try await composition.run()     // the last line; it reads the command the file was run with
```

- `width` and `height` are points; the video is `width × scale` by `height × scale` pixels.
  1920×1080 at scale 1 is 1080p, at scale 2 it is 4K. Vertical video: 1080×1920.
- `frames` is the length: seconds × fps. Frames are numbered from 0 to `frames - 1`.
- `fps` defaults to 30 and `scale` to 1.
- The view may be any SwiftUI. Define your own `View` structs above the composition and pass
  them the frame. A scene can also be a folder of `.swift` files with a `main.swift`.

## Frame: everything a view may depend on

| | |
| --- | --- |
| `frame.index`, `frame.time`, `frame.progress` | the frame number, seconds, and 0…1 through the current sequence |
| `frame.interpolate([0, 30], [0, 1], easing: .easeOut)` | map frame numbers to numbers, piecewise, clamped outside; easings are `.linear`, `.easeIn`, `.easeOut`, `.easeInOut`, `.cubicBezier(a, b, c, d)` |
| `frame.interpolate([0, 30], [Color.red, .blue])` | the same, to colours |
| `frame.spring(from: 10, stiffness: 100, damping: 10, settle: 45)` | a spring from 0 to 1 released at frame 10; `settle` makes it exactly 1 that many frames later |
| `frame.typed("text", from: 20, per: 2)` | the part of a string typed by this frame, one character every `per` frames |
| `frame.fade(in: 12, out: 12)` | opacity for a scene: up at the start of the sequence, down at its end |
| `frame.snap(value)` | a length rounded to whole pixels |
| `frame.sequence(from: 60, duration: 120)` | a frame counted from 60, or `nil` outside those 120 frames |
| `frame.shift(by: 30)`, `frame.loop(duration: 60)` | the timeline moved later; a frame that repeats |

The same, as declarations (every default shown):

```swift
struct Frame {                      // pass it to your own views: struct Title: View { let frame: Frame; ... }
    let index: Int                  // 0-based, local to the current sequence
    let fps: Int, frames: Int, scale: Int
    var time: Double                // seconds
    var progress: Double            // 0 at the first frame of the sequence, 1 at the last
    func interpolate(_ input: [Double], _ output: [Double], easing: Easing = .linear, extrapolate: Extrapolation = .clamp) -> Double
    func interpolate(_ input: [Double], _ output: [Color], easing: Easing = .linear) -> Color
    func spring(from: Int = 0, mass: Double = 1, stiffness: Double = 100, damping: Double = 10, settle: Int? = nil) -> Double
    func typed(_ text: String, from: Int = 0, per: Double = 2) -> String
    func fade(in: Int = 0, out: Int = 0, easing: Easing = .linear) -> Double
    func snap(_ points: Double) -> CGFloat
    func sequence(from: Int, duration: Int? = nil) -> Frame?    // nil duration: to the end
    func shift(by: Int) -> Frame
    func loop(duration: Int) -> Frame
}
```

- `interpolate` returns `Double`; SwiftUI takes it for `opacity`, `offset`, `scaleEffect` and `frame(width:)` as it is.
- A spring with the default damping overshoots: it goes a little past 1 and comes back. Raise
  `damping` to about 20 for one that does not. Before its `from` frame it is 0.
- Outside a sequence, `frames`, `progress` and `fade` are those of the whole composition, so
  `.opacity(frame.fade(out: 20))` on the root view fades the video out at its end.

Typed text, without the line moving and with a cursor:

```swift
let line = "A local task board."
let shown = frame.typed(line, from: 60, per: 2)
let typing = shown.count < line.count
ZStack(alignment: .leading) {
    Text(line).hidden()             // holds the full width, so centred text does not shift as it grows
    Text(shown + (typing || frame.loop(duration: 60).index < 30 ? "▍" : ""))
}
```

Scenes on a timeline:

```swift
ZStack {
    Background()
    if let local = frame.sequence(from: 0, duration: 120) { Title(frame: local).opacity(local.fade(out: 12)) }
    if let local = frame.sequence(from: 120, duration: 180) { Chart(frame: local).opacity(local.fade(in: 12)) }
}
```

## Rules

- **Only the frame.** No `withAnimation`, `.animation`, `.transition`, `TimelineView`, `Date()`,
  timers, `@State` that changes, `onAppear`, `task`, or anything asynchronous such as `AsyncImage`.
  They are either ignored or make frames depend on when they were drawn.
- **Snap what you move.** Wrap animated offsets in `frame.snap(...)` and give springs a
  `settle:`; otherwise text hops by a pixel long after it looks still.
- **Shadows go on shapes.** `.shadow` on a container gives every text inside it a shadow of
  its own. Put it on the background shape:
  `.background(RoundedRectangle(cornerRadius: 12).fill(.white).shadow(radius: 10))`.
- **Files travel with the scene.** `Assets.url("music.m4a")` is a file next to the scene file.
  Load images before the composition (`let logo = NSImage(contentsOf: Assets.url("logo.png"))!`)
  and use `Image(nsImage: logo)`.
- **Fonts.** System fonts just work: `.system(size:weight:design:)` with `.serif`, `.monospaced`,
  `.rounded`. For a font file: `let names = try Fonts.register(at: Assets.url("Inter.ttf"))`
  before the composition, then `.custom(names[0], fixedSize: 40)`.
- **Text is sized in points**, not for a phone: on a 1920×1080 canvas a headline is 80 to 160,
  body text 30 to 44. Keep a margin of about 100 points.
- `Canvas { context, size in ... }` works for drawing; pass `rendersAsynchronously: false`.

## Commands

```sh
flipbook render <scene> [--out file] [--scale 1..4] [--from n] [--to n]
                        [--codec hevc|h264|prores422|prores4444] [--audio file] [--speed] [--json]
flipbook still <scene> [--frame n] [--out file.png] [--scale n] [--json]
flipbook info <scene> [--json]      # size, fps, frames, duration, without rendering
flipbook preview <scene> [--frame n]   # a window; it blocks until the person closes it
flipbook run <scene> [arguments]    # for a scene that reads its own arguments
flipbook new <scene.swift>
flipbook doctor [--deep] [--json]
flipbook clean
```

- `--from`/`--to` render part of the timeline, to check one scene of a long video quickly:
  frames `from` up to but not including `to`. The view still sees the whole video's frame numbers.
- `still` writes frame 0 to `out/<scene name>-<frame>.png` unless told otherwise.
- `--scale` replaces the composition's `scale`: `--scale 2` on a 1920×1080 scene gives 3840×2160.
- The codec is HEVC unless you say so. It plays in QuickTime, Safari, recent Chrome and on phones;
  for the widest reach (older Windows players, some upload forms) use `--codec h264`.
- `--audio` lays a sound file under the video and cuts it to the video's length.
- `--codec prores4444 --out x.mov` keeps transparency when the scene sets
  `composition.transparent = true` (make `composition` a `var`). ProRes needs a `.mov` name.
- `--speed` encodes about 60% faster at the same bitrate.
- `--json` prints one object on standard output. Every one has `command`, `width`, `height`
  (pixels), `fps`, `frames` and `duration` (seconds) of the composition, and `summary`, a line
  for people. `render` adds `output`, `codec`, `rendered` (frames written), `seconds` (how long it
  took) and `renderFps`; `still` adds `output` and `frame`; `info` adds nothing. A failure is
  `{"error": "...", "fix": "..."}` with a non-zero exit status.
- `output` is an absolute path with links resolved, so `/tmp/x.mp4` comes back as `/private/tmp/x.mp4`.
- Do not run `preview` unless the person asked to see it: it waits for them to close the window.
- `run` builds the scene and passes it whatever follows, untouched. A scene that wants options of
  its own reads `CommandLine.arguments` and calls `composition.run(theRest)` with what is left.

Expect roughly 190 frames a second at 1080p and 50 at 4K on an M3 Pro.

## When it fails

| What you see | What to do |
| --- | --- |
| exit status 2, "the scene does not compile", then compiler errors with your file's path and line | fix the scene; the API is above |
| "there is no scene at …" | the path is wrong, or write one with `flipbook new` |
| "unknown option" or "needs a value" | the option list is above; `--speed` and `--json` take no value |
| "ProRes goes into a .mov file" | name the output `.mov` |
| "Audio: there is no file at …" | `--audio` is relative to where you run the command |
| "--frame is 0 to N" | the scene is shorter than you thought; `flipbook info` |
| a hardware encoder or Metal error | `flipbook doctor`; in a virtual machine try `--codec prores422` |
| the build hangs on "building … for the first time" with no network | the library is fetched from GitHub once; it needs the network that one time |
| stale or broken builds | `flipbook clean`, then render again |

A video that renders but looks wrong is the scene's doing: render stills and look.

"""#
