import CoreGraphics
import CoreVideo
import CryptoKit
import Foundation

enum PixelBuffers {
    /// BGRA, IOSurface-backed and Metal-compatible, so every render path can share one pool.
    static func attributes(width: Int, height: Int) -> [String: Any] {
        [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height,
            kCVPixelBufferIOSurfacePropertiesKey as String: [String: Any](),
            kCVPixelBufferMetalCompatibilityKey as String: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey as String: true,
        ]
    }

    static func makePool(width: Int, height: Int) throws -> CVPixelBufferPool {
        var pool: CVPixelBufferPool?
        let status = CVPixelBufferPoolCreate(nil, nil, attributes(width: width, height: height) as CFDictionary, &pool)
        guard status == kCVReturnSuccess, let pool else { throw FlipbookError.pixelBuffer("CVPixelBufferPoolCreate", status) }
        return pool
    }

    static func make(from pool: CVPixelBufferPool) throws -> CVPixelBuffer {
        var buffer: CVPixelBuffer?
        let status = CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer)
        guard status == kCVReturnSuccess, let buffer else { throw FlipbookError.pixelBuffer("CVPixelBufferPoolCreatePixelBuffer", status) }
        return buffer
    }

    static let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!

    /// Runs `body` with a bitmap context that draws straight into the buffer's memory.
    static func withContext<T>(_ buffer: CVPixelBuffer, _ body: (CGContext) throws -> T) throws -> T {
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        guard let context = CGContext(
            data: CVPixelBufferGetBaseAddress(buffer),
            width: CVPixelBufferGetWidth(buffer),
            height: CVPixelBufferGetHeight(buffer),
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
            space: colorSpace,
            bitmapInfo: CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue
        ) else { throw FlipbookError.pixelBuffer("CGContext over pixel buffer", -1) }
        return try body(context)
    }

    /// SHA-256 of the visible pixels, row padding excluded.
    static func hash(_ buffer: CVPixelBuffer) -> String {
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        let base = CVPixelBufferGetBaseAddress(buffer)!
        let rowBytes = CVPixelBufferGetBytesPerRow(buffer)
        let width = CVPixelBufferGetWidth(buffer) * 4
        var hasher = SHA256()
        for row in 0..<CVPixelBufferGetHeight(buffer) {
            hasher.update(bufferPointer: UnsafeRawBufferPointer(start: base + row * rowBytes, count: width))
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    static func image(_ buffer: CVPixelBuffer) throws -> CGImage {
        try withContext(buffer) { context in
            guard let image = context.makeImage() else { throw FlipbookError.pixelBuffer("CGContext.makeImage", -1) }
            return image
        }
    }
}
