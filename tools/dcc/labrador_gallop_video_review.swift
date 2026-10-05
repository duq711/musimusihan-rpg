// Read-only exact decoded temporal samples for the normal/half/quarter gallop reel.
import Foundation
import AVFoundation
import ImageIO
import UniformTypeIdentifiers

let source = URL(fileURLWithPath: CommandLine.arguments[1])
let output = URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true)
let receipt = URL(fileURLWithPath: CommandLine.arguments[3])
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
let asset = AVURLAsset(url: source)
let track = asset.tracks(withMediaType: .video).first!
let fps = Double(track.nominalFrameRate)
let duration = CMTimeGetSeconds(asset.duration)
guard abs(fps - 24) < 0.001 && abs(duration - 12) < 0.001 else {
    fatalError("Expected final 24 fps / 12 s gallop review reel")
}
let generator = AVAssetImageGenerator(asset: asset)
generator.requestedTimeToleranceBefore = .zero
generator.requestedTimeToleranceAfter = .zero
let shots: [(String, Int, Int)] = [("normal", 0, 12), ("half", 96, 24), ("quarter", 192, 12)]
var records: [[String: Any]] = []
for (name, start, count) in shots {
    for index in 0..<count {
        let frame = start + index
        let requested = Double(frame) / fps
        var actual = CMTime.zero
        let image = try generator.copyCGImage(at: CMTime(seconds: requested, preferredTimescale: 600), actualTime: &actual)
        let actualSeconds = CMTimeGetSeconds(actual)
        guard abs(requested - actualSeconds) < 0.00001 else { fatalError("Unexpected decoded sample time") }
        let filename = String(format: "%@_%03d.png", name, index)
        let url = output.appendingPathComponent(filename)
        let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { fatalError("Cannot save decoded frame") }
        records.append(["shot": name, "movie_frame_zero_based": frame, "requested_seconds": requested,
                        "actual_seconds": actualSeconds, "phase": Double(index) / Double(count),
                        "decoded_file": filename, "width": image.width, "height": image.height])
    }
}
let report: [String: Any] = ["scope": "Exact decoded one-cycle frame progression:12 normal side,24 half-speed side,12 normal quarter. Frame sequence review is separate from geometry checks.",
                           "source_file": source.path, "fps": fps, "duration_seconds": duration,
                           "decoded_samples": records, "sample_count": records.count]
let data = try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
try data.write(to: receipt)
print("TEMPORAL_SAMPLES", records.count)
