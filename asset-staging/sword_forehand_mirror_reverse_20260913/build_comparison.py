"""Compare actual forehand/reverse frames at equal ACTIVE times; never mirror pixels."""
from pathlib import Path
import hashlib
import json
import av
from PIL import Image, ImageDraw, ImageFont

root = Path('godot-game/artifacts/visual_qa/reference_sword_motion')
out = root / 'forehand_mirror_reverse_comparison'
out.mkdir(exist_ok=True)
font = ImageFont.truetype('godot-game/assets/fonts/NotoSansKR-Variable.ttf', 24)
small = ImageFont.truetype('godot-game/assets/fonts/NotoSansKR-Variable.ttf', 16)
clips = [('right_diagonal', '정베기 · 오른쪽 → 왼쪽'), ('left_reverse', '기준 역베기 · 왼쪽 → 오른쪽')]
stances = [('forehand_mirror_reverse_two_hand', '양손 파지', 'forehand_immediate_cut_two_hand'), ('forehand_mirror_reverse_shield', '방패 착용', 'forehand_immediate_cut_shield')]
selected = [0, 2, 4, 6, 8, 10, 12, 18, 30, 50]
loaded = []
report = {}
for directory, label, previous in stances:
    source = root / directory
    manifest = json.loads((source / 'capture_manifest.json').read_text())
    assert manifest['actual_renderer'] == 'vulkan' and manifest['display_driver'] == 'embedded'
    assert not manifest['candidate_manifest_path'] and not manifest['failures']
    assert manifest['sources_unchanged_during_capture'] and manifest['expedition_and_cursor_preserved']
    for uri, sha in manifest['source_sha256'].items():
        assert hashlib.sha256((Path('godot-game') / uri[6:]).read_bytes()).hexdigest() == sha, uri
    sequences = [sorted((source / 'sequences' / clip).glob('frame_*.png')) for clip, _ in clips]
    assert all(len(frames) == 91 for frames in sequences)
    unchanged = sum(path.read_bytes() == (root / previous / 'sequences/left_reverse' / path.name).read_bytes() for path in sequences[1])
    assert unchanged == 91
    records = {sequence['id'] if 'id' in sequence else sequence['sequence_id']: sequence for sequence in manifest['sequences']}
    starts = [next(row['frame'] for row in records[clip]['frames'] if row['combat_phase'] == 'active') for clip, _ in clips]
    count = min(91 - start for start in starts)
    sheet = Image.new('RGB', (1600, 808), (20, 20, 20))
    images = [[Image.open(path).convert('RGB').resize((960, 540)) for path in sequence] for sequence in sequences]
    for index in selected:
        assert index < count
        k = selected.index(index)
        for side, (_, title) in enumerate(clips):
            x, y = k % 5 * 320, (k // 5 * 2 + side) * 202
            sheet.paste(images[side][starts[side] + index].resize((320, 180)), (x, y + 22))
            ImageDraw.Draw(sheet).text((x + 3, y + 2), f'{title} {index / 60:.3f}s', font=small, fill='white')
    sheet.save(out / f'{directory}.jpg', quality=95)
    loaded.append((images, starts, count, label))
    report[directory] = {'actual_frames': 182, 'unchanged_reverse_pngs': unchanged, 'current_source_hashes_match': True, 'expedition_and_cursor_preserved': True, 'active_start_frames': starts, 'compared_frames': count}

video = out / 'matched_cuts.mp4'
container = av.open(str(video), 'w')
stream = container.add_stream('libx264', rate=60)
stream.width, stream.height = 1920, 606
stream.pix_fmt = 'yuv420p'
stream.options = {'crf': '18', 'preset': 'fast'}
encoded = 0
for repeats, speed in [(1, '정상 속도'), (2, '0.5배속')]:
    for images, starts, count, label in loaded:
        for index in range(count):
            canvas = Image.new('RGB', (1920, 606), (20, 20, 20))
            draw = ImageDraw.Draw(canvas)
            for side, (_, title) in enumerate(clips):
                canvas.paste(images[side][starts[side] + index], (side * 960, 66))
                draw.text((side * 960 + 16, 4), label + ' · ' + title, font=font, fill='white')
                draw.text((side * 960 + 16, 37), '실제 Godot 렌더 · 공격 시작 시점 정렬 · ' + speed, font=small, fill='#cccccc')
            for _ in range(repeats):
                frame = av.VideoFrame.from_image(canvas)
                frame.pts = encoded
                encoded += 1
                for packet in stream.encode(frame):
                    container.mux(packet)
for packet in stream.encode():
    container.mux(packet)
container.close()
with av.open(str(video)) as check:
    assert sum(1 for _ in check.decode(video=0)) == encoded
(out / 'capture_verification.json').write_text(json.dumps({'captures': report, 'video': str(video.resolve()), 'encoded_frames': encoded, 'fps': 60, 'presentation': 'Actual ACTIVE start aligned by cropping; normal then explicitly labeled half speed; no mirrored or reversed pixels.'}, indent=2) + '\n')
print('ACTUAL MATCHED CUTS', encoded, 'frames', json.dumps(report))
