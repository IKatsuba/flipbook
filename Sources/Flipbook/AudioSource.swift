import AVFoundation

/// An audio file decoded with `AVAssetReader` and fed, re-encoded as AAC, to the writer
/// alongside the video frames.
final class AudioSource {
    let reader: AVAssetReader
    let output: AVAssetReaderTrackOutput
    let input: AVAssetWriterInput
    let start: CMTime
    private var pending: CMSampleBuffer?
    private var finished = false

    /// `start` is where in the file the video's first frame falls; `duration` is the video's length.
    init(url: URL, start: CMTime, duration: CMTime) async throws {
        guard FileManager.default.fileExists(atPath: url.path) else { throw FlipbookError.audio("there is no file at \(url.path)") }
        let asset = AVURLAsset(url: url)
        guard let track = try await asset.loadTracks(withMediaType: .audio).first else {
            throw FlipbookError.audio("\(url.lastPathComponent) has no audio track")
        }
        let description = try await track.load(.formatDescriptions).first?.audioStreamBasicDescription
        let sampleRate = min(description?.mSampleRate ?? 48000, 48000)
        let channels = min(max(Int(description?.mChannelsPerFrame ?? 2), 1), 2)

        self.start = start
        reader = try AVAssetReader(asset: asset)
        reader.timeRange = CMTimeRange(start: start, duration: duration)
        output = AVAssetReaderTrackOutput(track: track, outputSettings: [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: channels,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false,
        ])
        guard reader.canAdd(output) else { throw FlipbookError.audio("cannot read \(url.lastPathComponent)") }
        reader.add(output)
        input = AVAssetWriterInput(mediaType: .audio, outputSettings: [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: channels,
            AVEncoderBitRateKey: 96_000 * channels,
        ])
        input.expectsMediaDataInRealTime = false
    }

    func begin() throws {
        guard reader.startReading() else { throw FlipbookError.audio(reader.error?.localizedDescription ?? "cannot start reading") }
    }

    /// Appends audio that starts before `limit`, as far as the writer will take it. The writer wants
    /// its tracks interleaved, so this runs between video frames rather than after them.
    func pump(upTo limit: CMTime) throws {
        while !finished, input.isReadyForMoreMediaData {
            guard let buffer = pending ?? next() else {
                finished = true
                input.markAsFinished()
                return
            }
            pending = buffer
            guard buffer.presentationTimeStamp < limit else { return }
            guard input.append(buffer) else { throw FlipbookError.audio("the writer refused audio") }
            pending = nil
        }
    }

    /// Everything that is left.
    func drain() async throws {
        while !finished {
            try pump(upTo: .positiveInfinity)
            if !finished { try await Task.sleep(for: .microseconds(250)) }
        }
    }

    /// The next buffer, on the video's clock: zero is the video's first frame.
    private func next() -> CMSampleBuffer? {
        guard let buffer = output.copyNextSampleBuffer() else { return nil }
        guard start != .zero, let timings = try? buffer.sampleTimingInfos() else { return buffer }
        let shifted = timings.map { timing in
            var timing = timing
            timing.presentationTimeStamp = timing.presentationTimeStamp - start
            if timing.decodeTimeStamp.isValid { timing.decodeTimeStamp = timing.decodeTimeStamp - start }
            return timing
        }
        return (try? CMSampleBuffer(copying: buffer, withNewTiming: shifted)) ?? buffer
    }
}
