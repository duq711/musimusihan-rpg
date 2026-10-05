import Foundation
import AVFoundation
let asset = AVURLAsset(url: URL(fileURLWithPath: CommandLine.arguments[1]))
let track = asset.tracks(withMediaType: .video).first!
let duration = CMTimeGetSeconds(asset.duration)
let generator = AVAssetImageGenerator(asset: asset)
generator.requestedTimeToleranceBefore = .zero
generator.requestedTimeToleranceAfter = .zero
var samples: [[String: Any]] = []
for requested in [0.0, 5.0, 17.25, 30.0, 31.5] {
    var actual = CMTime.zero
    let image = try generator.copyCGImage(at: CMTime(seconds: requested, preferredTimescale: 600), actualTime: &actual)
    let seconds = CMTimeGetSeconds(actual)
    let error = abs(requested - seconds)
    guard error <= 1.0 / 24.0 else { fatalError("Seek outside one frame") }
    samples.append(["requested_seconds": requested, "actual_seconds": seconds, "error_seconds": error, "width": image.width, "height": image.height])
}
let record: [String: Any] = ["duration_seconds": duration, "fps": track.nominalFrameRate, "exact_seek_samples": samples, "passed": true]
let data = try JSONSerialization.data(withJSONObject: record, options: [.prettyPrinted, .sortedKeys])
try data.write(to: URL(fileURLWithPath: CommandLine.arguments[2]))
print(String(data: data, encoding: .utf8)!)
