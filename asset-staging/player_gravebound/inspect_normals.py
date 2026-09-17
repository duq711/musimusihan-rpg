import bpy
from pathlib import Path
bpy.ops.wm.open_mainfile(filepath=str(Path('/Users/duq711gmail.com/Documents/ChatGPT/무시무시한 rpg/asset-staging/player_gravebound/gravebound_player.blend')))
for name in ['Gravebound_QuiltedTorso','Gravebound_PointHood','Gravebound_MantleBack','Gravebound_CoatBackAndSides','Gravebound_Bracer_L']:
 o=bpy.data.objects[name];back=[p for p in o.data.polygons if p.center.y>.05];front=[p for p in o.data.polygons if p.center.y<-.05]
 print(name,'BACK',sum(p.normal.y for p in back)/max(1,len(back)),len(back),'FRONT',sum(p.normal.y for p in front)/max(1,len(front)),len(front))
