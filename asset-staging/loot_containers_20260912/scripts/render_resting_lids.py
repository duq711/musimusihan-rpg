from pathlib import Path
p=Path(__file__).resolve().parent/'render_and_validate.py'
exec(p.read_text().split("for rec in manifest['assets']:")[0])
rest=[]
for rec in manifest['assets']:
 if rec['opening_mode']!='lift':continue
 name=rec['variant'];bpy.ops.wm.read_factory_settings(use_empty=True);bpy.ops.import_scene.gltf(filepath=str(OUT/(name+'.glb')));bpy.context.view_layer.update();lid=bpy.data.objects['LidPivot'];body=[o for o in bpy.context.scene.objects if o.type=='MESH' and o.parent!=lid];lids=[o for o in bpy.context.scene.objects if o.type=='MESH' and o.parent==lid]
 blo,bhi=bounds(body);llo,lhi=bounds(lids);delta=max(.012,bhi.z-llo.z+.006);back=rec['dimensions_m'][2]*.4
 lid.location.z+=delta;lid.location.y-=back;bpy.context.view_layer.update()
 scene=studio();scene.render.filepath=str(QA/(name+'_runtime_open.png'));bpy.ops.render.render(write_still=True)
 rest.append({'asset':name,'rest_translation_godot':[0,round(delta,6),round(back,6)],'body_rim_height_m':round(bhi.z,6),'lid_original_bottom_m':round(llo.z,6),'clearance_m':.006,'note':'Raised over rim, translated backward, then supported across the rear rim; animation peak lift remains .32m.'})
 print('REST_DONE',rest[-1],flush=True)
(BASE/'lid_rest_poses.json').write_text(json.dumps(rest,indent=2))
