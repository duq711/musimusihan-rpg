from pathlib import Path
import hashlib,json,av
from PIL import Image,ImageDraw,ImageFont
root=Path('godot-game/artifacts/visual_qa/reference_sword_motion');staging=Path('asset-staging/sword_shield_hold_reverse_finish_20260914')
out=root/'shield_hold_reverse_finish_comparison';out.mkdir(exist_ok=True)
font=ImageFont.truetype('godot-game/assets/fonts/NotoSansKR-Variable.ttf',25);small=ImageFont.truetype('godot-game/assets/fonts/NotoSansKR-Variable.ttf',16)
report={};records={}
for stance in ['shield','two_hand']:
 directory='shield_hold_reverse_finish_'+stance;source=root/directory;m=json.loads((source/'capture_manifest.json').read_text())
 assert m['actual_renderer']=='vulkan' and m['display_driver']=='embedded' and not m['failures'] and not m['candidate_manifest_path']
 assert m['sources_unchanged_during_capture'] and m['expedition_and_cursor_preserved']
 for uri,sha in m['source_sha256'].items():assert hashlib.sha256((Path('godot-game')/uri[6:]).read_bytes()).hexdigest()==sha,uri
 old=json.loads((root/('all_attacks_'+stance)/'capture_manifest.json').read_text())
 for uri in ['res://scripts/player.gd','res://assets/animations/reference_sword_motion/motion_manifest.json']:
  assert hashlib.sha256((staging/'baseline/godot-game'/uri[6:]).read_bytes()).hexdigest()==old['source_sha256'][uri]
 counts={}
 for seq in m['sequences']:
  clip=seq['id'];paths=sorted((source/'sequences'/clip).glob('frame_*.png'));assert len(paths)==91
  assert seq['frames'][-1]['combat_phase']=='ready';records[(stance,clip)]=seq['frames']
  if stance=='shield':
   held=seq['frames'][0]['shield_transform'];active=[f for f in seq['frames'] if f['combat_phase'] in ['windup','active','recovery']]
   assert all(f['shield_transform']==held and f['shield_visible'] for f in active),clip
   counts[clip]=len(active)
  elif clip in ['right_diagonal','overhead']:
   assert all(p.read_bytes()==(root/'all_attacks_two_hand/sequences'/clip/p.name).read_bytes() for p in paths),clip
 report[stance]={'actual_frames':273,'source_hashes_current':True,'preserved_expedition_and_cursor':True,'exact_held_shield_frame_counts':counts,'unchanged_two_hand_forehand_and_overhead':stance=='two_hand'}
segments=[('shield','right_diagonal','검과 방패 · 정베기'),('shield','left_reverse','검과 방패 · 역베기'),('shield','overhead','검과 방패 · 내려베기'),('two_hand','left_reverse','양손 파지 · 역베기')]
video=out/'shield_and_reverse.mp4';c=av.open(str(video),'w');stream=c.add_stream('libx264',rate=60);stream.width=1920;stream.height=612;stream.pix_fmt='yuv420p';stream.options={'crf':'18','preset':'fast'};encoded=0
for seg_index,(stance,clip,name) in enumerate(segments):
 directories=[root/('all_attacks_'+stance),root/('shield_hold_reverse_finish_'+stance)]
 pictures=[[Image.open(p).convert('RGB').resize((960,540)) for p in sorted((directory/'sequences'/clip).glob('frame_*.png'))] for directory in directories]
 frames=records[(stance,clip)];start=next(f['frame'] for f in frames if f['combat_phase']=='active')
 selected=[start+5,start+9,start+11,start+13,start+15]
 sheet=Image.new('RGB',(1600,404),'#141414');d=ImageDraw.Draw(sheet)
 for side in range(2):
  for k,i in enumerate(selected):
   sheet.paste(pictures[side][i].resize((320,180)),(k*320,side*202+22));d.text((k*320+3,side*202+2),f'{"수정 전" if side==0 else "수정 후"} {i/60:.3f}s',font=small,fill='white')
 sheet.save(out/(stance+'_'+clip+'.jpg'),quality=95)
 for repeats,speed in [(1,'정상 속도'),(2,'0.5배속')]:
  for i in range(91):
   canvas=Image.new('RGB',(1920,612),'#141414');d=ImageDraw.Draw(canvas)
   for side,title in enumerate(['수정 전','수정 후']):
    canvas.paste(pictures[side][i],(side*960,72));d.text((side*960+16,4),name+'  |  '+title,font=font,fill='white');d.text((side*960+16,40),'실제 Godot 렌더 · '+speed,font=small,fill='#cccccc')
   for _ in range(repeats):
    frame=av.VideoFrame.from_image(canvas);frame.pts=encoded;encoded+=1
    for packet in stream.encode(frame):c.mux(packet)
for packet in stream.encode():c.mux(packet)
c.close()
with av.open(str(video)) as check:assert sum(1 for _ in check.decode(video=0))==encoded
(out/'verification.json').write_text(json.dumps({'captures':report,'video':str(video.resolve()),'fps':60,'encoded_frames':encoded,'duration_seconds':encoded/60,'presentation':'Actual before/after gameplay frames; normal then labelled half speed. No pose retouching or image mirroring.'},indent=2)+'\n')
print('SHIELD AND REVERSE VIDEO PASS',encoded,'frames',report)
