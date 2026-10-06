#!/usr/bin/env python3
"""Verify and package 42 separate v2 imagegen PNGs without changing pixels.

Use the bundled Python with Pillow. --inspect-only never writes output.
--gallery-only supports a clearly incomplete preview while frames are generated.
"""

import argparse
import hashlib
import json
import os
import tempfile
import zipfile
from datetime import datetime, timezone
from pathlib import Path

from PIL import Image


DEFAULT_ROOT = (Path(__file__).resolve().parents[2] / "asset-staging" /
                "border-collie-run-imagegen-v2-20261006")
TEMPLATE = Path(__file__).with_name("border_collie_frames_v2_gallery.html")
ARCHIVE_NAME = "border-collie-run-v2-individual-frames-20261006.zip"
FRAME_COUNT = 42
RESOLUTION = [1536, 1024]
STAGES = {
    "gathered aerial": "모은 공중 자세",
    "hind touchdown": "뒷발 착지",
    "hind loading": "뒷다리 체중 수용",
    "hind support": "뒷다리 지지",
    "hind propulsion": "뒷다리 추진",
    "hind liftoff": "뒷발 이륙",
    "extended aerial": "펼친 공중 자세",
    "fore touchdown": "앞발 착지",
    "fore loading": "앞다리 체중 수용",
    "fore support": "앞다리 지지",
    "fore liftoff": "앞발 이륙",
    "fore recovery": "앞다리 회수",
    "fore landing, compression and release": "앞발 착지 · 체중 수용 · 이륙",
    "hind landing, compression and launch": "뒷발 착지 · 체중 수용 · 추진",
}
CONTACTS = {"near_fore": "가까운 앞발", "far_fore": "먼 앞발",
            "near_hind": "가까운 뒷발", "far_hind": "먼 뒷발"}


def read_json(path):
    return json.loads(path.read_text(encoding="utf-8"))


def json_text(value):
    return json.dumps(value, ensure_ascii=False, indent=2) + "\n"


def atomic_text(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    handle, temporary = tempfile.mkstemp(prefix=".package-v2-", dir=path.parent)
    try:
        with os.fdopen(handle, "w", encoding="utf-8") as stream:
            stream.write(value)
        Path(temporary).replace(path)
    finally:
        Path(temporary).unlink(missing_ok=True)


def read_catalog(root):
    catalog = read_json(root / "prompts.json")
    if not isinstance(catalog, dict) or not isinstance(catalog.get("schema"), str):
        raise ValueError("Expected a v2 catalog object with a schema")
    frames = sorted(catalog.get("frames", []), key=lambda frame: frame["frame"])
    if [frame["frame"] for frame in frames] != list(range(1, FRAME_COUNT + 1)):
        raise ValueError("Expected exactly catalog frames 1 through 42")
    for frame in frames:
        if not isinstance(frame.get("prompt"), str) or not frame["prompt"].strip():
            raise ValueError(f"Frame {frame['frame']:03d} has no prompt")
        if "guide" not in frame or "reference_roles" not in frame:
            raise ValueError("The v2 catalog must include guide and reference_roles")
        filename = f"Frame_{frame['frame']:03d}.png"
        if frame.get("filename", filename) != filename:
            raise ValueError("Catalog filenames must preserve the numbered sequence")
    return catalog, frames


def guide_metadata(root, frame):
    guide = frame.get("guide")
    if isinstance(guide, dict):
        return guide
    if not isinstance(guide, str):
        return {}
    path = Path(guide)
    if not path.is_absolute():
        path = root / path
    if path.suffix.lower() != ".json":
        path = path.with_suffix(".json")
    return read_json(path) if path.is_file() else {}


def verify_frame(root, number, planned=None):
    filename = f"Frame_{number:03d}.png"
    path = root / "export" / "frames" / filename
    receipt_path = root / "generation" / f"frame{number:03d}.json"
    if not path.is_file() or not receipt_path.is_file():
        raise ValueError("PNG and generation receipt are both required")
    record = read_json(receipt_path)
    if record.get("frame") != number:
        raise ValueError("Receipt frame number differs")
    if not isinstance(record.get("prompt"), str) or not record["prompt"].strip():
        raise ValueError("Receipt has no exact generated prompt")
    if "built-in" not in str(record.get("mode", "")).lower():
        raise ValueError("Receipt must identify built-in imagegen mode")
    if record.get("selected_image") != "export/frames/" + filename:
        raise ValueError("Receipt selected_image differs from the packaged PNG")
    payload = path.read_bytes()
    if not payload.startswith(b"\x89PNG\r\n\x1a\n"):
        raise ValueError("Selected frame is not a PNG")
    with Image.open(path) as image:
        if image.format != "PNG" or list(image.size) != RESOLUTION:
            raise ValueError("Expected a 1536 x 1024 PNG")
        image.verify()
    digest = hashlib.sha256(payload).hexdigest()
    if digest != record.get("sha256"):
        raise ValueError("Selected PNG checksum differs from its receipt")
    if record.get("resolution") != RESOLUTION or record.get("bytes") != len(payload):
        raise ValueError("Recorded dimensions or byte count differ")
    source_name = (record.get("default_image_path") or record.get("default_source") or
                   record.get("original_default_path"))
    if not source_name:
        raise ValueError("Receipt has no selected built-in default source")
    source = Path(source_name)
    if not source.is_file() or source.read_bytes() != payload:
        raise ValueError("Selected PNG differs from its built-in default source")
    planned = planned or {}
    guide = guide_metadata(root, planned)
    contacts = [key for key, value in guide.get("legs", {}).items()
                if isinstance(value, dict) and value.get("contact")]
    stage = guide.get("stage", planned.get("stage", ""))
    label = planned.get("label_ko") or STAGES.get(stage.replace("_", " "))
    return {
        "frame": number, "filename": filename, "file": "frames/" + filename,
        "sha256": digest, "bytes": len(payload), "resolution": RESOLUTION,
        "exact_default_source_copy": True,
        "generation_record": f"generation/frame{number:03d}.json",
        "exact_generated_prompt": record["prompt"],
        "referenced_image_paths": record.get("referenced_image_paths", []),
        "reference_roles": planned.get("reference_roles"),
        "guide": planned.get("guide", record.get("guide")),
        "time_seconds": guide.get("time_seconds"),
        "cycle_phase": guide.get("cycle_phase"),
        "stage": stage, "label_ko": label or f"달리기 자세 {number:02d}",
        "contacts_ko": " · ".join(CONTACTS.get(key, key) for key in contacts) or "공중 자세",
        "visual_review": record.get("visual_review"),
        "file_integrity_verified": True,
    }


def inspect(root):
    catalog, frames, catalog_error = None, [], None
    try:
        catalog, frames = read_catalog(root)
    except (ValueError, OSError, KeyError, TypeError) as error:
        catalog_error = str(error)
    planned = {frame["frame"]: frame for frame in frames}
    entries, errors, pending = [], [], []
    for number in range(1, FRAME_COUNT + 1):
        path = root / "export" / "frames" / f"Frame_{number:03d}.png"
        receipt = root / "generation" / f"frame{number:03d}.json"
        if not path.is_file() and not receipt.is_file():
            pending.append(number)
            continue
        try:
            entries.append(verify_frame(root, number, planned.get(number)))
        except (ValueError, OSError, KeyError, TypeError) as error:
            errors.append({"frame": number, "error": str(error)})
    unique = len({entry["sha256"] for entry in entries})
    if unique != len(entries):
        errors.append({"error": "Repeated PNG checksum across numbered frames"})
    complete = catalog_error is None and len(entries) == FRAME_COUNT and not errors
    return catalog, frames, entries, {
        "complete": complete, "catalog_available": catalog_error is None,
        "catalog_error": catalog_error, "verified_frames": len(entries),
        "unique_verified_images": unique, "pending_frames": pending,
        "errors": errors, "scope": "file integrity; no automatic anatomy or motion pass",
    }


def archive_is_current(root, entries):
    archive = root / "export" / ARCHIVE_NAME
    if not archive.is_file() or len(entries) != FRAME_COUNT:
        return False
    try:
        with zipfile.ZipFile(archive) as package:
            previous = json.loads(package.read("manifest.json"))
        old = {frame["frame"]: frame["sha256"] for frame in previous["frames"]}
        return old == {frame["frame"]: frame["sha256"] for frame in entries}
    except (OSError, ValueError, KeyError, zipfile.BadZipFile):
        return False


def gallery_html(root, frames, entries, archive_available=False):
    verified = {entry["frame"]: entry for entry in entries}
    display = []
    for frame in frames:
        number = frame["frame"]
        entry = verified.get(number, {})
        guide = guide_metadata(root, frame)
        stage = guide.get("stage", frame.get("stage", ""))
        display.append({
            "frame": number, "filename": f"Frame_{number:03d}.png",
            "label_ko": entry.get("label_ko") or frame.get("label_ko") or
                        STAGES.get(stage.replace("_", " "), f"달리기 자세 {number:02d}"),
            "contacts_ko": entry.get("contacts_ko", ""),
            "available": number in verified,
        })
    data = json.dumps({"frames": display, "archive_available": archive_available},
                      ensure_ascii=False)
    data = data.replace("<", "\\u003c").replace(">", "\\u003e").replace("&", "\\u0026")
    return TEMPLATE.read_text(encoding="utf-8").replace("__FRAME_DATA__", data).replace(
        "__ARCHIVE_NAME__", ARCHIVE_NAME)


def readme():
    return """# 보더콜리 달리기 v2 / Border Collie run v2

내장 imagegen으로 한 장씩 새로 제작한 개별 원본 PNG 42장입니다.
42 separate original PNGs newly generated one image at a time with built-in imagegen.

- `frames/Frame_001.png` … `frames/Frame_042.png`: 1536 × 1024 원본. 픽셀 수정·리사이즈·보간·합성 없음.
  Original 1536 × 1024 images; no pixel edits, resizing, interpolation or compositing.
- `index.html`: 한 번에 한 장만 표시합니다. 이전/다음, 슬라이더, 반복 재생, 12/24/60 fps 미리보기를 제공합니다.
  Displays one image at a time, with navigation, slider, loop playback and 12/24/60 fps preview settings.
- `manifest.json`: 파일 SHA-256, 원본 동일성, 실제 생성 프롬프트와 개별 검토 메모.
  File checksums, exact source-copy evidence, actual generated prompts and individual review notes.
- `prompts.json`, `generation/`: 제작 계획과 실제 호출 기록 / Art plan and actual per-image generation receipts.

`index.html`을 파일로 직접 열거나 정적 서버에서 열 수 있습니다. 같은 위치의 `frames` 폴더를 유지하세요.
Open index.html directly as a file or through a static server. Keep the sibling frames directory.

미리보기 fps는 재생 설정이며 실제 촬영 속도나 운동 측정값이 아닙니다. 각 PNG는 별도 생성한 2D 이미지입니다.
Preview fps is a playback setting, not a measured capture rate or motion measurement. Each PNG is a separately generated 2D image.

파일·해상도·체크섬 검증은 해부학이나 자연스러운 움직임의 자동 합격을 뜻하지 않습니다.
File, dimension and checksum verification does not automatically establish anatomical or temporal quality.
일부 발 이동·머리 높이·배경 연결 차이가 남아 있으며 완전히 자연스러운 연속 달리기는 아직 검증되지 않았습니다.
Some paw, head-height and background transitions remain uneven; a fully natural continuous run is not verified.
"""


def package(root, catalog, frames, entries, verification):
    if not verification["complete"]:
        raise ValueError("All 42 original PNGs, receipts and the v2 catalog must verify before packaging")
    export = root / "export"
    export.mkdir(parents=True, exist_ok=True)
    manifest = {
        "schema": "border-collie-run-original-frame-package-v2",
        "created_at_utc": datetime.now(timezone.utc).isoformat(),
        "frame_count": FRAME_COUNT,
        "generator": "built-in imagegen, one separate image per call",
        "image_processing": "none; exact selected built-in default-source bytes",
        "preview_rates_fps": [12, 24, 60],
        "preview_rate_is_measured_capture_rate": False,
        "shared_constraints": catalog.get("shared_constraints"),
        "reference_notes": catalog.get("reference_notes"),
        "validation": {"original_copies": FRAME_COUNT, "sha256_matches": FRAME_COUNT,
                       "unique_images": FRAME_COUNT, "png_dimensions_1536_1024": FRAME_COUNT,
                       "file_integrity_only": True},
        "limits_ko": "별도 생성한 2D 자세 참고 이미지입니다. 일부 발 이동·머리·배경 연결 차이가 남아 완전히 자연스러운 연속 달리기는 미검증입니다.",
        "limits_en": "Separate generated 2D pose references. Paw, head and background transitions remain uneven; a fully natural continuous run is not verified.",
        "frames": entries,
    }
    html = gallery_html(root, frames, entries, archive_available=True)
    handle, temporary = tempfile.mkstemp(prefix=".border-collie-v2-", suffix=".zip", dir=export)
    os.close(handle)
    temporary_path = Path(temporary)
    try:
        with zipfile.ZipFile(temporary_path, "w", compression=zipfile.ZIP_STORED) as archive:
            for entry in entries:
                archive.write(export / entry["file"], entry["file"])
                archive.write(root / entry["generation_record"], entry["generation_record"])
            archive.write(root / "prompts.json", "prompts.json")
            archive.writestr("manifest.json", json_text(manifest))
            archive.writestr("README.md", readme())
            archive.writestr("index.html", html)
        with zipfile.ZipFile(temporary_path) as archive:
            bad_file = archive.testzip()
            if bad_file:
                raise ValueError("ZIP CRC failed: " + bad_file)
            for entry in entries:
                if hashlib.sha256(archive.read(entry["file"])).hexdigest() != entry["sha256"]:
                    raise ValueError("ZIP PNG checksum differs: " + entry["file"])
        target = export / ARCHIVE_NAME
        temporary_path.replace(target)
        atomic_text(export / "manifest.json", json_text(manifest))
        atomic_text(export / "README.md", readme())
        atomic_text(export / "index.html", html)
    finally:
        temporary_path.unlink(missing_ok=True)
    return {"frames": FRAME_COUNT, "zip": str(target), "zip_bytes": target.stat().st_size,
            "gallery": str(export / "index.html"), "manifest": str(export / "manifest.json"),
            "validation": manifest["validation"], "zip_crc": "passed",
            "zip_frame_sha256_matches": FRAME_COUNT}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=DEFAULT_ROOT)
    modes = parser.add_mutually_exclusive_group()
    modes.add_argument("--inspect-only", action="store_true", help="Read current files without writing outputs")
    modes.add_argument("--gallery-only", action="store_true", help="Write a preview without creating a ZIP")
    args = parser.parse_args()
    root = args.root.resolve()
    catalog, frames, entries, verification = inspect(root)
    if args.inspect_only:
        print(json_text(verification), end="")
        return
    if not frames:
        parser.exit(1, "Cannot build without a complete v2 prompts catalog: " + str(verification["catalog_error"]) + "\n")
    if args.gallery_only:
        archive_available = verification["complete"] and archive_is_current(root, entries)
        atomic_text(root / "export" / "index.html",
                    gallery_html(root, frames, entries, archive_available))
        result = {"gallery": str(root / "export" / "index.html"), "archive_created": False,
                  "archive_available": archive_available, "verification": verification}
    else:
        if not verification["complete"]:
            print(json_text(verification), end="")
            parser.exit(1, "Packaging deferred: 42 complete verified frames are required.\n")
        result = package(root, catalog, frames, entries, verification)
    print(json_text(result), end="")


if __name__ == "__main__":
    main()
