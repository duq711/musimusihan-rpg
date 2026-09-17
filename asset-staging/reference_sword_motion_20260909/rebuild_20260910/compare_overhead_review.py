"""Compare actual decoded reference and authored videos at their original speed.

This is review composition, never animation authoring or a claim of similarity.
Requires PyAV and Pillow. The source files and their hashes are preserved.
"""
import argparse
import hashlib
import json
from fractions import Fraction
from pathlib import Path

import av
from PIL import Image, ImageDraw


def sha256(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def frames_at(path, start, count, fps):
    targets = [start + i / fps for i in range(count)]
    result = []
    previous = None
    with av.open(str(path)) as container:
        stream = container.streams.video[0]
        if not stream.average_rate or float(stream.average_rate) < fps - 0.01:
            raise ValueError(f"{path.name}: requires genuine {fps} fps or higher input")
        for frame in container.decode(video=0):
            stamp = float(frame.time)
            while targets and stamp + 1e-8 >= targets[0]:
                target = targets.pop(0)
                chosen = frame
                if previous is not None and abs(float(previous.time) - target) < abs(stamp - target):
                    chosen = previous
                if abs(float(chosen.time) - target) > 0.5 / fps + 0.001:
                    raise ValueError(f"Missing decoded frame near {target:.6f}s in {path.name}")
                result.append((float(chosen.time), chosen.to_image().convert("RGB")))
            previous = frame
            if not targets:
                break
    if targets:
        raise ValueError(f"{path.name}: video ends before the requested original-speed comparison")
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--reference", type=Path, required=True)
    parser.add_argument("--authored", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--reference-start", type=float, default=1040 / 60)
    parser.add_argument("--authored-start", type=float, default=0)
    parser.add_argument("--duration", type=float, default=1.55)
    parser.add_argument("--repeat", type=int, default=3)
    args = parser.parse_args()
    source, authored, output = [p.resolve() for p in (args.reference, args.authored, args.output)]
    report_path = output.with_suffix(".comparison.json")
    if output.exists() or report_path.exists() or output in (source, authored):
        parser.error("Use a new output path; existing sources and reviews are preserved")
    if not 0 < args.duration <= 10 or not 1 <= args.repeat <= 5:
        parser.error("Review duration must be (0,10] seconds and repeat must be 1..5")
    fps = 60
    count = round(args.duration * fps)
    if abs(count / fps - args.duration) > 1e-6:
        parser.error("Duration must span an integral number of 60 Hz intervals")
    before_hashes = {str(p): sha256(p) for p in (source, authored)}
    left = frames_at(source, args.reference_start, count, fps)
    right = frames_at(authored, args.authored_start, count, fps)
    output.parent.mkdir(parents=True, exist_ok=True)
    width, height, band = 640, 360, 32
    with av.open(str(output), "w") as container:
        stream = container.add_stream("libx264", rate=fps)
        stream.width, stream.height = width * 2, height + band
        stream.pix_fmt = "yuv420p"
        stream.options = {"crf": "17", "preset": "medium"}
        for index in range(count * args.repeat):
            i = index % count
            canvas = Image.new("RGB", (width * 2, height + band), "#171a20")
            draw = ImageDraw.Draw(canvas)
            for column, (label, sample) in enumerate((("REFERENCE", left[i]), ("WINDOWS REBUILD", right[i]))):
                stamp, picture = sample
                picture = picture.copy()
                picture.thumbnail((width, height), Image.Resampling.LANCZOS)
                x = column * width
                canvas.paste(picture, (x + (width - picture.width) // 2, band + (height - picture.height) // 2))
                draw.text((x + 10, 10), f"{label}  {stamp:.3f}s  |  1x speed  |  pass {index // count + 1}", fill="white")
            frame = av.VideoFrame.from_image(canvas)
            frame.pts = index
            frame.time_base = Fraction(1, fps)
            for packet in stream.encode(frame):
                container.mux(packet)
        for packet in stream.encode():
            container.mux(packet)
    with av.open(str(output)) as container:
        stamps = [float(frame.time) for frame in container.decode(video=0)]
    if len(stamps) != count * args.repeat or any(b <= a for a, b in zip(stamps, stamps[1:])):
        raise RuntimeError("Encoded review failed full decode/timestamp verification")
    if {str(p): sha256(p) for p in (source, authored)} != before_hashes:
        raise RuntimeError("A source video changed during comparison")
    report = {"status": "comparison_encoded_and_decoded", "similarity_pass_claimed": False,
              "gameplay_timing_remapped": False, "playback_speed": 1, "fps": fps,
              "unique_frames_per_motion": count, "repeat": args.repeat, "frames": len(stamps),
              "reference_start_seconds": args.reference_start, "authored_start_seconds": args.authored_start,
              "motion_duration_seconds": args.duration, "source_sha256": before_hashes,
              "actual_reference_frame_times": [x[0] for x in left],
              "actual_authored_frame_times": [x[0] for x in right],
              "output": str(output), "output_sha256": sha256(output)}
    with report_path.open("x", encoding="utf-8") as handle:
        json.dump(report, handle, indent=2)
    print(json.dumps({"output": str(output), "report": str(report_path), "decoded_frames": len(stamps)}))


if __name__ == "__main__":
    main()
