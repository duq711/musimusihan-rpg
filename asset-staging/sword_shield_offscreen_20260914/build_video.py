from pathlib import Path
import hashlib, json, av
from PIL import Image, ImageDraw, ImageFont

root = Path('godot-game/artifacts/visual_qa/reference_sword_motion')
staging = Path('asset-staging/sword_shield_offscreen_20260914')
before = root / 'shield_left_clear'
snapshot = staging / 'qa_project_stable'
after = snapshot / 'artifacts/visual_qa/reference_sword_motion/shield_offscreen_stable'
out = root / 'shield_offscreen_comparison'
out.mkdir(exist_ok=True)
font = ImageFont.truetype('godot-game/assets/fonts/NotoSansKR-Variable.ttf', 25)
small = ImageFont.truetype('godot-game/assets/fonts/NotoSansKR-Variable.ttf', 16)
old = json.loads((before / 'capture_manifest.json').read_text())
new = json.loads((after / 'capture_manifest.json').read_text())
assert new['actual_renderer'] == 'vulkan' and new['display_driver'] == 'embedded'
assert not new['failures'] and not new['candidate_manifest_path']
assert new['sources_unchanged_during_capture'] and new['expedition_and_cursor_preserved']
for uri, sha in new['source_sha256'].items():
    assert hashlib.sha256((snapshot / uri[6:]).read_bytes()).hexdigest() == sha, uri
for uri in ['res://scripts/player.gd', 'res://assets/animations/reference_sword_motion/motion_manifest.json']:
    assert hashlib.sha256((staging / 'baseline/godot-game' / uri[6:]).read_bytes()).hexdigest() == old['source_sha256'][uri]
assert new['source_sha256']['res://assets/animations/reference_sword_motion/motion_manifest.json'] == old['source_sha256']['res://assets/animations/reference_sword_motion/motion_manifest.json']
report = {}
video = out / 'shield_offscreen.mp4'
c = av.open(str(video), 'w')
stream = c.add_stream('libx264', rate=60)
stream.width, stream.height = 1920, 612
stream.pix_fmt = 'yuv420p'
stream.options = {'crf': '18', 'preset': 'fast'}
encoded = 0
for seq, name in zip(new['sequences'], ['정베기', '역베기', '내려베기']):
    clip, frames = seq['id'], seq['frames']
    previous = next(s for s in old['sequences'] if s['id'] == clip)['frames']
    held = frames[0]['shield_transform']['position']
    changed_sword_frames = []
    for f, b in zip(frames, previous):
        if f['combat_phase'] in ['windup', 'active', 'recovery']:
            assert f['weapon_transform'] == b['weapon_transform'], (clip, f['frame'], 'sword changed')
            assert f['shield_visible'] and f['shield_grip_error'] < 0.00001
            assert f['shield_transform']['position'][1] >= held[1] - 0.015
        if f['weapon_transform'] != b['weapon_transform']:
            changed_sword_frames.append(f['frame'])
    clear = next(f for f in frames if f['shield_transform']['position'][0] < held[0] - .90)
    contact = next(f for f in frames if f['combat_phase'] == 'active' and f['combat_phase_time'] >= .145)
    assert clear['time_seconds'] < contact['time_seconds']
    assert frames[-1]['combat_phase'] == 'ready'
    report[clip] = {'clear_time_seconds': clear['time_seconds'], 'contact_time_seconds': contact['time_seconds'], 'attack_sword_frames_exactly_preserved': True, 'changed_ready_sword_frames': changed_sword_frames, 'max_shield_grip_error_m': max(f['shield_grip_error'] for f in frames)}
    pictures = [[Image.open(p).convert('RGB').resize((960, 540)) for p in sorted((directory / 'sequences' / clip).glob('frame_*.png'))] for directory in [before, after]]
    assert all(len(p) == 91 for p in pictures)
    active_start = next(f['frame'] for f in frames if f['combat_phase'] == 'active')
    for suffix, selected in [('', [0, 3, 6, 8, contact['frame'], contact['frame'] + 7]), ('_return', [18, 27, 36, 45, 54, 63])]:
        sheet = Image.new('RGB', (1920, 404), '#141414')
        d = ImageDraw.Draw(sheet)
        for side in range(2):
            for k, i in enumerate(selected):
                sheet.paste(pictures[side][i].resize((320, 180)), (k * 320, side * 202 + 22))
                d.text((k * 320 + 3, side * 202 + 2), f'{"수정 전" if side == 0 else "수정 후"} {i / 60:.3f}s', font=small, fill='white')
        sheet.save(out / (clip + suffix + '.jpg'), quality=95)
    for repeats, speed in [(1, '정상 속도'), (2, '0.5배속')]:
        for i in range(91):
            canvas = Image.new('RGB', (1920, 612), '#141414')
            d = ImageDraw.Draw(canvas)
            for side, title in enumerate(['수정 전 · 일부만 이동', '수정 후 · 왼쪽 화면 밖으로']):
                canvas.paste(pictures[side][i], (side * 960, 72))
                d.text((side * 960 + 16, 4), name + '  |  ' + title, font=font, fill='white')
                d.text((side * 960 + 16, 40), '실제 Godot 렌더 · ' + speed, font=small, fill='#cccccc')
            for _ in range(repeats):
                frame = av.VideoFrame.from_image(canvas)
                frame.pts = encoded
                encoded += 1
                for packet in stream.encode(frame): c.mux(packet)
for packet in stream.encode(): c.mux(packet)
c.close()
with av.open(str(video)) as check:
    assert sum(1 for _ in check.decode(video=0)) == encoded
result = {'captures': report, 'video': str(video.resolve()), 'fps': 60, 'encoded_frames': encoded, 'duration_seconds': encoded / 60, 'presentation': 'Actual Godot before/after frames from a frozen QA copy to isolate concurrent body-health edits; normal then labelled half speed. No pose retouching, mirroring or frame interpolation.'}
(out / 'verification.json').write_text(json.dumps(result, indent=2) + '\n')
print(json.dumps(result, indent=2))
