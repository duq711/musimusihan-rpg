import sys,json,hashlib
from pathlib import Path
import bpy
root=Path.cwd()
new=root/'asset-staging/player_fingers_photoref_20260911/tools'
old=root/'asset-staging/player_fingers_detail_20260911/tools'
sys.path.insert(0,str(old));from build_finger_detail import collect
sys.path.insert(0,str(new));import detail_materials as detail
source=root/'asset-staging/player_fingers_detail_20260911/mac_output/iteration_10/bilateral_hands_finger_detail.blend'
before=hashlib.sha256(source.read_bytes()).hexdigest()
bpy.ops.wm.open_mainfile(filepath=str(source))
scene=bpy.data.scenes['Bilateral_Realistic_Review'];bpy.context.window.scene=scene
hands=collect(scene)
frames,owners,nails=detail._frames(hands['left'])
report={'source_unchanged':hashlib.sha256(source.read_bytes()).hexdigest()==before,'nodes':{},'dorsal':{d:list(frames[d,2][2]) for d in detail.DIGITS}}
materials={}
for name in ('Detailed_Skin','Detailed_Nail'):
 record=detail._procedural(bpy.data.materials[name],1.0);materials[name]=record
 report['nodes'][name]={'count':len(record['material'].node_tree.nodes),'links':len(record['material'].node_tree.links)}
surface,sr=detail._surface(scene,hands['left'],materials);report['surface']=sr
print('MATERIAL_PROBE '+json.dumps(report),flush=True)
