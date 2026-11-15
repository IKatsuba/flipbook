import CoreVideo
import Metal
import SwiftUI

/// A backdrop drawn by a Metal fragment shader instead of SwiftUI.
///
/// `source` is Metal Shading Language defining
/// `float4 backdrop(float2 point, float2 size, float frame, float time, const float *params)`,
/// which returns an opaque colour for a position in points. It must be a pure function of its arguments.
public struct MetalBackdrop {
    public var source: String
    /// Up to eight numbers handed to the shader for a frame, e.g. the result of `interpolate`.
    public var params: (Frame) -> [Float]

    public init(source: String, params: @escaping (Frame) -> [Float] = { _ in [] }) {
        self.source = source
        self.params = params
    }
}

/// Path 3: the backdrop in one Metal fragment shader, the SwiftUI content drawn by Core Animation
/// into a transparent texture, and the two composited straight into the pixel buffer's IOSurface.
@MainActor
final class MetalCompositePath<Content: View>: FrameRenderer {
    struct Uniforms {
        var size: SIMD2<Float>
        var scale: Float
        var frame: Float
        var time: Float
        var params: (Float, Float, Float, Float, Float, Float, Float, Float) = (0, 0, 0, 0, 0, 0, 0, 0)
    }

    let composition: Composition<Content>
    let backdrop: MetalBackdrop
    let overlay: CoreAnimationPath<Content>
    let overlayTexture: MTLTexture
    let pipeline: MTLRenderPipelineState

    init(_ composition: Composition<Content>) throws {
        guard let backdrop = composition.backdrop else {
            throw FlipbookError.metal("the metal-composite path needs Composition.backdrop")
        }
        self.composition = composition
        self.backdrop = backdrop
        overlay = try CoreAnimationPath(composition, transparent: true)

        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm, width: composition.pixelWidth, height: composition.pixelHeight, mipmapped: false
        )
        descriptor.usage = [.renderTarget, .shaderRead]
        descriptor.storageMode = .private
        guard let texture = overlay.device.makeTexture(descriptor: descriptor) else { throw FlipbookError.metal("cannot make the overlay texture") }
        overlayTexture = texture

        let library: MTLLibrary
        do {
            library = try overlay.device.makeLibrary(source: CompositeShader.prelude + backdrop.source + CompositeShader.stages, options: nil)
        } catch {
            throw FlipbookError.metal("the backdrop shader does not compile: \(error)")
        }
        let pipelineDescriptor = MTLRenderPipelineDescriptor()
        pipelineDescriptor.vertexFunction = library.makeFunction(name: "flipbook_vertex")
        pipelineDescriptor.fragmentFunction = library.makeFunction(name: "flipbook_fragment")
        pipelineDescriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        pipeline = try overlay.device.makeRenderPipelineState(descriptor: pipelineDescriptor)
    }

    func render(_ index: Int, into buffer: CVPixelBuffer) throws {
        try overlay.draw(index, to: overlayTexture)

        let (target, wrapper) = try overlay.texture(for: buffer)
        let frame = composition.frame(at: index)
        var uniforms = Uniforms(
            size: SIMD2(Float(composition.width), Float(composition.height)),
            scale: Float(composition.scale), frame: Float(index), time: Float(frame.time)
        )
        let params = backdrop.params(frame)
        withUnsafeMutableBytes(of: &uniforms.params) { raw in
            for (slot, value) in params.prefix(8).enumerated() { raw.storeBytes(of: value, toByteOffset: slot * 4, as: Float.self) }
        }

        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = target
        pass.colorAttachments[0].loadAction = .dontCare
        pass.colorAttachments[0].storeAction = .store
        guard let commands = overlay.queue.makeCommandBuffer(), let encoder = commands.makeRenderCommandEncoder(descriptor: pass) else {
            throw FlipbookError.metal("cannot start a render pass")
        }
        encoder.setRenderPipelineState(pipeline)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 0)
        encoder.setFragmentTexture(overlayTexture, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
        commands.commit()
        // Same queue as CARenderer, so this also waits for the overlay.
        commands.waitUntilCompleted()
        if let error = commands.error { throw FlipbookError.metal("\(error)") }
        withExtendedLifetime(wrapper) {}
        CVMetalTextureCacheFlush(overlay.textureCache, 0)
    }
}

enum CompositeShader {
    static let prelude = """
    #include <metal_stdlib>
    using namespace metal;

    struct Uniforms {
        float2 size;
        float scale;
        float frame;
        float time;
        float params[8];
    };

    """

    static let stages = """

    struct Varyings { float4 position [[position]]; };

    vertex Varyings flipbook_vertex(uint id [[vertex_id]]) {
        float2 corner = float2((id << 1) & 2, id & 2);
        return { float4(corner * 2 - 1, 0, 1) };
    }

    fragment float4 flipbook_fragment(Varyings in, constant Uniforms &u [[buffer(0)]], texture2d<float> overlay [[texture(0)]]) {
        float2 point = in.position.xy / u.scale;
        float4 below = backdrop(point, u.size, u.frame, u.time, u.params);
        // Premultiplied source-over, in the same gamma-encoded space Core Animation blends in.
        float4 above = overlay.read(uint2(in.position.xy));
        return float4(above.rgb + below.rgb * (1 - above.a), 1);
    }
    """
}
