"""Present unmodified actual Godot frames as a review sheet/video."""
from pathlib import Path
import json
import sys
import av
from PIL import Image, ImageDraw, ImageFont

root = Path(sys.argv[1])
manifest = json.loads((root / 'capture_manifest.json').read_text())
assert manifest['display_driver'] == 'embedded'
assert manifest['actual_renderer'] == 'vulkan'
assert manifest['expedition_and_cursor_preserved']
assert manifest['sources_unchanged_during_capture']
assert not manifest['failures']
font = ImageFont.truetype('godot-game/assets/fonts/NotoSansKR-Variable.ttf', 20)
review_status = '미적용 후보 · ' if manifest.get('candidate_manifest_path') else ''
labels = {'right_diagonal': '오른쪽 → 왼쪽 베기', 'left_reverse': '왼쪽 → 오른쪽 베기'}
clips = ['right_diagonal', 'left_reverse']
for name in clips:
    frames = sorted((root / 'sequences' / name).glob('frame_*.png'))
    selected = [0, 16, 28, 32, 34, 37, 40, 43, 46, 49, 53, 57, 62, 67, 75, 90]
    sheet = Image.new('RGB', (1600, 1000), (24, 24, 24))
    draw = ImageDraw.Draw(sheet)
    for i, index in enumerate(selected):
        x, y = i % 4 * 400, i // 4 * 250
        frame = Image.open(frames[index]).convert('RGB').resize((400, 225))
        sheet.paste(frame, (x, y + 25))
        draw.text((x + 8, y + 4), f'{name} · {index / 60:.3f}s', fill='white')
    sheet.save(root / f'{name}_sequence.jpg', quality=94)

out = root / 'two_hand_cut_review.mp4'
container = av.open(str(out), 'w')
stream = container.add_stream('libx264', rate=60)
stream.width, stream.height = 1280, 752
stream.pix_fmt = 'yuv420p'
stream.options = {'crf': '18', 'preset': 'fast'}
count = 0
for repeat, speed in [(1, '실제 속도'), (2, '0.5배속 확인')]:
    for name in clips:
        for path in sorted((root / 'sequences' / name).glob('frame_*.png')):
            canvas = Image.new('RGB', (1280, 752), (20, 20, 20))
            canvas.paste(Image.open(path), (0, 32))
            ImageDraw.Draw(canvas).text((15, 4), f'{review_status}실제 Godot 렌더링 · {labels[name]} · {speed}', fill='white', font=font)
            for _ in range(repeat):
                frame = av.VideoFrame.from_image(canvas)
                frame.pts = count
                count += 1
                for packet in stream.encode(frame):
                    container.mux(packet)
for packet in stream.encode():
    container.mux(packet)
container.close()
with av.open(str(out)) as review:
    decoded = sum(1 for _ in review.decode(video=0))
assert decoded == count
print(f'REVIEW VIDEO PASS: {count} decoded frames, actual 1x then 0.5x, {out}')
