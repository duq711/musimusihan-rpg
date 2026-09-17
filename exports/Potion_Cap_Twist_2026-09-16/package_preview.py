from pathlib import Path
from PIL import Image,ImageDraw
import json,shutil
out=Path(__file__).parent
p=out.parent.parent/'godot-game/artifacts/visual_qa/potion_drink/cap_twist_01'
m=json.loads((p/'manifest.json').read_text())
assert m['state_and_sources_preserved'] and m['timed_completion_verified'] and len(m['frames'])==219
frames=[Image.open(p/f'frame_{i:03d}.png').convert('RGB').resize((800,450)) for i in range(0,219,2)]
frames[0].save(out/'potion_cap_twist.gif',save_all=True,append_images=frames[1:],duration=67,loop=0,optimize=False)
# Focused clip at native speed, including reach, both turns, regrip and removal.
cap=[Image.open(p/f'frame_{i:03d}.png').convert('RGB').resize((800,450)) for i in range(15,85)]
cap[0].save(out/'cap_closeup.gif',save_all=True,append_images=cap[1:],duration=[33,33,34]*23+[33],loop=0,optimize=False)
shutil.copy2(p/'manifest.json',out/'manifest.json')
ids=[22,30,38,45,50,58,64,71,80]
sheet=Image.new('RGB',(1440,3*294),(24,27,27));draw=ImageDraw.Draw(sheet)
for k,i in enumerate(ids):
 x=k%3*480;y=k//3*294
 im=Image.open(p/f'frame_{i:03d}.png').convert('RGB').resize((480,270))
 sheet.paste(im,(x,y));draw.text((x+8,y+275),f'{i/30:.2f}s',fill=(225,230,227))
sheet.save(out/'contact_sheet.jpg',quality=92)
print('Packaged checked production capture:',len(m['frames']),'frames')
