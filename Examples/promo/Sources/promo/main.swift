import Flipbook
import Foundation

// promo [render|still|preview|social] [--scale n] [--frame n] [--from n] [--to n] [--out file]
// Flipbook's promo: 1920×1080, 60 fps, 29 seconds. Run it from the repository's root.

var options: [String: String] = [:]
var rest = CommandLine.arguments.dropFirst()
var command = "render"
if let first = rest.first, !first.hasPrefix("--") {
    command = first
    rest = rest.dropFirst()
}
while let key = rest.popFirst(), let value = rest.popFirst() { options[String(key.dropFirst(2))] = value }
let number = { (key: String) in options[key].flatMap { Int($0) } }

let composition = Composition(width: 1920, height: 1080, fps: 60, frames: Timeline.frames, scale: number("scale") ?? 1) { frame in
    Promo(frame: frame)
}

switch command {
case "still":
    let index = number("frame") ?? 0
    let url = URL(filePath: options["out"] ?? "out/flipbook-promo-\(index).png")
    try composition.still(at: index, to: url)
    print(url.path)
case "social":
    // The image for the repository's social preview, at twice GitHub's 1280×640.
    let url = URL(filePath: options["out"] ?? "docs/images/social.png")
    try Composition(width: 1280, height: 640, frames: 1, scale: 2) { _ in SocialCard() }.still(at: 0, to: url)
    print(url.path)
case "preview":
    composition.preview(title: "Flipbook promo", startAt: number("frame") ?? 0, playing: number("frame") == nil)
default:
    let url = URL(filePath: options["out"] ?? "out/flipbook-promo.mp4")
    let range = (number("from") ?? 0)..<(number("to") ?? composition.frames)
    let stats = try await composition.video(to: url, range: range)
    print(String(format: "%@: %d frames %dx%d in %.1fs = %.0f fps", url.path, stats.frames, stats.pixelWidth, stats.pixelHeight, stats.totalSeconds, stats.framesPerSecond))
}
