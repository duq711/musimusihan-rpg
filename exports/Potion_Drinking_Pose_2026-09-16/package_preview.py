from pathlib import Path
from PIL import Image,ImageDraw
import json,shutil
out=Path(__file__).parent
root=out.parent.parent
p=root/'godot-game/artifacts/visual_qa/potion_drink/mouth_body_final'
m=json.loads((p/'manifest.json').read_text())
assert m['state_and_sources_preserved'] and m['timed_completion_verified'] and len(m['frames'])==195
frames=[Image.open(p/f'frame_{i:03d}.png').convert('RGB').resize((800,450)) for i in range(0,195,2)]
frames[0].save(out/'potion_drinking_pose.gif',save_all=True,append_images=frames[1:],duration=67,loop=0,optimize=False)
shutil.copy2(p/'manifest.json',out/'manifest.json')
ids=[24,33,42,48,54,60,75,95,115,135,144,151]
sheet=Image.new('RGB',(1440,4*294),(24,27,27));draw=ImageDraw.Draw(sheet)
for k,i in enumerate(ids):
 x=k%3*480;y=k//3*294
 im=Image.open(p/f'frame_{i:03d}.png').convert('RGB').resize((480,270))
 sheet.paste(im,(x,y));draw.text((x+8,y+275),f'{i/30:.2f}s',fill=(225,230,227))
sheet.save(out/'contact_sheet.jpg',quality=92)
print('Verified manifest and packaged 195 rendered frames.')
