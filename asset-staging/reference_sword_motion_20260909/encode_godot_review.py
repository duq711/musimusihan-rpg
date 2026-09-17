#!/usr/bin/env python3
"""Build a labeled MP4 from actual Godot capture sequences.

Requires Pillow + PyAV/libx264; no package installation or renderer is invoked.
Default mode requires all six gameplay sequences and encodes every captured frame.
Explicit single-overhead mode preserves 94 source PNGs and encodes 93 at 60fps.
The original PNG area is uncropped; the title is added above it in a separate band.
"""

import argparse
import hashlib
import json
import math
import os
import sys
import tempfile
from fractions import Fraction
from pathlib import Path, PureWindowsPath


ORDER = ("idle", "run", "jump", "right_diagonal", "left_reverse", "overhead")
TITLES = {"idle": "대기", "run": "달리기", "jump": "도약 · 공중 · 착지",
          "right_diagonal": "우측 대각 베기", "left_reverse": "좌측 역베기", "overhead": "상단 내려베기"}
HEADER_HEIGHT = 80


def digest(path):
    value = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            value.update(block)
    return value.hexdigest()


def require(condition, message):
    if not condition:
        raise ValueError(message)


def source_path(root, relative):
    require(isinstance(relative, str), "Frame image path must be text")
    relative = relative.replace("\\", "/")
    require(relative and not relative.startswith("/") and not PureWindowsPath(relative).drive
            and not any(part in {"", ".", ".."} for part in relative.split("/")), "Unsafe frame path: " + relative)
    path = (root / relative).resolve()
    path.relative_to(root)
    require(path.is_file() and path.suffix.lower() == ".png", "Missing PNG frame: " + relative)
    return path


def inspect_capture(manifest_path, Image, single_overhead=False):
    root = manifest_path.parent
    manifest = json.loads(manifest_path.read_text(encoding="utf-8-sig"))
    require(isinstance(manifest, dict), "Capture manifest must contain an object")
    require(manifest.get("failures") == [], "Capture must have an empty failures array")
    require(manifest.get("sources_unchanged_during_capture") is True, "Capture did not confirm unchanged production sources")
    if single_overhead:
        require(manifest.get("preview_kind") == "overhead_only_authored_timing_review"
                and manifest.get("incomplete_delivery") is True
                and manifest.get("gameplay_timing_remapped") is False
                and manifest.get("authored_right_arm_joints_replayed") is True,
                "Single-overhead mode requires explicitly isolated authored-time and right-arm capture metadata")
    renderer = str(manifest.get("actual_renderer", "")).lower()
    require(renderer and renderer not in {"dummy", "headless", "null"}, "Actual renderer metadata is missing")
    fps_value = manifest.get("fps")
    require(type(fps_value) in (int, float) and math.isfinite(fps_value) and 0 < fps_value <= 240,
            "Capture FPS must be a finite positive number no greater than 240")
    fps = Fraction(str(fps_value)).limit_denominator(100000)
    if single_overhead:
        require(fps == 60 and abs(float(manifest.get("duration_seconds", 0.0)) - 1.55) < 1e-5,
                "Single-overhead review must retain 1.55 seconds at 60 fps")
    size = manifest.get("image_size")
    require(isinstance(size, list) and len(size) == 2 and all(type(v) is int and v > 0 for v in size), "Invalid capture image_size")
    sequences = manifest.get("sequences")
    require(isinstance(sequences, list), "Capture sequences are missing")
    by_id = {}
    for sequence in sequences:
        require(isinstance(sequence, dict) and sequence.get("id") not in by_id, "Invalid or duplicate capture sequence")
        by_id[sequence["id"]] = sequence
    order = ("overhead",) if single_overhead else ORDER
    require(all(name in by_id for name in order), "All requested complete capture sequences are required: " + ", ".join(order))
    if single_overhead:
        require(set(by_id) == {"overhead"}, "Single-overhead review must not be presented as a completed multi-clip capture")
    prepared = []
    for name in order:
        sequence = by_id[name]
        require(sequence.get("fps") == fps_value, name + ": sequence FPS differs from capture FPS")
        frames = sequence.get("frames")
        require(isinstance(frames, list) and len(frames) >= 2 and sequence.get("frame_count") == len(frames), name + ": incomplete frame list")
        duration = sequence.get("duration_seconds")
        require(type(duration) in (int, float) and math.isfinite(duration)
                and abs(duration - (len(frames) - 1) / float(fps)) < 1e-5, name + ": captured duration disagrees with frame count/FPS")
        frame_sources, seen = [], set()
        for index, frame in enumerate(frames):
            require(isinstance(frame, dict) and frame.get("frame") == index, name + ": frames must be complete and sequential from zero")
            timestamp = frame.get("time_seconds")
            require(type(timestamp) in (int, float) and math.isfinite(timestamp)
                    and abs(timestamp - index / float(fps)) < 1e-5, name + ": frame timestamp disagrees with manifest FPS")
            if single_overhead:
                require(frame.get("source_motion") == "external_overhead_review" and frame.get("gameplay_timing_remapped") is False,
                        "Frame lacks isolated authored-time review provenance")
            else:
                require(frame.get("reference_motion_available") is True, name + ": frame was captured without authored motion loaded")
            path = source_path(root, frame.get("image"))
            require(path not in seen, name + ": duplicate source PNG")
            seen.add(path)
            with Image.open(path) as pixels:
                require(pixels.format == "PNG" and pixels.size == tuple(size), "Wrong PNG format or dimensions: " + str(path))
                pixels.verify()
            frame_sources.append({"image": frame["image"], "sha256": digest(path), "source_time_seconds": timestamp, "path": path})
        if single_overhead:
            require(len(frame_sources) == 94 and abs(duration - 1.55) < 1e-5, "Single overhead needs 94 endpoint-inclusive source samples")
        prepared.append({"id": name, "frames": frame_sources, "capture_duration_seconds": duration,
                         "encoded_frame_count": len(frame_sources) - (1 if single_overhead else 0)})
    return manifest, fps, tuple(size), prepared


def encode(args):
    import av
    from PIL import Image, ImageDraw, ImageFont

    manifest_path, output = args.manifest.resolve(), args.output.resolve()
    report_path = output.with_suffix(".encode.json")
    require(output.suffix.lower() == ".mp4", "Output must use .mp4")
    require(not output.exists() and not report_path.exists(), "Existing video or report is preserved; choose a new output name")
    require(args.font.is_file(), "Known label font is missing; pass --font with an existing TrueType font")
    manifest_hash = digest(manifest_path)
    manifest, fps, (width, height), sequences = inspect_capture(manifest_path, Image, args.single_overhead_review)
    delivered = set(manifest.get("delivery_scope", {}).get("clips", []))
    partial_gameplay = manifest.get("qa_scope") in {"overhead_integration_and_existing_motion_regressions", "overhead_motion_on_existing_arm"}
    if partial_gameplay:
        require(delivered == {"overhead"} and manifest.get("incomplete_delivery") is True,
                "Partial gameplay review must truthfully identify only the delivered overhead clip")
    av.codec.Codec("libx264", "w")
    font = ImageFont.truetype(str(args.font), 22)
    small_font = ImageFont.truetype(str(args.font), 15)
    for selected in (font, small_font):
        try:
            selected.set_variation_by_name("Regular")
        except (OSError, ValueError):
            pass
    out_width, out_height = width + width % 2, height + HEADER_HEIGHT + height % 2
    output.parent.mkdir(parents=True, exist_ok=True)
    frame_number, segments = 0, []
    with tempfile.TemporaryDirectory(prefix="godot-review-", dir=output.parent) as folder:
        temporary_video = Path(folder) / "review.mp4"
        with av.open(str(temporary_video), "w", format="mp4", options={"movflags": "+faststart"}) as container:
            stream = container.add_stream("libx264", rate=fps)
            stream.width, stream.height = out_width, out_height
            stream.pix_fmt = "yuv420p"
            stream.options = {"crf": "18", "preset": "medium"}
            frame_time_base = Fraction(fps.denominator, fps.numerator)
            stream.time_base = frame_time_base
            for sequence in sequences:
                start_frame = frame_number
                for source in sequence["frames"][:sequence["encoded_frame_count"]]:
                    with Image.open(source["path"]) as pixels:
                        canvas = Image.new("RGB", (out_width, out_height), "#111619")
                        canvas.paste(pixels.convert("RGB"), (0, HEADER_HEIGHT))
                    label = ImageDraw.Draw(canvas)
                    title = "단일 내려베기 · 새 오른팔 · 원본 속도 검토" if args.single_overhead_review else "실제 Godot 캡처 · " + TITLES[sequence["id"]]
                    if partial_gameplay:
                        title = ("새 내리찍기 적용 · " if sequence["id"] in delivered else "기존 동작 연결 확인 · ") + TITLES[sequence["id"]]
                        if manifest.get("qa_scope") == "overhead_motion_on_existing_arm" and sequence["id"] in delivered:
                            title = "새 내리찍기 · 기존 팔 모델 · 새 소매 미적용"
                    label.text((14, 6), title, font=font, fill="white")
                    subtitle = "%s · %.6g fps · 촬영 시각 %.3f초" % (sequence["id"], float(fps), source["source_time_seconds"])
                    label.text((14, 43), subtitle, font=small_font, fill="#B8C5CB")
                    video_frame = av.VideoFrame.from_image(canvas)
                    video_frame.pts = frame_number
                    video_frame.time_base = frame_time_base
                    for packet in stream.encode(video_frame):
                        container.mux(packet)
                    frame_number += 1
                segments.append({"id": sequence["id"], "title": TITLES[sequence["id"]], "first_output_frame": start_frame,
                                 "last_output_frame": frame_number - 1, "output_start_seconds": start_frame / float(fps),
                                 "output_duration_seconds": (frame_number - start_frame) / float(fps),
                                 "capture_duration_seconds": sequence["capture_duration_seconds"],
                                 "terminal_endpoint_preserved_as_png_only": args.single_overhead_review,
                                 "sources": [{k: v for k, v in source.items() if k != "path"} for source in sequence["frames"]]})
            for packet in stream.encode():
                container.mux(packet)
        # Read back the completed file and every decoded frame before publishing.
        with av.open(str(temporary_video)) as check:
            decoded_count = 0
            for index, frame in enumerate(check.decode(video=0)):
                require(frame.width == out_width and frame.height == out_height, "Encoded video dimensions differ")
                require(frame.time is not None and abs(float(frame.time) - index / float(fps)) < 1e-4,
                        "Encoded timestamps differ from the manifest frame rate")
                decoded_count += 1
            require(decoded_count == frame_number, "Encoded video lost captured frames")
        for sequence in sequences:
            require(all(digest(source["path"]) == source["sha256"] for source in sequence["frames"]), "Source PNG changed during encoding")
        require(digest(manifest_path) == manifest_hash, "Capture manifest changed during encoding")
        report = {"status": "pass", "kind": "labeled_review_of_actual_Godot_PNG_sequences",
                  "manifest": str(manifest_path), "manifest_sha256": manifest_hash,
                  "source_renderer": manifest["actual_renderer"], "source_capture_kind": manifest.get("preview_kind", manifest.get("capture_kind")),
                  "fps": float(fps), "frame_count": frame_number, "duration_seconds": frame_number / float(fps),
                  "source_image_size": [width, height], "output_image_size": [out_width, out_height],
                  "labels_outside_original_image": True, "source_png_hashes_unchanged": True,
                  "incomplete_delivery": args.single_overhead_review or bool(manifest.get("incomplete_delivery", False)),
                  "delivery_scope": manifest.get("delivery_scope"),
                  "gameplay_timing_remapped": False if args.single_overhead_review else None,
                  "frame_policy": ("94 source samples include the 1.55s terminal endpoint. Encode the first 93 frames at 60fps for exactly 1.55s; preserve the endpoint PNG and hash for validation."
                                   if args.single_overhead_review else "Every source frame once, including each final endpoint for one frame interval; no interpolation, placeholders, slowdown or omitted phases."),
                  "scope": ("Review encoding of actual Godot player meshes at authored time; no gameplay attack was executed. No claim of reference-video visual equivalence."
                            if args.single_overhead_review else "Review encoding of captured Godot gameplay. No Blender rendering or claim of reference-video visual equivalence."),
                  "output": str(output), "output_sha256": digest(temporary_video), "segments": segments}
        # Exclusive hard-link publication refuses a racing overwrite as well.
        os.link(temporary_video, output)
        with report_path.open("x", encoding="utf-8") as stream:
            json.dump(report, stream, ensure_ascii=False, indent=2)
            stream.write("\n")
    return {"status": "pass", "output": str(output), "report": str(report_path),
            "frames": frame_number, "fps": float(fps), "duration_seconds": frame_number / float(fps)}


def main():
    here = Path(__file__).resolve().parent
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--manifest", type=Path, required=True, help="Actual capture_manifest.json; PNG paths are relative to its folder")
    parser.add_argument("--output", type=Path, required=True, help="New MP4 path; existing files are never overwritten")
    parser.add_argument("--font", type=Path, default=here.parents[1] / "godot-game/assets/fonts/NotoSansKR-Variable.ttf")
    parser.add_argument("--single-overhead-review", action="store_true", help="Explicit incomplete single-clip review: encode 93 frames for exactly 1.55s at 60fps")
    args = parser.parse_args()
    try:
        result = encode(args)
    except Exception as error:
        print(json.dumps({"status": "fail", "error": "%s: %s" % (type(error).__name__, error)}, ensure_ascii=False))
        return 1
    print(json.dumps(result, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    sys.exit(main())
