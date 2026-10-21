// Encodes a screen recording for the website: H.264 at most 1280 pixels wide, at most 30 frames a
// second and 1.2 Mbit/s, without sound, so that the six videos fit the media budget that
// scripts/site.sh checks. It also writes the poster, a JPEG of the first frame, next to the video.
// scripts/site-media.sh calls it.
// Usage: swift scripts/site-video.swift <recording.mov> <out.mp4> <poster.jpg>
import AppKit
import AVFoundation

enum SiteVideo {
    static let maxWidth = 1280.0
    static let frameInterval = 1.0 / 30
    static let bitsPerSecond = 1_200_000

    static func encode(_ source: URL, to destination: URL) async throws -> (width: Int, height: Int) {
        let asset = AVURLAsset(url: source)
        guard let track = try await asset.loadTracks(withMediaType: .video).first else {
            fatalError("site-video: no video in \(source.path)")
        }
        let size = try await track.load(.naturalSize)
        let scale = min(1, maxWidth / size.width)
        let width = Int((size.width * scale / 2).rounded()) * 2
        let height = Int((size.height * scale / 2).rounded()) * 2

        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
        ])
        reader.add(output)

        try? FileManager.default.removeItem(at: destination)
        let writer = try AVAssetWriter(outputURL: destination, fileType: .mp4)
        writer.shouldOptimizeForNetworkUse = true
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
            AVVideoScalingModeKey: AVVideoScalingModeResizeAspect,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: bitsPerSecond,
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
                AVVideoMaxKeyFrameIntervalKey: 60,
                AVVideoExpectedSourceFrameRateKey: 30,
            ],
        ])
        writer.add(input)

        reader.startReading()
        writer.startWriting()
        var lastSlot: Int?
        while let sample = output.copyNextSampleBuffer() {
            let time = CMSampleBufferGetPresentationTimeStamp(sample)
            // Screen recordings run at up to 60 frames a second, more once sped up; keep the first
            // frame in each 1/30 s slot, which keeps 30 a second whatever the source's rate.
            let slot = Int((time.seconds / frameInterval).rounded(.down))
            if let lastSlot {
                if slot == lastSlot { continue }
            } else {
                writer.startSession(atSourceTime: time)
            }
            lastSlot = slot
            while !input.isReadyForMoreMediaData {
                try await Task.sleep(nanoseconds: 2_000_000)
            }
            input.append(sample)
        }
        input.markAsFinished()
        await writer.finishWriting()
        if writer.status != .completed {
            fatalError("site-video: \(writer.error?.localizedDescription ?? "cannot write \(destination.path)")")
        }
        return (width, height)
    }

    /// Reads the frame from the encoded video itself, so the poster always matches it.
    static func writePoster(of video: URL, to destination: URL) async throws {
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: video))
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        let (image, _) = try await generator.image(at: .zero)
        guard let data = NSBitmapImageRep(cgImage: image)
            .representation(using: .jpeg, properties: [.compressionFactor: 0.8])
        else { fatalError("site-video: cannot encode the poster") }
        try data.write(to: destination)
    }

    static func run() {
        let arguments = CommandLine.arguments
        guard arguments.count == 4 else {
            fatalError("usage: swift scripts/site-video.swift <recording.mov> <out.mp4> <poster.jpg>")
        }
        let finished = DispatchSemaphore(value: 0)
        Task {
            do {
                let video = URL(fileURLWithPath: arguments[2])
                let size = try await encode(URL(fileURLWithPath: arguments[1]), to: video)
                try await writePoster(of: video, to: URL(fileURLWithPath: arguments[3]))
                print("site-video: \(size.width)×\(size.height)")
            } catch {
                fatalError("site-video: \(error.localizedDescription)")
            }
            finished.signal()
        }
        finished.wait()
    }
}

SiteVideo.run()
