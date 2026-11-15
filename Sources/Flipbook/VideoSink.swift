import AVFoundation
import CoreVideo
import VideoToolbox

/// `AVAssetWriter` with a pixel buffer adaptor and a hardware encoder behind it.
final class VideoSink {
    let writer: AVAssetWriter
    let input: AVAssetWriterInput
    let adaptor: AVAssetWriterInputPixelBufferAdaptor
    let fps: Int

    init(url: URL, width: Int, height: Int, fps: Int, codec: Codec, bitrate: Int?, prioritizeSpeed: Bool = false) throws {
        self.fps = fps
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? FileManager.default.removeItem(at: url)
        writer = try AVAssetWriter(outputURL: url, fileType: .mp4)

        // A target, not a floor: flat scenes come out far below 0.1 bit per pixel.
        let rate = bitrate ?? Int(Double(width * height * fps) * 0.1)
        var compression: [String: Any] = [
            AVVideoAverageBitRateKey: rate,
            AVVideoExpectedSourceFrameRateKey: fps,
            AVVideoMaxKeyFrameIntervalKey: fps * 2,
            AVVideoAllowFrameReorderingKey: true,
        ]
        // Tells the hardware encoder to spend less effort per frame; the bitrate target stays the same.
        if prioritizeSpeed { compression[kVTCompressionPropertyKey_PrioritizeEncodingSpeedOverQuality as String] = true }
        if codec == .h264 { compression[AVVideoProfileLevelKey] = AVVideoProfileLevelH264HighAutoLevel }
        let settings: [String: Any] = [
            AVVideoCodecKey: codec.avCodec,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
            AVVideoColorPropertiesKey: [
                AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_709_2,
                AVVideoTransferFunctionKey: AVVideoTransferFunction_ITU_R_709_2,
                AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_709_2,
            ],
            AVVideoCompressionPropertiesKey: compression,
            AVVideoEncoderSpecificationKey: [
                kVTVideoEncoderSpecification_RequireHardwareAcceleratedVideoEncoder as String: true,
            ],
        ]
        input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        input.expectsMediaDataInRealTime = false
        adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: PixelBuffers.attributes(width: width, height: height)
        )
        guard writer.canAdd(input) else { throw FlipbookError.writer("cannot add the video input") }
        writer.add(input)
        guard writer.startWriting() else { throw FlipbookError.writer(writer.error?.localizedDescription ?? "startWriting failed") }
        writer.startSession(atSourceTime: .zero)
    }

    func makeBuffer() throws -> CVPixelBuffer {
        guard let pool = adaptor.pixelBufferPool else { throw FlipbookError.writer("the adaptor has no pixel buffer pool") }
        return try PixelBuffers.make(from: pool)
    }

    func append(_ buffer: CVPixelBuffer, frame: Int) async throws {
        while !input.isReadyForMoreMediaData {
            guard writer.status == .writing else { break }
            try await Task.sleep(for: .microseconds(250))
        }
        let time = CMTime(value: CMTimeValue(frame), timescale: CMTimeScale(fps))
        guard adaptor.append(buffer, withPresentationTime: time) else {
            throw FlipbookError.writer(writer.error?.localizedDescription ?? "append failed at frame \(frame)")
        }
    }

    func finish(frames: Int) async throws {
        input.markAsFinished()
        writer.endSession(atSourceTime: CMTime(value: CMTimeValue(frames), timescale: CMTimeScale(fps)))
        await writer.finishWriting()
        guard writer.status == .completed else {
            throw FlipbookError.writer(writer.error?.localizedDescription ?? "finishWriting ended with status \(writer.status.rawValue)")
        }
    }
}
