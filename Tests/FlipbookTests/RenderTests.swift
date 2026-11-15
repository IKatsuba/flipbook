import Foundation
import SwiftUI
import Testing
@testable import Flipbook

/// A small scene with text, a shape and motion: enough to tell frames apart.
@MainActor
func sample(frames: Int = 24, scale: Int = 1) -> Composition<some View> {
    Composition(width: 160, height: 90, fps: 30, frames: frames, scale: scale) { frame in
        ZStack {
            Color.black
            Circle().fill(.pink).frame(width: 30, height: 30).offset(x: frame.snap(frame.interpolate([0, 23], [-50, 50])))
            Text("\(frame.index)").font(.system(size: 20, weight: .bold)).foregroundStyle(.white)
        }
    }
}

func scratch(_ name: String) -> URL {
    FileManager.default.temporaryDirectory.appending(path: "flipbook-tests-\(ProcessInfo.processInfo.processIdentifier)/\(name)")
}

@MainActor @Test func partOfAVideoMatchesTheWhole() async throws {
    let whole = try await sample().video(to: scratch("whole.mp4"), hashFrames: true)
    let part = try await sample().video(to: scratch("part.mp4"), range: 8..<16, hashFrames: true)
    #expect(whole.frames == 24)
    #expect(part.frames == 8)
    #expect(Set(whole.hashes).count == 24)
    #expect(part.hashes == Array(whole.hashes[8..<16]))
}

@MainActor @Test func rangeIsClampedAndMustNotBeEmpty() async throws {
    let stats = try await sample().video(to: scratch("clamped.mp4"), range: 20..<400)
    #expect(stats.frames == 4)
    await #expect(throws: FlipbookError.self) {
        try await sample().video(to: scratch("empty.mp4"), range: 30..<40)
    }
}

@MainActor @Test func stillIsWrittenAsPNG() throws {
    let url = scratch("stills/deep/frame.png")
    try sample(scale: 2).still(at: 5, to: url)
    let source = try #require(CGImageSourceCreateWithURL(url as CFURL, nil))
    let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
    #expect(image.width == 320)
    #expect(image.height == 180)
}

@MainActor @Test func progressCountsEveryFrame() async throws {
    var seen: [Int] = []
    try await sample().video(to: scratch("progress.mp4"), range: 4..<10) { done, total in
        #expect(total == 6)
        seen.append(done)
    }
    #expect(seen == [1, 2, 3, 4, 5, 6])
}
