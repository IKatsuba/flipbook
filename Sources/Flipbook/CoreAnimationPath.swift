import CoreVideo
import SwiftUI

@MainActor
final class CoreAnimationPath<Content: View>: FrameRenderer {
    init(_ composition: Composition<Content>) throws {
        throw FlipbookError.metal("the Core Animation path is not built yet")
    }

    func render(_ index: Int, into buffer: CVPixelBuffer) throws {}
}
