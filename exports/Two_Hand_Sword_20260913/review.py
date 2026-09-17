from pathlib import Path
from PIL import Image, ImageDraw, ImageFont
import av, json, sys
root=Path(sys.argv[1]);manifest=json.loads((root/'capture_manifest.json').read_text())
font=ImageFont.truetype('godot-game/assets/fonts/NotoSansKR-Variable.ttf',19)
fs=sorted((root/'sequences/shield_stow').glob('frame_*.png'))
sheet=Image.new('RGB',(1600,510),(22,22,22))
for n,i in enumerate([0,12,30,40,48,56,64,108]):
 x=n%4*400;y=n//4*255;sheet.paste(Image.open(fs[i]).resize((400,225)),(x,y+30));ImageDraw.Draw(sheet).text((x+8,y+5),f'수납 → 양손 파지 {i/60:.2f}초',font=font,fill='white')
sheet.save(root/'two_hand_transition.jpg',quality=95)
Image.open(fs[-1]).save(root/'two_hand_final.png')
out=root/'two_hand_sword_review.mp4';c=av.open(str(out),'w');s=c.add_stream('libx264',rate=60);s.width=1280;s.height=752;s.pix_fmt='yuv420p';s.options={'crf':'18','preset':'fast'};count=0
for seq,label in [('shield_stow','1번 · 방패 수납 후 양손 파지'),('run','양손 파지 · 달리기'),('jump','양손 파지 · 점프 / 착지'),('right_diagonal','양손 파지 · 검 공격')]:
 frames=sorted((root/'sequences'/seq).glob('frame_*.png'))
 assert frames,seq
 for f in frames:
  canvas=Image.new('RGB',(1280,752),(20,20,20));canvas.paste(Image.open(f),(0,32));ImageDraw.Draw(canvas).text((15,6),'실제 Godot 렌더링 · '+label,font=font,fill='white')
  frame=av.VideoFrame.from_image(canvas);frame.pts=count;count+=1
  for packet in s.encode(frame):c.mux(packet)
for packet in s.encode():c.mux(packet)
c.close()
with av.open(str(out)) as check: assert sum(1 for _ in check.decode(video=0))==count
print('VIDEO VERIFIED',count)
