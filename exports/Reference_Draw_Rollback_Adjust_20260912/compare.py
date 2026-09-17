from pathlib import Path
from PIL import Image,ImageDraw,ImageFont
root=Path('godot-game/artifacts/visual_qa/reference_sword_motion');out=root/'draw_rollback_adjust_final'
canvas=Image.new('RGB',(1280,760),(25,25,25));font=ImageFont.truetype('godot-game/assets/fonts/NotoSansKR-Variable.ttf',21)
for row,frame in enumerate([9,12,36]):
 for col,folder,label in [(0,'draw_left_adjust_final','지정하신 5cm 버전'),(1,'draw_rollback_adjust_final','복원 후 왼쪽으로 2cm 추가')]:
  p=root/folder/f'sequences/draw/frame_{frame:03d}.png'
  im=Image.open(p).crop((0,300,1280,720)).resize((640,210));x=col*640;y=row*253;canvas.paste(im,(x,y+35));ImageDraw.Draw(canvas).text((x+10,y+5),f'{label} · {frame/60:.3f}초',font=font,fill='white')
canvas.save(out/'rollback_comparison.jpg',quality=95)
