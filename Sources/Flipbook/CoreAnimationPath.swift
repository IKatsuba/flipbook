import AppKit
import CoreVideo
import Metal
import QuartzCore
import SwiftUI

/// A window that is never put on screen and reports the composition's scale as its backing scale,
/// so SwiftUI rasterises layer contents at that scale whatever display is attached.
final class OffscreenWindow: NSWindow {
    var forcedScale: CGFloat = 1
    override var backingScaleFactor: CGFloat { forcedScale }
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Path 2: an `NSHostingView` in a window that is never ordered in, its layer tree drawn by `CARenderer`
/// into a Metal texture that shares the pixel buffer's IOSurface. No readback, no copy.
///
/// The window is needed: a hosting view with no window does build a layer tree, but at contents scale 1
/// and with sublayers placed bottom-up while their contents stay upright (see README).
@MainActor
final class CoreAnimationPath<Content: View>: FrameRenderer {
    let composition: Composition<Content>
    let hosting: NSHostingView<SizedFrame<Content>>
    let window: OffscreenWindow
    let device: MTLDevice
    let queue: MTLCommandQueue
    let renderer: CARenderer
    let placeholder: MTLTexture
    var textureCache: CVMetalTextureCache!

    let clears: Bool

    /// `transparent` gives the window no background; `clears` empties the target before every frame,
    /// which CARenderer does not do by itself.
    init(_ composition: Composition<Content>, transparent: Bool = false, clears: Bool = false) throws {
        self.composition = composition
        self.clears = clears
        // AppKit's windows and SwiftUI's hosting views want an application object, even off screen.
        _ = NSApplication.shared
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() else {
            throw FlipbookError.metal("no Metal device")
        }
        self.device = device
        self.queue = queue
        let status = CVMetalTextureCacheCreate(nil, nil, device, nil, &textureCache)
        guard status == kCVReturnSuccess else { throw FlipbookError.pixelBuffer("CVMetalTextureCacheCreate", status) }

        let size = CGSize(width: composition.width, height: composition.height)
        let scale = CGFloat(composition.scale)
        hosting = NSHostingView(rootView: composition.sized(at: 0))
        hosting.frame = CGRect(origin: .zero, size: size)
        hosting.sizingOptions = []

        window = OffscreenWindow(contentRect: CGRect(origin: .zero, size: size), styleMask: [.borderless], backing: .buffered, defer: true)
        window.forcedScale = scale
        window.isReleasedWhenClosed = false
        window.colorSpace = .sRGB
        window.backgroundColor = transparent ? .clear : .black
        window.isOpaque = !transparent
        window.contentView = hosting
        hosting.layoutSubtreeIfNeeded()
        window.displayIfNeeded()

        // The destination changes every frame; CARenderer needs a texture to start with.
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm, width: composition.pixelWidth, height: composition.pixelHeight, mipmapped: false
        )
        descriptor.usage = [.renderTarget]
        guard let placeholder = device.makeTexture(descriptor: descriptor) else { throw FlipbookError.metal("cannot make a texture") }
        self.placeholder = placeholder
        renderer = CARenderer(mtlTexture: placeholder, options: [
            kCARendererColorSpace: PixelBuffers.colorSpace,
            kCARendererMetalCommandQueue: queue,
        ])

        // The window's root layer, drawn in pixels: points scaled up, and turned over,
        // because CARenderer's first texture row is the layer tree's bottom.
        var top = hosting.layer
        while let parent = top?.superlayer { top = parent }
        guard let top else { throw FlipbookError.metal("the offscreen window has no layer tree") }
        top.anchorPoint = .zero
        top.position = .zero
        top.setAffineTransform(CGAffineTransform(a: scale, b: 0, c: 0, d: -scale, tx: 0, ty: CGFloat(composition.pixelHeight)))
        renderer.layer = top
        renderer.bounds = CGRect(x: 0, y: 0, width: composition.pixelWidth, height: composition.pixelHeight)
    }

    func render(_ index: Int, into buffer: CVPixelBuffer) throws {
        let (texture, wrapper) = try texture(for: buffer)
        try draw(index, to: texture)
        try waitForGPU()
        withExtendedLifetime(wrapper) {}
    }

    /// The pixel buffer's IOSurface as a render target. Keep the returned wrapper alive until the GPU is done.
    func texture(for buffer: CVPixelBuffer) throws -> (MTLTexture, CVMetalTexture) {
        var wrapped: CVMetalTexture?
        let status = CVMetalTextureCacheCreateTextureFromImage(
            nil, textureCache, buffer, nil, .bgra8Unorm, composition.pixelWidth, composition.pixelHeight, 0, &wrapped
        )
        guard status == kCVReturnSuccess, let wrapped, let texture = CVMetalTextureGetTexture(wrapped) else {
            throw FlipbookError.pixelBuffer("CVMetalTextureCacheCreateTextureFromImage", status)
        }
        return (texture, wrapped)
    }

    /// Updates SwiftUI to frame `index` and has Core Animation draw the layer tree into `texture`.
    func draw(_ index: Int, to texture: MTLTexture) throws {
        hosting.rootView = composition.sized(at: index)
        hosting.layoutSubtreeIfNeeded()
        hosting.displayIfNeeded()
        CATransaction.flush()

        if clears {
            let pass = MTLRenderPassDescriptor()
            pass.colorAttachments[0].texture = texture
            pass.colorAttachments[0].loadAction = .clear
            pass.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
            pass.colorAttachments[0].storeAction = .store
            guard let commands = queue.makeCommandBuffer(), let encoder = commands.makeRenderCommandEncoder(descriptor: pass) else {
                throw FlipbookError.metal("cannot clear the target")
            }
            encoder.endEncoding()
            commands.commit()
        }

        renderer.setDestination(texture)
        renderer.beginFrame(atTime: CACurrentMediaTime(), timeStamp: nil)
        renderer.addUpdate(renderer.bounds)
        renderer.render()
        renderer.endFrame()
    }

    /// CARenderer commits on our queue; a command buffer behind it tells us when the pixels exist.
    func waitForGPU() throws {
        guard let fence = queue.makeCommandBuffer() else { throw FlipbookError.metal("cannot make a command buffer") }
        fence.commit()
        fence.waitUntilCompleted()
        CVMetalTextureCacheFlush(textureCache, 0)
    }

    var layerTree: String { renderer.layer?.dump() ?? "no layer" }
}

extension CALayer {
    /// The layer tree as text: what SwiftUI actually handed to Core Animation.
    func dump(indent: Int = 0) -> String {
        let contentsKind = contents.map { "\(type(of: $0))" } ?? "nil"
        var line = String(repeating: "  ", count: indent)
        line += "\(type(of: self)) frame=\(frame.integral) scale=\(contentsScale) flipped=\(isGeometryFlipped) opacity=\(opacity) contents=\(contentsKind)"
        if let delegate { line += " delegate=\(type(of: delegate))" }
        return ([line] + (sublayers ?? []).map { $0.dump(indent: indent + 1) }).joined(separator: "\n")
    }
}
