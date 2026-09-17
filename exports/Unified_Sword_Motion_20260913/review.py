from pathlib import Path
from PIL import Image, ImageDraw, ImageFont
import av, json, sys

root = Path(sys.argv[1])
manifest = json.loads((root / 'capture_manifest.json').read_text())
font = ImageFont.truetype('godot-game/assets/fonts/NotoSansKR-Variable.ttf', 19)
cuts = [('right_diagonal', '기본 베기'), ('left_reverse', '반대 방향 베기'), ('overhead', '내려베기')]
sheet = Image.new('RGB', (1600, 765), (22, 22, 22))
out = root / 'unified_two_hand_attacks.mp4'
container = av.open(str(out), 'w')
stream = container.add_stream('libx264', rate=60)
stream.width, stream.height, stream.pix_fmt = 1280, 752, 'yuv420p'
stream.options = {'crf': '18', 'preset': 'fast'}
count = 0
for row, (seq, label) in enumerate(cuts):
    frames = sorted((root / 'sequences' / seq).glob('frame_*.png'))
    assert len(frames) == 91, (seq, len(frames))
    for col, index in enumerate([15, 35, 54, 90]):
        x, y = col * 400, row * 255
        with Image.open(frames[index]) as im:
            sheet.paste(im.resize((400, 225)), (x, y + 30))
        ImageDraw.Draw(sheet).text((x + 8, y + 5), f'{label} · {index / 60:.2f}초', font=font, fill='white')
    for path in frames:
        canvas = Image.new('RGB', (1280, 752), (20, 20, 20))
        with Image.open(path) as im:
            canvas.paste(im, (0, 32))
        ImageDraw.Draw(canvas).text((15, 6), '실제 Godot 렌더링 · 양손 파지 · ' + label, font=font, fill='white')
        frame = av.VideoFrame.from_image(canvas)
        frame.pts = count
        count += 1
        for packet in stream.encode(frame):
            container.mux(packet)
for packet in stream.encode():
    container.mux(packet)
container.close()
sheet.save(root / 'attack_review.jpg', quality=95)
with av.open(str(out)) as check:
    assert sum(1 for _ in check.decode(video=0)) == count
print('VIDEO VERIFIED', count, out)
