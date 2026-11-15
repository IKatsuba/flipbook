import AppKit
import Flipbook
import Foundation
import ImageIO
import UniformTypeIdentifiers

// chord-promo [render|still] [--scale n] [--path p] [--out file] [--frame n]
// A promo for chord (github.com/IKatsuba/chord): 1920×1080 points, 60 fps, 29 seconds.

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("chord-promo: \(message)\n".utf8))
    exit(1)
}

var options: [String: String] = [:]
var rest = CommandLine.arguments.dropFirst()
var command = "render"
if let first = rest.first, !first.hasPrefix("--") {
    command = first
    rest = rest.dropFirst()
}
while let key = rest.popFirst() {
    guard key.hasPrefix("--"), let value = rest.popFirst() else { fail("unexpected argument \(key)") }
    options[String(key.dropFirst(2))] = value
}

_ = NSApplication.shared
// The terminal is set in JetBrains Mono; without it the columns would not line up.
guard NSFont(name: "JetBrainsMono-Regular", size: 20) != nil, NSFont(name: "JetBrainsMono-Bold", size: 20) != nil else {
    fail("JetBrains Mono is not installed")
}

let scale = Int(options["scale"] ?? "") ?? 1
let path = RenderPath(rawValue: options["path"] ?? "core-animation") ?? .coreAnimation
let composition = Composition(width: 1920, height: 1080, fps: 60, frames: Timeline.frames, scale: scale) { frame in
    Promo(frame: frame)
}

do {
    switch command {
    case "render":
        let url = URL(filePath: options["out"] ?? "out/chord-promo.mp4")
        let stats = try await composition.video(to: url, codec: .hevc, path: path)
        print(String(format: "%@: %d frames %dx%d in %.1fs = %.0f fps", url.path, stats.frames, stats.pixelWidth, stats.pixelHeight, stats.totalSeconds, stats.framesPerSecond))
    case "still":
        let index = Int(options["frame"] ?? "") ?? 0
        let url = URL(filePath: options["out"] ?? "out/chord-promo-\(index).png")
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let image = try composition.still(at: index, path: path)
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else { fail("cannot create \(url.path)") }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { fail("cannot write \(url.path)") }
        print(url.path)
    default:
        fail("unknown command \(command)")
    }
} catch {
    fail("\(error)")
}
