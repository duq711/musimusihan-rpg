from pathlib import Path
from PIL import Image,ImageDraw
import json,shutil,hashlib
out=Path(__file__).parent
root=out.parent.parent
p=root/'godot-game/artifacts/visual_qa/potion_drink/lower_arms_final'
m=json.loads((p/'manifest.json').read_text())
assert not m['diagnostic_pose_study']
assert m['state_and_sources_preserved'] and m['timed_completion_verified'] and len(m['frames'])==219
for source,digest in m['source_hashes'].items():
 assert hashlib.sha256((root/'godot-game'/source.removeprefix('res://')).read_bytes()).hexdigest()==digest,source
frames=[Image.open(p/f'frame_{i:03d}.png').convert('RGB').resize((800,450)) for i in range(0,219,2)]
frames[0].save(out/'potion_full.gif',save_all=True,append_images=frames[1:],duration=67,loop=0,optimize=False)
# Opens directly on the drink pose, not on the sword/equipment rest frame.
drink=[Image.open(p/f'frame_{i:03d}.png').convert('RGB').resize((800,450)) for i in range(93,165)]
drink[0].save(out/'potion_drinking.gif',save_all=True,append_images=drink[1:],duration=[33,33,34]*24,loop=0,optimize=False)
shutil.copy2(p/'frame_112.png',out/'drinking_pose.png')
shutil.copy2(p/'manifest.json',out/'manifest.json')
ids=[24,30,43,50,64,71,81,112,160]
a=Image.new('RGB',(1440,882),(24,26,27));d=ImageDraw.Draw(a)
for k,i in enumerate(ids):
 x=k%3*480;y=k//3*294
 a.paste(Image.open(p/f'frame_{i:03d}.png').resize((480,270)),(x,y));d.text((x+8,y+275),f'{i/30:.2f}s',fill='white')
a.save(out/'contact_sheet.jpg',quality=92)
print('Verified 219 production frames and 8 source hashes; packaged full and drinking clips.')
