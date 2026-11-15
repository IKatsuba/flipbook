import AppKit
import Flipbook
import Foundation
import ImageIO
import UniformTypeIdentifiers

// flipbook-demo [render|still|verify|hashes|bench] [--path p] [--scale n] [--codec c] [--out file] [--frame n] [--frames n]

struct Arguments {
    var command = "render"
    var options: [String: String] = [:]

    init(_ raw: [String]) {
        var rest = raw[...]
        if let first = rest.first, !first.hasPrefix("--") {
            command = first
            rest = rest.dropFirst()
        }
        while let key = rest.popFirst() {
            guard key.hasPrefix("--"), let value = rest.popFirst() else { fail("unexpected argument \(key)") }
            options[String(key.dropFirst(2))] = value
        }
    }

    var path: RenderPath {
        guard let raw = options["path"] else { return .imageRenderer }
        guard let path = RenderPath(rawValue: raw) else {
            fail("unknown path \(raw); use one of \(RenderPath.allCases.map(\.rawValue).joined(separator: ", "))")
        }
        return path
    }
    var codec: Codec { Codec(rawValue: options["codec"] ?? "hevc") ?? .hevc }
    var scale: Int { Int(options["scale"] ?? "") ?? 2 }
    var frames: Int { Int(options["frames"] ?? "") ?? 360 }
    func url(_ fallback: String) -> URL { URL(filePath: options["out"] ?? fallback) }
}

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("flipbook-demo: \(message)\n".utf8))
    exit(1)
}

func writePNG(_ image: CGImage, to url: URL) throws {
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
        fail("cannot create \(url.path)")
    }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else { fail("cannot write \(url.path)") }
}

/// User plus system CPU time of the whole process, every thread included.
func cpuSeconds() -> Double {
    var usage = rusage()
    getrusage(RUSAGE_SELF, &usage)
    func seconds(_ t: timeval) -> Double { Double(t.tv_sec) + Double(t.tv_usec) / 1e6 }
    return seconds(usage.ru_utime) + seconds(usage.ru_stime)
}

/// Peak resident set size in bytes (macOS reports `ru_maxrss` in bytes).
func peakRSS() -> Int {
    var usage = rusage()
    getrusage(RUSAGE_SELF, &usage)
    return Int(usage.ru_maxrss)
}

func fileSize(_ url: URL) -> Int {
    (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
}

func summary(_ stats: RenderStats) -> String {
    let perFrame = { (seconds: Double) in String(format: "%.2f", seconds / Double(stats.frames) * 1000) }
    return String(format: "%d frames %dx%d in %.2fs = %.1f fps", stats.frames, stats.pixelWidth, stats.pixelHeight, stats.totalSeconds, stats.framesPerSecond)
        + " (ms/frame: draw \(perFrame(stats.drawSeconds)), append \(perFrame(stats.appendSeconds)), finish \(perFrame(stats.finishSeconds)))"
}

let arguments = Arguments(Array(CommandLine.arguments.dropFirst()))
// SwiftUI's AppKit-backed pieces want an application object, even with no window on screen.
_ = NSApplication.shared

do {
    let composition = demoComposition(scale: arguments.scale, frames: arguments.frames)
    switch arguments.command {
    case "render":
        let url = arguments.url("out/demo.mp4")
        let stats = try await composition.video(to: url, codec: arguments.codec, path: arguments.path)
        print("\(url.path): \(summary(stats)), \(fileSize(url)) bytes")

    case "still":
        let index = Int(arguments.options["frame"] ?? "") ?? 120
        let url = arguments.url("out/still-\(index).png")
        try writePNG(try composition.still(at: index, path: arguments.path), to: url)
        print(url.path)

    case "hashes":
        // One hash per line, for comparing separate processes.
        let stats = try await composition.hashes(path: arguments.path)
        print(stats.hashes.joined(separator: "\n"))

    case "verify":
        // Two renders, each with its own renderer, compared frame by frame.
        let first = try await composition.hashes(path: arguments.path).hashes
        let second = try await composition.hashes(path: arguments.path).hashes
        let different = zip(first, second).enumerated().filter { $0.element.0 != $0.element.1 }.map(\.offset)
        let distinct = Set(first).count
        print("\(arguments.path.rawValue) @\(arguments.scale)x: \(first.count) frames, \(distinct) distinct, \(different.count) differ between two renders")
        if !different.isEmpty {
            print("differing frames: \(different.prefix(20).map(String.init).joined(separator: " "))")
            exit(2)
        }

    case "bench":
        // Warm up SwiftUI, the glyph caches and the encoder, then measure one full render.
        let scratch = FileManager.default.temporaryDirectory.appending(path: "flipbook-bench-\(getpid()).mp4")
        defer { try? FileManager.default.removeItem(at: scratch) }
        let warmup = demoComposition(scale: arguments.scale, frames: 30)
        _ = try await warmup.video(to: scratch, codec: arguments.codec, path: arguments.path)

        let cpuBefore = cpuSeconds()
        let stats = try await composition.video(to: scratch, codec: arguments.codec, path: arguments.path)
        let cpu = cpuSeconds() - cpuBefore
        let result: [String: Any] = [
            "path": arguments.path.rawValue,
            "scale": arguments.scale,
            "codec": arguments.codec.rawValue,
            "frames": stats.frames,
            "width": stats.pixelWidth,
            "height": stats.pixelHeight,
            "seconds": stats.totalSeconds,
            "fps": stats.framesPerSecond,
            "cpuMsPerFrame": cpu / Double(stats.frames) * 1000,
            "drawMsPerFrame": stats.drawSeconds / Double(stats.frames) * 1000,
            "appendMsPerFrame": stats.appendSeconds / Double(stats.frames) * 1000,
            "finishMs": stats.finishSeconds * 1000,
            "peakRSS": peakRSS(),
            "bytes": fileSize(scratch),
        ]
        let json = try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys])
        print(String(decoding: json, as: UTF8.self))

    default:
        fail("unknown command \(arguments.command)")
    }
} catch {
    fail("\(error)")
}
