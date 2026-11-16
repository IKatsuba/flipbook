import Foundation

/// Runs every render path of the demo three times, each run in a fresh process (so peak memory
/// belongs to that run alone), and prints the README tables.
struct BenchMatrix {
    struct Config {
        var path: String
        var mode: String
        var scale: Int
        var codec = "hevc"
        var speed = false
        var size = "1080x1350"

        var encoder: String { codec + (speed ? ", speed first" : "") }
        var arguments: [String] {
            ["bench", "--path", path, "--mode", mode, "--scale", "\(scale)", "--codec", codec, "--speed", speed ? "1" : "0", "--size", size]
        }
    }

    nonisolated(unsafe) static var runs = 3
    static let paths = ["image-renderer", "image-renderer-direct", "core-animation", "metal-composite"]

    static var configs: [Config] {
        var configs: [Config] = []
        for scale in [1, 2] {
            for speed in [false, true] {
                for path in paths { configs.append(Config(path: path, mode: "video", scale: scale, speed: speed)) }
            }
            configs.append(Config(path: "core-animation", mode: "video", scale: scale, codec: "h264"))
        }
        // 1920×1080, the usual size of a video.
        for speed in [false, true] {
            for path in ["core-animation", "metal-composite"] {
                configs.append(Config(path: path, mode: "video", scale: 1, speed: speed, size: "1920x1080"))
            }
        }
        for scale in [1, 2] {
            for path in paths { configs.append(Config(path: path, mode: "draw", scale: scale)) }
            configs.append(Config(path: "core-animation", mode: "encoder", scale: scale))
            configs.append(Config(path: "core-animation", mode: "encoder", scale: scale, speed: true))
            configs.append(Config(path: "core-animation", mode: "encoder", scale: scale, codec: "h264"))
        }
        return configs
    }

    /// One `bench` run of this executable in a child process; its JSON line, parsed.
    static func run(_ config: Config) throws -> [String: Double] {
        let process = Process()
        process.executableURL = Bundle.main.executableURL
        process.arguments = config.arguments
        let output = Pipe()
        process.standardOutput = output
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0, let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            fail("bench \(config.arguments.joined(separator: " ")) failed")
        }
        return object.compactMapValues { ($0 as? NSNumber)?.doubleValue }
    }

    static func median(_ values: [Double]) -> Double { values.sorted()[values.count / 2] }
    static func number(_ value: Double, _ digits: Int) -> String { String(format: "%.\(digits)f", value) }
    static func megabytes(_ bytes: Double) -> String { number(bytes / 1024 / 1024, 1) }
    static func spread(_ values: [Double]) -> String {
        "\(number(median(values), 1)) (\(number(values.min()!, 1))–\(number(values.max()!, 1)))"
    }

    static func main() throws {
        var videos: [String] = [
            "| Path | Encoder | Pixels | fps, median (min–max) | CPU ms/frame | Draw ms/frame | Encoder wait ms/frame | Peak RSS, MB | Peak footprint, MB | Output, MB |",
            "| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |",
        ]
        var parts: [String] = [
            "| What runs | Pixels | fps, median (min–max) | CPU ms/frame | Peak RSS, MB | Peak footprint, MB |",
            "| --- | --- | --- | --- | --- | --- |",
        ]
        for config in configs {
            let results = try (0..<runs).map { _ in try run(config) }
            let pick = { (key: String) in results.map { $0[key] ?? 0 } }
            let pixels = "\(Int(results[0]["width"] ?? 0))×\(Int(results[0]["height"] ?? 0)) (\(config.scale)x)"
            FileHandle.standardError.write(Data("\(config.mode) \(config.path) \(config.encoder) \(pixels): \(spread(pick("fps"))) fps\n".utf8))
            if config.mode == "video" {
                videos.append("| `\(config.path)` | \(config.encoder) | \(pixels) | \(spread(pick("fps"))) | \(number(median(pick("cpuMsPerFrame")), 2)) | \(number(median(pick("drawMsPerFrame")), 2)) | \(number(median(pick("appendMsPerFrame")), 2)) | \(megabytes(median(pick("peakRSS")))) | \(megabytes(median(pick("peakFootprint")))) | \(megabytes(median(pick("bytes")))) |")
            } else {
                let what = config.mode == "draw" ? "`\(config.path)`, drawing only" : "encoder only, \(config.encoder)"
                parts.append("| \(what) | \(pixels) | \(spread(pick("fps"))) | \(number(median(pick("cpuMsPerFrame")), 2)) | \(megabytes(median(pick("peakRSS")))) | \(megabytes(median(pick("peakFootprint")))) |")
            }
        }
        let tables = (videos + [""] + parts).joined(separator: "\n") + "\n"
        try FileManager.default.createDirectory(atPath: "out", withIntermediateDirectories: true)
        try tables.write(toFile: "out/bench.md", atomically: true, encoding: .utf8)
        print(tables, terminator: "")
    }
}
