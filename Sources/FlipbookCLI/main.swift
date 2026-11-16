import Foundation

// flipbook: render, still and preview a scene written as one Swift file.

let usage = """
flipbook \(Workspace.version): videos from SwiftUI views

  flipbook new <scene.swift>            write a scene to start from
  flipbook render <scene> [options]     encode the video; --out file (default out/<scene>.mp4)
  flipbook still <scene> [options]      one frame as PNG; --frame n, --out file.png
  flipbook preview <scene> [--frame n]  a window that plays the scene, with a scrubber
  flipbook info <scene>                 size, frame rate and length
  flipbook run <scene> [arguments]      build the scene and hand it the arguments as they are
  flipbook doctor [--deep]              what this machine is missing, and what to install
  flipbook skill                        the guide to writing scenes, for people and agents (also: guide)
  flipbook clean                        remove the build cache

A scene is a .swift file, or a folder with a main.swift.
  render: --out file  --scale 1..4  --from n  --to n  --audio file  --speed
          --codec hevc|h264|prores422|prores4444   (default hevc)
  still:  --frame n (default 0)  --out file.png  --scale 1..4
Every command takes --json and then prints one JSON object. Exit status: 0 done,
1 failed, 2 the scene does not compile.
"""

func emit(_ object: [String: Any]) {
    let data = (try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes])) ?? Data("{}".utf8)
    print(String(decoding: data, as: UTF8.self))
}

func fail(_ failure: Failure, json: Bool) -> Never {
    if json {
        var object: [String: Any] = ["error": failure.message]
        if let fix = failure.fix { object["fix"] = fix }
        emit(object)
    }
    var text = "flipbook: \(failure.message)\n"
    if let fix = failure.fix { text += "\n\(fix)\n" }
    FileHandle.standardError.write(Data(text.utf8))
    exit(failure.status)
}

var arguments = Array(CommandLine.arguments.dropFirst())
let json = arguments.contains("--json")
let command = arguments.first ?? "help"
arguments = Array(arguments.dropFirst())
let workspace = Workspace()

do {
    switch command {
    case "help", "--help", "-h":
        print(usage)

    case "version", "--version":
        print(Workspace.version)

    case "skill", "guide":
        print(skill)

    case "doctor":
        let checks = Doctor(workspace: workspace).run(deep: arguments.contains("--deep"))
        let missing = checks.filter { !$0.ok && $0.required }
        if json {
            emit(["ok": missing.isEmpty, "checks": checks.map(\.object)])
        } else {
            for check in checks { print(check.line) }
            print(missing.isEmpty ? "\nReady to render." : "\n\(missing.count) thing\(missing.count == 1 ? "" : "s") to fix before flipbook can render.")
        }
        exit(missing.isEmpty ? 0 : 1)

    case "clean":
        try? FileManager.default.removeItem(at: workspace.package)
        json ? emit(["removed": workspace.package.path]) : print("removed \(workspace.package.path)")

    case "new":
        guard let path = arguments.first(where: { !$0.hasPrefix("-") }) else {
            throw Failure("new needs a file name", fix: "For example: flipbook new scene.swift")
        }
        let url = URL(filePath: path).standardizedFileURL
        guard url.pathExtension == "swift" else { throw Failure("\(path) is not a .swift file", fix: "For example: flipbook new scene.swift") }
        guard !FileManager.default.fileExists(atPath: url.path) else {
            throw Failure("\(url.path) is already there", fix: "Pick another name, or edit that file.")
        }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try starter.write(to: url, atomically: true, encoding: .utf8)
        json ? emit(["scene": url.path]) : print("\(url.path)\n\nflipbook still \(path) --frame 90     # a frame to look at\nflipbook render \(path)               # the video\nflipbook preview \(path)              # a window that plays it")

    case "render", "still", "preview", "info", "run":
        guard let path = arguments.first, !path.hasPrefix("-") else {
            throw Failure("\(command) needs a scene", fix: "For example: flipbook \(command) scene.swift")
        }
        let scene = try workspace.scene(at: path)
        // Say so only when there is something to build; an unchanged scene starts at once.
        let changed = try workspace.sync(scene)
        let program = try workspace.build(scene, quiet: json || !changed)
        // The scene runs where the command was run, so the paths it is given are the caller's.
        // `run` hands the scene its arguments as they are, for scenes with commands of their own.
        let handed = command == "run" ? Array(arguments.dropFirst()) : [command] + arguments.dropFirst()
        let status = try Shell.hand(over: program, handed, environment: [
            "FLIPBOOK_SCENE_DIR": scene.directory.path,
            "FLIPBOOK_SCENE_NAME": scene.name,
        ])
        exit(status)

    default:
        throw Failure("unknown command \(command)", fix: usage)
    }
} catch let failure as Failure {
    fail(failure, json: json)
} catch {
    fail(Failure("\(error.localizedDescription)"), json: json)
}
