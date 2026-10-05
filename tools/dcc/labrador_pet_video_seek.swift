import Foundation
import AVFoundation

let asset = AVURLAsset(url: URL(fileURLWithPath: CommandLine.arguments[1]))
let track = asset.tracks(withMediaType: .video).first!
let duration = CMTimeGetSeconds(asset.duration)
let fps = Double(track.nominalFrameRate)
let generator = AVAssetImageGenerator(asset: asset)
generator.requestedTimeToleranceBefore = .zero
generator.requestedTimeToleranceAfter = .zero
var samples: [[String: Any]] = []
for proportion in [0.0, 0.18, 0.51, 0.76, 0.96] {
    let requested = floor(duration * proportion * fps) / fps
    var actual = CMTime.zero
    let image = try generator.copyCGImage(at: CMTime(seconds: requested, preferredTimescale: 600), actualTime: &actual)
    let seconds = CMTimeGetSeconds(actual)
    let error = abs(requested - seconds)
    guard error <= 1.0 / fps + 1e-6 else { fatalError("Seek outside one frame") }
    samples.append(["requested_seconds": requested, "actual_seconds": seconds, "error_seconds": error,
                    "width": image.width, "height": image.height])
}
let record: [String: Any] = ["duration_seconds": duration, "fps": fps, "exact_seek_samples": samples, "passed": true]
let data = try JSONSerialization.data(withJSONObject: record, options: [.prettyPrinted, .sortedKeys])
try data.write(to: URL(fileURLWithPath: CommandLine.arguments[2]))
print(String(data: data, encoding: .utf8)!)
