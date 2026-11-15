import AVFoundation
import CoreVideo
import SwiftUI

/// A video described as a pure function from frame number to SwiftUI view.
///
/// `width` and `height` are in points; the output is `width * scale` by `height * scale` pixels.
@MainActor
public struct Composition<Content: View> {
    public var width: Int
    public var height: Int
    public var fps: Int
    public var frames: Int
    public var scale: Int
    public var content: (Frame) -> Content
    /// Used only by `RenderPath.metalComposite`, which draws it under `content`.
    public var backdrop: MetalBackdrop?

    public init(
        width: Int,
        height: Int,
        fps: Int = 30,
        frames: Int,
        scale: Int = 1,
        @ViewBuilder content: @escaping (Frame) -> Content
    ) {
        self.width = width
        self.height = height
        self.fps = fps
        self.frames = frames
        self.scale = scale
        self.content = content
    }

    public var pixelWidth: Int { width * scale }
    public var pixelHeight: Int { height * scale }

    public func frame(at index: Int) -> Frame {
        Frame(index: index, fps: fps, frames: frames, scale: scale)
    }

    /// The view for one frame, pinned to the composition's size.
    func sized(at index: Int) -> SizedFrame<Content> {
        SizedFrame(content: content(frame(at: index)), width: CGFloat(width), height: CGFloat(height))
    }
}

struct SizedFrame<Content: View>: View {
    let content: Content
    let width: CGFloat
    let height: CGFloat

    var body: some View {
        content
            .frame(width: width, height: height)
            .clipped()
            // Animations would make a frame depend on the frames rendered before it.
            .transaction { $0.disablesAnimations = true; $0.animation = nil }
    }
}

public enum Codec: String, Sendable, CaseIterable {
    case hevc
    case h264

    var avCodec: AVVideoCodecType {
        switch self {
        case .hevc: return .hevc
        case .h264: return .h264
        }
    }
}

/// How frames get from SwiftUI into pixel buffers.
public enum RenderPath: String, Sendable, CaseIterable {
    /// `ImageRenderer.cgImage`, then a Core Graphics draw into the pixel buffer.
    case imageRenderer = "image-renderer"
    /// `ImageRenderer.render` straight into a `CGContext` that wraps the pixel buffer.
    case imageRendererDirect = "image-renderer-direct"
    /// An offscreen `NSHostingView` whose layer tree `CARenderer` draws into the pixel buffer's IOSurface.
    case coreAnimation = "core-animation"
    /// `Composition.backdrop` in a Metal shader, with the SwiftUI content drawn over it by Core Animation.
    case metalComposite = "metal-composite"
}

public enum FlipbookError: Error, CustomStringConvertible {
    case rendererProducedNoImage(frame: Int)
    case pixelBuffer(String, CVReturn)
    case writer(String)
    case metal(String)

    public var description: String {
        switch self {
        case let .rendererProducedNoImage(frame): return "ImageRenderer produced no image for frame \(frame)"
        case let .pixelBuffer(what, code): return "\(what) failed (CVReturn \(code))"
        case let .writer(message): return "AVAssetWriter: \(message)"
        case let .metal(message): return "Metal: \(message)"
        }
    }
}
