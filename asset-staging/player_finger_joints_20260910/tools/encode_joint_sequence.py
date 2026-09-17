"""Encode the unmodified, hash-verified GPU sequence as a 15 fps review GIF."""

import argparse
import hashlib
import json
from pathlib import Path

from PIL import Image


def sha256(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--capture-dir", required=True, type=Path)
    args = parser.parse_args()
    directory = args.capture_dir.resolve()
    manifest_path = directory / "capture_manifest.json"
    manifest = json.loads(manifest_path.read_text())
    assert not manifest["failures"]
    assert manifest["sources_unchanged_during_capture"]
    assert manifest["expedition_inventory_and_cursor_preserved"]
    captures = [c for c in manifest["captures"] if c["pose"] == "production_joint_sequence"]
    assert len(captures) == 226
    sources = []
    for index, capture in enumerate(captures):
        path = directory / capture["image"]
        assert capture["sequence_frame"] == index
        assert capture["passed"] and capture["controls_visible"]
        assert sha256(path) == capture["image_sha256"]
        sources.append(path)
    destination = directory / "finger_joint_sequence.gif"
    assert not destination.exists(), "Review exports must use a fresh output path."
    # A shared palette avoids palette changes between frames. No resize, crop,
    # compositing, redraw, camera change or replacement of source pixels occurs.
    with Image.open(sources[7]) as source:
        palette = source.convert("RGB").quantize(colors=256, method=Image.Quantize.MEDIANCUT)
    frames = []
    durations = []
    for index, path in enumerate(sources):
        with Image.open(path) as source:
            assert source.size == (1280, 720)
            frames.append(source.convert("RGB").quantize(palette=palette, dither=Image.Dither.NONE))
        durations.append((round((index + 1) * 100 / 15) - round(index * 100 / 15)) * 10)
    frames[0].save(destination, save_all=True, append_images=frames[1:], duration=durations,
                   loop=0, disposal=1, optimize=False)
    with Image.open(destination) as result:
        encoded_frames = result.n_frames
        total_duration = 0
        for index in range(encoded_frames):
            result.seek(index)
            assert result.size == (1280, 720)
            total_duration += result.info["duration"]
        assert total_duration == sum(durations)
        assert encoded_frames >= 200  # GIF may merge identical consecutive frames.
    report = {
        "status": "passed", "source_manifest_sha256": sha256(manifest_path),
        "source_frames": len(sources), "gif_frames": encoded_frames,
        "size": [1280, 720], "duration_ms": total_duration,
        "source_fps": 15, "loop": "continuous", "gif": destination.name,
        "gif_sha256": sha256(destination), "gif_bytes": destination.stat().st_size,
        "encoding": "256-color shared palette, GIF 10ms timing; original dimensions; no compositing or frame interpolation",
        "sources_verified_against_capture_manifest": True,
    }
    (directory / "animation_manifest.json").write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps(report, indent=2))


if __name__ == "__main__":
    main()
