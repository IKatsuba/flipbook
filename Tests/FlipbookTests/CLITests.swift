import Foundation
import Testing
@testable import FlipbookCLI

func home() -> URL {
    FileManager.default.temporaryDirectory.appending(path: "flipbook-cli-tests-\(UUID().uuidString)", directoryHint: .isDirectory)
}

@Test func scenesAreCopiedOnlyWhenTheyChange() throws {
    let folder = home()
    setenv("FLIPBOOK_HOME", folder.appending(path: "cache").path, 1)
    defer { unsetenv("FLIPBOOK_HOME") }
    let workspace = Workspace()
    #expect(workspace.home.path.hasSuffix("/cache"))

    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let file = folder.appending(path: "my scene.swift")
    try "print(1)".write(to: file, atomically: true, encoding: .utf8)
    let scene = try workspace.scene(at: file.path)
    #expect(scene.name == "my scene")
    #expect(scene.target.hasPrefix("Scene_") && scene.target.count == 18)
    #expect(try workspace.scene(at: file.path).target == scene.target)

    #expect(try workspace.sync(scene))
    #expect(try !workspace.sync(scene))
    try "print(2)".write(to: file, atomically: true, encoding: .utf8)
    #expect(try workspace.sync(scene))
    #expect(try String(contentsOf: scene.folder.appending(path: "main.swift"), encoding: .utf8) == "print(2)")

    let manifest = try String(contentsOf: workspace.package.appending(path: "Package.swift"), encoding: .utf8)
    #expect(manifest.contains(".executableTarget(name: \"\(scene.target)\""))
    #expect(manifest.contains("Flipbook"))
}

@Test func whatIsNotASceneIsRefused() throws {
    let folder = home()
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let workspace = Workspace()
    #expect(throws: Failure.self) { try workspace.scene(at: folder.appending(path: "missing.swift").path) }
    #expect(throws: Failure.self) { try workspace.scene(at: folder.path) }   // a folder with no main.swift
    try "x".write(to: folder.appending(path: "notes.txt"), atomically: true, encoding: .utf8)
    #expect(throws: Failure.self) { try workspace.scene(at: folder.appending(path: "notes.txt").path) }
    try "print(1)".write(to: folder.appending(path: "main.swift"), atomically: true, encoding: .utf8)
    #expect(try workspace.scene(at: folder.path).directory.path == workspace.scene(at: folder.path).origin.path)
}

@Test func libraryComesFromACheckoutOrARelease() {
    #expect(Workspace.Library.release("1.1.0").dependency.contains("exact: \"1.1.0\""))
    #expect(Workspace.Library.checkout(URL(filePath: "/x/flipbook")).dependency.contains("path: \"/x/flipbook\""))
    // This repository is recognised as the library; a folder that is not one is not.
    let root = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    #expect(Workspace.isLibrary(root))
    #expect(!Workspace.isLibrary(root.appending(path: "Sources")))
}

@Test func theGuideCoversEveryCommand() {
    for word in ["doctor", "render", "still", "info", "preview", "new", "clean", "--json", "frame.snap", "settle", "Assets.url"] {
        #expect(skill.contains(word))
    }
    #expect(starter.contains("try await composition.run()"))
}
