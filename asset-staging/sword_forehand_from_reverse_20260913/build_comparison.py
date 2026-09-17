"""Package actual game captures. Never reflect or reverse rendered video pixels."""
from pathlib import Path
import json
import hashlib
import av
from PIL import Image, ImageDraw, ImageFont

root = Path('godot-game/artifacts/visual_qa/reference_sword_motion')
out = root / 'forehand_from_reverse_final_comparison'
out.mkdir(exist_ok=True)
font = ImageFont.truetype('godot-game/assets/fonts/NotoSansKR-Variable.ttf', 24)
small = ImageFont.truetype('godot-game/assets/fonts/NotoSansKR-Variable.ttf', 15)
clips = [('right_diagonal', '수정한 정베기 · 오른쪽 → 왼쪽'), ('left_reverse', '기존 역베기 · 왼쪽 → 오른쪽')]
stances = [('forehand_from_reverse_final_two_hand', '양손 파지', 'reverse_restore_two_hand'), ('forehand_from_reverse_final_shield', '방패 착용', 'edge_aligned_final_shield')]
video = out / 'opposite_cuts.mp4'
container = av.open(str(video), 'w')
stream = container.add_stream('libx264', rate=60)
stream.width, stream.height = 1920, 582
stream.pix_fmt = 'yuv420p'
stream.options = {'crf': '18', 'preset': 'fast'}
count = 0
report = {}
selected = [0, 14, 17, 19, 21, 23, 26, 30, 40, 55]
for directory, label, previous in stances:
    source = root / directory
    if not (source / 'capture_manifest.json').exists():
        continue
    manifest = json.loads((source / 'capture_manifest.json').read_text())
    assert manifest['actual_renderer'] == 'vulkan' and manifest['display_driver'] == 'embedded'
    assert not manifest['candidate_manifest_path'] and not manifest['failures']
    assert manifest['sources_unchanged_during_capture'] and manifest['expedition_and_cursor_preserved']
    for uri, sha in manifest['source_sha256'].items():
        path = Path('godot-game') / uri[6:]
        assert hashlib.sha256(path.read_bytes()).hexdigest() == sha, path
    sequences = [sorted((source / 'sequences' / clip).glob('frame_*.png')) for clip, _ in clips]
    assert all(len(frames) == 91 for frames in sequences)
    same_reverse = sum(path.read_bytes() == (root / previous / 'sequences/left_reverse' / path.name).read_bytes() for path in sequences[1])
    assert same_reverse == 91
    sheet = Image.new('RGB', (1600, 808), (20, 20, 20))
    for index in range(91):
        canvas = Image.new('RGB', (1920, 582), (20, 20, 20))
        for side, (_, title) in enumerate(clips):
            frame_image = Image.open(sequences[side][index]).convert('RGB')
            canvas.paste(frame_image.resize((960, 540)), (side * 960, 42))
            ImageDraw.Draw(canvas).text((side * 960 + 16, 7), label + ' · ' + title, font=font, fill='white')
            if index in selected:
                selected_index = selected.index(index)
                x, y = selected_index % 5 * 320, (selected_index // 5 * 2 + side) * 202
                sheet.paste(frame_image.resize((320, 180)), (x, y + 22))
                ImageDraw.Draw(sheet).text((x + 4, y + 2), f'{clips[side][0]} {index / 60:.3f}s', font=small, fill='white')
        frame = av.VideoFrame.from_image(canvas)
        frame.pts = count
        count += 1
        for packet in stream.encode(frame):
            container.mux(packet)
    sheet.save(out / (directory + '.jpg'), quality=95)
    report[directory] = {'actual_frames': 182, 'unchanged_reverse_pngs': same_reverse, 'current_source_hashes_match': True, 'expedition_and_cursor_preserved': True}
for packet in stream.encode():
    container.mux(packet)
container.close()
with av.open(str(video)) as check:
    assert sum(1 for _ in check.decode(video=0)) == count
assert report
(out / 'capture_verification.json').write_text(json.dumps({'captures': report, 'frames': count, 'fps': 60, 'video': str(video.resolve())}, indent=2) + '\n')
print('ACTUAL CUT COMPARISON', count, 'frames;', json.dumps(report))
