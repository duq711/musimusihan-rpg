from pathlib import Path
from PIL import Image,ImageDraw,ImageFont
import av,sys
root=Path(sys.argv[1]);fs=sorted((root/'sequences/shield_stow').glob('frame_*.png'))
assert len(fs)==61,len(fs)
font=ImageFont.truetype('godot-game/assets/fonts/NotoSansKR-Variable.ttf',19)
sheet=Image.new('RGB',(1600,510),(22,22,22))
for n,i in enumerate([0,4,8,12,16,24,33,60]):
 x=n%4*400;y=n//4*255;sheet.paste(Image.open(fs[i]).resize((400,225)),(x,y+30));ImageDraw.Draw(sheet).text((x+8,y+5),f'방패 수납 {i/60:.2f}초',font=font,fill='white')
sheet.save(root/'shield_stow_sequence.jpg',quality=95)
out=root/'shield_stow_review.mp4';c=av.open(str(out),'w');s=c.add_stream('libx264',rate=60);s.width=1280;s.height=752;s.pix_fmt='yuv420p';s.options={'crf':'18','preset':'fast'};count=0
for frames,repeat,label in [(fs,1,'실제 Godot 렌더링 · 1번 방패 수납'),(fs[:35],4,'방패 수납 · 0.25배속 (실제 프레임 반복)')]:
 for f in frames:
  canvas=Image.new('RGB',(1280,752),(20,20,20));canvas.paste(Image.open(f),(0,32));ImageDraw.Draw(canvas).text((15,6),label,font=font,fill='white')
  for _ in range(repeat):
   frame=av.VideoFrame.from_image(canvas);frame.pts=count;count+=1
   for packet in s.encode(frame):c.mux(packet)
for packet in s.encode():c.mux(packet)
c.close()
with av.open(str(out)) as check: assert sum(1 for _ in check.decode(video=0))==count
print('VIDEO VERIFIED',count)
