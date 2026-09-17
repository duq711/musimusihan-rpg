import Foundation
import AVFoundation
import CoreGraphics
import CoreVideo
import ImageIO
import UniformTypeIdentifiers
import Darwin

// Native H.264 packaging of real PNG captures. No window, audio, synthesis,
// pose modification, color grading, resizing, or downloaded encoder is used.
struct Job: Decodable {
    let frames: [String]
    let fps: Int32
    let output: String
    let verificationDirectory: String
    let verificationFrames: [Int]?
}
enum EncodeError: Error, CustomStringConvertible {
    case failure(String)
    var description: String { switch self { case .failure(let text): return text } }
}
func fail(_ text: String) throws -> Never { throw EncodeError.failure(text) }
func imageAt(_ path: String) throws -> CGImage {
    guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil),
          let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
        try fail("Cannot decode original PNG: \(path)")
    }
    return image
}
func savePNG(_ image: CGImage, _ url: URL) throws {
    guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
        try fail("Cannot write decoded verification frame")
    }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else { try fail("Cannot finish decoded verification PNG") }
}

func encode(_ job: Job) throws {
    guard !job.frames.isEmpty, job.fps > 0, job.fps <= 240 else { try fail("Invalid frame list or frame rate") }
    let first = try imageAt(job.frames[0])
    let width = first.width, height = first.height
    guard width % 2 == 0, height % 2 == 0 else { try fail("H.264 frame dimensions must be even") }
    let destination = URL(fileURLWithPath: job.output)
    guard !FileManager.default.fileExists(atPath: destination.path) else { try fail("Refuse to overwrite an existing video") }
    let writer = try AVAssetWriter(outputURL: destination, fileType: .mp4)
    writer.shouldOptimizeForNetworkUse = true
    let settings: [String: Any] = [
        AVVideoCodecKey: AVVideoCodecType.h264,
        AVVideoWidthKey: width, AVVideoHeightKey: height,
        AVVideoCompressionPropertiesKey: [
            AVVideoAverageBitRateKey: 12_000_000,
            AVVideoExpectedSourceFrameRateKey: Int(job.fps),
            AVVideoMaxKeyFrameIntervalKey: Int(job.fps),
            AVVideoAllowFrameReorderingKey: false,
            AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
        ],
    ]
    guard writer.canApply(outputSettings: settings, forMediaType: .video) else {
        try fail("The installed AVFoundation encoder does not accept H.264 settings")
    }
    let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
    input.expectsMediaDataInRealTime = false
    let attributes: [String: Any] = [
        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB,
        kCVPixelBufferWidthKey as String: width,
        kCVPixelBufferHeightKey as String: height,
        kCVPixelBufferCGImageCompatibilityKey as String: true,
        kCVPixelBufferCGBitmapContextCompatibilityKey as String: true,
    ]
    let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: attributes)
    guard writer.canAdd(input) else { try fail("Cannot attach native video input") }
    writer.add(input)
    guard writer.startWriting() else { try fail("Cannot start writing: \(String(describing: writer.error))") }
    writer.startSession(atSourceTime: .zero)
    let timeout = Date().addingTimeInterval(90)
    for (index, path) in job.frames.enumerated() {
        try autoreleasepool {
            while !input.isReadyForMoreMediaData {
                guard Date() < timeout, writer.status == .writing else {
                    try fail("Native encoder stopped accepting frames: \(String(describing: writer.error))")
                }
                usleep(1000)
            }
            let image = try imageAt(path)
            guard image.width == width, image.height == height else { try fail("Source frame dimensions changed") }
            var buffer: CVPixelBuffer?
            let result = CVPixelBufferCreate(kCFAllocatorDefault, width, height, kCVPixelFormatType_32ARGB, attributes as CFDictionary, &buffer)
            guard result == kCVReturnSuccess, let pixelBuffer = buffer else { try fail("Cannot allocate video pixel buffer") }
            CVPixelBufferLockBaseAddress(pixelBuffer, [])
            defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }
            guard let context = CGContext(data: CVPixelBufferGetBaseAddress(pixelBuffer), width: width, height: height,
                                          bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(pixelBuffer),
                                          space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                          bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.noneSkipFirst.rawValue) else {
                try fail("Cannot create native pixel context")
            }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            guard adaptor.append(pixelBuffer, withPresentationTime: CMTime(value: Int64(index), timescale: job.fps)) else {
                try fail("Cannot append source frame \(index): \(String(describing: writer.error))")
            }
        }
    }
    writer.endSession(atSourceTime: CMTime(value: Int64(job.frames.count), timescale: job.fps))
    input.markAsFinished()
    let finished = DispatchSemaphore(value: 0)
    writer.finishWriting { finished.signal() }
    guard finished.wait(timeout: .now() + 90) == .success, writer.status == .completed else {
        try fail("Native video encoding failed: \(String(describing: writer.error))")
    }

    // Decode actual MP4 checkpoints, and count encoded samples. The Python
    // builder compares these to their corresponding original PNGs.
    let asset = AVURLAsset(url: destination)
    guard let track = asset.tracks(withMediaType: .video).first else { try fail("Encoded MP4 has no video track") }
    let reader = try AVAssetReader(asset: asset)
    let samples = AVAssetReaderTrackOutput(track: track, outputSettings: nil)
    reader.add(samples)
    guard reader.startReading() else { try fail("Cannot inspect encoded video samples") }
    var sampleCount = 0
    var sampleTimes: [Double] = []
    var metadataBuffers = 0
    while let buffer = samples.copyNextSampleBuffer() {
        let count = CMSampleBufferGetNumSamples(buffer)
        if count == 0 { metadataBuffers += 1; continue }
        let seconds = CMSampleBufferGetPresentationTimeStamp(buffer).seconds
        guard count == 1, abs(seconds - Double(sampleCount) / Double(job.fps)) < 0.000001 else {
            try fail("Encoded frame timing or ordering differs from the source sequence")
        }
        sampleTimes.append(seconds)
        sampleCount += count
    }
    guard reader.status == .completed, sampleCount == job.frames.count else {
        try fail("Encoded video lost or added frames: \(sampleCount) / \(job.frames.count)")
    }
    let verification = URL(fileURLWithPath: job.verificationDirectory, isDirectory: true)
    try FileManager.default.createDirectory(at: verification, withIntermediateDirectories: true)
    let generator = AVAssetImageGenerator(asset: asset)
    generator.appliesPreferredTrackTransform = true
    generator.requestedTimeToleranceBefore = .zero
    generator.requestedTimeToleranceAfter = .zero
    let indices = Array(Set(job.verificationFrames ?? [0, min(11, job.frames.count - 1), job.frames.count - 1])).sorted()
    guard !indices.isEmpty, indices.allSatisfy({ $0 >= 0 && $0 < job.frames.count }) else {
        try fail("A requested decoded keyframe is outside the source sequence")
    }
    var decoded: [[String: Any]] = []
    for index in indices {
        var actual = CMTime.zero
        let requested = CMTime(value: Int64(index), timescale: job.fps)
        let image = try generator.copyCGImage(at: requested, actualTime: &actual)
        guard abs(actual.seconds - requested.seconds) < 0.000001 else {
            try fail("Decoded checkpoint time differs from original frame \(index)")
        }
        let imageURL = verification.appendingPathComponent(String(format: "frame_%03d.png", index))
        try savePNG(image, imageURL)
        decoded.append(["frame": index, "time_seconds": actual.seconds, "image": imageURL.path])
    }
    let report: [String: Any] = [
        "encoder": "Installed macOS AVFoundation AVAssetWriter", "codec": "H.264", "container": "MP4",
        "width": width, "height": height, "fps": track.nominalFrameRate,
        "sample_count": sampleCount, "duration_seconds": asset.duration.seconds,
        "sample_times": sampleTimes, "non_image_marker_buffers": metadataBuffers,
        "source_frames": job.frames.count, "decoded_checkpoints": decoded,
        "ai_generated_video": false, "audio_tracks": asset.tracks(withMediaType: .audio).count,
    ]
    let data = try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
    try data.write(to: verification.appendingPathComponent("encoding.json"))
    print("NATIVE VIDEO PASS: \(destination.path); \(sampleCount) actual capture frames at \(job.fps)fps")
}

do {
    guard CommandLine.arguments.count == 2 else { try fail("Usage: encode_capture_video job.json") }
    let data = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))
    try encode(JSONDecoder().decode(Job.self, from: data))
} catch {
    fputs("NATIVE VIDEO FAIL: \(error)\n", stderr)
    exit(1)
}
