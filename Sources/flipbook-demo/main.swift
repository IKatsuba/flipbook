import AppKit
import Flipbook
import Foundation
import SwiftUI

// flipbook-demo [render|still|layers|hashes|verify|diff|cross|bench|bench-all] [--path p] [--scale n] [--codec c] [--out file] [--frame n] [--frames n] [--mode m] [--speed 1] [--size WxH] [--from n] [--to n]

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
        guard let raw = options["path"] else { return .coreAnimation }
        guard let path = RenderPath(rawValue: raw) else {
            fail("unknown path \(raw); use one of \(RenderPath.allCases.map(\.rawValue).joined(separator: ", "))")
        }
        return path
    }
    var codec: Codec { Codec(rawValue: options["codec"] ?? "hevc") ?? .hevc }
    var scale: Int { Int(options["scale"] ?? "") ?? 2 }
    var frames: Int { Int(options["frames"] ?? "") ?? 360 }
    var speed: Bool { options["speed"] == "1" }
    /// The card is designed for 1080×1350; other sizes exist to compare pixel counts.
    var size: (width: Int, height: Int) {
        let parts = (options["size"] ?? "1080x1350").split(separator: "x").compactMap { Int($0) }
        return parts.count == 2 ? (parts[0], parts[1]) : (1080, 1350)
    }
    func url(_ fallback: String) -> URL { URL(filePath: options["out"] ?? fallback) }
}

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("flipbook-demo: \(message)\n".utf8))
    exit(1)
}

/// User plus system CPU time of the whole process, every thread included.
func cpuSeconds() -> Double {
    var usage = rusage()
    getrusage(RUSAGE_SELF, &usage)
    func seconds(_ t: timeval) -> Double { Double(t.tv_sec) + Double(t.tv_usec) / 1e6 }
    return seconds(usage.ru_utime) + seconds(usage.ru_stime)
}

/// Peak physical footprint in bytes: what Activity Monitor calls memory, IOSurfaces included.
func peakFootprint() -> Int {
    var info = task_vm_info_data_t()
    var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
    let status = withUnsafeMutablePointer(to: &info) {
        $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count) }
    }
    return status == KERN_SUCCESS ? Int(info.ledger_phys_footprint_peak) : 0
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

/// Tightly packed BGRA bytes of a pixel buffer.
func bytes(of buffer: CVPixelBuffer) -> [UInt8] {
    CVPixelBufferLockBaseAddress(buffer, .readOnly)
    defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
    let (width, height, stride) = (CVPixelBufferGetWidth(buffer) * 4, CVPixelBufferGetHeight(buffer), CVPixelBufferGetBytesPerRow(buffer))
    let base = CVPixelBufferGetBaseAddress(buffer)!.assumingMemoryBound(to: UInt8.self)
    var out = [UInt8](repeating: 0, count: width * height)
    for row in 0..<height {
        out.withUnsafeMutableBufferPointer { $0.baseAddress!.advanced(by: row * width).update(from: base + row * stride, count: width) }
    }
    return out
}

/// Renders a range twice and says where and by how much the two passes disagree.
@MainActor
func diffPasses<V: View>(_ composition: Composition<V>, path: RenderPath, range: Range<Int>) throws {
    var first: [Int: [UInt8]] = [:]
    try composition.forEachFrame(path: path, range: range) { index, buffer in first[index] = bytes(of: buffer) }
    try composition.forEachFrame(path: path, range: range) { index, buffer in
        let (a, b) = (first[index]!, bytes(of: buffer))
        guard a != b else { return }
        let width = composition.pixelWidth
        var count = 0, maxDelta = 0
        var (minX, minY, maxX, maxY) = (Int.max, Int.max, 0, 0)
        for pixel in 0..<(a.count / 4) {
            var delta = 0
            for channel in 0..<4 { delta = max(delta, abs(Int(a[pixel * 4 + channel]) - Int(b[pixel * 4 + channel]))) }
            guard delta > 0 else { continue }
            count += 1
            maxDelta = max(maxDelta, delta)
            let (x, y) = (pixel % width, pixel / width)
            (minX, minY, maxX, maxY) = (min(minX, x), min(minY, y), max(maxX, x), max(maxY, y))
        }
        print("frame \(index): \(count) pixels differ, max channel delta \(maxDelta), bounds x \(minX)...\(maxX) y \(minY)...\(maxY)")
    }
}

/// Mean absolute difference per channel between two frames.
func meanDifference(_ a: [UInt8], _ b: [UInt8]) -> Double {
    var sum = 0
    for i in a.indices { sum += abs(Int(a[i]) - Int(b[i])) }
    return Double(sum) / Double(a.count)
}

/// Checks that frame N of `path` shows frame N of the reference path, not a neighbour:
/// an asynchronously drawn layer that lagged a frame behind would still be deterministic.
@MainActor
func crossCheck<V: View>(_ composition: Composition<V>, path: RenderPath, reference: RenderPath, range: Range<Int>) throws {
    var expected: [Int: [UInt8]] = [:]
    try composition.forEachFrame(path: reference, range: range) { index, buffer in expected[index] = bytes(of: buffer) }
    var lagging = 0
    try composition.forEachFrame(path: path, range: range) { index, buffer in
        let actual = bytes(of: buffer)
        let same = meanDifference(actual, expected[index]!)
        let previous = expected[index - 1].map { meanDifference(actual, $0) }
        let next = expected[index + 1].map { meanDifference(actual, $0) }
        let closest = min(same, previous ?? .infinity, next ?? .infinity)
        if closest != same { lagging += 1 }
        if index % 10 == 0 || closest != same {
            let show = { (value: Double?) in value.map { String(format: "%.3f", $0) } ?? "-" }
            print("frame \(index): vs reference n \(show(same)), n-1 \(show(previous)), n+1 \(show(next))")
        }
    }
    print("\(path.rawValue) vs \(reference.rawValue): \(lagging) of \(range.count) frames are closer to a neighbouring frame")
}

let arguments = Arguments(Array(CommandLine.arguments.dropFirst()))

do {
    let path = arguments.path
    let useMetal = path == .metalComposite
    let size = arguments.size
    let composition = demoComposition(width: size.width, height: size.height, scale: arguments.scale, frames: arguments.frames, metalBackdrop: useMetal)
    switch arguments.command {
    case "render":
        let url = arguments.url("out/demo.mp4")
        // --from and --to render part of the timeline.
        let from = Int(arguments.options["from"] ?? "") ?? 0
        let to = Int(arguments.options["to"] ?? "") ?? composition.frames
        let stats = try await composition.video(to: url, codec: arguments.codec, path: path, range: from..<to, prioritizeSpeed: arguments.speed) { done, total in
            // A line that rewrites itself, when someone is watching.
            guard isatty(STDERR_FILENO) != 0, done % 30 == 0 || done == total else { return }
            FileHandle.standardError.write(Data("\r\(done)/\(total) frames\(done == total ? "\n" : "")".utf8))
        }
        print("\(url.path): \(summary(stats)), \(fileSize(url)) bytes")

    case "still":
        let index = Int(arguments.options["frame"] ?? "") ?? 120
        let url = arguments.url("out/still-\(index).png")
        try composition.still(at: index, to: url, path: path)
        print(url.path)

    case "layers":
        // What SwiftUI hands to Core Animation for one frame.
        print(try composition.layerTree(at: Int(arguments.options["frame"] ?? "") ?? 120))

    case "hashes":
        // "index hash" per line, for comparing separate processes.
        let from = Int(arguments.options["from"] ?? "") ?? 0
        let stats = try await composition.hashes(path: path, range: from..<composition.frames)
        print(stats.hashes.enumerated().map { "\($0.offset + from) \($0.element)" }.joined(separator: "\n"))

    case "verify":
        // Two full renders, each with its own renderer, compared frame by frame;
        // then a render that starts in the middle, which must not change what a frame looks like.
        let first = try await composition.hashes(path: path).hashes
        let second = try await composition.hashes(path: path).hashes
        let repeated = first.indices.filter { first[$0] != second[$0] }
        let middle = composition.frames / 3
        let partial = try await composition.hashes(path: path, range: middle..<composition.frames).hashes
        let shifted = partial.indices.filter { partial[$0] != second[$0 + middle] }.map { $0 + middle }
        let list = { (frames: [Int]) in frames.isEmpty ? "" : " (frames \(frames.prefix(12).map(String.init).joined(separator: " ")))" }
        print("\(path.rawValue) @\(arguments.scale)x: \(first.count) frames, \(Set(first).count) distinct")
        print("  rendered twice in one process: \(repeated.count) frames differ\(list(repeated))")
        print("  rendered from frame \(middle) instead of 0: \(shifted.count) frames differ\(list(shifted))")
        if !repeated.isEmpty || !shifted.isEmpty { exit(2) }

    case "diff":
        try diffPasses(composition, path: path, range: 0..<min(arguments.frames, 60))

    case "cross":
        try crossCheck(composition, path: path, reference: .imageRenderer, range: 60..<min(arguments.frames, 120))

    case "bench-all":
        // The whole matrix behind the README tables; takes several minutes.
        BenchMatrix.runs = Int(arguments.options["runs"] ?? "") ?? 3
        try BenchMatrix.main()

    case "bench":
        // Warm up SwiftUI, the glyph caches, the shaders and the encoder, then measure one full render.
        // --mode video (default) | draw (no encoder) | encoder (encoder alone, frames rendered beforehand)
        let mode = arguments.options["mode"] ?? "video"
        let scratch = FileManager.default.temporaryDirectory.appending(path: "flipbook-bench-\(getpid()).mp4")
        defer { try? FileManager.default.removeItem(at: scratch) }
        let warmup = demoComposition(width: size.width, height: size.height, scale: arguments.scale, frames: 30, metalBackdrop: useMetal)
        _ = try await warmup.video(to: scratch, codec: arguments.codec, path: path, prioritizeSpeed: arguments.speed)

        let clock = ContinuousClock()
        let cpuBefore = cpuSeconds()
        var stats: RenderStats
        switch mode {
        case "video":
            stats = try await composition.video(to: scratch, codec: arguments.codec, path: path, prioritizeSpeed: arguments.speed)
        case "draw":
            stats = RenderStats(frames: composition.frames, width: composition.pixelWidth, height: composition.pixelHeight)
            let start = clock.now
            try composition.forEachFrame(path: path) { _, _ in }
            let elapsed = (clock.now - start).components
            stats.totalSeconds = Double(elapsed.seconds) + Double(elapsed.attoseconds) * 1e-18
            stats.drawSeconds = stats.totalSeconds
        case "encoder":
            stats = try await composition.encoderCeiling(to: scratch, codec: arguments.codec, prioritizeSpeed: arguments.speed)
        default:
            fail("unknown mode \(mode)")
        }
        let cpu = cpuSeconds() - cpuBefore
        let result: [String: Any] = [
            "path": mode == "encoder" ? "encoder" : path.rawValue,
            "mode": mode,
            "scale": arguments.scale,
            "codec": arguments.codec.rawValue,
            "speed": arguments.speed,
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
            "peakFootprint": peakFootprint(),
            "bytes": mode == "draw" ? 0 : fileSize(scratch),
        ]
        let json = try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys])
        print(String(decoding: json, as: UTF8.self))

    default:
        fail("unknown command \(arguments.command)")
    }
} catch {
    fail("\(error)")
}
