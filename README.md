# Flipbook

An experiment: videos from SwiftUI views, where every frame is a pure function of its number. macOS on Apple Silicon only. Not a product; the point is to find out how fast SwiftUI can be turned into video and to measure it honestly. Inspired by [MyGo's Render plugin](https://mygo.run/docs/plugins/render), which quotes about 242 fps for 1080p on an M-series Mac.

```swift
import Flipbook

let comp = Composition(width: 1080, height: 1350, fps: 60, frames: 360, scale: 2) { frame in
    Card(title: "Make", accent: "changelogs", frame: frame)
        .opacity(frame.interpolate([0, 20], [0, 1], easing: .easeOut))
}
try await comp.video(to: URL(filePath: "out/demo.mp4"), codec: .hevc)
let image = try comp.still(at: 42)
```

`width` and `height` are points; the video is `width × scale` by `height × scale` pixels (MyGo counts the other way round: pixels, divided by the scale). `Frame` has `index`, `time`, `progress`, `interpolate` (piecewise, with easing), `spring` (a damped spring in closed form, checked in the tests against fixed-step integration), `sequence(from:duration:)`, `shift(by:)` and `loop(duration:)`.

The rule for views: depend on the frame and nothing else. No `withAnimation`, no `.animation`, no `Date()`, no `TimelineView`, and load fonts and images before rendering. Flipbook disables animations in the transaction of every frame, but cannot stop a view from reading a clock.

## Running it

```sh
swift run -c release flipbook-demo                                  # out/demo.mp4, 2160×2700, 6 s
swift run -c release flipbook-demo render --path core-animation --speed 1
swift run -c release flipbook-demo still --frame 90 --out out/frame.png
swift run -c release flipbook-demo verify --path core-animation     # determinism, see below
swift run -c release flipbook-demo layers                           # the CALayer tree SwiftUI builds
swift build -c release && deno run --allow-run --allow-read --allow-write scripts/bench.ts
```

## Render paths

All four fill a BGRA, IOSurface-backed `CVPixelBuffer` from the `AVAssetWriterInputPixelBufferAdaptor`'s pool and hand it to `AVAssetWriter` with a hardware encoder required.

| Path | How | Works |
| --- | --- | --- |
| `image-renderer` (default) | `ImageRenderer.cgImage`, then `CGContext.draw` into the pixel buffer | Yes |
| `image-renderer-direct` | `ImageRenderer.render(rasterizationScale:)` into a `CGContext` wrapping the pixel buffer | Yes, slowest |
| `core-animation` | `NSHostingView` in a window that is never ordered in; `CARenderer` draws its layer tree into a Metal texture that is the pixel buffer's IOSurface | Yes |
| `metal-composite` | A Metal fragment shader draws the backdrop (colour, glow, grid, grain) into that texture, then `CARenderer` draws the SwiftUI text over it | Yes; needs `Composition.backdrop` |

### What turned out differently from what was expected

**`ImageRenderer.cgImage` is not CPU rasterisation.** On macOS 26 the `CGImage` it returns is lazy and backed by a RenderBox image provider: a `sample` of the process shows the Metal driver loaded and the main thread inside `CGContextDrawImage → RB::ImageProvider::copy_image_block_set → wait_phase`, followed by a vImage pixel format conversion and a `memmove`. So the baseline already rasterises on the GPU and pays for a readback and a copy. The variant that really is CPU rasterisation is `image-renderer-direct` (`argb32_shade_radial_RGB`, `blt_bitmap_blend_AXXX32` and friends at the top of the profile), and it is 2 to 5 times slower.

**SwiftUI can be GPU-composited without an on-screen window, with two caveats.** `flipbook-demo layers` shows what SwiftUI hands to Core Animation for the demo: solid colours as plain backing layers, the gradient as a `GradientLayer`, each `Canvas` as a `RenderBoxLayer` with an `RBImageQueueLayer` (drawn by RenderBox on the GPU), and every `Text` as a `CGDrawingLayer` whose contents are a CPU-rasterised bitmap. `CARenderer` composites all of them correctly, including the asynchronous-looking canvas layers: frame N of this path matches frame N of the baseline and not its neighbours (`flipbook-demo cross`, mean difference 0.17 to 0.31 of 255 against 9 for the adjacent frame).

- A hosting view with no window at all does build a layer tree, but it is wrong: sublayers are positioned bottom-up while their contents stay upright (the headline ends up above the kicker, each right way up), layer `contentsScale` stays 1 so text is soft at 2x, and neither `isGeometryFlipped` on a parent layer nor wrapping the view in a plain `NSView` fixes it (the first mirrors the glyphs, the second renders black). Putting the hosting view in a borderless `NSWindow` that is never ordered in fixes the geometry; the window subclass overrides `backingScaleFactor` to get the composition's scale regardless of the attached display. The result then only needs one vertical flip.
- `CARenderer` does not clear what its layers leave transparent. Rendering into a fresh private texture gave magenta with trails of earlier frames. The `metal-composite` path uses that: the shader fills the target first and Core Animation composites the text onto it, with no intermediate texture.

Both caveats rest on undocumented behaviour (the `backingScaleFactor` override, `CARenderer` on a window's own layer tree), verified only on the OS below.

## Benchmarks

Apple M3 Pro (12 cores), 18 GB, macOS 26.6.2 (25G83), Swift 6.4, release build. The demo: 360 frames at 60 fps. Every row is three runs, each in a fresh process that first renders 30 frames to warm up; times come from `ContinuousClock`. fps is frames divided by wall time from the first frame to the closed file. CPU is user plus system time of the process (all threads) per frame, from `getrusage`. Draw is the wall time to build the SwiftUI view and have its pixels in the buffer; encoder wait is time spent in `append` waiting for the encoder to accept more. Peak RSS is `ru_maxrss`; it does not count IOSurface memory, which is where the pixel buffers live, so peak physical footprint is listed as well. "Speed first" sets `kVTCompressionPropertyKey_PrioritizeEncodingSpeedOverQuality` (`prioritizeSpeed: true`); the bitrate target is the same 0.1 bit per pixel, and frame 200 measured 34.4 dB PSNR against the unencoded frame either way.

| Path | Encoder | Pixels | fps, median (min–max) | CPU ms/frame | Draw ms/frame | Encoder wait ms/frame | Peak RSS, MB | Peak footprint, MB | Output, MB |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `image-renderer` | hevc | 1080×1350 (1x) | 266.3 (263.4–271.5) | 2.58 | 2.95 | 0.60 | 293.9 | 228.8 | 6.1 |
| `image-renderer-direct` | hevc | 1080×1350 (1x) | 126.9 (123.9–127.3) | 8.14 | 7.80 | 0.04 | 67.1 | 38.7 | 6.3 |
| `core-animation` | hevc | 1080×1350 (1x) | 264.4 (263.3–267.1) | 1.79 | 3.03 | 0.55 | 69.8 | 305.1 | 6.3 |
| `metal-composite` | hevc | 1080×1350 (1x) | 265.7 (264.9–265.8) | 1.56 | 1.37 | 2.18 | 66.3 | 230.2 | 6.4 |
| `image-renderer` | hevc, speed first | 1080×1350 (1x) | 437.7 (437.5–437.8) | 1.83 | 2.15 | 0.04 | 289.0 | 221.5 | 6.3 |
| `image-renderer-direct` | hevc, speed first | 1080×1350 (1x) | 117.5 (108.8–123.5) | 8.86 | 8.42 | 0.06 | 67.3 | 38.8 | 6.3 |
| `core-animation` | hevc, speed first | 1080×1350 (1x) | 387.6 (364.8–389.4) | 1.42 | 2.48 | 0.06 | 70.1 | 297.8 | 6.3 |
| `metal-composite` | hevc, speed first | 1080×1350 (1x) | 437.2 (419.6–439.1) | 1.22 | 1.13 | 1.08 | 67.2 | 231.4 | 6.3 |
| `core-animation` | h264 | 1080×1350 (1x) | 276.0 (275.5–276.1) | 1.32 | 2.51 | 0.93 | 70.2 | 298.5 | 6.4 |
| `image-renderer` | hevc | 2160×2700 (2x) | 75.4 (75.2–75.7) | 6.37 | 8.18 | 4.40 | 995.2 | 516.3 | 25.3 |
| `image-renderer-direct` | hevc | 2160×2700 (2x) | 33.2 (32.7–33.7) | 30.63 | 29.98 | 0.07 | 108.4 | 105.3 | 25.9 |
| `core-animation` | hevc | 2160×2700 (2x) | 74.8 (74.8–75.0) | 4.11 | 7.29 | 5.39 | 72.5 | 695.5 | 25.2 |
| `metal-composite` | hevc | 2160×2700 (2x) | 77.2 (77.1–77.2) | 4.14 | 4.54 | 7.76 | 68.5 | 511.7 | 25.5 |
| `image-renderer` | hevc, speed first | 2160×2700 (2x) | 127.7 (127.3–127.7) | 5.54 | 7.43 | 0.05 | 929.5 | 450.2 | 25.4 |
| `image-renderer-direct` | hevc, speed first | 2160×2700 (2x) | 34.3 (29.4–34.4) | 29.51 | 28.95 | 0.06 | 108.7 | 105.7 | 25.3 |
| `core-animation` | hevc, speed first | 2160×2700 (2x) | 128.0 (127.3–128.1) | 1.79 | 5.25 | 2.15 | 73.4 | 705.2 | 25.4 |
| `metal-composite` | hevc, speed first | 2160×2700 (2x) | 125.4 (125.1–125.4) | 2.91 | 3.82 | 3.73 | 69.9 | 513.2 | 25.5 |
| `core-animation` | h264 | 2160×2700 (2x) | 75.9 (75.7–76.0) | 3.46 | 6.75 | 5.73 | 72.2 | 680.3 | 25.2 |
| `core-animation` | hevc | 1920×1080 (1x) | 195.4 (195.0–199.8) | 2.24 | 3.71 | 1.13 | 70.4 | 363.1 | 9.0 |
| `metal-composite` | hevc | 1920×1080 (1x) | 202.3 (201.5–202.5) | 1.38 | 1.27 | 3.43 | 66.8 | 271.0 | 9.2 |
| `core-animation` | hevc, speed first | 1920×1080 (1x) | 331.2 (330.5–331.4) | 1.23 | 2.44 | 0.42 | 71.2 | 358.3 | 9.1 |
| `metal-composite` | hevc, speed first | 1920×1080 (1x) | 324.3 (322.0–326.7) | 1.20 | 1.48 | 1.45 | 67.1 | 268.1 | 9.1 |

The last four rows are 1920×1080, the frame size MyGo's 242 fps is quoted for. The scene, the machine and the encoder settings behind that number are not the same as here, so this is the same order of magnitude and no more: 195 to 202 fps with default HEVC, 324 to 331 fps speed first.

Where the time goes, with the encoder taken out and then left alone ("drawing only" reuses one pixel buffer; "encoder only" renders 30 consecutive frames beforehand and times encoding 360 frames that cycle through them):

| What runs | Pixels | fps, median (min–max) | CPU ms/frame | Peak RSS, MB | Peak footprint, MB |
| --- | --- | --- | --- | --- | --- |
| `image-renderer`, drawing only | 1080×1350 (1x) | 560.1 (540.9–571.1) | 1.36 | 269.0 | 213.2 |
| `image-renderer-direct`, drawing only | 1080×1350 (1x) | 128.9 (125.8–130.0) | 7.76 | 63.9 | 35.7 |
| `core-animation`, drawing only | 1080×1350 (1x) | 512.8 (511.6–678.9) | 0.72 | 70.2 | 270.9 |
| `metal-composite`, drawing only | 1080×1350 (1x) | 1594.6 (1558.9–1613.7) | 0.45 | 66.4 | 220.3 |
| encoder only, hevc | 1080×1350 (1x) | 269.0 (268.7–269.2) | 0.90 | 69.9 | 412.1 |
| encoder only, hevc, speed first | 1080×1350 (1x) | 435.7 (435.0–436.4) | 0.57 | 70.3 | 410.3 |
| encoder only, h264 | 1080×1350 (1x) | 276.3 (274.7–276.6) | 0.57 | 69.8 | 409.7 |
| `image-renderer`, drawing only | 2160×2700 (2x) | 172.4 (171.5–176.2) | 4.51 | 882.6 | 431.1 |
| `image-renderer-direct`, drawing only | 2160×2700 (2x) | 35.0 (34.6–35.2) | 28.56 | 101.1 | 98.3 |
| `core-animation`, drawing only | 2160×2700 (2x) | 216.4 (204.3–226.7) | 1.69 | 73.8 | 590.6 |
| `metal-composite`, drawing only | 2160×2700 (2x) | 1034.4 (1026.7–1050.5) | 0.56 | 69.8 | 501.1 |
| encoder only, hevc | 2160×2700 (2x) | 75.2 (75.2–75.3) | 2.93 | 72.1 | 1141.1 |
| encoder only, hevc, speed first | 2160×2700 (2x) | 126.2 (125.5–126.3) | 2.22 | 72.9 | 1141.4 |
| encoder only, h264 | 2160×2700 (2x) | 75.8 (75.7–75.8) | 2.86 | 72.0 | 1141.1 |

**The bottleneck is the hardware encoder, not SwiftUI.** With default settings every GPU path lands on the encoder-only number (75 fps at 2x, 266 fps at 1x) whatever its draw cost, and the time saved drawing reappears as encoder wait. HEVC and H.264 are within 3% of each other. Speed first raises the ceiling by about two thirds, and the paths again sit on it at 2x (125 to 128 fps). Two things that did not help in one-off probes: feeding the encoder NV12 instead of BGRA (75.5 against 75.8 fps at 2x, so colour conversion is not the cost), and changing the bitrate between 8 and 80 Mbit/s (75 to 77 fps).

Behind the encoder, drawing costs: SwiftUI through Core Animation manages 216 fps at 2160×2700; moving the grid and grain out of SwiftUI `Canvas` into one shader takes that to about 1030 fps, so the two canvases are roughly four fifths of the drawing time and the text, layout and layer updates the rest (under 1 ms a frame). The baseline's readback and copy cost it about 20% against Core Animation at 2x and several hundred MB of RSS. `image-renderer-direct` is bound by CPU rasterisation at 29 ms a frame for 2x.

## Determinism

`flipbook-demo verify` hashes (SHA-256) the pixel buffer of every frame, renders the composition twice in one process with separate renderers, and renders it once more starting at frame 120. `flipbook-demo hashes`, run twice as separate processes, was compared with `cmp`.

| Path | Two processes | Twice in one process | Started mid-way |
| --- | --- | --- | --- |
| `image-renderer` | identical | **6 of 360 frames differ** | differs in a fresh process |
| `image-renderer-direct` | identical | identical | identical |
| `core-animation` | identical | identical | identical |
| `metal-composite` | identical | identical | identical |

Same result at 1x and 2x. All 360 frames are distinct in every path (the grain moves).

The baseline is reproducible but not pure. Rendering the same sequence in a fresh process gives byte-identical buffers every time. Within one process, the second pass differs from the first on frames 1, 2, 12, 13, 31 and 32, by at most 1 in one 8-bit channel (`flipbook-demo diff`: between 41 and 36 000 pixels). Those are the first two frames after something is drawn for the first time in the process: the first visible frames, the frames where the card's opacity reaches 1 and its group layer goes away, the first frames with the headline. In a fresh process, a render started at frame 5 or 13 differs from the full render on its own first two frames in the same way. So with `ImageRenderer.cgImage` a frame depends, in the last bit, on what the process drew before it; the cause is inside RenderBox and was not pinned down further. Second and third passes agree with each other.

The other three paths passed every check, so on this machine their frames are a function of the frame number alone. Nothing here says anything about other GPUs or OS versions: the GPU paths are not expected to match each other or another machine bit for bit, and they differ from the baseline by a fraction of a level.

## What to try next

- More than one encoder. A single hardware session is the ceiling; splitting the timeline into segments encoded by parallel `VTCompressionSession`s and concatenated would show whether the media engine scales.
- Rendering and encoding overlapped properly. The loop waits for the GPU after every frame; with the encoder as the limit that is free today, but it will matter once the encoder is faster.
- Find what makes `ImageRenderer.cgImage` differ on first draws, or drop it as the default in favour of `core-animation`, which is as fast, uses far less resident memory and is pure, at the price of leaning on undocumented behaviour.
- Text is still rasterised on the CPU into `CGDrawingLayer` bitmaps. It is cheap here (a few lines); a scene with a lot of changing text would show whether that becomes the draw bottleneck.
- Scenes that are harder for Core Animation: blurs, masks, `drawingGroup()`, images, shadows, and whether each survives `CARenderer` offscreen.
- ProRes and transparent output; motion blur by averaging sub-frame samples; audio.
