"""Generate deterministic 4K PBR texture sets for the game-ready character.

The maps are intentionally authored as UV textures rather than Blender-only
procedural nodes so the Godot glTF export keeps the surface information.
"""

from __future__ import annotations

import math
from pathlib import Path

import numpy as np
from PIL import Image, ImageFilter


ROOT = Path(__file__).resolve().parent
OUT = ROOT / "textures"
OUT.mkdir(parents=True, exist_ok=True)
SIZE = 4096
SEED = 918273


def smooth_noise(size: int, coarse: int, seed: int) -> np.ndarray:
    rng = np.random.default_rng(seed)
    small = np.uint8(rng.random((coarse, coarse)) * 255.0)
    image = Image.fromarray(small, mode="L").resize((size, size), Image.Resampling.BICUBIC)
    return np.asarray(image, dtype=np.float32) / 255.0


def multiscale_noise(seed: int) -> np.ndarray:
    return (
        smooth_noise(SIZE, 32, seed) * 0.44
        + smooth_noise(SIZE, 96, seed + 1) * 0.31
        + smooth_noise(SIZE, 384, seed + 2) * 0.18
        + smooth_noise(SIZE, 1024, seed + 3) * 0.07
    )


def save_rgb_jpg(name: str, array: np.ndarray, quality: int = 94) -> None:
    image = Image.fromarray(np.uint8(np.clip(array, 0.0, 1.0) * 255.0), mode="RGB")
    image.save(OUT / name, quality=quality, subsampling=0, optimize=True)


def save_rgb_png(name: str, array: np.ndarray) -> None:
    image = Image.fromarray(np.uint8(np.clip(array, 0.0, 1.0) * 255.0), mode="RGB")
    image.save(OUT / name, optimize=True, compress_level=8)


def normal_from_height(height: np.ndarray, strength: float) -> np.ndarray:
    gy, gx = np.gradient(height.astype(np.float32))
    nx = -gx * strength
    ny = gy * strength
    nz = np.ones_like(height)
    length = np.sqrt(nx * nx + ny * ny + nz * nz)
    return np.dstack((nx / length * 0.5 + 0.5, ny / length * 0.5 + 0.5, nz / length * 0.5 + 0.5))


def make_skin() -> None:
    noise = multiscale_noise(SEED)
    pores = smooth_noise(SIZE, 1500, SEED + 10)
    freckles = smooth_noise(SIZE, 700, SEED + 11)
    base = np.array([0.34, 0.235, 0.175], dtype=np.float32)
    color = base[None, None, :] * (0.82 + noise[..., None] * 0.34)
    warm = np.clip((freckles - 0.57) * 1.8, 0.0, 1.0)
    color[..., 0] += warm * 0.025
    color[..., 1] -= warm * 0.012
    color[..., 2] -= warm * 0.015
    save_rgb_jpg("skin_basecolor_4k.jpg", color)

    height = (noise - 0.5) * 0.22 + (pores - 0.5) * 0.75
    save_rgb_png("skin_normal_4k.png", normal_from_height(height, 8.0))
    roughness = np.clip(0.56 + (noise - 0.5) * 0.18 + (pores - 0.5) * 0.07, 0.44, 0.72)
    orm = np.dstack((np.full_like(roughness, 0.96), roughness, np.zeros_like(roughness)))
    save_rgb_jpg("skin_orm_4k.jpg", orm, quality=96)


def make_fabric(prefix: str, base_rgb: tuple[float, float, float], seed: int, quilt: bool = False) -> None:
    noise = multiscale_noise(seed)
    weave = smooth_noise(SIZE, 1300, seed + 20)
    yy, xx = np.mgrid[0:SIZE, 0:SIZE]
    warp = 0.5 + 0.5 * np.sin(xx * (math.tau / 9.0))
    weft = 0.5 + 0.5 * np.sin(yy * (math.tau / 11.0))
    fibers = warp * 0.52 + weft * 0.48
    height = (noise - 0.5) * 0.28 + (weave - 0.5) * 0.32 + (fibers - 0.5) * 0.16
    if quilt:
        cell = SIZE / 17.0
        dx = np.minimum(np.mod(xx, cell), cell - np.mod(xx, cell))
        dy = np.minimum(np.mod(yy, cell), cell - np.mod(yy, cell))
        seam = np.exp(-((np.minimum(dx, dy) / 4.6) ** 2))
        puff = np.sin(np.pi * np.mod(xx, cell) / cell) * np.sin(np.pi * np.mod(yy, cell) / cell)
        height += puff * 0.38 - seam * 0.52
    base = np.array(base_rgb, dtype=np.float32)
    color = base[None, None, :] * (0.70 + noise[..., None] * 0.48)
    dirt = np.clip((smooth_noise(SIZE, 80, seed + 40) - 0.56) * 1.7, 0.0, 0.55)
    color *= 1.0 - dirt[..., None] * 0.33
    save_rgb_jpg(f"{prefix}_basecolor_4k.jpg", color)
    save_rgb_png(f"{prefix}_normal_4k.png", normal_from_height(height, 10.0 if quilt else 7.0))
    roughness = np.clip(0.70 + (noise - 0.5) * 0.20 + fibers * 0.06, 0.56, 0.96)
    orm = np.dstack((np.full_like(roughness, 0.93), roughness, np.zeros_like(roughness)))
    save_rgb_jpg(f"{prefix}_orm_4k.jpg", orm, quality=96)


def make_leather() -> None:
    noise = multiscale_noise(SEED + 200)
    grain = smooth_noise(SIZE, 1100, SEED + 201)
    cracks = smooth_noise(SIZE, 240, SEED + 202)
    base = np.array([0.205, 0.112, 0.060], dtype=np.float32)
    color = base[None, None, :] * (0.62 + noise[..., None] * 0.68)
    worn = np.clip((cracks - 0.62) * 2.3, 0.0, 0.7)
    color += worn[..., None] * np.array([0.115, 0.072, 0.042], dtype=np.float32)
    save_rgb_jpg("leather_basecolor_4k.jpg", color)
    height = (noise - 0.5) * 0.28 + (grain - 0.5) * 0.54 - worn * 0.28
    save_rgb_png("leather_normal_4k.png", normal_from_height(height, 8.5))
    roughness = np.clip(0.56 + (noise - 0.5) * 0.25 + grain * 0.08, 0.38, 0.86)
    orm = np.dstack((np.full_like(roughness, 0.92), roughness, np.zeros_like(roughness)))
    save_rgb_jpg("leather_orm_4k.jpg", orm, quality=96)


def make_hair() -> None:
    size = 2048
    rgba = np.zeros((size, size, 4), dtype=np.float32)
    rng = np.random.default_rng(SEED + 500)
    base = np.array([0.055, 0.035, 0.022], dtype=np.float32)
    rgba[..., :3] = base
    canvas = Image.new("L", (size, size), 0)
    from PIL import ImageDraw

    draw = ImageDraw.Draw(canvas)
    for _ in range(190):
        x = int(rng.integers(6, size - 6))
        width = int(rng.integers(2, 8))
        drift = int(rng.integers(-34, 35))
        value = int(rng.integers(105, 235))
        draw.line([(x, 0), (x + drift // 2, size // 2), (x + drift, size - 1)], fill=value, width=width)
    canvas = canvas.filter(ImageFilter.GaussianBlur(radius=1.15))
    alpha = np.asarray(canvas, dtype=np.float32) / 255.0
    fade = np.clip(np.sin(np.linspace(0.0, math.pi, size, dtype=np.float32)), 0.0, 1.0) ** 0.28
    rgba[..., 3] = np.clip(alpha * fade[:, None] * 1.28, 0.0, 1.0)
    rgba[..., :3] *= 0.78 + rgba[..., 3:4] * 0.34
    image = Image.fromarray(np.uint8(np.clip(rgba, 0.0, 1.0) * 255.0), mode="RGBA")
    image.save(OUT / "hair_cards_2k.png", optimize=True, compress_level=8)


if __name__ == "__main__":
    make_skin()
    make_fabric("gambeson", (0.39, 0.335, 0.275), SEED + 100, quilt=True)
    make_fabric("outer_wool", (0.075, 0.072, 0.065), SEED + 130, quilt=False)
    make_fabric("cowl_wool", (0.040, 0.039, 0.036), SEED + 160, quilt=False)
    make_leather()
    make_hair()
    for path in sorted(OUT.iterdir()):
        with Image.open(path) as image:
            print(path.name, image.size, image.mode)
