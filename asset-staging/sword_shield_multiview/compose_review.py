#!/usr/bin/env python3
"""Assemble unaltered production captures and generated six-view references.

Usage: python compose_review.py /absolute/path/to/capture_directory

Requires Pillow. Outputs default to CAPTURE_DIRECTORY/review_sheets. Actual
captures are only copied or uniformly resized with contain; they are never
cropped, retouched, contrast-adjusted, or covered by captions. The only crops
are the documented six panels of the two generated reference sheets.
"""

import argparse
import hashlib
import json
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont


STAGING = Path(__file__).resolve().parent
DIRECTIONS = ("front", "back", "left", "right", "top", "bottom")
POSES = ("idle", "guard", "impact", "riposte")
MODELS = (
    ("sword", "rusted_longsword", "LONGSWORD", "sword_views_v2.png", 638),
    ("shield", "weathered_round_shield", "ROUND SHIELD", "shield_views_v1.png", 512),
)
BACKGROUND = (23, 25, 27, 255)
FOREGROUND = (231, 234, 236, 255)
MUTED = (159, 170, 178, 255)
PANEL = 512
GUTTER = 16
CAPTION = 32
TITLE = 48


def font(size):
    for path in (
        "/System/Library/Fonts/Supplemental/Arial.ttf",
        "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf",
    ):
        if Path(path).is_file():
            return ImageFont.truetype(path, size)
    try:
        return ImageFont.load_default(size=size)
    except TypeError:
        return ImageFont.load_default()


def load(path):
    with Image.open(path) as source:
        source.load()
        return source.convert("RGBA")


def sha256(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def canvas(width, height):
    return Image.new("RGBA", (width, height), BACKGROUND)


def text(sheet, at, value, size=22, color=FOREGROUND):
    ImageDraw.Draw(sheet).text(at, value, fill=color, font=font(size))


def contain_paste(sheet, source, box):
    """Return the exact destination rectangle; no crop, mask, or paint pass."""
    x, y, width, height = box
    scale = min(width / source.width, height / source.height)
    dimensions = (max(1, round(source.width * scale)),
                  max(1, round(source.height * scale)))
    fitted = source if source.size == dimensions else source.resize(dimensions, Image.Resampling.LANCZOS)
    left = x + (width - dimensions[0]) // 2
    top = y + (height - dimensions[1]) // 2
    # No mask: RGBA capture pixels, including their original alpha, are copied.
    sheet.paste(fitted, (left, top))
    return {"box": [left, top, *dimensions], "source_size": list(source.size),
            "uniform_scale": scale, "crop": None}


def reference_panels(path, split_y):
    source = load(path)
    if source.size != (1536, 1024):
        raise ValueError(f"Reference must retain its original 1536x1024 layout: {path}")
    images, crops = {}, {}
    for index, direction in enumerate(DIRECTIONS):
        column = index % 3
        top, bottom = (0, split_y) if index < 3 else (split_y, 1024)
        bounds = (column * 512, top, (column + 1) * 512, bottom)
        images[direction] = source.crop(bounds)
        crops[direction] = list(bounds)
    return images, crops


def six_view_sheet(label, captures):
    width = GUTTER + 3 * (PANEL + GUTTER)
    height = TITLE + GUTTER + 2 * (CAPTION + PANEL + GUTTER)
    sheet = canvas(width, height)
    text(sheet, (GUTTER, 12), f"{label} / ACTUAL GAME SIX VIEWS", 25)
    placements = {}
    for index, direction in enumerate(DIRECTIONS):
        x = GUTTER + index % 3 * (PANEL + GUTTER)
        y = TITLE + GUTTER + index // 3 * (CAPTION + PANEL + GUTTER)
        text(sheet, (x, y + 2), direction.upper(), 20, MUTED)
        placements[direction] = contain_paste(sheet, captures[direction], (x, y + CAPTION, PANEL, PANEL))
    return sheet, placements


def comparison_sheet(label, references, captures):
    width = GUTTER + 2 * (PANEL + GUTTER)
    header = TITLE + CAPTION
    height = header + GUTTER + 6 * (CAPTION + PANEL + GUTTER)
    sheet = canvas(width, height)
    text(sheet, (GUTTER, 12), f"{label} / DIRECTION COMPARISON", 25)
    text(sheet, (GUTTER, TITLE), "GENERATED REFERENCE", 19, MUTED)
    text(sheet, (GUTTER * 2 + PANEL, TITLE), "ACTUAL GAME CAPTURE", 19, MUTED)
    placements = {}
    for index, direction in enumerate(DIRECTIONS):
        y = header + GUTTER + index * (CAPTION + PANEL + GUTTER)
        text(sheet, (GUTTER, y + 2), direction.upper(), 20, MUTED)
        placements[direction] = {
            "reference": contain_paste(sheet, references[direction], (GUTTER, y + CAPTION, PANEL, PANEL)),
            "actual": contain_paste(sheet, captures[direction], (GUTTER * 2 + PANEL, y + CAPTION, PANEL, PANEL)),
        }
    return sheet, placements


def first_person_sheet(captures):
    panel_width, panel_height = 960, 540
    width = GUTTER + 2 * (panel_width + GUTTER)
    height = TITLE + GUTTER + 2 * (CAPTION + panel_height + GUTTER)
    sheet = canvas(width, height)
    text(sheet, (GUTTER, 12), "ACTUAL FIRST PERSON / IDLE, GUARD, IMPACT, RIPOSTE", 25)
    placements = {}
    for index, pose in enumerate(POSES):
        x = GUTTER + index % 2 * (panel_width + GUTTER)
        y = TITLE + GUTTER + index // 2 * (CAPTION + panel_height + GUTTER)
        text(sheet, (x, y + 2), pose.upper(), 20, MUTED)
        placements[pose] = contain_paste(sheet, captures[pose], (x, y + CAPTION, panel_width, panel_height))
    return sheet, placements


def save(sheet, path):
    sheet.save(path, format="PNG", optimize=True)
    return {"file": path.name, "size": list(sheet.size), "sha256": sha256(path)}


def compose(capture_directory, output_directory=None):
    capture_directory = Path(capture_directory).expanduser().resolve()
    output_directory = (Path(output_directory).expanduser().resolve() if output_directory
                        else capture_directory / "review_sheets")
    required = [capture_directory / f"{object_id}_{direction}.png"
                for _, object_id, _, _, _ in MODELS for direction in DIRECTIONS]
    required += [capture_directory / f"first_person_{pose}.png" for pose in POSES]
    required += [STAGING / filename for _, _, _, filename, _ in MODELS]
    missing = [str(path) for path in required if not path.is_file()]
    if missing:
        raise FileNotFoundError("Missing source images:\n" + "\n".join(missing))
    # Validate all source images before creating any output files.
    sources = {str(path): {"sha256": sha256(path), "size": list(load(path).size)} for path in required}
    model_data = []
    for slug, object_id, label, filename, split_y in MODELS:
        references, crops = reference_panels(STAGING / filename, split_y)
        captures = {direction: load(capture_directory / f"{object_id}_{direction}.png")
                    for direction in DIRECTIONS}
        model_data.append((slug, label, references, crops, captures))
    poses = {pose: load(capture_directory / f"first_person_{pose}.png") for pose in POSES}
    output_directory.mkdir(parents=True, exist_ok=True)
    manifest = {
        "capture_directory": str(capture_directory), "source_images": sources,
        "actual_capture_processing": "Whole original image, uniform contain resize only; no crop, paint, overlay, color or contrast change.",
        "reference_processing": "Original six-view panel crops, each uniformly contained without stretching.",
        "panel_size": PANEL, "outputs": {},
    }
    for slug, label, references, crops, captures in model_data:
        sheet, placements = six_view_sheet(label, captures)
        record = save(sheet, output_directory / f"{slug}_six_views.png")
        record["actual_placements"] = placements
        manifest["outputs"][f"{slug}_six_views"] = record
        sheet, placements = comparison_sheet(label, references, captures)
        record = save(sheet, output_directory / f"{slug}_reference_vs_game.png")
        record.update(placements=placements, reference_crops=crops)
        manifest["outputs"][f"{slug}_reference_vs_game"] = record
        thumb_height = 1600
        thumbnail = sheet.resize((round(sheet.width * thumb_height / sheet.height), thumb_height), Image.Resampling.LANCZOS)
        manifest["outputs"][f"{slug}_comparison_thumbnail"] = save(thumbnail, output_directory / f"{slug}_comparison_thumbnail.png")
    sheet, placements = first_person_sheet(poses)
    record = save(sheet, output_directory / "first_person_four_poses.png")
    record["actual_placements"] = placements
    manifest["outputs"]["first_person_four_poses"] = record
    manifest["source_images_unchanged"] = all(sha256(Path(path)) == record["sha256"] for path, record in sources.items())
    if not manifest["source_images_unchanged"]:
        raise RuntimeError("A source image changed while composing review sheets; retry after capture is frozen.")
    (output_directory / "composition_manifest.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    return output_directory, manifest


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("capture_directory", type=Path)
    parser.add_argument("--output-dir", type=Path, help="Default: CAPTURE_DIRECTORY/review_sheets")
    args = parser.parse_args()
    try:
        output, manifest = compose(args.capture_directory, args.output_dir)
    except (OSError, ValueError, RuntimeError) as error:
        parser.exit(1, f"Review composition failed: {error}\n")
    print(f"REVIEW COMPOSITION PASS: {len(manifest['outputs'])} PNG sheets; sources unchanged; {output}")


if __name__ == "__main__":
    main()
