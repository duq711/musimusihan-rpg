#!/usr/bin/env python3
"""Single-image/video review of real sword/shield captures; no sheets or grids.

python3 asset-staging/sword_shield_single_pose/build_review.py iteration_04
Optional: --references asset-staging/sword_shield_single_pose/references.json
All generated files stay under this new staging directory. Game and original
capture files are read-only. Native AVFoundation is used; no encoder download.
"""
from __future__ import annotations

import argparse
import hashlib
import html
import json
import math
import os
from pathlib import Path
import subprocess
from urllib.parse import quote

from PIL import Image, ImageChops, ImageStat

STAGING = Path(__file__).resolve().parent
PROJECT = STAGING.parent.parent / "godot-game"
CAPTURES = PROJECT / "artifacts/visual_qa/sword_shield_choreography"
TITLES = {"ready": "준비", "right_diagonal": "우측 대각 베기", "left_reverse": "좌측 역베기", "overhead": "상단 내려베기", "shield_raise": "방패 올리기", "block_impact": "방어 충격"}
PHASES = {"ready": "준비", "windup": "공격 준비", "active": "베기", "recovery": "회수", "guard_break": "가드 붕괴"}
DIRECTIONS = {"pov": "1인칭", "front": "정면", "back": "뒤", "top": "위", "bottom": "아래", "left": "왼쪽", "right": "오른쪽"}
ATTACKS = {"right_diagonal", "left_reverse", "overhead"}
ATTACK_CONTACT_FRAME = 11


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def local_url(path: Path, base: Path) -> str:
    return quote(Path(os.path.relpath(path, base)).as_posix(), safe="/.")


def original_png(folder: Path, value: str) -> Path:
    path = (folder / value).resolve()
    if not path.is_relative_to(folder) or not path.is_file() or path.suffix.lower() != ".png":
        raise ValueError(f"Invalid original capture: {value}")
    return path


def frame_label(action_id: str, frame: dict, previous: dict | None = None) -> str:
    production = frame["production"]
    phase = production["phase"]
    state = PHASES.get(phase, phase)
    if action_id in ("shield_raise", "block_impact") and phase != "guard_break":
        progress = max(0.0, min(1.0, float(production.get("shield_raise_progress", 0.0))))
        prior = float(previous["production"].get("shield_raise_progress", progress)) if previous else progress
        if float(production.get("shield_impact_remaining", 0.0)) > 0.000001:
            state = "방어 충격"
        elif progress >= 0.999999:
            state = "방어 유지"
        elif progress <= 0.000001:
            state = "방패 내림"
        else:
            motion = "방패 내리는 중" if progress < prior - 0.000001 else "방패 올리는 중"
            state = f"{motion} · {progress:.0%}"
    if action_id in ATTACKS and int(frame["frame"]) == ATTACK_CONTACT_FRAME:
        state += " · 검격 기준"
    return f"{float(frame['time_seconds']):.3f}초 · {state}"


def validate_sequence(action: dict, fps: int) -> list[int]:
    frames = sorted(action["pov"], key=lambda frame: int(frame["frame"]))
    if not frames or [int(f["frame"]) for f in frames] != list(range(len(frames))):
        raise ValueError("Source frame order is incomplete")
    keyframes = sorted({int(value) for value in action["keyframes"]})
    if any(frame < 0 or frame >= len(frames) for frame in keyframes):
        raise ValueError("A capture keyframe is outside the source sequence")
    for frame in frames + action["external"]:
        index = int(frame["frame"])
        if not 0 <= index < len(frames) or not math.isclose(float(frame["time_seconds"]), index / fps, abs_tol=0.000001):
            raise ValueError("Capture timestamp differs from the encoded frame timeline")
    for direction in ("top", "bottom", "left", "right"):
        external = [int(frame["frame"]) for frame in action["external"] if frame["view"] == direction]
        if sorted(external) != keyframes:
            raise ValueError(f"Incomplete or repeated external keyframes: {action['id']} / {direction}")
    if action["id"] in ATTACKS:
        if ATTACK_CONTACT_FRAME not in keyframes:
            raise ValueError("Sword contact review requires captured keyframe 11")
        state = frames[ATTACK_CONTACT_FRAME]["production"]
        if state["phase"] != "active" or state.get("sword_attack_variant") != action["id"]:
            raise ValueError("Sword keyframe 11 is not the requested actual active attack")
    return sorted({0, *keyframes, len(frames) - 1})


def ensure_encoder() -> Path:
    build = STAGING / ".build"
    cache = build / "module-cache"
    cache.mkdir(parents=True, exist_ok=True)
    source = STAGING / "encode_capture_video.swift"
    binary = build / "encode_capture_video"
    if not binary.is_file() or binary.stat().st_mtime < source.stat().st_mtime:
        completed = subprocess.run(["/usr/bin/nice", "-n", "10", "/usr/bin/xcrun", "swiftc", "-module-cache-path", str(cache), str(source), "-o", str(binary)], text=True, capture_output=True)
        (build / "compiler.log").write_text(completed.stdout + completed.stderr)
        if completed.returncode:
            raise RuntimeError("Installed Swift/AVFoundation compilation failed; see .build/compiler.log")
    return binary


def video_for(action_id: str, frames: list[Path], output: Path, fps: int, encoder: Path, verification_frames: list[int]) -> tuple[Path, dict]:
    folder = output / "videos"
    folder.mkdir(exist_ok=True)
    verification = output / "verification" / action_id
    verification.mkdir(parents=True, exist_ok=True)
    video = folder / f"{action_id}.mp4"
    report_path = verification / "video_verification.json"
    frame_hashes = [sha256(path) for path in frames]
    if video.is_file() and report_path.is_file():
        cached = json.loads(report_path.read_text())
        if cached.get("source_frame_sha256") == frame_hashes and cached.get("video_sha256") == sha256(video) and cached.get("fps") == fps and cached.get("swift_source_sha256") == sha256(STAGING / "encode_capture_video.swift") and cached.get("verification_frames") == verification_frames:
            return video, cached
    # Only this builder's own derived video can be replaced, never an input PNG.
    if video.is_file():
        video.unlink()
    job = {"frames": [str(path) for path in frames], "fps": fps, "output": str(video), "verificationDirectory": str(verification), "verificationFrames": verification_frames}
    job_path = verification / "job.json"
    job_path.write_text(json.dumps(job))
    subprocess.run(["/usr/bin/nice", "-n", "10", str(encoder), str(job_path)], check=True, timeout=120)
    native = json.loads((verification / "encoding.json").read_text())
    checks = []
    for checkpoint in native["decoded_checkpoints"]:
        index = int(checkpoint["frame"])
        if not math.isclose(float(checkpoint["time_seconds"]), index / fps, abs_tol=0.000001):
            raise ValueError("Decoded checkpoint is not at the original frame time")
        with Image.open(frames[index]) as original, Image.open(checkpoint["image"]) as decoded:
            if original.size != decoded.size:
                raise ValueError("Video resized the source capture")
            a, b = original.convert("RGB"), decoded.convert("RGB")
            error = sum(ImageStat.Stat(ImageChops.difference(a, b)).mean) / 3
            flipped_error = sum(ImageStat.Stat(ImageChops.difference(a, b.transpose(Image.Transpose.FLIP_TOP_BOTTOM))).mean) / 3
            # MP4 is compressed video, not a claim of PNG pixel identity. This
            # detects orientation/channel failures while allowing codec loss.
            if error > 12.0 or error > flipped_error:
                raise ValueError(f"Decoded MP4 differs unexpectedly from original frame {index}: {error:.3f}")
            checks.append({"frame": index, "mean_absolute_rgb_error": error, "vertically_flipped_error": flipped_error, "actual_time_seconds": checkpoint["time_seconds"]})
    if int(native["sample_count"]) != len(frames) or abs(float(native["fps"]) - fps) > 0.001 or native["audio_tracks"] != 0:
        raise ValueError("Encoded video frame count, frame rate or silence differs from the capture")
    if sorted(int(check["frame"]) for check in checks) != verification_frames or not math.isclose(float(native["duration_seconds"]), len(frames) / fps, abs_tol=0.0001):
        raise ValueError("Decoded keyframes or MP4 duration differ from the source timeline")
    report = {**native, "decoded_checks": checks, "verification_frames": verification_frames, "source_frame_sha256": frame_hashes, "video_sha256": sha256(video), "swift_source_sha256": sha256(STAGING / "encode_capture_video.swift"), "ai_generated_video": False, "source": "Actual game-capture PNG sequence"}
    report_path.write_text(json.dumps(report, indent=2) + "\n")
    return video, report


HTML = r'''<!doctype html><html lang="ko"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>검과 방패 · 한 장씩 검토</title>
<style>:root{color-scheme:dark;--bg:#101619;--panel:#192228;--line:#3b484f;--text:#eaf0f2;--muted:#aebfc8;--accent:#d7b67c}*{box-sizing:border-box}[hidden]{display:none!important}body{margin:0;background:var(--bg);color:var(--text);font:16px/1.55 system-ui,-apple-system,"Noto Sans KR",sans-serif}main{max-width:1380px;margin:auto;padding:24px 24px 42px}h1{font-size:27px;margin:0 0 4px}p{margin:6px 0 15px;color:var(--muted)}button,select,input,a{font:inherit}button,select{background:#243039;color:var(--text);border:1px solid var(--line);padding:8px 13px;border-radius:7px;cursor:pointer}button[aria-selected=true]{background:var(--accent);color:#14191c;border-color:var(--accent)}button:focus-visible,a:focus-visible,select:focus-visible,input:focus-visible{outline:3px solid #80b6d0;outline-offset:3px}.row{display:flex;gap:9px;flex-wrap:wrap;align-items:center;margin:13px 0}.row label{display:flex;align-items:center;gap:7px}.stage{display:flex;align-items:center;justify-content:center;height:min(70vh,760px);min-height:320px;border:1px solid var(--line);border-radius:12px;background:#060a0c;overflow:hidden}.stage img,.stage video{width:100%;height:100%;object-fit:contain;display:block}.stage p{max-width:500px;padding:25px;text-align:center}.framebar{background:var(--panel);padding:13px 16px;border:1px solid var(--line);border-radius:9px;margin-top:12px;display:flex;gap:12px;align-items:center}.framebar input{flex:1;accent-color:var(--accent);min-width:80px}.status{font-size:14px;min-width:210px;font-variant-numeric:tabular-nums}.caption{color:#dbe5ea;margin-top:13px}.small{font-size:13px}.links{display:flex;gap:17px;flex-wrap:wrap;margin:14px 0}a{color:#daba83;text-underline-offset:3px}.badge{padding:3px 9px;border-radius:5px;background:#3c3124;border:1px solid #765d3e;color:#ead0a4;font-size:13px}.footer{border-top:1px solid var(--line);padding-top:14px;margin-top:20px}@media(max-width:640px){main{padding:17px 11px}.stage{height:60vh;min-height:260px}h1{font-size:23px}.framebar{flex-wrap:wrap}.status{width:100%}.row{gap:7px}button{padding:8px 10px}}</style></head><body><main>
<h1>검과 방패 · 한 장씩 검토</h1><p><span class="badge">__REVIEW_STAGE__</span> 동작과 방향을 골라 한 자세씩 확인합니다.</p>
<div class="row" role="tablist" aria-label="보는 자료"><button data-mode="actual" role="tab">실제 촬영</button><button data-mode="generated" role="tab">생성 참고</button><button data-mode="video" role="tab">실제 영상</button></div>
<div class="row"><label>동작 <select id="action"><option value="ready">준비</option><option value="right_diagonal">우측 대각 베기</option><option value="left_reverse">좌측 역베기</option><option value="overhead">상단 내려베기</option><option value="shield">방패 동작</option></select></label><label id="shield-label" hidden>방패 <select id="shield"><option value="shield_raise">올리기</option><option value="block_impact">방어 충격</option></select></label><label>방향 <select id="direction"></select></label><label id="speed-label" hidden>속도 <select id="speed"><option value="1">1×</option><option value="0.5">0.5×</option></select></label></div>
<div class="stage"><img id="single-image" alt="선택한 한 자세" hidden><video id="single-video" controls playsinline loop preload="metadata" hidden></video><p id="empty" hidden></p></div>
<div id="framebar" class="framebar"><button id="previous" aria-label="이전 자세">이전</button><input id="frame" type="range" min="0" value="0" step="1" aria-label="자세 선택"><button id="next" aria-label="다음 자세">다음</button><span id="status" class="status"></span></div>
<p id="video-time" class="small status" hidden></p>
<div class="caption"><span id="kind" class="badge"></span> <span id="caption"></span></div><p id="note" class="small"></p>
<div class="links small"><a id="open-source" target="_blank">현재 파일 열기</a><a id="download-video" download>이 동작 MP4 저장</a></div>
<p class="small footer">__ITERATION__ · __REVIEW_STAGE__ · 영상은 실제 게임 촬영 프레임을 순서대로 인코딩한 MP4입니다. 생성 영상이 아닙니다. 이미지 원본은 수정하지 않았습니다.</p>
</main><script>
const DATA=__DATA__;const $=id=>document.getElementById(id);let mode='actual',index=0;const selectedDirection={actual:'pov',generated:'pov',video:'pov'};
function actionId(){return $('action').value==='shield'?$('shield').value:$('action').value}
function itemsFor(action){return mode==='generated'?action.generated:action.actual}
function directionsFor(action){return mode==='video'?['pov']:Object.keys(itemsFor(action))}
function updateVideoTime(){const video=$('single-video'),a=DATA.actions[actionId()],duration=Number.isFinite(video.duration)&&video.duration>0?video.duration:a.video_duration_seconds,current=Number.isFinite(video.currentTime)?Math.max(0,Math.min(video.currentTime,duration)):0;$('video-time').textContent=`${current.toFixed(3)} / ${duration.toFixed(3)}초 · ${video.playbackRate}× · 원본 타임라인`}
function rebuildDirections(){const a=DATA.actions[actionId()],available=directionsFor(a);$('direction').replaceChildren();for(const id of available){const o=document.createElement('option');o.value=id;o.textContent=DATA.directions[id]||id;$('direction').append(o)}if(!available.includes(selectedDirection[mode]))selectedDirection[mode]=available[0]||'';$('direction').value=selectedDirection[mode];$('direction').disabled=available.length<2}
function render(){const a=DATA.actions[actionId()],direction=selectedDirection[mode],video=$('single-video'),image=$('single-image');video.pause();image.hidden=true;video.hidden=true;$('empty').hidden=true;$('shield-label').hidden=$('action').value!=='shield';$('speed-label').hidden=mode!=='video';$('video-time').hidden=mode!=='video';$('framebar').hidden=mode==='video';document.querySelectorAll('[data-mode]').forEach(b=>b.setAttribute('aria-selected',b.dataset.mode===mode));$('download-video').href=a.video;$('kind').textContent=mode==='generated'?'생성 참고':mode==='video'?'실제 촬영 영상':'실제 촬영';
if(mode==='video'){if(video.dataset.source!==a.video){video.src=a.video;video.dataset.source=a.video;video.poster=a.actual.pov[0].image;video.load()}video.playbackRate=Number($('speed').value);video.hidden=false;updateVideoTime();$('caption').textContent=`${a.title} · 1인칭 · 원본 순서 ${a.video_fps}fps`;$('note').textContent='실제 게임 연속 촬영을 MP4로 인코딩했습니다. AI 생성 영상이 아닙니다. 위·아래·좌·우는 네 주요 순간의 정지 이미지로 제공됩니다.';$('open-source').href=a.video;$('open-source').hidden=false;return}
const items=itemsFor(a)[direction]||[];if(!items.length){$('empty').textContent=mode==='generated'?'이 동작의 단일 자세 참고 이미지가 아직 연결되지 않았습니다.':'이 방향의 실제 촬영 이미지가 없습니다.';$('empty').hidden=false;$('framebar').hidden=true;$('caption').textContent=a.title;$('note').textContent='';$('open-source').hidden=true;return}index=Math.max(0,Math.min(index,items.length-1));const item=items[index];image.src=item.image;image.alt=`${mode==='generated'?'생성 참고':'실제 촬영'} · ${a.title} · ${DATA.directions[direction]||direction} · ${item.label}`;image.hidden=false;$('frame').max=items.length-1;$('frame').value=index;$('status').textContent=`${index+1}/${items.length} · ${item.label}`;$('caption').textContent=`${a.title} · ${DATA.directions[direction]||direction} · ${item.label}`;$('note').textContent=mode==='generated'?'자세와 방향마다 AI로 독립 생성한 참고 원본 한 장을 전체 표시합니다. 같은 3D 자세를 여러 카메라로 촬영한 이미지가 아니므로 세부 형상과 관절 각도는 서로 다를 수 있습니다.':direction==='pov'?'실제 촬영한 원본 프레임 한 장입니다.':DATA.external_caption;$('open-source').href=item.image;$('open-source').hidden=false}
document.querySelectorAll('[data-mode]').forEach(b=>b.addEventListener('click',()=>{mode=b.dataset.mode;index=0;rebuildDirections();render()}));for(const id of ['action','shield'])$(id).addEventListener('change',()=>{index=0;rebuildDirections();render()});$('direction').addEventListener('change',()=>{selectedDirection[mode]=$('direction').value;index=0;render()});$('frame').addEventListener('input',()=>{index=Number($('frame').value);render()});$('previous').addEventListener('click',()=>{index--;render()});$('next').addEventListener('click',()=>{index++;render()});$('speed').addEventListener('change',()=>{$('single-video').playbackRate=Number($('speed').value);updateVideoTime()});for(const event of ['loadedmetadata','durationchange','timeupdate','seeking','seeked','ratechange','ended'])$('single-video').addEventListener(event,updateVideoTime);document.addEventListener('visibilitychange',()=>{if(document.hidden)$('single-video').pause()});rebuildDirections();render();
</script></body></html>'''


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("iteration", help="Capture iteration name or directory")
    parser.add_argument("--references", type=Path, default=STAGING / "references.json")
    parser.add_argument("--review-stage", choices=("intermediate", "final"), default="intermediate", help="Explicitly label the review; defaults to an intermediate capture")
    args = parser.parse_args()
    supplied = Path(args.iteration).expanduser()
    source = (supplied if supplied.exists() else CAPTURES / supplied).resolve()
    if source.is_file():
        source = source.parent
    manifest_path = source / "capture_manifest.json"
    manifest = json.loads(manifest_path.read_text())
    fps_value = float(manifest["fps"])
    if not math.isfinite(fps_value) or not fps_value.is_integer() or not 0 < fps_value <= 240:
        raise ValueError("Expected an integer source frame rate from 1 to 240")
    fps = int(fps_value)
    sequences = {action["id"]: action for action in manifest["sequences"]}
    if set(sequences) != set(TITLES) or manifest.get("failures") or not all(a.get("passed") for a in sequences.values()):
        raise ValueError("Expected the six completed actual capture actions")
    output = STAGING / "reviews" / source.name
    output.mkdir(parents=True, exist_ok=True)
    references = []
    reference_file = args.references.expanduser().resolve()
    watched = {manifest_path}
    if reference_file.is_file():
        references = json.loads(reference_file.read_text())["references"]
        watched.add(reference_file)
    reference_paths = []
    for ref in references:
        if ref["action"] not in TITLES or ref["direction"] not in DIRECTIONS:
            raise ValueError("Reference manifest contains an unsupported action/direction")
        path = (reference_file.parent / ref["image"]).resolve()
        if not path.is_file() or path.suffix.lower() != ".png":
            raise ValueError(f"Missing single-pose reference image: {path}")
        if ref.get("single_pose") is False:
            raise ValueError("Contact sheets and collages are not accepted as references")
        reference_paths.append(path)
        watched.add(path)
    originals = {original_png(source, frame["image"]) for action in sequences.values() for kind in ("pov", "external") for frame in action[kind]}
    watched.update(originals)
    before = {str(path): sha256(path) for path in watched}
    encoder = ensure_encoder()
    actions = {}
    videos = {}
    verification_frames_by_action = {}
    for action_id, title in TITLES.items():
        action = sequences[action_id]
        frames = sorted(action["pov"], key=lambda frame: int(frame["frame"]))
        verification_frames = validate_sequence(action, fps)
        verification_frames_by_action[action_id] = verification_frames
        paths = [original_png(source, frame["image"]) for frame in frames]
        video, verification = video_for(action_id, paths, output, fps, encoder, verification_frames)
        labels = {int(frame["frame"]): frame_label(action_id, frame, frames[index - 1] if index else None) for index, frame in enumerate(frames)}
        actual = {"pov": [{"image": local_url(path, output), "label": labels[int(frame["frame"])]} for path, frame in zip(paths, frames)]}
        for frame in sorted(action["external"], key=lambda frame: int(frame["frame"])):
            actual.setdefault(frame["view"], []).append({"image": local_url(original_png(source, frame["image"]), output), "label": labels[int(frame["frame"])]})
        generated = {}
        for ref, path in zip(references, reference_paths):
            if ref["action"] == action_id:
                generated.setdefault(ref["direction"], []).append({"image": local_url(path, output), "label": str(ref.get("label", ref.get("pose", "참고 자세")))})
        actions[action_id] = {"title": title, "video": local_url(video, output), "video_duration_seconds": float(verification["duration_seconds"]), "video_fps": float(verification["fps"]), "actual": actual, "generated": generated}
        videos[action_id] = verification
        print(f"Single-view review prepared: {action_id}", flush=True)
    data = {"actions": actions, "directions": DIRECTIONS, "external_caption": manifest["external_caption"]}
    stage_label = "중간 검토본" if args.review_stage == "intermediate" else "최종 촬영 검토본"
    page = HTML.replace("__ITERATION__", html.escape(source.name)).replace("__REVIEW_STAGE__", stage_label).replace("__DATA__", json.dumps(data, ensure_ascii=False).replace("</", "<\\/"))
    page_path = output / "review.html"
    page_path.write_text(page)
    after = {str(path): sha256(path) for path in watched}
    if before != after:
        raise RuntimeError("An original capture or reference changed during review packaging")
    report = {"source_iteration": source.name, "review_stage": args.review_stage, "review_stage_label": stage_label, "sword_contact_frame": ATTACK_CONTACT_FRAME, "verification_frames_by_action": verification_frames_by_action, "source_capture_manifest_sha256": before[str(manifest_path)], "original_capture_count": len(originals), "reference_count": len(reference_paths), "all_originals_preserved": True,
              "display_rule": "One whole image or one actual video visible at a time; no thumbnails, split views, collage or contact sheet", "ai_generated_video": False, "video_encoder": "Installed macOS AVFoundation AVAssetWriter", "videos": videos,
              "source_sha256": {local_url(Path(path), output): digest for path, digest in before.items()}, "html_sha256": sha256(page_path), "builder_sha256": sha256(Path(__file__))}
    (output / "review_build.json").write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n")
    print(f"SINGLE POSE REVIEW PASS: {page_path}")


if __name__ == "__main__":
    main()
