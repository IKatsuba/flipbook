import CryptoKit
import Foundation

/// Where scenes are built: one Swift package shared by every scene, so the library is compiled once.
/// It lives in the user's cache folder, out of the way of the scene and of the repository it sits in.
struct Workspace {
    static let version = "1.1.0"
    static let repository = "https://github.com/IKatsuba/flipbook"

    let home: URL

    init() {
        if let custom = ProcessInfo.processInfo.environment["FLIPBOOK_HOME"], !custom.isEmpty {
            home = URL(filePath: custom, directoryHint: .isDirectory)
        } else {
            home = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appending(path: "flipbook", directoryHint: .isDirectory)
        }
    }

    var package: URL { home.appending(path: "workspace", directoryHint: .isDirectory) }
    var sources: URL { package.appending(path: "Sources", directoryHint: .isDirectory) }

    /// Where the library comes from: a checkout named by FLIPBOOK_PACKAGE, the checkout this
    /// command was built in, or the release of this command's version.
    enum Library: Equatable {
        case checkout(URL)
        case release(String)

        var dependency: String {
            switch self {
            case let .checkout(url): return ".package(name: \"Flipbook\", path: \"\(url.path)\")"
            case let .release(version): return ".package(url: \"\(Workspace.repository)\", exact: \"\(version)\")"
            }
        }

        var product: String {
            switch self {
            case .checkout: return ".product(name: \"Flipbook\", package: \"Flipbook\")"
            case .release: return ".product(name: \"Flipbook\", package: \"flipbook\")"
            }
        }

        var description: String {
            switch self {
            case let .checkout(url): return "the checkout at \(url.path)"
            case let .release(version): return "\(Workspace.repository) \(version) (fetched on the first build)"
            }
        }
    }

    static func isLibrary(_ folder: URL) -> Bool {
        guard let manifest = try? String(contentsOf: folder.appending(path: "Package.swift"), encoding: .utf8) else { return false }
        return manifest.contains("name: \"Flipbook\"") && manifest.contains(".library(name: \"Flipbook\"")
    }

    var library: Library {
        if let path = ProcessInfo.processInfo.environment["FLIPBOOK_PACKAGE"], !path.isEmpty {
            return .checkout(URL(filePath: path).standardizedFileURL)
        }
        var folder = (Bundle.main.executableURL ?? URL(filePath: CommandLine.arguments[0])).resolvingSymlinksInPath().deletingLastPathComponent()
        while folder.path != "/" {
            if Workspace.isLibrary(folder) { return .checkout(folder) }
            folder = folder.deletingLastPathComponent()
        }
        return .release(Workspace.version)
    }

    /// A scene in the workspace: the target built from one scene file or one folder of them.
    struct Scene {
        /// What the person wrote: a `.swift` file, or a folder with a `main.swift`.
        let origin: URL
        let target: String
        let folder: URL

        var name: String { origin.hasDirectoryPath ? origin.lastPathComponent : origin.deletingPathExtension().lastPathComponent }
        /// The folder files next to the scene are found in.
        var directory: URL { origin.hasDirectoryPath ? origin : origin.deletingLastPathComponent() }
    }

    func scene(at path: String) throws -> Scene {
        var isFolder: ObjCBool = false
        let plain = URL(filePath: path).standardizedFileURL
        guard FileManager.default.fileExists(atPath: plain.path, isDirectory: &isFolder) else {
            throw Failure("there is no scene at \(plain.path)", fix: "Write one with `flipbook new \(path)`.")
        }
        let origin = URL(filePath: plain.path, directoryHint: isFolder.boolValue ? .isDirectory : .notDirectory)
        if isFolder.boolValue {
            guard FileManager.default.fileExists(atPath: origin.appending(path: "main.swift").path) else {
                throw Failure("\(origin.path) has no main.swift", fix: "A scene folder needs a main.swift that ends with `try await composition.run()`.")
            }
        } else if origin.pathExtension != "swift" {
            throw Failure("\(origin.path) is not a .swift file", fix: "A scene is a Swift file; `flipbook new scene.swift` writes one to start from.")
        }
        let digest = SHA256.hash(data: Data(origin.path.utf8)).prefix(6).map { String(format: "%02x", $0) }.joined()
        let target = "Scene_\(digest)"
        return Scene(origin: origin, target: target, folder: sources.appending(path: target, directoryHint: .isDirectory))
    }

    /// Copies the scene's Swift files into its target, touching only what changed so that an
    /// unchanged scene is not rebuilt, and rewrites the manifest. Returns whether anything changed.
    @discardableResult
    func sync(_ scene: Scene) throws -> Bool {
        var changed = false
        let files = FileManager.default
        try files.createDirectory(at: scene.folder, withIntermediateDirectories: true)
        var wanted: [String: URL] = [:]
        if scene.origin.hasDirectoryPath {
            for file in try files.contentsOfDirectory(at: scene.origin, includingPropertiesForKeys: nil) where file.pathExtension == "swift" {
                wanted[file.lastPathComponent] = file
            }
        } else {
            wanted["main.swift"] = scene.origin
        }
        for existing in try files.contentsOfDirectory(at: scene.folder, includingPropertiesForKeys: nil) where wanted[existing.lastPathComponent] == nil {
            try files.removeItem(at: existing)
            changed = true
        }
        for (name, source) in wanted {
            let copy = scene.folder.appending(path: name)
            let data = try Data(contentsOf: source)
            if (try? Data(contentsOf: copy)) != data {
                try data.write(to: copy)
                changed = true
            }
        }
        try writeManifest()
        return changed
    }

    func writeManifest() throws {
        let library = library
        let targets = ((try? FileManager.default.contentsOfDirectory(at: sources, includingPropertiesForKeys: nil)) ?? [])
            .filter(\.hasDirectoryPath).map(\.lastPathComponent).sorted()
        let manifest = """
        // swift-tools-version: 6.0
        // Written by the flipbook command; one target per scene. Do not edit.
        import PackageDescription

        let package = Package(
            name: "flipbook-workspace",
            platforms: [.macOS(.v15)],
            dependencies: [\(library.dependency)],
            targets: [
        \(targets.map { "        .executableTarget(name: \"\($0)\", dependencies: [\(library.product)], swiftSettings: [.swiftLanguageMode(.v5)])," }.joined(separator: "\n"))
            ]
        )

        """
        let url = package.appending(path: "Package.swift")
        if (try? String(contentsOf: url, encoding: .utf8)) != manifest {
            try manifest.write(to: url, atomically: true, encoding: .utf8)
        }
    }

    /// Builds the scene and returns its program. Compiler output is shown only when the build fails,
    /// with the workspace's copy of the scene named as the file the person wrote.
    func build(_ scene: Scene, quiet: Bool) throws -> URL {
        let program = package.appending(path: ".build/release/\(scene.target)")
        let first = !FileManager.default.fileExists(atPath: package.appending(path: ".build").path)
        if !quiet {
            let note = first ? "building \(scene.name) and the library for the first time; this takes about a minute\n" : "building \(scene.name)\n"
            FileHandle.standardError.write(Data(note.utf8))
        }
        let result = try Shell.run("/usr/bin/xcrun", ["swift", "build", "-c", "release", "--product", scene.target, "--package-path", package.path])
        guard result.status == 0 else {
            let copy = scene.folder.path + "/"
            let mine = scene.origin.hasDirectoryPath ? scene.origin.path + "/" : nil
            let lines = result.output.replacing(#/\u{1B}\[[0-9;]*m/#, with: "")
                .split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
            // Keep what the compiler said about the scene; drop the build system's narration and
            // the compiler invocation it prints, which is thousands of characters long.
            let noise = ["swift-frontend", "error: SwiftCompile", "error: SwiftDriver", "error: Build failed", "Command line:"]
            let diagnostics = lines.filter { line in
                !noise.contains { line.contains($0) } && !line.trimmingCharacters(in: .whitespaces).isEmpty
                    && (line.contains("error:") || line.contains("warning:") || line.contains("note:") || line.contains("|"))
            }
            let shown = (diagnostics.isEmpty ? lines : diagnostics).joined(separator: "\n")
                .replacingOccurrences(of: copy + (mine == nil ? "main.swift" : ""), with: mine ?? scene.origin.path)
            throw Failure("the scene does not compile\n\n\(shown)", fix: "Fix the errors above in \(scene.origin.path). `flipbook skill` has the API.", status: 2)
        }
        guard FileManager.default.isExecutableFile(atPath: program.path) else {
            throw Failure("the build finished but left no program at \(program.path)", fix: "Run `flipbook clean` and try again.")
        }
        return program
    }
}

/// Something that went wrong, with what to do about it.
struct Failure: Error {
    let message: String
    let fix: String?
    let status: Int32

    init(_ message: String, fix: String? = nil, status: Int32 = 1) {
        self.message = message
        self.fix = fix
        self.status = status
    }
}

enum Shell {
    /// Runs a program and returns its exit status with everything it printed.
    static func run(_ program: String, _ arguments: [String]) throws -> (status: Int32, output: String) {
        let process = Process()
        process.executableURL = URL(filePath: program)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        do { try process.run() } catch { return (127, "\(error.localizedDescription)") }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus, String(decoding: data, as: UTF8.self))
    }

    /// Runs a program with this process's input and output, and returns its exit status.
    static func hand(over program: URL, _ arguments: [String], environment: [String: String]) throws -> Int32 {
        let process = Process()
        process.executableURL = program
        process.arguments = arguments
        process.environment = ProcessInfo.processInfo.environment.merging(environment) { _, new in new }
        try process.run()
        process.waitUntilExit()
        return process.terminationStatus
    }
}
