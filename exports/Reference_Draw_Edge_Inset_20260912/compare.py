from pathlib import Path
from PIL import Image,ImageDraw,ImageFont
root=Path('godot-game/artifacts/visual_qa/reference_sword_motion');out=root/'draw_edge_inset_final'
canvas=Image.new('RGB',(1280,760),(25,25,25));font=ImageFont.truetype('godot-game/assets/fonts/NotoSansKR-Variable.ttf',21)
for row,frame in enumerate([17,18,19]):
 for col,folder,label in [(0,'draw_left_edge_final','이전'),(1,'draw_edge_inset_final','조금 오른쪽으로')]:
  p=root/folder/f'sequences/draw/frame_{frame:03d}.png'
  im=Image.open(p).crop((0,300,1280,720)).resize((640,210));x=col*640;y=row*253;canvas.paste(im,(x,y+35));ImageDraw.Draw(canvas).text((x+10,y+5),f'{label} · {frame/60:.3f}초',font=font,fill='white')
canvas.save(out/'inset_comparison.jpg',quality=95)
