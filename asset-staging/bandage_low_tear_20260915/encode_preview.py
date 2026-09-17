from pathlib import Path
import json
import av
from PIL import Image, ImageDraw, ImageFont
root = Path(__file__).resolve().parents[2]
frames = root / 'godot-game/artifacts/visual_qa/bandage_forearm/low_tear_08'
manifest = json.loads((frames/'manifest.json').read_text())
assert len(manifest['frames']) == 176 and manifest['state_and_sources_preserved']
video = frames/'bandage_tear.mp4'
font = ImageFont.truetype(str(root/'godot-game/assets/fonts/NotoSansKR-Variable.ttf'), 23)
small = ImageFont.truetype(str(root/'godot-game/assets/fonts/NotoSansKR-Variable.ttf'), 16)
with av.open(str(video), 'w', options={'movflags': '+faststart'}) as container:
    stream = container.add_stream('libx264', rate=30)
    stream.width, stream.height = 960, 540
    stream.pix_fmt = 'yuv420p'
    stream.options = {'crf':'18', 'preset':'medium'}
    for frame in manifest['frames']:
        picture = Image.open(frames/frame['file']).convert('RGB')
        draw = ImageDraw.Draw(picture)
        draw.text((24,20), '붕대 감기 · 낮은 팔 자세로 마무리', font=font, fill='#f1eee7')
        draw.text((24,54), '실제 Godot 렌더링 · 검증본 · 1배속', font=small, fill='#a5aca9')
        for packet in stream.encode(av.VideoFrame.from_image(picture)):
            container.mux(packet)
    for packet in stream.encode(): container.mux(packet)
with av.open(str(video)) as container:
    decoded = sum(1 for _ in container.decode(video=0))
assert decoded == 176
print(f'{video}\n176 decoded frames / 30fps / {video.stat().st_size} bytes')
