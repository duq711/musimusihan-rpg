"""Compare both directions at the same actual frame; pixels are not mirrored."""
from pathlib import Path
import json,hashlib,av
from PIL import Image,ImageDraw,ImageFont
root=Path('godot-game/artifacts/visual_qa/reference_sword_motion')
stances=[('reverse_match_two_hand','양손 파지'),('reverse_match_shield','방패 착용')]
clips=[('right_diagonal','오른쪽 → 왼쪽 · 기존 베기'),('left_reverse','왼쪽 → 오른쪽 · 수정 베기')]
out=root/'reverse_match_comparison';out.mkdir(exist_ok=True)
font=ImageFont.truetype('godot-game/assets/fonts/NotoSansKR-Variable.ttf',24)
small=ImageFont.truetype('godot-game/assets/fonts/NotoSansKR-Variable.ttf',15)
container=av.open(str(out/'opposite_directions.mp4'),'w')
stream=container.add_stream('libx264',rate=60);stream.width=1920;stream.height=582;stream.pix_fmt='yuv420p';stream.options={'crf':'18','preset':'fast'}
count=0;preserved={}
for dirname,label in stances:
 p=root/dirname;m=json.loads((p/'capture_manifest.json').read_text())
 assert m['actual_renderer']=='vulkan' and m['display_driver']=='embedded' and m['candidate_manifest_path']==''
 assert not m['failures'] and m['attack_release_seconds']==0 and m['sources_unchanged_during_capture'] and m['expedition_and_cursor_preserved']
 sequences=[sorted((p/'sequences'/clip).glob('frame_*.png')) for clip,_ in clips];assert all(len(s)==91 for s in sequences)
 old=root/('edge_aligned_final_two_hand' if 'two_hand' in dirname else 'edge_aligned_final_shield')/'sequences/right_diagonal'
 preserved[dirname]=sum(hashlib.sha256(f.read_bytes()).digest()==hashlib.sha256((old/f.name).read_bytes()).digest() for f in sequences[0])
 sheet=Image.new('RGB',(1600,808),(20,20,20))
 selected=[0,6,12,15,18,22,25,30]
 for index in range(91):
  canvas=Image.new('RGB',(1920,582),(20,20,20));draw=ImageDraw.Draw(canvas)
  for side in range(2):
   source=Image.open(sequences[side][index]).convert('RGB')
   canvas.paste(source.resize((960,540)),(side*960,42))
   draw.text((side*960+16,7),f'{label} · {clips[side][1]}',font=font,fill='white')
   if index in selected:
    j=selected.index(index);x,y=(j%4)*400,(j//4*2+side)*202
    sheet.paste(source.resize((320,180)),(x,y+22));ImageDraw.Draw(sheet).text((x+4,y+2),f'{clips[side][0]} {index/60:.3f}s',font=small,fill='white')
  frame=av.VideoFrame.from_image(canvas);frame.pts=count;count+=1
  for packet in stream.encode(frame):container.mux(packet)
 sheet.save(out/f'{dirname}.jpg',quality=94)
for packet in stream.encode():container.mux(packet)
container.close()
with av.open(str(out/'opposite_directions.mp4')) as video:assert sum(1 for _ in video.decode(video=0))==count
(out/'approved_forehand_pixel_preservation.json').write_text(json.dumps({'same_png_count_out_of_91':preserved},indent=2))
print('ACTUAL OPPOSITE DIRECTIONS VIDEO PASS',count,'frames; approved forehand unchanged PNG counts',preserved)
