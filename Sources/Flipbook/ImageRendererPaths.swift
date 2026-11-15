import CoreVideo
import SwiftUI

/// Draws one frame of a composition into a pixel buffer.
@MainActor
protocol FrameRenderer {
    func render(_ index: Int, into buffer: CVPixelBuffer) throws
}

/// Path 1: `ImageRenderer` rasterises on the CPU into a `CGImage`, which is then drawn into the buffer.
@MainActor
final class ImageRendererPath<Content: View>: FrameRenderer {
    let composition: Composition<Content>
    let renderer: ImageRenderer<SizedFrame<Content>>
    let direct: Bool

    init(_ composition: Composition<Content>, direct: Bool) {
        self.composition = composition
        self.direct = direct
        renderer = ImageRenderer(content: composition.sized(at: 0))
        renderer.scale = CGFloat(composition.scale)
        renderer.proposedSize = ProposedViewSize(width: CGFloat(composition.width), height: CGFloat(composition.height))
        renderer.isOpaque = !composition.transparent
        renderer.colorMode = .nonLinear
    }

    func render(_ index: Int, into buffer: CVPixelBuffer) throws {
        renderer.content = composition.sized(at: index)
        if direct {
            let scale = CGFloat(composition.scale)
            try PixelBuffers.withContext(buffer) { context in
                context.clear(CGRect(x: 0, y: 0, width: context.width, height: context.height))
                context.scaleBy(x: scale, y: scale)
                renderer.render(rasterizationScale: scale) { _, draw in draw(context) }
            }
        } else {
            guard let image = renderer.cgImage else { throw FlipbookError.rendererProducedNoImage(frame: index) }
            try PixelBuffers.withContext(buffer) { context in
                context.setBlendMode(.copy)
                context.interpolationQuality = .none
                context.draw(image, in: CGRect(x: 0, y: 0, width: context.width, height: context.height))
            }
        }
    }
}
