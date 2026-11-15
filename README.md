# Flipbook

An experiment: videos from SwiftUI views, where every frame is a pure function of its number. macOS on Apple Silicon only. Not a product; the point is to find out how fast SwiftUI can be turned into video and to measure it honestly. Inspired by [MyGo's Render plugin](https://mygo.run/docs/plugins/render), which quotes about 242 fps for 1080p on an M-series Mac.

```swift
import Flipbook

let comp = Composition(width: 1080, height: 1350, fps: 60, frames: 360, scale: 2) { frame in
    Card(title: "Make", accent: "changelogs", frame: frame)
        .opacity(frame.interpolate([0, 20], [0, 1], easing: .easeOut))
}
try await comp.video(to: URL(filePath: "out/demo.mp4"), codec: .hevc)
try await comp.video(to: URL(filePath: "out/part.mp4"), range: 60..<150) { done, total in print("\(done)/\(total)") }
try await comp.video(to: URL(filePath: "out/sound.mp4"), audio: URL(filePath: "music.m4a"))
try await comp.video(to: URL(filePath: "out/overlay.mov"), codec: .proRes4444)   // with alpha, when comp.transparent is set
let image = try comp.still(at: 42)
try comp.still(at: 42, to: URL(filePath: "out/frame.png"))
```

`width` and `height` are points; the video is `width × scale` by `height × scale` pixels (MyGo counts the other way round: pixels, divided by the scale). `Frame` has `index`, `time`, `progress`, `interpolate` (piecewise, with easing), `spring` (a damped spring in closed form, checked in the tests against fixed-step integration, with `settle:` to make it arrive exactly after a number of frames), `sequence(from:duration:)`, `shift(by:)` and `loop(duration:)`.

The rule for views: depend on the frame and nothing else. No `withAnimation`, no `.animation`, no `Date()`, no `TimelineView`, and load fonts and images before rendering (`Fonts.register(at:)` takes a font file or a folder of them and returns the names for `Font.custom`). Flipbook disables animations in the transaction of every frame, but cannot stop a view from reading a clock.

## Running it

```sh
swift run -c release flipbook-demo                                  # out/demo.mp4, 2160×2700, 6 s
swift run -c release flipbook-demo render --path image-renderer --speed 1
swift run -c release flipbook-demo still --frame 90 --out out/frame.png
swift run -c release flipbook-demo verify                           # determinism, see below
swift run -c release flipbook-demo layers                           # the CALayer tree SwiftUI builds
swift run -c release flipbook-demo bench-all                        # the tables below, several minutes
```

The demo is a dark card with a pink glow and a faint grid, a monospace kicker, "Make" rising on a spring and "changelogs" typed after it, a frame counter and a progress bar.

## Render paths

All four fill a BGRA, IOSurface-backed `CVPixelBuffer` from the `AVAssetWriterInputPixelBufferAdaptor`'s pool and hand it to `AVAssetWriter` with a hardware encoder required.

| Path | How | Works |
| --- | --- | --- |
| `core-animation` (default) | `NSHostingView` in a window that is never ordered in; `CARenderer` draws its layer tree into a Metal texture that is the pixel buffer's IOSurface | Yes |
| `image-renderer` | `ImageRenderer.cgImage`, then `CGContext.draw` into the pixel buffer | Yes, but see Determinism |
| `image-renderer-direct` | `ImageRenderer.render(rasterizationScale:)` into a `CGContext` wrapping the pixel buffer | Yes, slowest |
| `metal-composite` | A Metal fragment shader draws the backdrop (colour, glow, grid) into that texture, then `CARenderer` draws the SwiftUI text over it | Yes; needs `Composition.backdrop` |

### What turned out differently from what was expected

**`ImageRenderer.cgImage` is not CPU rasterisation.** On macOS 26 the `CGImage` it returns is lazy and backed by a RenderBox image provider: a `sample` of the process shows the Metal driver loaded and the main thread inside `CGContextDrawImage → RB::ImageProvider::copy_image_block_set → wait_phase`, followed by a vImage pixel format conversion and a `memmove`. So the baseline already rasterises on the GPU and pays for a readback and a copy. The variant that really is CPU rasterisation is `image-renderer-direct` (`argb32_shade_radial_RGB`, `blt_bitmap_blend_AXXX32` and friends at the top of the profile), and it is about twice as slow at 1x and three to four times at 2x.

**SwiftUI can be GPU-composited without an on-screen window, with two caveats.** `flipbook-demo layers` shows what SwiftUI hands to Core Animation for the demo: solid colours as plain backing layers, the gradient as a `GradientLayer`, the `Canvas` as a `RenderBoxLayer` with an `RBImageQueueLayer` (drawn by RenderBox on the GPU), and every `Text` as a `CGDrawingLayer` whose contents are a CPU-rasterised bitmap. `CARenderer` composites all of them correctly, and in step: frame N of this path is closer to frame N of the baseline than to either neighbour for every frame checked (`flipbook-demo cross`).

- A hosting view with no window at all does build a layer tree, but it is wrong: sublayers are positioned bottom-up while their contents stay upright (the headline ends up above the kicker, each right way up), layer `contentsScale` stays 1 so text is soft at 2x, and neither `isGeometryFlipped` on a parent layer nor wrapping the view in a plain `NSView` fixes it (the first mirrors the glyphs, the second renders black). Putting the hosting view in a borderless `NSWindow` that is never ordered in fixes the geometry; the window subclass overrides `backingScaleFactor` to get the composition's scale regardless of the attached display. The result then only needs one vertical flip.
- `CARenderer` does not clear what its layers leave transparent. Rendering into a fresh private texture gave magenta with trails of earlier frames. The `metal-composite` path uses that: the shader fills the target first and Core Animation composites the text onto it, with no intermediate texture.

Both caveats rest on undocumented behaviour (the `backingScaleFactor` override, `CARenderer` on a window's own layer tree), verified only on the OS below.

## Benchmarks

Apple M3 Pro (12 cores), 18 GB, macOS 26.6.2 (25G83), Swift 6.4, release build. The demo: 360 frames at 60 fps. Every row is three runs, each in a fresh process that first renders 30 frames to warm up; times come from `ContinuousClock`. fps is frames divided by wall time from the first frame to the closed file. CPU is user plus system time of the process (all threads) per frame, from `getrusage`. Draw is the wall time to build the SwiftUI view and have its pixels in the buffer; encoder wait is time spent in `append` waiting for the encoder to accept more. Peak RSS is `ru_maxrss`; it does not count IOSurface memory, which is where the pixel buffers live, so peak physical footprint is listed as well. "Speed first" sets `kVTCompressionPropertyKey_PrioritizeEncodingSpeedOverQuality` (`prioritizeSpeed: true`); the bitrate target is the same, and frame 200 measured 42.0 dB PSNR against the unencoded frame by default and 41.9 dB speed first.

| Path | Encoder | Pixels | fps, median (min–max) | CPU ms/frame | Draw ms/frame | Encoder wait ms/frame | Peak RSS, MB | Peak footprint, MB | Output, MB |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `image-renderer` | hevc | 1080×1350 (1x) | 250.6 (246.2–259.9) | 2.36 | 3.12 | 0.85 | 287.4 | 222.5 | 0.8 |
| `image-renderer-direct` | hevc | 1080×1350 (1x) | 135.3 (134.8–135.6) | 7.33 | 7.23 | 0.09 | 74.2 | 51.9 | 1.1 |
| `core-animation` | hevc | 1080×1350 (1x) | 245.5 (214.3–250.2) | 1.04 | 1.44 | 2.17 | 63.7 | 257.8 | 0.8 |
| `metal-composite` | hevc | 1080×1350 (1x) | 265.4 (248.7–273.9) | 1.12 | 1.07 | 2.41 | 61.5 | 228.7 | 0.7 |
| `image-renderer` | hevc, speed first | 1080×1350 (1x) | 419.7 (366.1–434.3) | 1.93 | 2.18 | 0.04 | 283.6 | 216.4 | 1.1 |
| `image-renderer-direct` | hevc, speed first | 1080×1350 (1x) | 132.6 (128.6–142.8) | 7.75 | 7.46 | 0.05 | 61.6 | 33.1 | 1.4 |
| `core-animation` | hevc, speed first | 1080×1350 (1x) | 411.4 (352.4–413.3) | 1.28 | 2.02 | 0.33 | 62.8 | 263.6 | 1.2 |
| `metal-composite` | hevc, speed first | 1080×1350 (1x) | 407.2 (403.7–410.9) | 1.20 | 1.11 | 1.22 | 62.6 | 224.6 | 1.0 |
| `core-animation` | h264 | 1080×1350 (1x) | 272.1 (228.8–277.4) | 1.35 | 2.12 | 1.37 | 64.7 | 265.5 | 0.9 |
| `image-renderer` | hevc | 2160×2700 (2x) | 72.7 (71.1–72.7) | 6.26 | 8.74 | 4.43 | 562.6 | 503.2 | 2.2 |
| `image-renderer-direct` | hevc | 2160×2700 (2x) | 40.3 (39.7–41.4) | 24.76 | 24.16 | 0.07 | 98.3 | 106.8 | 5.0 |
| `core-animation` | hevc | 2160×2700 (2x) | 72.1 (71.8–72.5) | 1.73 | 4.06 | 9.02 | 65.1 | 571.0 | 2.8 |
| `metal-composite` | hevc | 2160×2700 (2x) | 72.4 (71.5–73.0) | 2.14 | 3.16 | 9.81 | 62.7 | 533.8 | 1.3 |
| `image-renderer` | hevc, speed first | 2160×2700 (2x) | 113.1 (110.9–118.3) | 5.80 | 7.48 | 0.60 | 987.7 | 503.7 | 2.4 |
| `image-renderer-direct` | hevc, speed first | 2160×2700 (2x) | 40.6 (40.4–41.0) | 24.71 | 24.08 | 0.07 | 98.6 | 97.9 | 5.3 |
| `core-animation` | hevc, speed first | 2160×2700 (2x) | 118.9 (115.3–119.3) | 1.63 | 3.94 | 3.99 | 66.9 | 593.6 | 3.1 |
| `metal-composite` | hevc, speed first | 2160×2700 (2x) | 119.3 (119.1–119.6) | 1.72 | 2.81 | 5.15 | 64.5 | 530.5 | 1.4 |
| `core-animation` | h264 | 2160×2700 (2x) | 76.6 (76.6–76.7) | 1.44 | 3.91 | 8.45 | 66.6 | 562.0 | 2.5 |
| `core-animation` | hevc | 1920×1080 (1x) | 187.8 (185.3–194.1) | 1.12 | 1.76 | 3.12 | 64.8 | 307.9 | 0.9 |
| `metal-composite` | hevc | 1920×1080 (1x) | 198.1 (195.4–200.2) | 1.45 | 1.36 | 3.32 | 62.6 | 261.9 | 0.7 |
| `core-animation` | hevc, speed first | 1920×1080 (1x) | 293.4 (293.1–295.8) | 1.39 | 1.96 | 1.11 | 64.9 | 311.3 | 1.2 |
| `metal-composite` | hevc, speed first | 1920×1080 (1x) | 302.7 (295.9–304.6) | 1.38 | 1.41 | 1.64 | 62.7 | 272.9 | 1.0 |

The last four rows are 1920×1080, the frame size MyGo's 242 fps is quoted for. The scene, the machine and the encoder settings behind that number are not the same as here, so this is the same order of magnitude and no more: 188 to 198 fps with default HEVC, 293 to 303 fps speed first.

Where the time goes, with the encoder taken out and then left alone ("drawing only" reuses one pixel buffer; "encoder only" renders 30 consecutive frames beforehand and times encoding 360 frames that cycle through them):

| What runs | Pixels | fps, median (min–max) | CPU ms/frame | Peak RSS, MB | Peak footprint, MB |
| --- | --- | --- | --- | --- | --- |
| `image-renderer`, drawing only | 1080×1350 (1x) | 498.6 (474.9–541.3) | 1.50 | 224.3 | 210.1 |
| `image-renderer-direct`, drawing only | 1080×1350 (1x) | 153.0 (146.4–154.3) | 6.54 | 60.5 | 34.4 |
| `core-animation`, drawing only | 1080×1350 (1x) | 1088.1 (1041.1–1120.3) | 0.41 | 66.1 | 244.8 |
| `metal-composite`, drawing only | 1080×1350 (1x) | 1639.9 (1460.2–1735.3) | 0.45 | 63.9 | 212.1 |
| encoder only, hevc | 1080×1350 (1x) | 258.6 (241.4–262.8) | 0.58 | 64.5 | 372.1 |
| encoder only, hevc, speed first | 1080×1350 (1x) | 410.3 (407.7–415.4) | 0.49 | 64.6 | 374.3 |
| encoder only, h264 | 1080×1350 (1x) | 271.9 (269.7–274.3) | 0.54 | 64.5 | 370.0 |
| `image-renderer`, drawing only | 2160×2700 (2x) | 148.2 (144.4–149.2) | 5.04 | 556.9 | 449.5 |
| `image-renderer-direct`, drawing only | 2160×2700 (2x) | 42.6 (42.1–42.8) | 23.44 | 93.7 | 99.2 |
| `core-animation`, drawing only | 2160×2700 (2x) | 528.6 (508.4–542.9) | 0.50 | 68.2 | 506.5 |
| `metal-composite`, drawing only | 2160×2700 (2x) | 1393.8 (1367.2–1650.0) | 0.44 | 66.0 | 488.9 |
| encoder only, hevc | 2160×2700 (2x) | 71.7 (70.3–72.3) | 0.98 | 65.7 | 1007.9 |
| encoder only, hevc, speed first | 2160×2700 (2x) | 118.0 (115.6–118.2) | 0.86 | 65.8 | 1007.8 |
| encoder only, h264 | 2160×2700 (2x) | 75.6 (75.4–76.2) | 1.10 | 65.6 | 1007.9 |

**The bottleneck is the hardware encoder, not SwiftUI.** With default settings every GPU path lands on the encoder-only number (72 fps at 2x, about 260 fps at 1x) whatever its draw cost, and the time saved drawing reappears as encoder wait. HEVC and H.264 are within about 5% of each other. Speed first raises the ceiling by about 60%, and the paths again sit on it (113 to 119 fps at 2x).

The encoder's speed barely depends on what is in the picture. An earlier version of this scene had film grain that changed every frame, which made the files ten times larger (25 MB against 2 to 3 MB at 2x); the encoder-only ceiling was 75 fps then and is 72 fps now. Two probes made with that noisier scene, not repeated since: feeding the encoder NV12 instead of BGRA changed nothing (75.5 against 75.8 fps at 2x, so colour conversion is not the cost), and neither did moving the bitrate between 8 and 80 Mbit/s (75 to 77 fps).

Behind the encoder, drawing costs: SwiftUI through Core Animation manages about 530 fps at 2160×2700 (0.5 ms of CPU a frame), and moving the glow and grid out of SwiftUI into one shader takes that to about 1400 fps. The baseline's readback and copy leave it at 148 fps and several hundred MB of RSS. `image-renderer-direct` is bound by CPU rasterisation at 24 ms a frame for 2x.

## Determinism

`flipbook-demo verify` hashes (SHA-256) the pixel buffer of every frame, renders the composition twice in one process with separate renderers, and renders it once more starting at frame 120. `flipbook-demo hashes`, run twice as separate processes, was compared with `cmp` (that comparison was made on the earlier scene with grain; the in-process checks were repeated on the current one).

| Path | Two processes | Twice in one process | Started mid-way |
| --- | --- | --- | --- |
| `image-renderer` | identical | **4 of 360 frames differ** | differs in a fresh process |
| `image-renderer-direct` | identical | identical | identical |
| `core-animation` | identical | identical | identical |
| `metal-composite` | identical | identical | identical |

Same result at 1x and 2x. All 360 frames are distinct in every path (the frame counter and progress bar change every frame).

`image-renderer` is reproducible but not pure. Rendering the same sequence in a fresh process gives byte-identical buffers every time. Within one process, the second pass differs from the first on frames 1, 2, 31 and 32, by at most 1 in one 8-bit channel (`flipbook-demo diff`: between 13 and 3200 pixels at 1x). Those are the first two frames after something is drawn for the first time in the process: the first visible frames and the first frames with the headline. With the grain the list also had frames 12 and 13, where the card's opacity reaches 1, and a render started at frame 5 or 13 in a fresh process differed on its own first two frames in the same way. So with `ImageRenderer.cgImage` a frame depends, in the last bit, on what the process drew before it; the cause is inside RenderBox and was not pinned down further. Second and third passes agree with each other.

The other three paths passed every check, so on this machine their frames are a function of the frame number alone. Nothing here says anything about other GPUs or OS versions: the GPU paths are not expected to match each other or another machine bit for bit, and they differ from the baseline by a fraction of a level.

## Text that hops by a pixel

At 1x, text that is moved by a spring keeps hopping by a pixel long after it looks still. A spring's tail never reaches 1, SwiftUI puts every text layer on whole pixels, and a resting position that falls on half a pixel rounds one way with a tiny offset and the other way without it. Measured on a 1920×1080 scene, a caption went 970, 971, 970 over two seconds. Two things fix it: `spring(settle:)`, which bends the curve to land exactly, and rounding animated offsets to whole pixels. At 2x the hop is half a point and hard to see.

## What to try next

- More than one encoder. A single hardware session is the ceiling; splitting the timeline into segments encoded by parallel `VTCompressionSession`s and concatenated would show whether the media engine scales.
- Rendering and encoding overlapped properly. The loop waits for the GPU after every frame; with the encoder as the limit that is free today, but it will matter once the encoder is faster.
- Find what makes `ImageRenderer.cgImage` differ on first draws. It is why `core-animation` is the default: as fast, far less resident memory, and pure, at the price of leaning on undocumented behaviour.
- Text is still rasterised on the CPU into `CGDrawingLayer` bitmaps. It is cheap here; a scene with far more changing text would show whether that becomes the draw bottleneck.
- Scenes that are harder for Core Animation: blurs, masks, `drawingGroup()`, images, and whether each survives `CARenderer` offscreen.
- ProRes and transparent output; motion blur by averaging sub-frame samples; audio.
