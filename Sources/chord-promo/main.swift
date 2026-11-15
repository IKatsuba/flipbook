import AppKit
import Flipbook
import Foundation
import ImageIO
import UniformTypeIdentifiers

// chord-promo [render|still|probe] [--vertical 1] [--scale n] [--path p] [--out file] [--frame n]
// A promo for chord (github.com/IKatsuba/chord): 1920×1080 points, or 1080×1920 with --vertical 1; 60 fps, 29 seconds.

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
Stage.vertical = options["vertical"] == "1"
Stage.scale = scale
let composition = Composition(width: Int(Stage.size.width), height: Int(Stage.size.height), fps: 60, frames: Timeline.frames, scale: scale) { frame in
    Promo(frame: frame)
}

do {
    switch command {
    case "render":
        let url = URL(filePath: options["out"] ?? (Stage.vertical ? "out/chord-promo-vertical.mp4" : "out/chord-promo.mp4"))
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
    case "probe":
        // Where the bright pixels of a region sit, frame by frame: shows text that drifts or snaps.
        let numbers = (options["rect"] ?? "0,0,1920,1080").split(separator: ",").compactMap { Int($0) }
        let (x0, y0, w, h) = (numbers[0] * scale, numbers[1] * scale, numbers[2] * scale, numbers[3] * scale)
        let from = Int(options["from"] ?? "") ?? 0
        let to = Int(options["to"] ?? "") ?? from + 60
        try composition.forEachFrame(path: path, range: from..<to) { index, buffer in
            CVPixelBufferLockBaseAddress(buffer, .readOnly)
            defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
            let base = CVPixelBufferGetBaseAddress(buffer)!.assumingMemoryBound(to: UInt8.self)
            let stride = CVPixelBufferGetBytesPerRow(buffer)
            var (sum, sx, sy) = (0.0, 0.0, 0.0)
            for y in y0..<(y0 + h) {
                for x in x0..<(x0 + w) {
                    let pixel = base + y * stride + x * 4
                    let v = Double(min(pixel[0], pixel[1], pixel[2]))
                    guard v > 150 else { continue }
                    sum += v; sx += v * Double(x); sy += v * Double(y)
                }
            }
            print(String(format: "%d  x %.3f  y %.3f  mass %.0f", index, sx / sum / Double(scale), sy / sum / Double(scale), sum / 255 / Double(scale * scale)))
        }

    default:
        fail("unknown command \(command)")
    }
} catch {
    fail("\(error)")
}
