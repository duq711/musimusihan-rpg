#!/usr/bin/env python3
"""Generate a silhouette donor with the official MIT-licensed TripoSR Space."""

from __future__ import annotations

import shutil
from pathlib import Path

from gradio_client import Client, handle_file


ROOT = Path(__file__).resolve().parent
INPUT = ROOT / "references" / "mercenary_tpose_front.png"
OUTPUT = ROOT / "triposr" / "mercenary_tpose_triposr_raw_320.glb"


def main() -> None:
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    client = Client("stabilityai/TripoSR")
    processed = client.predict(handle_file(str(INPUT)), True, 0.90, api_name="/preprocess")
    print("PREPROCESSED", processed)
    _obj, glb = client.predict(handle_file(processed), 320, api_name="/generate")
    shutil.copy2(glb, OUTPUT)
    print("TRIPOSR_GLB", OUTPUT, OUTPUT.stat().st_size)


if __name__ == "__main__":
    main()
