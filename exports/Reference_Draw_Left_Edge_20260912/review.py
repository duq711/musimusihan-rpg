from pathlib import Path
from PIL import Image, ImageDraw, ImageFont
import av, sys
root=Path(sys.argv[1])
frames=sorted((root/'sequences/draw').glob('frame_*.png'))
font=ImageFont.truetype('godot-game/assets/fonts/NotoSansKR-Variable.ttf',19)
# Fixed crop of the actual player render; no generated poses or interpolation.
indices=[0,6,12,15,18,21]
sheet=Image.new('RGB',(1440,396),(24,24,24))
for slot,i in enumerate(indices):
 x=slot%3*480;y=slot//3*198
 im=Image.open(frames[i]).convert('RGB').crop((0,300,1280,720)).resize((480,158))
 sheet.paste(im,(x,y+35))
 ImageDraw.Draw(sheet).text((x+10,y+6),f'실제 렌더 | {i/60:.2f}초',font=font,fill='white')
sheet.save(root/'finger_sequence.jpg',quality=94)
output=root/'left_edge_draw.mp4'
container=av.open(str(output),'w');stream=container.add_stream('libx264',rate=60)
stream.width=1280;stream.height=752;stream.pix_fmt='yuv420p';stream.options={'crf':'18','preset':'fast'}
count=0
for selected,repeat,label in [(frames,1,'실제 Godot 렌더링 · 정상 속도'),(frames[:44],4,'화면 왼쪽 끝까지 연속 이동 · 0.25배속 (실제 프레임 반복)')]:
 for f in selected:
  canvas=Image.new('RGB',(1280,752),(20,20,20));canvas.paste(Image.open(f),(0,32))
  ImageDraw.Draw(canvas).text((15,6),label,font=font,fill='white')
  for _ in range(repeat):
   frame=av.VideoFrame.from_image(canvas);frame.pts=count;count+=1
   for packet in stream.encode(frame):container.mux(packet)
for packet in stream.encode():container.mux(packet)
container.close()
with av.open(str(output)) as check:
 decoded=sum(1 for _ in check.decode(video=0))
assert decoded==count
print('Verified encoded/decoded frames:', count)
