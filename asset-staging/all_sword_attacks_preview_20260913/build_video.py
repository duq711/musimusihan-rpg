from pathlib import Path
import hashlib,json,av
from PIL import Image,ImageDraw,ImageFont
root=Path('godot-game/artifacts/visual_qa/reference_sword_motion')
out=root/'all_sword_attacks_showcase';out.mkdir(exist_ok=True)
font=ImageFont.truetype('godot-game/assets/fonts/NotoSansKR-Variable.ttf',25)
small=ImageFont.truetype('godot-game/assets/fonts/NotoSansKR-Variable.ttf',17)
clips=[('right_diagonal','정베기 · 오른쪽 → 왼쪽'),('left_reverse','역베기 · 왼쪽 → 오른쪽'),('overhead','내려베기 · 위 → 아래')]
stances=[('all_attacks_two_hand','양손 파지'),('all_attacks_shield','검과 방패')]
images={};records={};report={}
for directory,label in stances:
 source=root/directory;m=json.loads((source/'capture_manifest.json').read_text())
 assert m['actual_renderer']=='vulkan' and m['display_driver']=='embedded' and not m['failures'] and not m['candidate_manifest_path']
 assert m['sources_unchanged_during_capture'] and m['expedition_and_cursor_preserved'] and m['attack_release_seconds']==0.0
 assert [seq['id'] for seq in m['sequences']]==[clip for clip,_ in clips]
 for uri,sha in m['source_sha256'].items():assert hashlib.sha256((Path('godot-game')/uri[6:]).read_bytes()).hexdigest()==sha,uri
 for seq in m['sequences']:
  clip=seq['id'];paths=sorted((source/'sequences'/clip).glob('frame_*.png'));assert len(paths)==91
  assert any(row['combat_phase']=='active' for row in seq['frames']) and seq['frames'][-1]['combat_phase']=='ready'
  images[(directory,clip)]=[Image.open(p).convert('RGB').resize((960,540)) for p in paths]
  records[(directory,clip)]=seq['frames']
 report[directory]={'actual_frames':273,'three_actual_attacks_complete':True,'source_hashes_current':True,'expedition_and_cursor_preserved':True}
video=out/'all_attacks.mp4';c=av.open(str(video),'w');stream=c.add_stream('libx264',rate=60);stream.width=1920;stream.height=612;stream.pix_fmt='yuv420p';stream.options={'crf':'18','preset':'fast'};encoded=0
sheet=Image.new('RGB',(1600,1212),'#141414');sd=ImageDraw.Draw(sheet)
for clip_index,(clip,name) in enumerate(clips):
 for side,(directory,label) in enumerate(stances):
  rows=records[(directory,clip)];start=next(row['frame'] for row in rows if row['combat_phase']=='active')
  for k,frame in enumerate([start,start+5,start+9,start+15,min(start+40,90)]):
   x=k*320;y=(clip_index*2+side)*202;sheet.paste(images[(directory,clip)][frame].resize((320,180)),(x,y+22));sd.text((x+3,y+2),f'{label} · {name.split(" · ")[0]} {frame/60:.2f}s',font=small,fill='white')
 for repeats,speed in [(1,'정상 속도'),(2,'0.5배속')]:
  for i in range(91):
   canvas=Image.new('RGB',(1920,612),'#141414');d=ImageDraw.Draw(canvas)
   for side,(directory,label) in enumerate(stances):
    x=960*side;canvas.paste(images[(directory,clip)][i],(x,72));d.text((x+16,4),f'{clip_index+1}/3  {name}  |  {label}',font=font,fill='white');d.text((x+16,40),'실제 Godot 렌더 · 짧은 클릭 · '+speed,font=small,fill='#cccccc')
   for _ in range(repeats):
    frame=av.VideoFrame.from_image(canvas);frame.pts=encoded;encoded+=1
    for packet in stream.encode(frame):c.mux(packet)
for packet in stream.encode():c.mux(packet)
c.close();sheet.save(out/'all_attacks_contact.jpg',quality=95)
with av.open(str(video)) as check:assert sum(1 for _ in check.decode(video=0))==encoded
(out/'verification.json').write_text(json.dumps({'captures':report,'video':str(video.resolve()),'fps':60,'encoded_frames':encoded,'duration_seconds':encoded/60,'ordering':[name for _,name in clips],'presentation':'Same real short-click attack shown in both equipment states, normal then labelled half speed; no gameplay edits or pixel animation.'},ensure_ascii=False,indent=2)+'\n')
print('ALL ATTACKS VIDEO PASS',encoded,'frames',encoded/60,'seconds')
