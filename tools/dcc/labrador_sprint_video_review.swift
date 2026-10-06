// Read-only local authored movie review: dynamic cycle/fps and repeat-boundary samples.
// Usage: swift tool.swift video.mp4 decoded-dir receipt.json cycle-seconds video-summary.json
import Foundation
import AVFoundation
import ImageIO
import UniformTypeIdentifiers

guard CommandLine.arguments.count == 6 else {
    fatalError("Expected video, decoded directory, receipt, cycle seconds and video-summary JSON")
}
let source = URL(fileURLWithPath: CommandLine.arguments[1])
let output = URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true)
let receipt = URL(fileURLWithPath: CommandLine.arguments[3])
let cycle = Double(CommandLine.arguments[4])!
guard cycle > 0 else { fatalError("Cycle duration must be positive") }
let summaryData = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[5]))
let summary = try JSONSerialization.jsonObject(with: summaryData) as! [String: Any]
let timeline = summary["timeline"] as! [[String: Any]]
let asset = AVURLAsset(url: source)
let track = asset.tracks(withMediaType: .video).first!
let fps = Double(track.nominalFrameRate)
let exactFrameDuration = track.minFrameDuration
let duration = CMTimeGetSeconds(asset.duration)
if let declaredFPS = summary["fps"] as? NSNumber {
    guard abs(fps - declaredFPS.doubleValue) < 0.001 else { fatalError("Movie/summary fps mismatch") }
}
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
let generator = AVAssetImageGenerator(asset: asset)
generator.requestedTimeToleranceBefore = .zero
generator.requestedTimeToleranceAfter = .zero
var records: [[String: Any]] = []
var shotRecords: [[String: Any]] = []
for (shotIndex, shot) in timeline.enumerated() {
    let first = (shot["first_frame"] as! NSNumber).intValue - 1
    let last = (shot["last_frame"] as! NSNumber).intValue - 1
    let rate = (shot["playback_rate"] as! NSNumber).doubleValue
    let view = shot["view"] as! String
    let cycleFrames = cycle * fps / rate
    let count = Int(ceil(cycleFrames - 1e-8))
    let firstAfterBoundary = count
    let boundaryFrames = [firstAfterBoundary - 2, firstAfterBoundary - 1,
                          firstAfterBoundary, firstAfterBoundary + 1]
    var offsets = Set(0..<count)
    for offset in boundaryFrames where offset >= 0 { offsets.insert(offset) }
    guard first + offsets.max()! <= last else { fatalError("Shot too short for one cycle plus repeat boundary") }
    let name = "shot\(shotIndex)_\(view)_\(rate == 1 ? "normal" : "half")"
    for offset in offsets.sorted() {
        let frame = first + offset
        let exactRequested = CMTimeMultiply(exactFrameDuration, multiplier: Int32(frame))
        let requested = CMTimeGetSeconds(exactRequested)
        var actual = CMTime.zero
        let image = try generator.copyCGImage(at: exactRequested, actualTime: &actual)
        let actualSeconds = CMTimeGetSeconds(actual)
        guard abs(requested - actualSeconds) < 1.0 / fps * 0.01 else { fatalError("Unexpected decoded sample time frame=\(frame) fps=\(fps) requested=\(requested) actual=\(actualSeconds)") }
        let filename = String(format: "%@_%03d.png", name, offset)
        let url = output.appendingPathComponent(filename)
        let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { fatalError("Cannot save decoded frame") }
        let unwrappedPhase = Double(offset) / fps * rate / cycle
        records.append(["shot": name, "movie_frame_zero_based": frame, "offset_frame": offset,
                        "requested_seconds": requested, "actual_seconds": actualSeconds,
                        "unwrapped_phase": unwrappedPhase, "phase": unwrappedPhase.truncatingRemainder(dividingBy: 1),
                        "loop_boundary_sample": boundaryFrames.contains(offset),
                        "decoded_file": filename, "width": image.width, "height": image.height])
    }
    shotRecords.append(["shot": name, "playback_rate": rate, "cycle_frame_count": count,
                        "cycle_frame_count_exact": cycleFrames, "unique_decoded_samples": offsets.count,
                        "repeat_boundary_offset_frames": boundaryFrames])
}
let report: [String: Any] = ["scope": "Exactly decoded authored local movie one-cycle frame progression plus two samples on each side of the first repeat boundary. No remote reference media download.",
                           "source_file": source.path, "fps_from_actual_track": fps,
                           "duration_seconds": duration, "cycle_duration_seconds": cycle,
                           "shots": shotRecords, "decoded_samples": records, "sample_count": records.count,
                           "limits": ["This exports a frame sequence for actual visual inspection; decode success alone is not a naturalness acceptance."]]
let data = try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
try data.write(to: receipt)
print("SPRINT_TEMPORAL_SAMPLES", records.count)
