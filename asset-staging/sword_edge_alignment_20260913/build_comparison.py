"""Assemble unchanged actual engine frames, labeled with their input/stance."""
from pathlib import Path
import json
import av
from PIL import Image, ImageDraw, ImageFont

root=Path('godot-game/artifacts/visual_qa/reference_sword_motion')
paths=[root/'edge_aligned_final_shield',root/'edge_aligned_final_two_hand']
for p in paths:
    m=json.loads((p/'capture_manifest.json').read_text())
    assert m['actual_renderer']=='vulkan' and m['display_driver']=='embedded'
    assert m['attack_release_seconds']==0 and m['candidate_manifest_path']==''
    assert m['sources_unchanged_during_capture'] and m['expedition_and_cursor_preserved'] and not m['failures']
out=root/'edge_aligned_final_comparison'
out.mkdir(exist_ok=True)
font=ImageFont.truetype('godot-game/assets/fonts/NotoSansKR-Variable.ttf',24)
labels=['방패 착용','방패 수납 · 양손']
clips={'right_diagonal':'기본 베기','left_reverse':'역방향 베기'}
container=av.open(str(out/'short_click_comparison.mp4'),'w')
stream=container.add_stream('libx264',rate=60)
stream.width,stream.height=1920,582
stream.pix_fmt='yuv420p'
stream.options={'crf':'18','preset':'fast'}
count=0
for clip,title in clips.items():
    sequences=[sorted((p/'sequences'/clip).glob('frame_*.png')) for p in paths]
    assert len(sequences[0])==len(sequences[1])==91
    sheet=Image.new('RGB',(1600,808),(20,20,20))
    for index in range(91):
        canvas=Image.new('RGB',(1920,582),(20,20,20))
        draw=ImageDraw.Draw(canvas)
        for side in range(2):
            source=Image.open(sequences[side][index]).convert('RGB')
            canvas.paste(source.resize((960,540)),(side*960,42))
            draw.text((side*960+16,7),f'{labels[side]} · {title} · 짧게 클릭 · 실제 속도',font=font,fill='white')
            if index in [0,6,12,15,18,22,25,30]:
                col=[0,6,12,15,18,22,25,30].index(index)%4
                row=[0,6,12,15,18,22,25,30].index(index)//4
                x,y=col*400,(row*2+side)*202
                sheet.paste(source.resize((320,180)),(x,y+22))
                ImageDraw.Draw(sheet).text((x+4,y+2),f'{labels[side]} {index/60:.3f}s',font=ImageFont.truetype('godot-game/assets/fonts/NotoSansKR-Variable.ttf',14),fill='white')
        frame=av.VideoFrame.from_image(canvas);frame.pts=count;count+=1
        for packet in stream.encode(frame):container.mux(packet)
    sheet.save(out/f'{clip}_comparison.jpg',quality=94)
for packet in stream.encode():container.mux(packet)
container.close()
with av.open(str(out/'short_click_comparison.mp4')) as video:
    assert sum(1 for _ in video.decode(video=0))==count
print(f'ACTUAL COMPARISON VIDEO PASS: {count} frames; two stances, short input, 1x speed; {out}')
