from pathlib import Path
import json,hashlib,av
from PIL import Image,ImageDraw,ImageFont
root=Path('godot-game/artifacts/visual_qa/reference_sword_motion')
out=root/'forehand_followthrough_comparison';out.mkdir(exist_ok=True)
font=ImageFont.truetype('godot-game/assets/fonts/NotoSansKR-Variable.ttf',24)
small=ImageFont.truetype('godot-game/assets/fonts/NotoSansKR-Variable.ttf',16)
loaded=[];report={}
for stance,label in [('two_hand','양손 파지'),('shield','방패 착용')]:
 before=root/('forehand_mirror_reverse_'+stance);after=root/('forehand_followthrough_'+stance)
 m=json.loads((after/'capture_manifest.json').read_text())
 assert m['actual_renderer']=='vulkan' and m['display_driver']=='embedded' and not m['candidate_manifest_path'] and not m['failures']
 assert m['sources_unchanged_during_capture'] and m['expedition_and_cursor_preserved']
 for uri,sha in m['source_sha256'].items():assert hashlib.sha256((Path('godot-game')/uri[6:]).read_bytes()).hexdigest()==sha,uri
 reverse=sorted((after/'sequences/left_reverse').glob('frame_*.png'))
 assert len(reverse)==91 and all(p.read_bytes()==(before/'sequences/left_reverse'/p.name).read_bytes() for p in reverse)
 pictures=[[Image.open(p).convert('RGB').resize((960,540)) for p in sorted((d/'sequences/right_diagonal').glob('frame_*.png'))] for d in [before,after]]
 assert all(len(seq)==91 for seq in pictures)
 sheet=Image.new('RGB',(1600,808),'#141414');draw=ImageDraw.Draw(sheet)
 selected=[8,10,12,14,16,18,24,38,43,48]
 for k,frame in enumerate(selected):
  for side in range(2):
   x=k%5*320;y=(k//5*2+side)*202
   sheet.paste(pictures[side][frame].resize((320,180)),(x,y+22));draw.text((x+3,y+2),f'{"수정 전" if side==0 else "수정 후"} {frame/60:.3f}s',font=small,fill='white')
 sheet.save(out/(stance+'.jpg'),quality=95)
 loaded.append((label,pictures));report[stance]={'actual_sequence_frames':182,'unchanged_reverse_frames':91,'current_source_hashes_match':True,'expedition_and_cursor_preserved':True}
video=out/'followthrough_comparison.mp4';c=av.open(str(video),'w');stream=c.add_stream('libx264',rate=60);stream.width=1920;stream.height=606;stream.pix_fmt='yuv420p';stream.options={'crf':'18','preset':'fast'}
count=0
for repeats,speed in [(1,'정상 속도'),(2,'0.5배속')]:
 for label,pictures in loaded:
  for i in range(91):
   canvas=Image.new('RGB',(1920,606),'#141414');d=ImageDraw.Draw(canvas)
   for side,title in enumerate(['수정 전','수정 후 · 화면 밖까지 베기']):
    canvas.paste(pictures[side][i],(side*960,66));d.text((side*960+16,4),label+' · '+title,font=font,fill='white');d.text((side*960+16,37),'실제 Godot 렌더 · '+speed,font=small,fill='#cccccc')
   for _ in range(repeats):
    frame=av.VideoFrame.from_image(canvas);frame.pts=count;count+=1
    for packet in stream.encode(frame):c.mux(packet)
for packet in stream.encode():c.mux(packet)
c.close()
with av.open(str(video)) as check:assert sum(1 for _ in check.decode(video=0))==count
(out/'capture_verification.json').write_text(json.dumps({'captures':report,'video':str(video.resolve()),'encoded_frames':count,'fps':60,'presentation':'Actual normal-speed then labelled half-speed before/after forehand; no mirrored, reversed or replaced pixels.'},indent=2)+'\n')
print('FOLLOWTHROUGH VIDEO PASS',count,'frames',report)
