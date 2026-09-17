"""Losslessly package actual rendered PNG frames; never synthesize a frame."""

import argparse
import hashlib
import json
from pathlib import Path

from PIL import Image, ImageChops


def build(capture: Path) -> None:
    manifest = json.loads((capture / "capture_manifest.json").read_text())
    assert manifest["sources_unchanged_during_capture"]
    assert manifest["expedition_and_cursor_preserved"]
    assert not manifest["failures"]
    assert manifest["actual_renderer"] not in ("", "dummy", "headless")
    encoded = []
    for sequence in manifest["sequences"]:
        source_dir = capture / "sequences" / sequence["id"]
        paths = sorted(source_dir.glob("frame_*.png"))
        assert len(paths) == sequence["frame_count"]
        frames = [Image.open(path).convert("RGBA") for path in paths]
        assert all(frame.size == tuple(manifest["image_size"]) for frame in frames)
        fps = sequence["fps"]
        durations = [round((i + 1) * 1000 / fps) - round(i * 1000 / fps) for i in range(len(frames))]
        output = capture / (sequence["id"] + ".png")
        frames[0].save(output, format="PNG", save_all=True, append_images=frames[1:],
                       duration=durations, loop=0, disposal=0, blend=0)
        with Image.open(output) as animation:
            assert animation.n_frames == len(frames)
            for index, original in enumerate(frames):
                animation.seek(index)
                difference = ImageChops.difference(animation.convert("RGBA"), original)
                assert difference.getbbox(alpha_only=False) is None, (output, index)
        encoded.append({"file": output.name, "frame_count": len(frames), "fps": fps,
                        "sampled_action_seconds": sequence["duration_seconds"],
                        "playback_milliseconds": sum(durations),
                        "pixel_identical_to_source_frames": True,
                        "sha256": hashlib.sha256(output.read_bytes()).hexdigest()})
        print(f"ACTUAL MOTION PREVIEW PASS: {output.name}, {len(frames)} original frames")
    assert encoded, "Capture with FIRST_PERSON_MOTION_QA_SEQUENCE=1 first."
    (capture / "animation_manifest.json").write_text(json.dumps(encoded, indent=2) + "\n")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("capture_directory", type=Path)
    build(parser.parse_args().capture_directory.resolve())
