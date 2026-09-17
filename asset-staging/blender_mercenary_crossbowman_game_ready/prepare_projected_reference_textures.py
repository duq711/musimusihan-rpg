#!/usr/bin/env python3
"""Build aligned 4K front/back projection textures from clean T-pose references."""

from __future__ import annotations

from pathlib import Path

import numpy as np
from PIL import Image, ImageFilter


ROOT = Path(__file__).resolve().parent
REFERENCE_DIR = ROOT / "references"
TEXTURE_DIR = ROOT / "textures"
TEXTURE_DIR.mkdir(parents=True, exist_ok=True)


def foreground_crop(source: Path) -> Image.Image:
    image = Image.open(source).convert("RGB")
    pixels = np.asarray(image, dtype=np.float32)
    border = np.concatenate(
        (pixels[:24].reshape(-1, 3), pixels[-24:].reshape(-1, 3), pixels[:, :24].reshape(-1, 3), pixels[:, -24:].reshape(-1, 3)),
        axis=0,
    )
    background = np.median(border, axis=0)
    distance = np.sqrt(np.sum((pixels - background) ** 2, axis=2))
    alpha = np.clip((distance - 10.0) / 30.0, 0.0, 1.0)
    alpha_image = Image.fromarray(np.uint8(alpha * 255.0), "L").filter(ImageFilter.GaussianBlur(1.2))
    alpha_array = np.asarray(alpha_image)
    ys, xs = np.nonzero(alpha_array > 96)
    if not len(xs):
        raise RuntimeError(f"Could not isolate subject: {source}")
    margin_x = max(6, int((xs.max() - xs.min()) * 0.012))
    margin_y = max(6, int((ys.max() - ys.min()) * 0.012))
    box = (
        max(0, int(xs.min()) - margin_x),
        max(0, int(ys.min()) - margin_y),
        min(image.width, int(xs.max()) + margin_x + 1),
        min(image.height, int(ys.max()) + margin_y + 1),
    )
    return image.crop(box)


def make_projection(view: str) -> None:
    source = REFERENCE_DIR / f"mercenary_tpose_{view}.png"
    cropped = foreground_crop(source)
    projection = cropped.resize((4096, 4096), Image.Resampling.LANCZOS)
    output = TEXTURE_DIR / f"reference_projection_{view}_basecolor_4k.jpg"
    projection.save(output, quality=96, subsampling=0, optimize=True)
    print(output.name, projection.size)


for direction in ("front", "back"):
    make_projection(direction)
