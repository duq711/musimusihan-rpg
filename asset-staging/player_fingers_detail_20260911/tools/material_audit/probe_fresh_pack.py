import bpy,sys,json,hashlib
from pathlib import Path
root=Path.cwd();stage=root/'asset-staging/player_fingers_detail_20260911';out=stage/'tools/material_audit/fresh_pack_probe';out.mkdir(exist_ok=True)
sys.path.insert(0,str(stage/'tools'));from detail_materials import _load_fresh_packed,_source_pixels
bpy.ops.wm.read_factory_settings(use_empty=True)
material=bpy.data.materials.new('Persistence_Probe');material.use_nodes=True
mesh=bpy.data.meshes.new('Probe');mesh.from_pydata([(0,0,0),(1,0,0),(0,1,0)],[],[(0,1,2)]);obj=bpy.data.objects.new('PersistenceProbe',mesh);bpy.context.scene.collection.objects.link(obj);mesh.materials.append(material)
report={'method':'fresh load, pack, save minimal native scene, reopen and compare packed bytes plus decoded pixels','maps':{}}
for mode in ('basecolor','roughness','normal'):
 path=stage/'mac_output/iteration_02'/('realistic_hands_'+mode+'.png')
 image=_load_fresh_packed(path,'sRGB'if mode=='basecolor'else'Non-Color','Persistence_'+mode)
 tex=material.node_tree.nodes.new('ShaderNodeTexImage');tex.name=mode;tex.image=image
 report['maps'][mode]={'disk_png_sha256':hashlib.sha256(path.read_bytes()).hexdigest(),'before_packed_sha256':hashlib.sha256(image.packed_file.data).hexdigest(),'before_pixel_sha256':hashlib.sha256(_source_pixels(image)).hexdigest()}
bpy.context.preferences.filepaths.save_version=0;bpy.ops.wm.save_as_mainfile(filepath=str(out/'fresh_packed_images.blend'),check_existing=False)
bpy.ops.wm.open_mainfile(filepath=str(out/'fresh_packed_images.blend'))
for mode,row in report['maps'].items():
 image=bpy.data.materials['Persistence_Probe'].node_tree.nodes[mode].image
 row['reopened_packed_sha256']=hashlib.sha256(image.packed_file.data).hexdigest();row['reopened_pixel_sha256']=hashlib.sha256(_source_pixels(image)).hexdigest()
 assert row['disk_png_sha256']==row['before_packed_sha256']==row['reopened_packed_sha256']
 assert row['before_pixel_sha256']==row['reopened_pixel_sha256']
report['status']='passed';(out/'report.json').write_text(json.dumps(report,indent=2));print('FRESH_PACK_REOPEN_PASS',json.dumps(report),flush=True)
