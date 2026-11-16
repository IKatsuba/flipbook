import CoreGraphics
import Foundation
import Metal
import VideoToolbox

/// One thing a render needs, whether it is there, and what to do when it is not.
struct Check {
    let name: String
    let ok: Bool
    /// False for what only some commands need.
    var required = true
    let detail: String
    var fix: String?

    var line: String {
        let mark = ok ? "ok  " : (required ? "FAIL" : "warn")
        return "\(mark)  \(name): \(detail)" + (ok || fix == nil ? "" : "\n      → \(fix!)")
    }

    var object: [String: Any] {
        var object: [String: Any] = ["name": name, "ok": ok, "required": required, "detail": detail]
        if !ok, let fix { object["fix"] = fix }
        return object
    }
}

struct Doctor {
    let workspace: Workspace

    func run(deep: Bool) -> [Check] {
        var checks = [chip(), system(), toolchain(), metal(), encoder(), session(), cache(), library()]
        if deep { checks.append(checks.allSatisfy { $0.ok || !$0.required } ? render() : Check(
            name: "test render", ok: false, detail: "skipped, because of the failures above"
        )) }
        return checks
    }

    func chip() -> Check {
        var info = utsname()
        uname(&info)
        let machine = withUnsafeBytes(of: &info.machine) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) }
        return Check(
            name: "Apple Silicon", ok: machine == "arm64", detail: machine,
            fix: "Flipbook is built for Apple Silicon Macs; an Intel Mac or a Rosetta shell will not do. In Rosetta, run `arch -arm64 flipbook doctor`."
        )
    }

    func system() -> Check {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        return Check(
            name: "macOS 15 or later", ok: version.majorVersion >= 15,
            detail: "macOS \(version.majorVersion).\(version.minorVersion).\(version.patchVersion)",
            fix: "Update macOS in System Settings → General → Software Update."
        )
    }

    func toolchain() -> Check {
        let result = (try? Shell.run("/usr/bin/xcrun", ["swift", "--version"])) ?? (status: 127, output: "")
        let found = result.output.firstMatch(of: #/Swift version (\d+)\.(\d+)/#)
        guard result.status == 0, let found, let major = Int(found.1) else {
            return Check(
                name: "Swift 6 toolchain", ok: false, detail: "no working `swift` (\(result.output.split(separator: "\n").first.map(String.init) ?? "not found"))",
                fix: "Install Xcode 16 or later from the App Store and open it once, or run `xcode-select --install` for the command line tools."
            )
        }
        let developer = ((try? Shell.run("/usr/bin/xcode-select", ["-p"]))?.output ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return Check(
            name: "Swift 6 toolchain", ok: major >= 6, detail: "Swift \(found.1).\(found.2) at \(developer)",
            fix: "Scenes are built with Swift 6. Install Xcode 16 or later, then `sudo xcode-select -s /Applications/Xcode.app`."
        )
    }

    func metal() -> Check {
        let device = MTLCreateSystemDefaultDevice()
        return Check(
            name: "Metal", ok: device != nil, detail: device?.name ?? "no device",
            fix: "Frames are drawn on the GPU. A virtual machine without GPU passthrough cannot render."
        )
    }

    func encoder() -> Check {
        var list: CFArray?
        VTCopyVideoEncoderList(nil, &list)
        let encoders = (list as? [[String: Any]]) ?? []
        let hardware = encoders.filter {
            ($0[kVTVideoEncoderList_CodecType as String] as? NSNumber)?.uint32Value == kCMVideoCodecType_HEVC
                && ($0[kVTVideoEncoderList_IsHardwareAccelerated as String] as? Bool) == true
        }
        return Check(
            name: "hardware HEVC encoder", ok: !hardware.isEmpty,
            detail: (hardware.first?[kVTVideoEncoderList_DisplayName as String] as? String) ?? "none",
            fix: "The hardware encoder is missing, as in most virtual machines. `--codec prores422` does not need it."
        )
    }

    func session() -> Check {
        let attached = CGSessionCopyCurrentDictionary() != nil
        return Check(
            name: "graphical session", ok: attached, required: false,
            detail: attached ? "logged in" : "none (ssh or a daemon)",
            fix: "Rendering draws through the window server and `preview` opens a window. Run flipbook from a session logged in at the Mac's screen."
        )
    }

    func cache() -> Check {
        let probe = workspace.home.appending(path: ".probe")
        do {
            try FileManager.default.createDirectory(at: workspace.home, withIntermediateDirectories: true)
            try Data().write(to: probe)
            try FileManager.default.removeItem(at: probe)
            return Check(name: "build cache", ok: true, detail: workspace.home.path)
        } catch {
            return Check(
                name: "build cache", ok: false, detail: "cannot write to \(workspace.home.path)",
                fix: "Set FLIPBOOK_HOME to a folder you can write to."
            )
        }
    }

    func library() -> Check {
        let library = workspace.library
        if case let .checkout(url) = library, !Workspace.isLibrary(url) {
            return Check(
                name: "Flipbook library", ok: false, detail: "\(url.path) is not a checkout of Flipbook",
                fix: "Point FLIPBOOK_PACKAGE at a clone of \(Workspace.repository), or unset it to use the release."
            )
        }
        return Check(name: "Flipbook library", ok: true, detail: library.description)
    }

    /// The real thing, small: build a scene and render it.
    func render() -> Check {
        let folder = FileManager.default.temporaryDirectory.appending(path: "flipbook-doctor-\(ProcessInfo.processInfo.processIdentifier)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: folder) }
        let started = Date()
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let file = folder.appending(path: "doctor.swift")
            try starter.write(to: file, atomically: true, encoding: .utf8)
            let scene = try workspace.scene(at: file.path)
            defer { try? FileManager.default.removeItem(at: scene.folder) }
            try workspace.sync(scene)
            let program = try workspace.build(scene, quiet: true)
            let output = folder.appending(path: "doctor.mp4")
            let result = try Shell.run(program.path, ["render", "--to", "20", "--out", output.path])
            let size = (try? FileManager.default.attributesOfItem(atPath: output.path)[.size] as? Int) ?? 0
            guard result.status == 0, size > 0 else {
                return Check(
                    name: "test render", ok: false, detail: result.output.trimmingCharacters(in: .whitespacesAndNewlines),
                    fix: "The scene built but did not render. The message above is the renderer's."
                )
            }
            return Check(name: "test render", ok: true, detail: String(format: "built and rendered 20 frames in %.0f s", Date().timeIntervalSince(started)))
        } catch let failure as Failure {
            return Check(name: "test render", ok: false, detail: failure.message, fix: failure.fix)
        } catch {
            return Check(name: "test render", ok: false, detail: error.localizedDescription)
        }
    }
}
