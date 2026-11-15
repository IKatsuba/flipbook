import AVFoundation
import CoreVideo
import SwiftUI

/// What a render cost. Stage times are wall-clock sums over all frames.
public struct RenderStats: Sendable, Codable {
    public var frames = 0
    public var pixelWidth = 0
    public var pixelHeight = 0
    /// Building the SwiftUI view and getting its pixels into the buffer.
    public var drawSeconds = 0.0
    /// Hashing, when asked for.
    public var hashSeconds = 0.0
    /// `append`, including waiting for the encoder to take more.
    public var appendSeconds = 0.0
    /// Draining the encoder and closing the file.
    public var finishSeconds = 0.0
    public var totalSeconds = 0.0
    public var hashes: [String] = []

    public init(frames: Int = 0, width: Int = 0, height: Int = 0) {
        self.frames = frames
        pixelWidth = width
        pixelHeight = height
    }

    public var framesPerSecond: Double { totalSeconds > 0 ? Double(frames) / totalSeconds : 0 }
}

extension Duration {
    var seconds: Double {
        let (s, atto) = components
        return Double(s) + Double(atto) * 1e-18
    }
}

extension Composition {
    func makeRenderer(_ path: RenderPath) throws -> any FrameRenderer {
        switch path {
        case .imageRenderer: return ImageRendererPath(self, direct: false)
        case .imageRendererDirect: return ImageRendererPath(self, direct: true)
        case .coreAnimation: return try CoreAnimationPath(self)
        case .metalComposite: return try MetalCompositePath(self)
        }
    }

    /// Encodes the composition to an MP4.
    @discardableResult
    public func video(
        to url: URL,
        codec: Codec = .hevc,
        path: RenderPath = .imageRenderer,
        bitrate: Int? = nil,
        prioritizeSpeed: Bool = false,
        hashFrames: Bool = false
    ) async throws -> RenderStats {
        let sink = try VideoSink(url: url, width: pixelWidth, height: pixelHeight, fps: fps, codec: codec, bitrate: bitrate, prioritizeSpeed: prioritizeSpeed)
        return try await run(renderer: makeRenderer(path), sink: sink, range: 0..<frames, hashFrames: hashFrames)
    }

    /// Renders frames without encoding them and returns the SHA-256 of every pixel buffer.
    public func hashes(path: RenderPath = .imageRenderer, range: Range<Int>? = nil) async throws -> RenderStats {
        try await run(renderer: makeRenderer(path), sink: nil, range: range ?? 0..<frames, hashFrames: true)
    }

    /// One frame as an image.
    public func still(at index: Int, path: RenderPath = .imageRenderer) throws -> CGImage {
        let pool = try PixelBuffers.makePool(width: pixelWidth, height: pixelHeight)
        let buffer = try PixelBuffers.make(from: pool)
        try makeRenderer(path).render(index, into: buffer)
        return try PixelBuffers.image(buffer)
    }

    func run(renderer: any FrameRenderer, sink: VideoSink?, range: Range<Int>, hashFrames: Bool) async throws -> RenderStats {
        let clock = ContinuousClock()
        let pool = sink == nil ? try PixelBuffers.makePool(width: pixelWidth, height: pixelHeight) : nil
        var stats = RenderStats(frames: range.count, width: pixelWidth, height: pixelHeight)
        let start = clock.now

        for index in range {
            var mark = clock.now
            // A fresh buffer per frame: the encoder holds on to the ones it has not finished with.
            let buffer = try sink?.makeBuffer() ?? PixelBuffers.make(from: pool!)
            try renderer.render(index, into: buffer)
            stats.drawSeconds += (clock.now - mark).seconds

            if hashFrames {
                mark = clock.now
                stats.hashes.append(PixelBuffers.hash(buffer))
                stats.hashSeconds += (clock.now - mark).seconds
            }
            if let sink {
                mark = clock.now
                try await sink.append(buffer, frame: index - range.lowerBound)
                stats.appendSeconds += (clock.now - mark).seconds
            }
        }

        if let sink {
            let mark = clock.now
            try await sink.finish(frames: range.count)
            stats.finishSeconds = (clock.now - mark).seconds
        }
        stats.totalSeconds = (clock.now - start).seconds
        return stats
    }
}

extension Composition {
    /// Renders frames one after another with a single renderer and hands each pixel buffer (32BGRA) to `body`.
    /// The buffer is reused, so copy out of it whatever has to outlive the call.
    public func forEachFrame(
        path: RenderPath = .imageRenderer,
        range: Range<Int>? = nil,
        _ body: (Int, CVPixelBuffer) throws -> Void
    ) throws {
        let renderer = try makeRenderer(path)
        let buffer = try PixelBuffers.make(from: PixelBuffers.makePool(width: pixelWidth, height: pixelHeight))
        for index in range ?? 0..<frames {
            try renderer.render(index, into: buffer)
            try body(index, buffer)
        }
    }
}

extension Composition {
    /// The Core Animation layer tree SwiftUI builds for a frame, as text.
    public func layerTree(at index: Int) throws -> String {
        let path = try CoreAnimationPath(self)
        try path.draw(index, to: path.placeholder)
        return path.layerTree
    }
}

extension Composition {
    /// A measurement helper: how fast the encoder alone takes this composition's frames.
    /// Renders `distinct` consecutive frames up front, then times encoding `frames` frames that cycle through them.
    public func encoderCeiling(
        to url: URL, codec: Codec = .hevc, prioritizeSpeed: Bool = false, path: RenderPath = .coreAnimation, distinct: Int = 30
    ) async throws -> RenderStats {
        let renderer = try makeRenderer(path)
        let pool = try PixelBuffers.makePool(width: pixelWidth, height: pixelHeight)
        let start = frames / 2
        let buffers = try (0..<distinct).map { offset in
            let buffer = try PixelBuffers.make(from: pool)
            try renderer.render(start + offset, into: buffer)
            return buffer
        }
        let clock = ContinuousClock()
        var stats = RenderStats(frames: frames, width: pixelWidth, height: pixelHeight)
        let sink = try VideoSink(url: url, width: pixelWidth, height: pixelHeight, fps: fps, codec: codec, bitrate: nil, prioritizeSpeed: prioritizeSpeed)
        let begin = clock.now
        for index in 0..<frames {
            try await sink.append(buffers[index % distinct], frame: index)
        }
        stats.appendSeconds = (clock.now - begin).seconds
        let mark = clock.now
        try await sink.finish(frames: frames)
        stats.finishSeconds = (clock.now - mark).seconds
        stats.totalSeconds = (clock.now - begin).seconds
        return stats
    }
}
