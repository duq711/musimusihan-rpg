"""Package actual restored game frames and verify exact pre-mirror restoration."""
from pathlib import Path
import hashlib
import json
import av
from PIL import Image, ImageDraw, ImageFont

root = Path('godot-game/artifacts/visual_qa/reference_sword_motion')
source = root / 'reverse_restore_two_hand'
baseline = root / 'edge_aligned_final_two_hand'
out = root / 'reverse_restore_video'
out.mkdir(exist_ok=True)
manifest = json.loads((source / 'capture_manifest.json').read_text())
assert manifest['actual_renderer'] == 'vulkan'
assert manifest['display_driver'] == 'embedded'
assert manifest['candidate_manifest_path'] == '' and not manifest['failures']
assert manifest['sources_unchanged_during_capture']
assert manifest['expedition_and_cursor_preserved']
assert manifest['attack_release_seconds'] == 0
for uri, expected in manifest['source_sha256'].items():
    assert uri.startswith('res://')
    path = Path('godot-game') / uri[6:]
    assert hashlib.sha256(path.read_bytes()).hexdigest() == expected, path

font = ImageFont.truetype('godot-game/assets/fonts/NotoSansKR-Variable.ttf', 24)
small = ImageFont.truetype('godot-game/assets/fonts/NotoSansKR-Variable.ttf', 16)
video = out / 'restored_cuts.mp4'
container = av.open(str(video), 'w')
stream = container.add_stream('libx264', rate=60)
stream.width, stream.height = 1280, 762
stream.pix_fmt = 'yuv420p'
stream.options = {'crf': '18', 'preset': 'fast'}
sheet = Image.new('RGB', (1600, 448), (20, 20, 20))
selected = [0, 15, 22, 30, 50]
count = 0
matches = {}
for row, (clip, label) in enumerate([
    ('right_diagonal', '오른쪽 → 왼쪽 · 기존 기본 베기'),
    ('left_reverse', '왼쪽 → 오른쪽 · 복원한 역베기'),
]):
    frames = sorted((source / 'sequences' / clip).glob('frame_*.png'))
    assert len(frames) == 91
    matches[clip] = 0
    for index, path in enumerate(frames):
        old = baseline / 'sequences' / clip / path.name
        assert path.read_bytes() == old.read_bytes(), path
        matches[clip] += 1
        image = Image.open(path).convert('RGB')
        canvas = Image.new('RGB', (1280, 762), (20, 20, 20))
        canvas.paste(image, (0, 42))
        ImageDraw.Draw(canvas).text((16, 5), '양손 파지 · ' + label, font=font, fill='white')
        frame = av.VideoFrame.from_image(canvas)
        frame.pts = count
        count += 1
        for packet in stream.encode(frame):
            container.mux(packet)
        if index in selected:
            x, y = selected.index(index) * 320, row * 224
            sheet.paste(image.resize((320, 180)), (x, y + 44))
            ImageDraw.Draw(sheet).text((x + 5, y + 4), f'{label}\n{index / 60:.3f}s', font=small, fill='white')
for packet in stream.encode():
    container.mux(packet)
container.close()
with av.open(str(video)) as check:
    assert sum(1 for _ in check.decode(video=0)) == count
sheet.save(out / 'restored_sequence.jpg', quality=94)
report = {
    'frames': count,
    'fps': 60,
    'video': str(video.resolve()),
    'exact_baseline_png_matches': matches,
    'capture': str(source.resolve()),
    'previous_capture': str(baseline.resolve()),
    'current_source_hashes_match': True,
    'expedition_and_cursor_preserved': True,
    'scope': 'Restoration equality; not a new animation quality claim.',
}
(out / 'restoration_verification.json').write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n')
print(json.dumps(report, ensure_ascii=False, indent=2))
