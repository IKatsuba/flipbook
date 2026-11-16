import Foundation
import SwiftUI

/// Files that travel with a scene: sounds, fonts, pictures.
public enum Assets {
    /// The folder the scene file is in when it is run by the `flipbook` command; otherwise the working directory.
    public static var directory: URL {
        if let path = ProcessInfo.processInfo.environment["FLIPBOOK_SCENE_DIR"], !path.isEmpty {
            return URL(filePath: path, directoryHint: .isDirectory)
        }
        return URL(filePath: FileManager.default.currentDirectoryPath, directoryHint: .isDirectory)
    }

    /// A file next to the scene, by its path from the scene's folder.
    public static func url(_ path: String) -> URL { directory.appending(path: path) }
}

/// What a command line asks a composition to do.
struct RunRequest: Equatable {
    enum Command: String, CaseIterable { case render, still, preview, info }

    var command = Command.render
    var out: String?
    var scale: Int?
    var frame: Int?
    var from: Int?
    var to: Int?
    var codec: Codec?
    var path: RenderPath?
    var audio: String?
    var speed = false
    var json = false

    struct Mistake: Error, Equatable, CustomStringConvertible {
        let description: String
    }

    static let usage = """
    render [--out file] [--scale n] [--from n] [--to n] [--codec hevc|h264|prores422|prores4444] [--audio file] [--speed] [--json]
    still [--frame n] [--out file.png] [--scale n] [--json]
    preview [--frame n]
    info [--json]
    """

    init(_ arguments: [String]) throws {
        var rest = arguments[...]
        if let first = rest.first, !first.hasPrefix("-") {
            guard let command = Command(rawValue: first) else {
                throw Mistake(description: "unknown command \(first); use one of \(Command.allCases.map(\.rawValue).joined(separator: ", "))")
            }
            self.command = command
            rest = rest.dropFirst()
        }
        while let option = rest.popFirst() {
            func value() throws -> String {
                guard let value = rest.popFirst() else { throw Mistake(description: "\(option) needs a value") }
                return value
            }
            func number() throws -> Int {
                let text = try value()
                guard let number = Int(text) else { throw Mistake(description: "\(option) needs a whole number, not \(text)") }
                return number
            }
            switch option {
            case "--out": out = try value()
            case "--scale": scale = try number()
            case "--frame": frame = try number()
            case "--from": from = try number()
            case "--to": to = try number()
            case "--audio": audio = try value()
            case "--speed": speed = true
            case "--json": json = true
            case "--codec":
                let name = try value()
                guard let codec = Codec(rawValue: name) else {
                    throw Mistake(description: "unknown codec \(name); use one of \(Codec.allCases.map(\.rawValue).joined(separator: ", "))")
                }
                self.codec = codec
            case "--path":
                let name = try value()
                guard let path = RenderPath(rawValue: name) else {
                    throw Mistake(description: "unknown path \(name); use one of \(RenderPath.allCases.map(\.rawValue).joined(separator: ", "))")
                }
                self.path = path
            default:
                throw Mistake(description: "unknown option \(option)")
            }
        }
        if let scale, !(1...4).contains(scale) { throw Mistake(description: "--scale is 1 to 4, not \(scale)") }
    }
}

extension Composition {
    /// Makes the scene a command-line program: `render`, `still`, `preview` and `info`, with their options
    /// read from the arguments. Put `try await composition.run()` at the end of a scene file.
    ///
    /// It prints what it wrote and returns; on a mistake or a failure it prints why to standard error
    /// and ends the process with status 1. With `--json` both are one JSON object on standard output.
    public func run(_ arguments: [String] = Array(CommandLine.arguments.dropFirst())) async {
        let json = arguments.contains("--json")
        do {
            let request = try RunRequest(arguments)
            let result = try await perform(request)
            if request.json {
                print(String(decoding: try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys, .withoutEscapingSlashes]), as: UTF8.self))
            } else if let line = result["summary"] as? String {
                print(line)
            }
        } catch {
            let message = (error as? RunRequest.Mistake).map { "\($0)\n\nusage:\n\(RunRequest.usage)" } ?? "\(error)"
            if json, let data = try? JSONSerialization.data(withJSONObject: ["error": "\(error)"], options: [.withoutEscapingSlashes]) {
                print(String(decoding: data, as: UTF8.self))
            }
            FileHandle.standardError.write(Data("flipbook: \(message)\n".utf8))
            exit(1)
        }
    }

    /// The scene's name, for default file names: the scene file's when run by the `flipbook` command.
    private var name: String {
        ProcessInfo.processInfo.environment["FLIPBOOK_SCENE_NAME"].flatMap { $0.isEmpty ? nil : $0 } ?? "video"
    }

    private func perform(_ request: RunRequest) async throws -> [String: Any] {
        var composition = self
        if let scale = request.scale { composition.scale = scale }
        var facts: [String: Any] = [
            "command": request.command.rawValue,
            "width": composition.pixelWidth,
            "height": composition.pixelHeight,
            "fps": composition.fps,
            "frames": composition.frames,
            "duration": Double(composition.frames) / Double(composition.fps),
        ]
        let absolute = { (path: String) in URL(filePath: path).standardizedFileURL }

        switch request.command {
        case .info:
            facts["summary"] = "\(composition.pixelWidth)×\(composition.pixelHeight), \(composition.fps) fps, \(composition.frames) frames, "
                + String(format: "%.2f s", Double(composition.frames) / Double(composition.fps))

        case .preview:
            composition.preview(title: name, startAt: request.frame ?? 0, playing: request.frame == nil)

        case .still:
            let index = request.frame ?? 0
            guard (0..<composition.frames).contains(index) else {
                throw RunRequest.Mistake(description: "--frame is 0 to \(composition.frames - 1), not \(index)")
            }
            let url = absolute(request.out ?? "out/\(name)-\(index).png")
            try composition.still(at: index, to: url, path: request.path ?? .coreAnimation)
            facts["output"] = url.path
            facts["frame"] = index
            facts["summary"] = url.path

        case .render:
            let codec = request.codec ?? .hevc
            let url = absolute(request.out ?? "out/\(name).\(codec.isProRes ? "mov" : "mp4")")
            let range = (request.from ?? 0)..<(request.to ?? composition.frames)
            let watching = isatty(STDERR_FILENO) != 0 && !request.json
            let stats = try await composition.video(
                to: url, codec: codec, path: request.path ?? .coreAnimation, range: range,
                audio: request.audio.map(absolute), prioritizeSpeed: request.speed
            ) { done, total in
                guard watching, done % 30 == 0 || done == total else { return }
                FileHandle.standardError.write(Data("\r\(done)/\(total) frames\(done == total ? "\n" : "")".utf8))
            }
            facts["output"] = url.path
            facts["rendered"] = stats.frames
            facts["seconds"] = stats.totalSeconds
            facts["renderFps"] = stats.framesPerSecond
            facts["codec"] = codec.rawValue
            facts["summary"] = String(
                format: "%@: %d frames %d×%d in %.1f s (%.0f fps)",
                url.path, stats.frames, stats.pixelWidth, stats.pixelHeight, stats.totalSeconds, stats.framesPerSecond
            )
        }
        return facts
    }
}
