import AVFoundation
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

/// Terminal ships SF Mono inside its bundle; it is not available by name until registered.
let bundledFonts = URL(filePath: "/System/Applications/Utilities/Terminal.app/Contents/Resources/Fonts")

@MainActor @Test(.enabled(if: FileManager.default.fileExists(atPath: bundledFonts.path)))
func fontsFromFilesRender() throws {
    let names = try Fonts.register(at: bundledFonts.appending(path: "SF-Mono-Bold.otf"))
    #expect(names == ["SFMono-Bold"])
    #expect(try Fonts.register(at: bundledFonts).contains("SFMono-Regular"))

    // Monospaced means "iiii" and "MMMM" are equally wide; in the fallback font they are not.
    func inkWidth(_ text: String) throws -> Int {
        let image = try Composition(width: 200, height: 40, frames: 1) { _ in
            ZStack { Color.black; Text(text).font(.custom("SFMono-Bold", fixedSize: 24)).foregroundStyle(.white) }
        }.still(at: 0)
        let data = try #require(image.dataProvider?.data as Data?)
        let columns = (0..<image.width).filter { x in
            (0..<image.height).contains { y in data[y * image.bytesPerRow + x * 4 + 1] > 128 }
        }
        return (columns.last ?? 0) - (columns.first ?? 0)
    }
    #expect(abs(try inkWidth("iiii") - inkWidth("MMMM")) <= 14)
}

@Test func registeringSomethingElseFails() {
    #expect(throws: FlipbookError.self) { try Fonts.register(at: URL(filePath: "/nonexistent/font.ttf")) }
    #expect(throws: FlipbookError.self) { try Fonts.register(at: URL(filePath: "/etc/hosts")) }
}

/// Two seconds of a 440 Hz tone as a WAV file.
func tone(_ name: String) throws -> URL {
    let url = scratch(name)
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1)!
    let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 88200)!
    buffer.frameLength = 88200
    for sample in 0..<88200 { buffer.floatChannelData![0][sample] = 0.3 * sin(Float(sample) * 2 * .pi * 440 / 44100) }
    try AVAudioFile(forWriting: url, settings: format.settings).write(from: buffer)
    return url
}

@MainActor @Test func soundIsCutToTheVideo() async throws {
    let audio = try tone("tone.wav")
    for (name, range) in [("sound.mp4", 0..<24), ("sound-part.mp4", 12..<24)] {
        let url = scratch(name)
        try await sample().video(to: url, range: range, audio: audio)
        let asset = AVURLAsset(url: url)
        let tracks = try await asset.loadTracks(withMediaType: .audio)
        #expect(tracks.count == 1)
        let length = try await tracks[0].load(.timeRange).duration.seconds
        // 30 fps; AAC rounds to whole packets of 1024 samples.
        #expect(abs(length - Double(range.count) / 30) < 0.06)
        #expect(try await asset.loadTracks(withMediaType: .video).count == 1)
    }
}

@MainActor @Test func missingSoundIsAnError() async throws {
    await #expect(throws: FlipbookError.self) {
        try await sample().video(to: scratch("nosound.mp4"), audio: URL(filePath: "/nonexistent.wav"))
    }
}

/// A pink disc on nothing.
@MainActor
func disc() -> Composition<some View> {
    var composition = Composition(width: 64, height: 64, fps: 30, frames: 6) { _ in
        Circle().fill(.pink).frame(width: 40, height: 40)
    }
    composition.transparent = true
    return composition
}

/// The alpha of the corner and of the centre of a BGRA or RGBA image.
func alphas(_ image: CGImage) throws -> (corner: UInt8, centre: UInt8) {
    let data = try #require(image.dataProvider?.data as Data?)
    let alphaFirst = image.alphaInfo == .premultipliedFirst || image.alphaInfo == .first
    let littleEndian = image.bitmapInfo.contains(.byteOrder32Little)
    // BGRA in memory is "alpha first, little endian"; RGBA is "alpha last".
    let offset = alphaFirst ? (littleEndian ? 3 : 0) : 3
    let at = { (x: Int, y: Int) in data[y * image.bytesPerRow + x * 4 + offset] }
    return (at(1, 1), at(image.width / 2, image.height / 2))
}

@MainActor @Test(arguments: [RenderPath.coreAnimation, .imageRenderer, .imageRendererDirect])
func transparentStillsKeepAlpha(path: RenderPath) throws {
    let clear = try alphas(disc().still(at: 0, path: path))
    #expect(clear.corner == 0)
    #expect(clear.centre == 255)
    let solid = try alphas(sample().still(at: 0, path: path))
    #expect(solid.corner == 255)
}

@MainActor @Test func proRes4444KeepsAlpha() async throws {
    let url = scratch("alpha.mov")
    // Several frames: a target that is not cleared would keep the disc of the frame before.
    try await disc().video(to: url, codec: .proRes4444)
    let asset = AVURLAsset(url: url)
    let track = try #require(try await asset.loadTracks(withMediaType: .video).first)
    let format = try #require(try await track.load(.formatDescriptions).first)
    #expect(format.mediaSubType == .proRes4444)

    let reader = try AVAssetReader(asset: asset)
    let output = AVAssetReaderTrackOutput(track: track, outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA])
    reader.add(output)
    reader.startReading()
    let buffer = try #require(output.copyNextSampleBuffer()?.imageBuffer)
    CVPixelBufferLockBaseAddress(buffer, .readOnly)
    defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
    let base = CVPixelBufferGetBaseAddress(buffer)!.assumingMemoryBound(to: UInt8.self)
    let row = CVPixelBufferGetBytesPerRow(buffer)
    #expect(base[1 * row + 1 * 4 + 3] == 0)
    #expect(base[32 * row + 32 * 4 + 3] == 255)
}

@MainActor @Test func proResNeedsAMovie() async throws {
    let stats = try await sample().video(to: scratch("plain.mov"), codec: .proRes422)
    #expect(stats.frames == 24)
    await #expect(throws: FlipbookError.self) {
        try await sample().video(to: scratch("wrong.mp4"), codec: .proRes422)
    }
}
