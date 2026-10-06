#!/usr/bin/env python3
"""Package the new Border Collie's original PNGs; never transform image pixels."""

import argparse
import hashlib
import json
import struct
import tempfile
import zipfile
from datetime import datetime, timezone
from pathlib import Path


DEFAULT_ROOT = (Path(__file__).resolve().parents[2] / "asset-staging" /
                "border-collie-run-imagegen-20261006")
ARCHIVE_NAME = "border-collie-run-original-frames-20261006.zip"
STAGES = {
    "gathered_aerial": "모은 공중 자세",
    "hind_support": "뒷다리 지지",
    "hind_reach": "뒷발 착지 준비",
    "hind_touchdown": "뒷발 착지",
    "hind_loading": "뒷다리 체중 수용",
    "hind_propulsion": "뒷다리 추진",
    "hind_launch": "뒷다리 도약",
    "hind_liftoff": "뒷발 이륙",
    "extended_aerial": "펼친 공중 자세",
    "fore_reach": "앞발 착지 준비",
    "fore_touchdown": "앞발 착지",
    "fore_loading": "앞다리 체중 수용",
    "fore_support": "앞다리 지지",
    "fore_propulsion": "앞다리 추진",
    "fore_launch": "앞다리 이륙",
    "fore_liftoff": "앞발 이륙",
}
CONTACTS = {
    "near_fore": "가까운 앞발", "far_fore": "먼 앞발",
    "near_hind": "가까운 뒷발", "far_hind": "먼 뒷발",
}

HTML = r'''<!doctype html>
<html lang="ko">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="color-scheme" content="light">
<title>보더 콜리 달리기 · 개별 프레임 42장</title>
<style>
:root{font-family:system-ui,-apple-system,BlinkMacSystemFont,"Apple SD Gothic Neo","Noto Sans KR",sans-serif;color:#242725;background:#eeefeb;line-height:1.55}
*{box-sizing:border-box}body{margin:0}main{max-width:1464px;margin:auto;padding:26px 28px 32px}header{display:flex;align-items:flex-end;justify-content:space-between;gap:20px;margin-bottom:18px}.eyebrow{margin:0 0 3px;color:#536355;font-size:12px;letter-spacing:.14em;font-weight:650}h1{margin:0;font-size:clamp(23px,3vw,34px);letter-spacing:-.045em;line-height:1.25}.subtitle{margin:9px 0 0;color:#676d68;font-size:14px}.tag{white-space:nowrap;border:1px solid #c9ceca;border-radius:30px;padding:6px 13px;color:#536355;font-size:12px}.viewer{background:#f8f8f5;border:1px solid #d1d6cf;border-radius:18px;overflow:hidden;box-shadow:0 12px 32px #303a3110}.framebar{display:flex;justify-content:space-between;align-items:center;gap:12px;padding:13px 20px;background:#fbfcf8;border-bottom:1px solid #d9ddd6}.counter{font-variant-numeric:tabular-nums;font-size:14px;font-weight:700}.filename{color:#768073;font:12px ui-monospace,SFMono-Regular,Menlo,monospace}.image-area{position:relative;background:#dfdfda;min-height:180px}.image-area img{display:block;width:100%;height:auto}#load-error{display:none;margin:0;padding:40px 24px;text-align:center;color:#773a2f}.frame-caption{display:flex;justify-content:space-between;align-items:baseline;gap:15px;padding:15px 20px;background:#fbfcf8}.label{margin:0;font-size:18px;font-weight:650;letter-spacing:-.025em}.phase{margin:0;color:#677064;font-size:12px;white-space:nowrap;font-variant-numeric:tabular-nums}.controls{margin-top:18px;padding:20px 23px;background:#fbfcf8;border:1px solid #d1d6cf;border-radius:15px}.navigation{display:flex;gap:8px;align-items:center;justify-content:center}.navigation button,.download{display:inline-flex;align-items:center;justify-content:center;gap:7px;min-height:42px;padding:9px 18px;font:inherit;font-size:14px;font-weight:600;border:1px solid #cbd2c8;border-radius:9px;color:#344735;background:#fff;cursor:pointer;text-decoration:none}.navigation button:hover:not(:disabled),.download:hover{background:#f0f4eb;border-color:#9da99a}.navigation button:disabled{opacity:.36;cursor:default}button:focus-visible,a:focus-visible,input:focus-visible{outline:3px solid #668658;outline-offset:4px}.slider-row{display:flex;align-items:center;gap:14px;margin:21px 0 15px;color:#798273;font-size:12px;font-variant-numeric:tabular-nums}#frame-slider{flex:1;min-width:0;accent-color:#4a6944;cursor:pointer}.below{display:flex;justify-content:space-between;gap:15px;align-items:center}.contact{margin:0;color:#70796b;font-size:12px}.downloads{display:flex;gap:8px;flex-wrap:wrap}.download.primary{background:#344b32;color:#fff;border-color:#344b32}.download.primary:hover{background:#45633f}.download[aria-disabled="true"]{opacity:.45;pointer-events:none}.note{margin:15px 2px 0;max-width:1000px;color:#72796e;font-size:12px}.keys{color:#687560} @media(max-width:700px){main{padding:18px 12px 24px}header{align-items:flex-start}.tag{display:none}.framebar,.frame-caption{padding:11px 14px}.frame-caption{align-items:flex-start;flex-direction:column;gap:2px}.label{font-size:16px}.controls{padding:16px 13px}.below{align-items:flex-start;flex-direction:column}.downloads{width:100%}.download{flex:1;padding:9px 11px}.navigation button{padding:8px 12px;font-size:13px}.filename{font-size:11px}}
@media (min-width:701px){
  .image-area{min-height:0}
  .image-area img{height:min(55vh,380px);max-height:380px;object-fit:contain}
}
@media (min-width:960px){
  main{padding:14px 22px 18px}
  header{align-items:center;margin-bottom:10px}
  .eyebrow{display:none}
  h1{font-size:25px;line-height:1.15}
  .subtitle{font-size:12px;line-height:1.35;margin-top:3px}
  .framebar{padding:7px 16px}
  .counter{font-size:13px}
  .frame-caption{padding:7px 16px}
  .label{font-size:15px}
  .phase{font-size:11px}
  .image-area img{height:max(220px,min(55vh,380px,calc(100dvh - 355px)))}
  .controls{display:grid;grid-template-columns:auto minmax(160px,1fr);gap:12px 18px;padding:12px 16px;margin-top:12px}
  .navigation{justify-content:flex-start;gap:6px}
  .navigation button,.download{min-height:36px;padding:7px 14px}
  .slider-row{margin:0;min-height:36px}
  .below{grid-column:1/-1}
  .note{margin-top:11px}
}
</style>
</head>
<body>
<main>
<header><div><p class="eyebrow">BORDER COLLIE · RUNNING STUDY</p><h1>보더 콜리 달리기</h1><p class="subtitle">한 장씩 살펴보는 42개의 달리기 자세</p></div><span class="tag">개별 원본 PNG · 1536 × 1024</span></header>
<section class="viewer" aria-label="현재 프레임">
<div class="framebar"><span class="counter" id="counter" aria-live="polite">프레임 01 / 42</span><span class="filename" id="filename">Frame_001.png</span></div>
<div class="image-area"><img id="frame-image" src="frames/Frame_001.png" alt="보더 콜리 달리기 프레임 01" width="1536" height="1024"><p id="load-error" role="alert">프레임 파일을 열 수 없습니다. frames 폴더가 갤러리 옆에 있는지 확인해 주세요.</p></div>
<div class="frame-caption"><p class="label" id="pose-label">모은 공중 자세</p><p class="phase" id="phase-label">제작 시점 0.000초 · 60 fps 기준</p></div>
</section>
<section class="controls" aria-label="프레임 이동과 다운로드">
<div class="navigation"><button type="button" id="first" aria-label="첫 프레임">처음</button><button type="button" id="previous" aria-label="이전 프레임">← 이전</button><button type="button" id="next" aria-label="다음 프레임">다음 →</button><button type="button" id="last" aria-label="마지막 프레임">마지막</button></div>
<div class="slider-row"><span>01</span><input id="frame-slider" type="range" min="1" max="42" step="1" value="1" aria-label="프레임 선택" aria-valuetext="프레임 1 / 42"><span>42</span></div>
<div class="below"><p class="contact" id="contact-label">접지 계획: 공중 자세</p><div class="downloads"><a class="download" id="download-frame" href="frames/Frame_001.png" download="Frame_001.png">현재 PNG 다운로드</a><a class="download primary" id="download-all" href="__ARCHIVE_NAME__" download>전체 42장 ZIP 다운로드</a></div></div>
</section>
<p class="note"><span class="keys">키보드 ← →로 이동 · Home / End로 처음과 마지막 이동</span><br>새로 생성한 개의 2D 자세 참고 이미지입니다. 60 fps·0.70초는 제작 순서의 기준이며, 측정된 운동이나 완성된 3D 동작은 아닙니다. 접지 계획은 요청한 자세를 뜻하며 실제 표현은 각 이미지에서 확인할 수 있습니다.</p>
</main>
<script id="frame-data" type="application/json">__FRAME_DATA__</script>
<script>
"use strict";
const data = JSON.parse(document.getElementById("frame-data").textContent);
const frames = data.frames;
const image = document.getElementById("frame-image");
const slider = document.getElementById("frame-slider");
const currentDownload = document.getElementById("download-frame");
let current = 0;
function showFrame(index) {
  current = Math.max(0, Math.min(frames.length - 1, index));
  const frame = frames[current];
  const number = String(frame.frame).padStart(2, "0");
  const relativeImage = "frames/" + frame.filename;
  document.getElementById("counter").textContent = "프레임 " + number + " / " + frames.length;
  document.getElementById("filename").textContent = frame.filename;
  document.getElementById("pose-label").textContent = frame.label_ko;
  document.getElementById("phase-label").textContent = "제작 시점 " + frame.nominal_time_seconds.toFixed(3) + "초 · " + data.nominal_fps + " fps 기준";
  document.getElementById("contact-label").textContent = "접지 계획: " + frame.contacts_ko;
  slider.value = String(frame.frame);
  slider.setAttribute("aria-valuetext", "프레임 " + frame.frame + " / " + frames.length + " · " + frame.label_ko);
  image.style.display = "block";
  document.getElementById("load-error").style.display = "none";
  image.alt = "보더 콜리 달리기 프레임 " + number + ": " + frame.label_ko;
  image.src = relativeImage;
  currentDownload.href = relativeImage;
  currentDownload.download = frame.filename;
  currentDownload.setAttribute("aria-disabled", String(!frame.available));
  currentDownload.tabIndex = frame.available ? 0 : -1;
  document.getElementById("first").disabled = current === 0;
  document.getElementById("previous").disabled = current === 0;
  document.getElementById("next").disabled = current === frames.length - 1;
  document.getElementById("last").disabled = current === frames.length - 1;
}
image.addEventListener("error", () => {
  image.style.display = "none";
  document.getElementById("load-error").style.display = "block";
});
document.getElementById("first").addEventListener("click", () => showFrame(0));
document.getElementById("previous").addEventListener("click", () => showFrame(current - 1));
document.getElementById("next").addEventListener("click", () => showFrame(current + 1));
document.getElementById("last").addEventListener("click", () => showFrame(frames.length - 1));
slider.addEventListener("input", () => showFrame(Number(slider.value) - 1));
currentDownload.addEventListener("click", (event) => {
  if (!frames[current].available) event.preventDefault();
});
document.addEventListener("keydown", (event) => {
  if (event.target === slider || event.altKey || event.ctrlKey || event.metaKey) return;
  const destinations = {ArrowLeft: current - 1, ArrowRight: current + 1, Home: 0, End: frames.length - 1};
  if (Object.prototype.hasOwnProperty.call(destinations, event.key)) {
    event.preventDefault();
    showFrame(destinations[event.key]);
  }
});
if (!data.archive_available) {
  const archiveLink = document.getElementById("download-all");
  archiveLink.setAttribute("aria-disabled", "true");
  archiveLink.textContent = "전체 ZIP 준비 중";
  archiveLink.tabIndex = -1;
  archiveLink.addEventListener("click", (event) => event.preventDefault());
}
showFrame(0);
</script>
</body>
</html>
'''


def write_json(path, value):
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def catalog_frames(root):
    catalog = json.loads((root / "prompts.json").read_text(encoding="utf-8"))
    if catalog.get("schema") != "new-dog-built-in-imagegen-frame-prompts-v1":
        raise ValueError("This helper accepts only the new Border Collie frame catalog")
    frames = sorted(catalog["frames"], key=lambda frame: frame["frame"])
    if [frame["frame"] for frame in frames] != list(range(1, 43)):
        raise ValueError("Expected exactly frames 1 through 42")
    for frame in frames:
        if frame["filename"] != f"Frame_{frame['frame']:03d}.png":
            raise ValueError("Frame filenames must match the catalog sequence")
    return catalog, frames


def write_gallery(root, catalog, frames, archive_available=False):
    export = root / "export"
    export.mkdir(parents=True, exist_ok=True)
    display_frames = []
    for frame in frames:
        display_frames.append({
            "frame": frame["frame"], "filename": frame["filename"],
            "label_ko": frame["label_ko"],
            "stage_ko": STAGES.get(frame["stage"], frame["stage"]),
            "nominal_time_seconds": frame["nominal_time_seconds"],
            "contacts_ko": " · ".join(CONTACTS.get(key, key) for key in
                                      frame["intended_ground_contacts"]) or "공중 자세",
            "available": (export / "frames" / frame["filename"]).is_file(),
        })
    data = json.dumps({"frames": display_frames,
                       "nominal_fps": catalog["nominal_fps"],
                       "archive_available": archive_available}, ensure_ascii=False)
    data = data.replace("<", "\\u003c").replace(">", "\\u003e").replace("&", "\\u0026")
    html = HTML.replace("__FRAME_DATA__", data).replace("__ARCHIVE_NAME__", ARCHIVE_NAME)
    (export / "index.html").write_text(html, encoding="utf-8")


def verify_frames(root, frames):
    entries = []
    for frame in frames:
        n = frame["frame"]
        path = root / "export" / "frames" / frame["filename"]
        receipt = root / "generation" / f"frame{n:03d}.json"
        if not path.is_file() or not receipt.is_file():
            raise ValueError(f"Frame {n:03d} is incomplete; frame and receipt are required")
        record = json.loads(receipt.read_text(encoding="utf-8"))
        if record.get("frame") != n or not record.get("prompt"):
            raise ValueError(f"Frame {n:03d} has an incomplete generation record")
        payload = path.read_bytes()
        if payload[:16] != b"\x89PNG\r\n\x1a\n\x00\x00\x00\rIHDR":
            raise ValueError(f"Frame {n:03d} is not an original PNG")
        resolution = list(struct.unpack(">II", payload[16:24]))
        digest = hashlib.sha256(payload).hexdigest()
        if resolution != [1536, 1024] or digest != record.get("sha256"):
            raise ValueError(f"Frame {n:03d} dimensions or recorded checksum differ")
        source = (record.get("default_image_path") or record.get("default_source") or
                  record.get("original_default_path"))
        if not source or payload != Path(source).read_bytes():
            raise ValueError(f"Frame {n:03d} differs from its selected built-in default image")
        entries.append({
            "frame": n, "file": "frames/" + frame["filename"],
            "sha256": digest, "bytes": len(payload), "resolution": resolution,
            "nominal_time_seconds": frame["nominal_time_seconds"],
            "cycle_phase": frame["cycle_phase"], "stage": frame["stage"],
            "label_ko": frame["label_ko"],
            "intended_ground_contacts": frame["intended_ground_contacts"],
            "pose_description": frame["pose_description"],
            "generation_record": f"generation/frame{n:03d}.json",
            "exact_default_source_copy": True,
            "visual_review": record.get("visual_review"),
        })
    if len({entry["sha256"] for entry in entries}) != 42:
        raise ValueError("Every frame must be an individually generated unique image")
    return entries


def readme(catalog):
    return f"""# 보더 콜리 달리기 개별 원본 / Border Collie original run frames

새 검정·흰색 보더 콜리를 내장 image_gen으로 한 프레임씩 생성한 원본 PNG 42장입니다.
42 original PNGs of a newly generated black-and-white Border Collie, each created by a separate built-in image_gen call.

- `frames/Frame_001.png` … `frames/Frame_042.png`: 1536 × 1024 개별 원본. 픽셀 수정·자르기·리사이즈·보간·합성 없음.
  Individual 1536 × 1024 originals, with no pixel edits, cropping, resizing, interpolation or compositing.
- `manifest.json`: 프레임 순서, SHA-256, 크기, 제작 시점과 개별 검수 한계.
  Frame order, SHA-256 checksums, dimensions, intended art timing and individual review limitations.
- `prompts.json`: 프레임별 자세 제작 지시 / Per-frame pose briefs.
- `generation/`: 실제 사용한 전체 프롬프트·입력 참조·원본 선택 경로와 개별 검수 기록.
  Actual full prompts, references, selected source paths and per-frame review records.

명목상 {catalog['nominal_fps']} fps·{catalog['nominal_period_seconds']:.2f}초는 제작 순서를 나타냅니다. 측정된 운동학·물리 시뮬레이션·완성된 3D 리그나 게임 애니메이션이 아닙니다.
Nominal {catalog['nominal_fps']} fps and {catalog['nominal_period_seconds']:.2f} seconds describe an art schedule, not measured kinematics, physical simulation, a completed 3D rig or game animation.

접지와 자세는 요청한 제작 계획이며 생성 이미지의 정확한 접지·관절·프레임 간 연속성을 보증하지 않습니다. 각 프레임의 검수 메모는 manifest와 generation 기록에서 확인할 수 있습니다.
Contacts and poses are art-direction intent. Exact contacts, joint positions and temporal continuity are not guaranteed; see the per-frame review notes in the manifest and generation records.

프로젝트의 `export/index.html` 갤러리는 한 번에 한 장만 표시합니다. 파일로 직접 열거나 정적 서버에서 사용할 수 있으며, 현재 PNG와 이 전체 ZIP을 내려받을 수 있습니다. ZIP에는 원본 프레임과 제작 기록이 포함됩니다.
The project's `export/index.html` gallery displays one image at a time and works directly from a file or a static server. It offers the current PNG and this complete ZIP. This ZIP contains original frames and production records.

기존 레브라도 모델·게임 소스·최신 실행본은 변경하지 않았습니다.
The former Labrador model, game source and latest playable app remain preserved.
"""


def package(root, catalog, frames):
    entries = verify_frames(root, frames)
    export = root / "export"
    manifest = {
        "schema": "new-border-collie-original-frame-package-v1",
        "created_at_utc": datetime.now(timezone.utc).isoformat(),
        "frame_count": 42, "subject": catalog["subject"],
        "generator": "built-in image_gen, one separate image per call",
        "nominal_fps": catalog["nominal_fps"],
        "nominal_period_seconds": catalog["nominal_period_seconds"],
        "image_processing": "none; exact selected default-source bytes",
        "limits_ko": ["2D 생성 참고 이미지이며 측정된 운동 또는 완성된 3D 게임 동작이 아닙니다.",
                      "접지·자세는 제작 지시이며 개별 표현과 연속성의 한계는 프레임 기록을 확인합니다."],
        "limits_en": ["Generative 2D references, not measured motion or completed 3D game animation.",
                      "Contacts and poses are intended art direction; see individual review limitations."],
        "validation": {"original_copies": 42, "sha256_matches": 42,
                       "unique_images": 42, "png_dimensions_1536_1024": 42},
        "frames": entries,
    }
    write_json(export / "manifest.json", manifest)
    (export / "README.md").write_text(readme(catalog), encoding="utf-8")
    target = export / ARCHIVE_NAME
    with tempfile.NamedTemporaryFile(prefix=".border-collie-", suffix=".zip",
                                     dir=export, delete=False) as temporary:
        temporary_path = Path(temporary.name)
    try:
        with zipfile.ZipFile(temporary_path, "w", compression=zipfile.ZIP_STORED) as archive:
            for frame in frames:
                archive.write(export / "frames" / frame["filename"], "frames/" + frame["filename"])
                record_name = f"generation/frame{frame['frame']:03d}.json"
                archive.write(root / record_name, record_name)
            for filename in ("manifest.json", "README.md"):
                archive.write(export / filename, filename)
            archive.write(root / "prompts.json", "prompts.json")
        with zipfile.ZipFile(temporary_path) as archive:
            bad_file = archive.testzip()
            if bad_file:
                raise ValueError(f"ZIP CRC failed: {bad_file}")
            for entry in entries:
                if hashlib.sha256(archive.read(entry["file"])).hexdigest() != entry["sha256"]:
                    raise ValueError(f"ZIP original checksum differs: {entry['file']}")
        temporary_path.replace(target)
    finally:
        temporary_path.unlink(missing_ok=True)
    write_gallery(root, catalog, frames, archive_available=True)
    return {"frames": 42, "zip": str(target), "zip_bytes": target.stat().st_size,
            "gallery": str(export / "index.html"), "validation": manifest["validation"],
            "zip_crc": "passed", "zip_frame_sha256": 42}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=DEFAULT_ROOT,
                        help="New Border Collie catalog directory")
    parser.add_argument("--gallery-only", action="store_true",
                        help="Create the gallery before all 42 frames are available; do not package")
    args = parser.parse_args()
    root = args.root.resolve()
    catalog, frames = catalog_frames(root)
    if args.gallery_only:
        archive_available = (root / "export" / ARCHIVE_NAME).is_file()
        write_gallery(root, catalog, frames, archive_available=archive_available)
        result = {"gallery": str(root / "export/index.html"), "catalog_frames": len(frames),
                  "available_frames": sum((root / "export/frames" / f["filename"]).is_file() for f in frames),
                  "archive_created": False, "archive_available": archive_available}
    else:
        result = package(root, catalog, frames)
    print(json.dumps(result, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
