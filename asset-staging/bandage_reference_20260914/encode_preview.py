from pathlib import Path
import json
import av
from PIL import Image, ImageDraw, ImageFont
root = Path(__file__).resolve().parents[2]
frames = root / 'godot-game/artifacts/visual_qa/bandage_forearm/reference_01'
manifest = json.loads((frames/'manifest.json').read_text())
assert len(manifest['frames']) == 136 and manifest['state_and_sources_preserved']
video = frames/'bandage_reference.mp4'
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
        draw.text((24,20), '붕대 감기 · 참고 동작 반영', font=font, fill='#f1eee7')
        draw.text((24,54), '실제 Godot 렌더링 · 1배속', font=small, fill='#a5aca9')
        for packet in stream.encode(av.VideoFrame.from_image(picture)):
            container.mux(packet)
    for packet in stream.encode(): container.mux(packet)
with av.open(str(video)) as container:
    decoded = sum(1 for _ in container.decode(video=0))
assert decoded == 136
print(f'{video}\n136 decoded frames / 30fps / {video.stat().st_size} bytes')
