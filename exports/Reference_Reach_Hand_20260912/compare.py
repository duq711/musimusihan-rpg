from pathlib import Path
from PIL import Image,ImageDraw,ImageFont
root=Path.cwd();dest=root/'godot-game/artifacts/visual_qa/reference_sword_motion/reach_hand_final'
reference=Image.open('/var/folders/7r/486gfldn6f57tqk3gxh1rmfh0000gn/T/codex-clipboard-ca866b38-baa8-41a8-af14-85155dafbd56.png').convert('RGB')
reference=reference.crop((0,162,2940,1815))
old=Image.open(root/'godot-game/artifacts/visual_qa/reference_sword_motion/equip_verified/sequences/draw/frame_008.png').convert('RGB')
new=Image.open(dest/'sequences/draw/frame_008.png').convert('RGB')
font=ImageFont.truetype(str(root/'godot-game/assets/fonts/NotoSansKR-Variable.ttf'),22)
sheet=Image.new('RGB',(960,572*3),'#222222');d=ImageDraw.Draw(sheet)
for i,(im,label) in enumerate([(reference,'첨부 사진 · 자세 참고'),(old,'수정 전 · 실제 Godot'),(new,'수정 후 · 실제 Godot')]):
 sheet.paste(im.resize((960,540)),(0,i*572+32));d.text((15,i*572+5),label,fill='white',font=font)
sheet.save(dest/'hand_comparison.jpg',quality=94)
new.save(dest/'reaching_hand.png')
