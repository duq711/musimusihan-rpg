from pathlib import Path
from PIL import Image,ImageDraw,ImageFont
import json,sys,av
font=ImageFont.truetype('godot-game/assets/fonts/NotoSansKR-Variable.ttf',19)
labels={'idle':'대기','walk':'걷기','run':'달리기','jump':'도약 · 공중 · 착지','overhead':'내려베기','left_reverse':'왼쪽 → 오른쪽 베기','right_diagonal':'오른쪽 → 왼쪽 베기'}
root=Path(sys.argv[1]); m=json.loads((root/'capture_manifest.json').read_text()) if (root/'capture_manifest.json').exists() else {}
for seq in (root/'sequences').iterdir():
 fs=sorted(seq.glob('frame_*.png'))
 if not fs:continue
 if seq.name in ['idle','walk','run','jump']:sel=fs[::max(1,len(fs)//12)][:12]
 else:sel=[fs[min(len(fs)-1,i)] for i in [0,4,8,15,25,28,31,34,37,40,44,49,54,60,70,85]]
 w,h=400,225; sheet=Image.new('RGB',(w*4,(h+25)*((len(sel)+3)//4)),(25,25,25));draw=ImageDraw.Draw(sheet)
 for i,f in enumerate(sel):
  im=Image.open(f).convert('RGB').resize((w,h));x=(i%4)*w;y=(i//4)*(h+25);sheet.paste(im,(x,y+25));draw.text((x+8,y+6),seq.name+' '+str(int(f.stem.split('_')[1])/60)[:5]+' s',fill='white')
 sheet.save(root/(seq.name+'_sequence.jpg'),quality=92)
if '--video' in sys.argv:
 out=root/'motion_review.mp4'
 container=av.open(str(out),'w'); stream=container.add_stream('libx264',rate=60);stream.width=1280;stream.height=752;stream.pix_fmt='yuv420p';stream.options={'crf':'19','preset':'fast'};count=0
 for seq in ['idle','walk','run','jump','overhead','left_reverse','right_diagonal']:
  for f in sorted((root/'sequences'/seq).glob('frame_*.png')):
   canvas=Image.new('RGB',(1280,752),(20,20,20));canvas.paste(Image.open(f),(0,32));ImageDraw.Draw(canvas).text((15,10),'실제 Godot 렌더링 | '+labels[seq]+' | '+str(int(f.stem.split('_')[1])/60)[:5]+' s',fill='white',font=font)
   frame=av.VideoFrame.from_image(canvas);frame.pts=count;count+=1
   for packet in stream.encode(frame):container.mux(packet)
 for packet in stream.encode():container.mux(packet)
 container.close()
 with av.open(str(out)) as c:decoded=sum(1 for _ in c.decode(video=0))
 assert count==decoded
 print('VIDEO VERIFIED',count,out)
