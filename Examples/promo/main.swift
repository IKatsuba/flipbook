import Flipbook

// Flipbook's promo, made with Flipbook: 1920×1080, 60 fps, 31.5 seconds.
//
//   flipbook render Examples/promo --out out/flipbook-promo.mp4
//   flipbook render Examples/promo --scale 2 --out out/flipbook-promo-4k.mp4
//   flipbook preview Examples/promo

let composition = Composition(width: 1920, height: 1080, fps: 60, frames: Timeline.frames) { frame in
    Promo(frame: frame)
}

try await composition.run()
