from pathlib import Path
from PIL import Image,ImageDraw,ImageFont
import av,json,sys
r=Path(sys.argv[1]) if len(sys.argv)>1 else Path('godot-game/artifacts/visual_qa/reference_sword_motion/mac_rebuild_final')
source=Path('asset-staging/reference_sword_motion_20260909/reference/sU7jk2OQlgc.mp4')
rows=[('기본 자세',8.0,'idle',30),('도약 때 내려감',15.0,'jump',12),('공중 반동',15.5,'jump',27),('착지 압축',16.0,'jump',42),('내려베기 통과',18.05,'overhead',36),('왼쪽에서 오른쪽으로',19.95,'left_reverse',37),('오른쪽에서 왼쪽으로',21.9,'right_diagonal',36)]
targets=sorted({x[1] for x in rows}); frames={}
with av.open(str(source)) as c:
 for frame in c.decode(video=0):
  while targets and float(frame.time)>=targets[0]-.008:
   frames[targets.pop(0)]=frame.to_image().convert('RGB')
  if not targets:break
font=ImageFont.truetype('godot-game/assets/fonts/NotoSansKR-Variable.ttf',20)
sheet=Image.new('RGB',(1280,len(rows)*395),(20,20,20));draw=ImageDraw.Draw(sheet)
for i,(name,t,clip,f) in enumerate(rows):
 y=i*395; sheet.paste(frames[t].resize((640,360)),(0,y+35));sheet.paste(Image.open(r/'sequences'/clip/('frame_%03d.png'%f)).resize((640,360)),(640,y+35));draw.text((8,y+6),'참고 영상 %.2f초 · '%t+name,font=font,fill='white');draw.text((650,y+6),'실제 Godot · '+name,font=font,fill='white')
sheet.save(r/'reference_comparison.jpg',quality=93)
m=json.loads((r/'capture_manifest.json').read_text());metrics={}
for seq in m['sequences']:
 fs=seq['frames']; metrics[seq['id']]={'frames':len(fs),'grip_y_range':[min(f['grip_screen'][1] for f in fs),max(f['grip_screen'][1] for f in fs)],'grip_x_range':[min(f['grip_screen'][0] for f in fs),max(f['grip_screen'][0] for f in fs)],'max_contact_error_m':max(f['grip_contact_error'] for f in fs),'max_shield_upper_m':max(f['shield_upper_length'] for f in fs)}
(r/'measured_features.json').write_text(json.dumps(metrics,indent=2));print(json.dumps(metrics,indent=2))
