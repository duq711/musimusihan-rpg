#!/usr/bin/env python3
"""Use the official TripoSR preprocessor to isolate both T-pose views."""

from pathlib import Path

from gradio_client import Client, handle_file
import numpy as np
from PIL import Image


ROOT = Path(__file__).resolve().parent
client = Client("stabilityai/TripoSR")
for view in ("front", "back"):
    source = ROOT / "references" / f"mercenary_tpose_{view}.png"
    processed = client.predict(handle_file(str(source)), True, 0.90, api_name="/preprocess")
    image = Image.open(processed).convert("RGB").resize((4096, 4096), Image.Resampling.LANCZOS)
    pixels = np.asarray(image, dtype=np.float32)
    distance = np.sqrt(np.sum((pixels - 127.0) ** 2, axis=2))
    mask = np.clip((distance - 3.0) / 18.0, 0.0, 1.0)[..., None]
    fallback = np.full_like(pixels, (20.0, 17.0, 14.0))
    image = Image.fromarray(np.uint8(np.clip(pixels * mask + fallback * (1.0 - mask), 0, 255)), "RGB")
    output = ROOT / "textures" / f"reference_projection_{view}_basecolor_4k.png"
    image.save(output, compress_level=6)
    print(output, image.size)
