import bpy,json,math
import numpy as np
from pathlib import Path
from array import array
bpy.ops.wm.read_factory_settings(use_empty=True)
scene=bpy.context.scene;scene.render.engine='CYCLES';scene.cycles.device='CPU';scene.cycles.samples=1
scene.render.bake.use_selected_to_active=False
mesh=bpy.data.meshes.new('PartialSkinTriangle');mesh.from_pydata([(0,0,0),(1,0,0),(0,1,0)],[],[(0,1,2)]);mesh.update()
uv=mesh.uv_layers.new(name='RealismUV')
for l,v in zip(uv.data,((.1,.1),(.9,.1),(.1,.9))):l.uv=v
obj=bpy.data.objects.new('NativeBakeMarginProbe',mesh);scene.collection.objects.link(obj);obj.select_set(True);bpy.context.view_layer.objects.active=obj
m=bpy.data.materials.new('ProbeSkin');m.use_nodes=True;n=m.node_tree.nodes;n.clear();out=n.new('ShaderNodeOutputMaterial');emit=n.new('ShaderNodeEmission');emit.inputs['Color'].default_value=(.4,.4,.4,1);m.node_tree.links.new(emit.outputs[0],out.inputs['Surface']);tex=n.new('ShaderNodeTexImage');n.active=tex;mesh.materials.append(m)
report={}
for margin in (0,2):
 image=bpy.data.images.new('NativeMargin'+str(margin),width=128,height=128,alpha=False);image.colorspace_settings.name='Non-Color';image.generated_color=(.7,.7,.7,1);tex.image=image
 before=np.array(image.pixels[:],dtype=np.float32).reshape(128,128,4)
 bpy.ops.object.bake(type='EMIT',use_clear=False,margin=margin)
 after=np.array(image.pixels[:],dtype=np.float32).reshape(128,128,4)
 yy,xx=np.mgrid[:128,:128];outside=(xx+.5+yy+.5)>128
 # A second material is conceptually on the other side of this shared diagonal.
 distances=(xx+.5+yy+.5-128)/math.sqrt(2)
 changed=np.max(np.abs(after[:,:,:3]-before[:,:,:3]),axis=2)>1e-6
 crossing=changed&outside
 report[str(margin)]={'changed_outside_triangle':int(crossing.sum()),'maximum_crossing_distance_px':float(distances[crossing].max()) if crossing.any() else 0.0,'preserved_pixels_more_than_1px_outside':bool(not np.any(changed & (distances>1.0)))}
print('NATIVE_MARGIN_PROBE',json.dumps(report),flush=True)
Path('asset-staging/player_fingers_detail_20260911/tools/material_audit/image_copy_probe/margin_probe.json').write_text(json.dumps(report,indent=2))
assert report['0']['preserved_pixels_more_than_1px_outside']
assert report['2']['changed_outside_triangle']>report['0']['changed_outside_triangle']
