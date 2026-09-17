"""Read-only OBJ import/PCA and three actual grey source-shape views.

Saves a new inspection blend only. Original OBJ/ZTL bytes remain unchanged.
Raw OBJ axes and units are preserved by forward Y/up Z import. The grey material
is explicitly diagnostic because the supplied OBJ has no material declaration.
"""
import argparse,hashlib,json,sys
from pathlib import Path
import bpy
import numpy as np
from mathutils import Matrix,Vector

def sha(p):return hashlib.sha256(Path(p).read_bytes()).hexdigest()
def vec(v):return [float(x) for x in v]
p=argparse.ArgumentParser();p.add_argument('--source',type=Path,required=True);p.add_argument('--stage',type=Path,required=True);p.add_argument('--samples',type=int,default=16);a=p.parse_args(sys.argv[sys.argv.index('--')+1:])
assert bpy.app.background
src=a.source.resolve();stage=a.stage.resolve();review=stage/'review';review.mkdir(exist_ok=True,parents=True)
assert not (stage/'input/source_inspection.blend').exists()
original=sha(src);manifest=json.loads((stage/'input/source_manifest.json').read_text())
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.wm.obj_import(filepath=str(src),forward_axis='Y',up_axis='Z',global_scale=1.0,use_split_objects=False,use_split_groups=False)
scene=bpy.context.scene;scene.name='Supplied_Hand_Source_Inspection'
meshes=[o for o in scene.objects if o.type=='MESH'];allpoints=[];items=[]
for ob in meshes:
 m=ob.data;coords=np.empty(len(m.vertices)*3,dtype=np.float32);m.vertices.foreach_get('co',coords);coords=coords.reshape(-1,3)
 mat=np.array(ob.matrix_world);world=coords@mat[:3,:3].T+mat[:3,3];allpoints.append(world)
 items.append({'object':ob.name,'vertices':len(m.vertices),'edges':len(m.edges),'polygons':len(m.polygons),'triangles':sum(len(x.vertices)-2 for x in m.polygons),'uv_layers':[x.name for x in m.uv_layers],'color_attributes':[x.name for x in m.color_attributes],'source_materials':[x.name if x else None for x in m.materials],'world_bounds_min':world.min(axis=0).tolist(),'world_bounds_max':world.max(axis=0).tolist(),'matrix_world':[list(x) for x in ob.matrix_world]})
 for face in m.polygons:face.use_smooth=True
 material=bpy.data.materials.new('Source_Inspection_Constant_Grey');material.use_nodes=True
 bsdf=material.node_tree.nodes.get('Principled BSDF');bsdf.inputs['Base Color'].default_value=(.27,.27,.27,1);bsdf.inputs['Roughness'].default_value=.68
 m.materials.clear();m.materials.append(material)
 for poly in m.polygons:poly.material_index=0
points=np.concatenate(allpoints);center=points.mean(axis=0);eigval,eigvec=np.linalg.eigh(np.cov(points[::10].T));up=eigvec[:,2];outward=eigvec[:,0]
if up[1]<0:up=-up
if outward[2]<0:outward=-outward
outward-=up*np.dot(up,outward);outward/=np.linalg.norm(outward);right=np.cross(up,outward);right/=np.linalg.norm(right)
projections=np.stack([(points-center)@axis for axis in [right,up,outward]],axis=1)
mid=(projections.min(axis=0)+projections.max(axis=0))*.5;center=center+right*mid[0]+up*mid[1]+outward*mid[2]
length=float(projections[:,1].max()-projections[:,1].min());width=float(projections[:,0].max()-projections[:,0].min());depth=float(projections[:,2].max()-projections[:,2].min())
np.savez_compressed(stage/'input/source_world_points.npz',positions=points)
scene.render.engine='CYCLES';scene.cycles.device='CPU';scene.cycles.samples=a.samples;scene.cycles.use_denoising=True;scene.render.threads_mode='FIXED';scene.render.threads=2;scene.render.resolution_x=1000;scene.render.resolution_y=1200;scene.render.resolution_percentage=100;scene.render.image_settings.file_format='PNG';scene.render.image_settings.color_mode='RGB';scene.view_settings.view_transform='AgX';scene.view_settings.look='AgX - Medium High Contrast'
world=bpy.data.worlds.new('Inspection_Charcoal');world.use_nodes=True;world.node_tree.nodes['Background'].inputs['Color'].default_value=(.035,.035,.035,1);world.node_tree.nodes['Background'].inputs['Strength'].default_value=.5;scene.world=world
camera_data=bpy.data.cameras.new('Inspection_Camera');camera_data.type='ORTHO';camera_data.clip_start=length*.0001;camera_data.clip_end=length*20;camera=bpy.data.objects.new('Inspection_Camera',camera_data);scene.collection.objects.link(camera);scene.camera=camera
report={'status':'rendering','source':str(src),'source_sha256':original,'original_inputs':manifest,'blender_version':bpy.app.version_string,'objects':items,'import_axis_mapping':'OBJ coordinates unchanged: forward Y / up Z / scale 1','units':'Unspecified OBJ units; no anatomical size assumed','pca_eigenvalues':eigval.tolist(),'pca_up_axis':up.tolist(),'pca_positive_normal_axis':outward.tolist(),'pca_right_axis':right.tolist(),'pca_center':center.tolist(),'pca_extent':{'width':width,'length':length,'depth':depth},'render_material':'Diagnostic constant grey; source has no authored material/UVs','renders':{}}
for name,direction in [('positive_normal',outward),('negative_normal',-outward),('side',right)]:
 direction=Vector(direction);up_v=Vector(up);center_v=Vector(center);right_v=up_v.cross(direction).normalized();rotation=Matrix((right_v,up_v,direction)).transposed()
 camera.matrix_world=rotation.to_4x4();camera.location=center_v+direction*length*3;camera_data.ortho_scale=max(length,(depth if name=='side' else width)/(.833333333))*1.12
 lights=[]
 for label,offset,power,size in [('Key',(-.7,.7,1.0),800,.9),('Fill',(.7,.05,.8),300,1.2)]:
  data=bpy.data.lights.new('Inspection_'+label,'AREA');data.energy=power*length*length;data.shape='DISK';data.size=size*length
  ob=bpy.data.objects.new(data.name,data);scene.collection.objects.link(ob);ob.location=center_v+(right_v*offset[0]+up_v*offset[1]+direction*offset[2])*length;ob.rotation_euler=(center_v-ob.location).to_track_quat('-Z','Y').to_euler();lights.append(ob)
 path=review/('source_'+name+'.png');scene.render.filepath=str(path);bpy.ops.render.render(write_still=True)
 report['renders'][name]={'file':str(path.relative_to(stage)),'sha256':sha(path),'actual_supplied_geometry':True,'view_direction_world':vec(direction),'camera_location':vec(camera.location),'camera_up':vec(up_v),'ortho_scale':camera_data.ortho_scale}
 for ob in lights:bpy.data.objects.remove(ob,do_unlink=True)
 (stage/'input/source_inspection.json').write_text(json.dumps(report,indent=2))
# Store the actual imported source with diagnostic material/camera, never a retopo.
bpy.context.preferences.filepaths.save_version=0;blend=stage/'input/source_inspection.blend';bpy.ops.wm.save_as_mainfile(filepath=str(blend),check_existing=False)
assert sha(src)==original
for item in manifest.values():assert sha(item['source'])==item['sha256'] and sha(item['preserved_copy'])==item['sha256']
report.update(status='complete',source_inspection_blend=str(blend),source_inspection_blend_sha256=sha(blend),original_obj_and_ztl_unchanged=True)
(stage/'input/source_inspection.json').write_text(json.dumps(report,indent=2));print('SUPPLIED_HAND_INSPECTION_COMPLETE',json.dumps({'objects':items,'pca_extent':report['pca_extent'],'pca_up_axis':up.tolist(),'pca_positive_normal_axis':outward.tolist()}),flush=True)
