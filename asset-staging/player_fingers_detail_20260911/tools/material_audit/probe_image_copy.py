import bpy,json,sys,hashlib
import numpy as np
from pathlib import Path
from array import array
root=Path.cwd();out=root/'asset-staging/player_fingers_detail_20260911/tools/material_audit/image_copy_probe';out.mkdir(exist_ok=True)
sys.path.insert(0,str(out.parent.parent));from detail_materials import _source_pixels,_protected_non_skin_texels
bpy.ops.wm.open_mainfile(filepath=str(root/'asset-staging/player_hands_proportions_20260911/mac_output/iteration_01/bilateral_hands_proportions.blend'))
scene=bpy.data.scenes['Bilateral_Realistic_Review'];bpy.context.window.scene=scene
holder=scene.objects['LEFT_PreviewTranslationOnly']
def desc(root):
 result=[]
 for c in root.children:result.append(c);result.extend(desc(c))
 return result
objects=desc(holder);hand={'holder':holder,'objects':objects}
protected=_protected_non_skin_texels(hand,4096)
(out/'protected_texels.json').write_text(json.dumps(protected))
r={}
for mode in ('roughness','normal','basecolor'):
 src=bpy.data.materials['Detailed_Skin'].node_tree.nodes['Baked_'+mode].image
 original=_source_pixels(src);src_np=np.frombuffer(original,dtype=np.float32).reshape(-1,4)
 def compare(im):
  vals=_source_pixels(im);a=np.frombuffer(vals,dtype=np.float32).reshape(-1,4);delta=np.abs(a[protected,:3]-src_np[protected,:3]);return {'max_delta':float(delta.max()),'changed_channels':int((delta>1e-6).sum()),'all_rgb_pixel_sha256':hashlib.sha256(vals).hexdigest(),'protected_changed_rows':[{'index':protected[i],'source':src_np[protected[i]].tolist(),'after':a[protected[i]].tolist()}for i in np.nonzero(np.max(delta,axis=1)>1e-6)[0][:5]]}
 target=src.copy();row={'depth':src.depth,'is_float':src.is_float,'channels':src.channels,'colorspace':src.colorspace_settings.name,'source':src.source,'copy':compare(target)}
 target.colorspace_settings.name='sRGB' if mode=='basecolor' else 'Non-Color';row['after_colorspace']=compare(target)
 target.filepath_raw=str(out/(mode+'.png'));target.file_format='PNG';target.save();row['after_save']=compare(target);target.pack();row['after_pack']=compare(target)
 reload=bpy.data.images.load(str(out/(mode+'.png')),check_existing=False);reload.colorspace_settings.name=target.colorspace_settings.name;row['loaded_png']=compare(reload)
 row['original_buffer_unchanged']=compare(src)
 r[mode]=row
 print(mode,row,flush=True)
(out/'report.json').write_text(json.dumps(r,indent=2))
