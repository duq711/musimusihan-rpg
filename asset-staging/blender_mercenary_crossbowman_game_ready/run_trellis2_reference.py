#!/usr/bin/env python3
"""Generate a T-pose reference mesh with Microsoft's public TRELLIS.2 Space."""

from __future__ import annotations

import shutil
from pathlib import Path

from gradio_client import Client, handle_file


ROOT = Path(__file__).resolve().parent
INPUT = ROOT / "references" / "mercenary_tpose_front.png"
OUTPUT = ROOT / "trellis2" / "mercenary_tpose_trellis2_raw.glb"


def main() -> None:
    if not INPUT.is_file():
        raise FileNotFoundError(INPUT)
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)

    client = Client("microsoft/TRELLIS.2")
    client.predict(api_name="/start_session")
    processed = client.predict(handle_file(str(INPUT)), api_name="/preprocess_image")
    print("PREPROCESSED", processed)
    preview = client.predict(
        processed,
        20260901,
        "1024",
        7.5,
        0.7,
        12,
        5.0,
        7.5,
        0.5,
        12,
        3.0,
        1.0,
        0.0,
        12,
        3.0,
        api_name="/image_to_3d",
    )
    print("PREVIEW_READY", len(preview))
    extracted, downloadable = client.predict(
        120000,
        4096,
        api_name="/extract_glb",
    )
    source = Path(downloadable or extracted)
    shutil.copy2(source, OUTPUT)
    print("TRELLIS2_GLB", OUTPUT, OUTPUT.stat().st_size)


if __name__ == "__main__":
    main()
