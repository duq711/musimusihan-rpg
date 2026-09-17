#!/usr/bin/env python3
"""Package untouched choreography captures as APNGs and a local review page.

Usage: python3 asset-staging/sword_shield_choreography/build_review.py iteration_01
An absolute capture directory (or its capture_manifest.json) also works.
Only derived review files are written; captured PNGs and references stay intact.
"""
from __future__ import annotations

import argparse
import hashlib
import html
import json
import os
from pathlib import Path
import struct
from urllib.parse import quote
import zlib

from PIL import Image, ImageChops, ImageDraw, ImageFont


STAGING = Path(__file__).resolve().parent
PROJECT = STAGING.parent.parent / "godot-game"
CAPTURES = PROJECT / "artifacts/visual_qa/sword_shield_choreography"
TITLES = {
    "ready": "준비",
    "right_diagonal": "우측 대각 베기",
    "left_reverse": "좌측 역베기",
    "overhead": "상단 내려베기",
    "shield_raise": "방패 올리기",
    "block_impact": "방어 충격",
}
PHASES = {"ready": "준비", "windup": "공격 준비", "active": "베기", "recovery": "회수", "guard_break": "가드 붕괴"}
VIEWS = {"top": "위", "bottom": "아래", "left": "왼쪽", "right": "오른쪽"}
REFERENCES = {
    "ready": ["ready_grip_v1.png", "ready_four_directions_reference.png"],
    "right_diagonal": ["right_diagonal_reference.png", "first_person_attack_keys_reference.png"],
    "left_reverse": ["left_reverse_reference.png", "first_person_attack_keys_reference.png"],
    "overhead": ["overhead_reference.png", "first_person_attack_keys_reference.png"],
    "shield_raise": ["shield_raise_reference.png", "first_person_guard_keys_reference.png"],
    "block_impact": ["block_impact_reference.png", "first_person_guard_keys_reference.png"],
}
PNG_MAGIC = b"\x89PNG\r\n\x1a\n"


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def local_url(path: Path, base: Path) -> str:
    return quote(Path(os.path.relpath(path, base)).as_posix(), safe="/.")


def capture_path(folder: Path, value: str) -> Path:
    path = (folder / value).resolve()
    if not path.is_relative_to(folder) or not path.is_file() or path.suffix.lower() != ".png":
        raise ValueError(f"Missing or invalid original PNG: {value}")
    return path


def png_chunks(path: Path) -> list[tuple[bytes, bytes]]:
    blob = path.read_bytes()
    if not blob.startswith(PNG_MAGIC):
        raise ValueError(f"Not a PNG: {path}")
    chunks = []
    at = len(PNG_MAGIC)
    while at < len(blob):
        length = struct.unpack_from(">I", blob, at)[0]
        kind = blob[at + 4:at + 8]
        data = blob[at + 8:at + 8 + length]
        crc = struct.unpack_from(">I", blob, at + 8 + length)[0]
        if zlib.crc32(kind + data) & 0xFFFFFFFF != crc:
            raise ValueError(f"Invalid source PNG checksum: {path}")
        chunks.append((kind, data))
        at += length + 12
        if kind == b"IEND":
            break
    return chunks


def write_chunk(stream, kind: bytes, data: bytes) -> None:
    stream.write(struct.pack(">I", len(data)))
    stream.write(kind + data)
    stream.write(struct.pack(">I", zlib.crc32(kind + data) & 0xFFFFFFFF))


def write_apng(paths: list[Path], output: Path, fps: int) -> None:
    """Rewrap the original compressed IDAT streams; never repaint/re-encode.

    Explicit full SOURCE frames retain even identical ready frames and exact
    1/fps timing, without a GIF palette or APNG writer frame deduplication.
    """
    first = png_chunks(paths[0])
    header = first[0][1]
    width, height = struct.unpack_from(">II", header)
    sequence = 0
    temporary = output.with_suffix(".tmp")
    with temporary.open("wb") as stream:
        stream.write(PNG_MAGIC)
        write_chunk(stream, b"IHDR", header)
        for kind, data in first[1:]:
            if kind == b"IDAT":
                break
            if kind not in (b"acTL", b"fcTL", b"fdAT"):
                write_chunk(stream, kind, data)
        write_chunk(stream, b"acTL", struct.pack(">II", len(paths), 0))
        for index, path in enumerate(paths):
            chunks = first if index == 0 else png_chunks(path)
            if chunks[0] != (b"IHDR", header):
                raise ValueError("Animation frames must have identical original PNG encoding and dimensions")
            write_chunk(stream, b"fcTL", struct.pack(">IIIIIHHBB", sequence, width, height, 0, 0, 1, fps, 0, 0))
            sequence += 1
            for kind, data in chunks:
                if kind != b"IDAT":
                    continue
                if index == 0:
                    write_chunk(stream, b"IDAT", data)
                else:
                    write_chunk(stream, b"fdAT", struct.pack(">I", sequence) + data)
                    sequence += 1
        write_chunk(stream, b"IEND", b"")
    temporary.replace(output)


def identical_pixels(a: Image.Image, b: Image.Image) -> bool:
    if a.size != b.size:
        return False
    extrema = ImageChops.difference(a.convert("RGBA"), b.convert("RGBA")).getextrema()
    return all(high == 0 for _low, high in extrema)


def verify_apng(output: Path, originals: list[Path], fps: int) -> None:
    with Image.open(output) as animation:
        if animation.n_frames != len(originals):
            raise ValueError(f"Animation lost a source frame: {output}")
        for index, source in enumerate(originals):
            animation.seek(index)
            with Image.open(source) as frame:
                if not identical_pixels(animation, frame):
                    raise ValueError(f"Animation pixels differ from source: {source}")
            if abs(float(animation.info["duration"]) - 1000 / fps) > 0.001:
                raise ValueError("Animation changed the source frame cadence")


def keyframe_sheet(folder: Path, action: dict, output: Path) -> None:
    selected = {int(frame["frame"]): frame for frame in action["pov"]}
    keys = action["keyframes"]
    if len(keys) != 4:
        raise ValueError("Review sheets require the four actually captured keyframes")
    font = ImageFont.truetype(str(PROJECT / "assets/fonts/NotoSansKR-Variable.ttf"), 27)
    source_size = (1280, 720)
    label_height = 58
    canvas = Image.new("RGB", (source_size[0] * 2, (source_size[1] + label_height) * 2), "#151b20")
    draw = ImageDraw.Draw(canvas)
    regions = []
    for index, key in enumerate(keys):
        record = selected[int(key)]
        source = capture_path(folder, record["image"])
        x = (index % 2) * source_size[0]
        y = (index // 2) * (source_size[1] + label_height)
        phase = PHASES.get(record["production"]["phase"], record["production"]["phase"])
        label = f"{TITLES[action['id']]} · {phase} · {float(record['time_seconds']):.3f}초 · 프레임 {key:03d}"
        draw.text((x + 16, y + 11), label, fill="#e8edf0", font=font)
        with Image.open(source) as image:
            if image.size != source_size or image.mode != "RGB":
                raise ValueError("Sheet inputs must be the unchanged RGB 1280x720 POV captures")
            canvas.paste(image, (x, y + label_height))
        regions.append((source, (x, y + label_height, x + source_size[0], y + label_height + source_size[1])))
    canvas.save(output, format="PNG")
    with Image.open(output) as sheet:
        for source, region in regions:
            with Image.open(source) as image:
                if not identical_pixels(sheet.crop(region), image):
                    raise ValueError(f"Mechanical sheet changed source pixels: {source}")


HTML = r'''<!doctype html>
<html lang="ko"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>검과 방패 · 실제 동작 검토</title>
<style>
:root{color-scheme:dark;--bg:#111619;--panel:#192126;--line:#354149;--text:#eaf0f2;--muted:#aebec6;--accent:#d8b577}
*{box-sizing:border-box}body{margin:0;background:var(--bg);color:var(--text);font:16px/1.55 system-ui,-apple-system,"Noto Sans KR",sans-serif}main{max-width:1450px;margin:auto;padding:28px 26px 60px}h1{font-size:28px;margin:0 0 6px;font-weight:650}h2{font-size:21px;margin:24px 0 7px}p{margin:5px 0 12px;color:var(--muted)}button,select,a{font:inherit}button,select{color:var(--text);background:#253039;border:1px solid var(--line);border-radius:8px;padding:9px 14px;cursor:pointer}button[aria-selected=true],button.active{color:#171a1c;background:var(--accent);border-color:var(--accent)}button:focus-visible,a:focus-visible,input:focus-visible,select:focus-visible{outline:3px solid #81bdda;outline-offset:3px}a{color:#d7b986;text-underline-offset:3px}.tabs{display:flex;gap:8px;flex-wrap:wrap;margin:22px 0 16px}.viewer{border:1px solid var(--line);background:#070b0d;border-radius:12px;overflow:hidden}.viewer img{display:block;width:100%;aspect-ratio:16/9;object-fit:contain}.controls{display:flex;gap:10px;align-items:center;flex-wrap:wrap;padding:15px;background:var(--panel)}input[type=range]{flex:1;min-width:200px;accent-color:var(--accent)}.readout{font-variant-numeric:tabular-nums;min-width:225px;color:#d2dde2;font-size:14px}.links{display:flex;gap:18px;flex-wrap:wrap;margin:11px 0}.small{font-size:14px}.keybuttons{display:flex;gap:8px;flex-wrap:wrap;margin:12px 0}.external{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:14px}figure{margin:0;border:1px solid var(--line);border-radius:10px;overflow:hidden;background:var(--panel)}figcaption{padding:10px 13px;color:#dce5e9}figure img{display:block;width:100%;height:auto;object-fit:contain;background:#090d0f}.references{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:16px}.reference-badge{display:inline-block;color:#e8caaa;background:#3b2f24;border:1px solid #705740;padding:2px 9px;border-radius:5px;margin-right:9px;font-size:13px}details{margin-top:26px;border-top:1px solid var(--line);padding-top:16px}summary{cursor:pointer;font-size:20px;font-weight:600;margin-bottom:12px}.meta{color:#879aa5;font-size:13px;margin-top:27px}.notice{border-left:3px solid var(--line);padding:6px 12px;margin:12px 0 15px;max-width:1000px} @media(max-width:680px){main{padding:18px 12px}.external,.references{grid-template-columns:1fr}h1{font-size:24px}.controls{padding:11px}button{padding:8px 11px}.readout{min-width:0;width:100%}}
</style></head><body><main>
<header><h1>검과 방패 · 실제 동작 검토</h1><p>__ITERATION__ · 게임에서 촬영한 원본 프레임 · 30fps</p></header>
<div id="tabs" class="tabs" role="tablist" aria-label="동작 선택"></div>
<section role="tabpanel" aria-label="선택한 실제 동작"><div class="viewer"><img id="pov" alt="실제 게임 촬영 프레임"><div class="controls">
<button id="play" type="button" aria-label="동작 재생">재생</button><button id="previous" type="button" aria-label="이전 프레임">이전</button><button id="next" type="button" aria-label="다음 프레임">다음</button>
<label>속도 <select id="speed" aria-label="재생 속도"><option value="1">1×</option><option value="0.5">0.5×</option></select></label>
<input id="scrub" type="range" min="0" step="1" value="0" aria-label="프레임 선택"><span id="readout" class="readout" aria-live="off"></span></div></div>
<div class="links small"><a id="original" target="_blank">현재 원본 PNG</a><a id="animation" download>원본 순서의 APNG</a><a id="sheet" target="_blank">주요 네 프레임 한눈에 보기</a><a href="capture_manifest.json" target="_blank">촬영 기록</a></div>
<p class="small">재생은 원본 PNG를 순서대로 보여 줍니다. APNG도 같은 프레임과 색을 보존합니다. 네 프레임 모음은 원본을 배치하고 이미지 바깥에만 라벨을 붙였습니다.</p></section>
<section aria-labelledby="external-title"><h2 id="external-title">같은 동작의 네 방향</h2><p id="keynote"></p><div id="keys" class="keybuttons" aria-label="실제 촬영한 주요 순간"></div>
<p class="small notice">__EXTERNAL_CAPTION__ 네 방향은 선택한 주요 순간의 같은 실제 팔과 장비입니다. 위·아래·좌·우는 플레이어 시선을 기준으로 합니다.</p>
<div id="external" class="external"></div></section>
<details open><summary><span class="reference-badge">생성 참고</span>목표 동작 이미지</summary><p>아래는 생성한 참고 이미지입니다. 실제 게임 촬영과 구분해 전체 이미지를 표시합니다.</p><div id="references" class="references"></div></details>
<p class="meta">실제 촬영: __RENDERER__ · 숨김 렌더러 · 원정·커서 보존: __PRESERVED__<br>이 화면과 APNG는 촬영 원본의 검토용 묶음입니다. 외형의 일치도나 완성도를 판정하지 않습니다.</p>
</main><script>
const DATA=__DATA__;const $=id=>document.getElementById(id);let action=DATA.actions[0],frame=0,playing=false,speed=1,origin=0,lastFrame=-1,lastKey=-1;
function pause(){playing=false;$('play').textContent='재생';$('play').setAttribute('aria-label','동작 재생')}
function choose(id){pause();action=DATA.actions.find(a=>a.id===id);frame=0;lastFrame=-1;lastKey=-1;document.querySelectorAll('[role=tab]').forEach(b=>{const yes=b.dataset.id===id;b.setAttribute('aria-selected',yes);b.tabIndex=yes?0:-1});$('scrub').max=action.frames.length-1;$('animation').href=action.animation;$('sheet').href=action.sheet;$('keys').replaceChildren();for(const key of action.keys){const b=document.createElement('button');b.type='button';b.dataset.frame=key;b.textContent=`${action.frames[key].time.toFixed(3)}초`;b.addEventListener('click',()=>{pause();show(key)});$('keys').append(b)}$('references').replaceChildren();for(const ref of action.references){const f=document.createElement('figure'),cap=document.createElement('figcaption'),a=document.createElement('a'),img=document.createElement('img');cap.textContent=`생성 참고 · ${ref.label}`;a.href=ref.image;a.target='_blank';img.src=ref.image;img.alt=`생성 참고: ${ref.label}`;img.loading='lazy';a.append(img);f.append(cap,a);$('references').append(f)}for(const f of action.frames){const preload=new Image();preload.src=f.image}show(0)}
function show(index){frame=Math.max(0,Math.min(action.frames.length-1,index));if(frame===lastFrame)return;lastFrame=frame;const f=action.frames[frame];$('pov').src=f.image;$('pov').alt=`실제 촬영 · ${action.title} · ${f.time.toFixed(3)}초 · ${f.phase}`;$('original').href=f.image;$('scrub').value=frame;$('readout').textContent=`${f.time.toFixed(3)}초 · ${frame+1}/${action.frames.length} · ${f.phase}`;const key=action.keys.reduce((a,b)=>Math.abs(b-frame)<Math.abs(a-frame)?b:a);$('keynote').textContent=`네 방향 촬영 시점 ${action.frames[key].time.toFixed(3)}초${key===frame?' · 현재 프레임과 같은 순간':' · 현재 재생 위치에서 가장 가까운 주요 순간'}`;document.querySelectorAll('#keys button').forEach(b=>b.classList.toggle('active',Number(b.dataset.frame)===key));if(lastKey===key)return;lastKey=key;$('external').replaceChildren();for(const view of DATA.views){const original=action.external[String(key)][view.id],f=document.createElement('figure'),cap=document.createElement('figcaption'),a=document.createElement('a'),img=document.createElement('img');cap.textContent=`${view.title} · 실제 촬영 · ${action.frames[key].time.toFixed(3)}초`;a.href=original;a.target='_blank';img.src=original;img.alt=`${action.title}, ${view.title}에서 본 같은 실제 팔과 장비`;a.append(img);f.append(cap,a);$('external').append(f)}}
for(const item of DATA.actions){const b=document.createElement('button');b.type='button';b.role='tab';b.dataset.id=item.id;b.textContent=item.title;b.addEventListener('click',()=>choose(item.id));b.addEventListener('keydown',event=>{if(!['ArrowLeft','ArrowRight'].includes(event.key))return;event.preventDefault();const i=DATA.actions.findIndex(a=>a.id===item.id),next=DATA.actions[(i+(event.key==='ArrowRight'?1:-1)+DATA.actions.length)%DATA.actions.length];choose(next.id);document.querySelector(`[data-id="${next.id}"]`).focus()});$('tabs').append(b)}
$('play').addEventListener('click',()=>{if(playing){pause();return}playing=true;origin=performance.now()-frame*1000/DATA.fps/speed;$('play').textContent='일시정지';$('play').setAttribute('aria-label','동작 일시정지')});$('previous').addEventListener('click',()=>{pause();show(frame-1)});$('next').addEventListener('click',()=>{pause();show(frame+1)});$('scrub').addEventListener('input',()=>{pause();show(Number($('scrub').value))});$('speed').addEventListener('change',()=>{speed=Number($('speed').value);origin=performance.now()-frame*1000/DATA.fps/speed});document.addEventListener('visibilitychange',()=>{if(document.hidden)pause()});
function tick(now){if(playing)show(Math.floor((now-origin)*DATA.fps*speed/1000)%action.frames.length);requestAnimationFrame(tick)}choose(action.id);requestAnimationFrame(tick);
</script></body></html>'''


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("iteration", help="Iteration name, capture directory, or capture_manifest.json")
    args = parser.parse_args()
    supplied = Path(args.iteration).expanduser()
    folder = (supplied if supplied.exists() else CAPTURES / supplied).resolve()
    if folder.is_file():
        folder = folder.parent
    manifest_path = folder / "capture_manifest.json"
    manifest = json.loads(manifest_path.read_text())
    sequences = {item["id"]: item for item in manifest["sequences"]}
    if set(sequences) != set(TITLES) or manifest.get("failures") or not all(s.get("passed") for s in sequences.values()):
        raise ValueError("Review expects six complete, passing actual capture sequences")
    fps = int(manifest["fps"])
    if fps != 30:
        raise ValueError("This choreography review expects the recorded 30fps source cadence")
    original_paths = {capture_path(folder, f["image"]) for s in sequences.values() for category in ("pov", "external") for f in s[category]}
    references = {STAGING / name for names in REFERENCES.values() for name in names}
    for path in references:
        if not path.is_file():
            raise FileNotFoundError(path)
    input_paths = sorted(original_paths | references | {manifest_path})
    before = {str(path): sha256(path) for path in input_paths}
    review_assets = folder / "review_assets"
    review_assets.mkdir(exist_ok=True)
    actions = []
    artifacts = []
    for action_id, title in TITLES.items():
        action = sequences[action_id]
        frames = sorted(action["pov"], key=lambda f: int(f["frame"]))
        if [f["frame"] for f in frames] != list(range(len(frames))) or len(frames) != 34:
            raise ValueError(f"Missing, duplicated or unordered source frames: {action_id}")
        paths = [capture_path(folder, frame["image"]) for frame in frames]
        animation = review_assets / f"{action_id}.apng"
        sheet = review_assets / f"{action_id}_keyframes.png"
        write_apng(paths, animation, fps)
        verify_apng(animation, paths, fps)
        keyframe_sheet(folder, action, sheet)
        external: dict[str, dict[str, str]] = {}
        for frame in action["external"]:
            external.setdefault(str(frame["frame"]), {})[frame["view"]] = local_url(capture_path(folder, frame["image"]), folder)
        if any(set(external.get(str(key), {})) != set(VIEWS) for key in action["keyframes"]):
            raise ValueError(f"Incomplete four-direction source images: {action_id}")
        actions.append({
            "id": action_id, "title": title, "animation": local_url(animation, folder), "sheet": local_url(sheet, folder),
            "keys": action["keyframes"], "external": external,
            "frames": [{"image": local_url(path, folder), "time": float(frame["time_seconds"]), "phase": PHASES.get(frame["production"]["phase"], frame["production"]["phase"])} for path, frame in zip(paths, frames)],
            "references": [{"image": local_url(STAGING / name, folder), "label": title if index == 0 else "관련 동작과 방향"} for index, name in enumerate(REFERENCES[action_id])],
        })
        artifacts.extend([animation, sheet])
        print(f"Verified {action_id}: 34 APNG frames equal their originals; four-key sheet pixels unchanged", flush=True)
    data = {"fps": fps, "actions": actions, "views": [{"id": key, "title": title} for key, title in VIEWS.items()]}
    page = HTML.replace("__ITERATION__", html.escape(folder.name)).replace("__EXTERNAL_CAPTION__", html.escape(manifest["external_caption"]))
    page = page.replace("__RENDERER__", html.escape(str(manifest["actual_renderer"]))).replace("__PRESERVED__", "확인됨" if manifest.get("expedition_and_cursor_preserved") else "확인 필요")
    page = page.replace("__DATA__", json.dumps(data, ensure_ascii=False).replace("</", "<\\/"))
    html_path = folder / "review.html"
    html_path.write_text(page)
    after = {str(path): sha256(path) for path in input_paths}
    if after != before:
        raise RuntimeError("A captured PNG, reference or capture manifest changed during packaging")
    artifacts.append(html_path)
    record = {
        "source_iteration": folder.name, "capture_manifest_sha256": before[str(manifest_path)], "original_png_count": len(original_paths),
        "original_pngs_and_references_preserved": True, "apng_count": 6, "frames_per_apng": 34, "fps": fps,
        "apng_pixels_verified_against_all_original_frames": True, "keyframe_sheets": "Only original 1280x720 pixels pasted in a two-by-two layout; labels outside images",
        "reference_handling": "Whole original files linked; no cropping, retouching, color adjustment or synthesis",
        "source_sha256": {local_url(Path(path), folder): digest for path, digest in before.items()},
        "derived_sha256": {local_url(path, folder): sha256(path) for path in artifacts},
    }
    (folder / "review_build.json").write_text(json.dumps(record, ensure_ascii=False, indent=2) + "\n")
    print(f"REVIEW BUILD PASS: {html_path}")


if __name__ == "__main__":
    main()
