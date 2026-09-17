import bpy,sys,json,hashlib
from pathlib import Path
from array import array
import numpy as np
root=Path.cwd();stage=root/'asset-staging/player_fingers_detail_20260911';folder=stage/'mac_output/iteration_02';blend=folder/'bilateral_hands_finger_detail.blend'
before=hashlib.sha256(blend.read_bytes()).hexdigest()
bpy.ops.wm.open_mainfile(filepath=str(blend))
report={'blend_sha256':before,'maps':{}}
for mode in ('basecolor','roughness','normal'):
 image=bpy.data.materials['Detailed_Skin'].node_tree.nodes['Baked_'+mode].image
 file=folder/('realistic_hands_'+mode+'.png');fresh=bpy.data.images.load(str(file),check_existing=False);fresh.colorspace_settings.name=image.colorspace_settings.name
 def pixels(im):
  a=array('f',[0.0])*len(im.pixels);im.pixels.foreach_get(a);return a
 old=pixels(image);new=pixels(fresh)
 a=np.frombuffer(old,dtype=np.float32).reshape(-1,4);b=np.frombuffer(new,dtype=np.float32).reshape(-1,4)
 diffs=0;maxdelta=0.0
 for s in range(0,len(a),262144):
  diff=np.abs(a[s:s+262144,:3]-b[s:s+262144,:3]);diffs+=int(np.count_nonzero(np.any(diff>1e-6,axis=1)));maxdelta=max(maxdelta,float(diff.max()))
 srcfile=root/'asset-staging/player_hands_proportions_20260911/mac_output/iteration_01'/file.name
 report['maps'][mode]={'image_name':image.name,'filepath':image.filepath,'packed_sha256':hashlib.sha256(image.packed_file.data).hexdigest()if image.packed_file else None,'new_disk_png_sha256':hashlib.sha256(file.read_bytes()).hexdigest(),'original_disk_png_sha256':hashlib.sha256(srcfile.read_bytes()).hexdigest(),'packed_decoded_pixel_sha256':hashlib.sha256(old).hexdigest(),'new_png_decoded_pixel_sha256':hashlib.sha256(new).hexdigest(),'changed_rgb_texels':diffs,'max_rgb_delta':maxdelta}
 print(mode,report['maps'][mode],flush=True)
 del old,new,a,b
report['input_blend_unchanged']=hashlib.sha256(blend.read_bytes()).hexdigest()==before
(stage/'tools/material_audit/packed_persistence_iteration02.json').write_text(json.dumps(report,indent=2))
