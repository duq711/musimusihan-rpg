"""Resize the user's original gloved hand; preserve its authored surface assets."""
import argparse,hashlib,json,sys,shutil
from pathlib import Path
import bpy
from mathutils import Vector
sys.path.insert(0,str(Path(__file__).resolve().parent))
from proportion_math import ProportionMap,digit_weights,DIGITS,body
from reference_export import descendants,export_native,bone_signature

def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()

def payload(mesh):
    return {'vertices':len(mesh.vertices),'faces':[list(p.vertices) for p in mesh.polygons],
        'materials':[m.name for m in mesh.materials], 'face_material':[p.material_index for p in mesh.polygons],
        'weights':[[(g.group,g.weight) for g in v.groups] for v in mesh.vertices],
        'uv':{u.name:[list(x.uv) for x in u.data] for u in mesh.uv_layers}}

def main():
    parser=argparse.ArgumentParser();parser.add_argument('--source-dir',type=Path,required=True);parser.add_argument('--output-dir',type=Path,required=True)
    args=parser.parse_args(sys.argv[sys.argv.index('--')+1:]);source=args.source_dir.resolve();out=args.output_dir.resolve()
    assert bpy.app.background and not out.exists();out.mkdir(parents=True)
    original=source/'bilateral_hands_realistic.blend';source_sha=sha(original)
    bpy.ops.wm.open_mainfile(filepath=str(original));scene=bpy.data.scenes['Bilateral_Realistic_Review'];bpy.context.window.scene=scene
    report={'status':'built_pending_review','source':str(original),'source_sha256':source_sha,'scope':'Only proportions. All original glove, skin, nail, trim, UV and PBR image content retained.',
        'parameters':{'palm_width':.82,'wrist_width':.75,'palm_and_wrist_depth':.85,'palm_length':1.,'arm_identity_native_y_le':-.075,'palmar_contact_native':[0,.0825,-.019]},'hands':{},'renders':{}}
    hands={}
    for side in ('left','right'):
        holder=scene.objects[side.upper()+'_PreviewTranslationOnly'];objects=descendants(holder)
        rig=next(o for o in objects if o.type=='ARMATURE');skin=next(o for o in objects if o.type=='MESH' and 'Anatomical' in o.name)
        mapping=ProportionMap(holder,rig,skin);before_bones=bone_signature(rig);rows=[]
        for obj in objects:
            if obj.type!='MESH':continue
            mesh=obj.data;before=payload(mesh);native=holder.matrix_world.inverted()@obj.matrix_world;local=native.inverted()
            points=[native@v.co for v in mesh.vertices];weights=[digit_weights(obj,v) for v in mesh.vertices]
            old_normals=[x.vector.copy() for x in mesh.corner_normals]
            normal_to_native=native.to_3x3().inverted().transposed();normal_to_local=native.to_3x3().transposed()
            changed=0;minimum=1.;inverse_j=[]
            for p,w in zip(points,weights):
                J=mapping.jacobian(p,w);minimum=min(minimum,J.determinant());inverse_j.append(J.inverted().transposed())
            assert minimum>0.01,(obj.name,minimum)
            new_points=[local@mapping.warp(p,w) for p,w in zip(points,weights)]
            if mesh.shape_keys:
                for key in mesh.shape_keys.key_blocks:
                    for i,v in enumerate(key.data):v.co=local@mapping.warp(native@v.co,weights[i])
                    key.value=0.
            for i,v in enumerate(mesh.vertices):
                if (new_points[i]-v.co).length>1e-8:changed+=1
                v.co=new_points[i]
            mesh.update()
            transformed=[]
            for loop,n in zip(mesh.loops,old_normals):
                transformed.append((normal_to_local@inverse_j[loop.vertex_index]@normal_to_native@n).normalized())
            mesh.normals_split_custom_set(transformed)
            assert payload(mesh)==before,(obj.name,'Non-proportion payload changed')
            rows.append({'object':obj.name,'vertices':len(points),'changed_vertices':changed,'minimum_local_map_jacobian':minimum,'unchanged_topology_uv_material_assignments_weights':True})
        # New proportioned rest frames; no object scale or global contact shift.
        bpy.ops.object.select_all(action='DESELECT');rig.select_set(True);bpy.context.view_layer.objects.active=rig
        native=holder.matrix_world.inverted()@rig.matrix_world;local=native.inverted()
        bpy.ops.object.mode_set(mode='EDIT')
        for bone in rig.data.edit_bones:
            if bone.name=='wrist':continue
            digit=next(d for d in DIGITS if bone.name.startswith(d))
            head,tail=bone.head.copy(),bone.tail.copy();roll_axis=bone.z_axis.copy()
            bone.head=local@mapping.warp(native@head,{digit:1.})
            bone.tail=local@mapping.warp(native@tail,{digit:1.})
            bone.align_roll(roll_axis)
        bpy.ops.object.mode_set(mode='OBJECT')
        for pose in rig.pose.bones:pose.matrix_basis.identity()
        bpy.context.view_layer.update()
        after_bones=bone_signature(rig);assert before_bones['wrist']==after_bones['wrist']
        assert (body(Vector((0,.0825,-.019)))-Vector((0,.0825,-.019))).length<1e-8
        hands[side]=(holder,objects,rig,skin)
        report['hands'][side]={'dimensions':mapping.dimensions,'meshes':rows,'rest_before':before_bones,'rest_after':after_bones,'wrist_rest_exact':True}
    for side,(holder,objects,rig,skin) in hands.items():
        report['hands'][side]['export']=export_native(scene,objects,holder,out/f'{side}_hand_proportions.glb')
    for name in ('realistic_hands_basecolor.png','realistic_hands_normal.png','realistic_hands_roughness.png'):
        shutil.copy2(source/name,out/name);assert sha(source/name)==sha(out/name)
    report['textures_unchanged_sha256']={p.name:sha(p) for p in out.glob('*.png')}
    visibility={o.name:o.hide_render for o in scene.objects};camera=scene.camera
    for obj in hands['right'][1]:obj.hide_render=True
    configurations=[('preview_finger_dorsum',(0,.135,.005),(0,-.08,1),.205,1400,1200),
        ('hand_dorsum',(0,.075,0),(0,0,1),.295,1400,1200),('hand_palm',(0,.075,0),(0,0,-1),.295,1400,1200)]
    for name,center,direction,scale,width,height in configurations:
        center=hands['left'][0].matrix_world@Vector(center);camera.location=center+Vector(direction).normalized()*1.2
        camera.rotation_euler=(center-camera.location).to_track_quat('-Z','Y').to_euler();camera.data.ortho_scale=scale
        scene.render.resolution_x=width;scene.render.resolution_y=height;scene.render.resolution_percentage=100
        scene.cycles.samples=40 if name=='preview_finger_dorsum' else 24;scene.cycles.use_denoising=True
        scene.render.filepath=str(out/(name+'.png'));bpy.ops.render.render(write_still=True)
        report['renders'][name]={'file':name+'.png','sha256':sha(out/(name+'.png')),'actual_blender_render':True,'samples':scene.cycles.samples,'same_original_lights_and_materials':True}
        print('PROPORTION_RENDER',name,flush=True)
    for obj in scene.objects:obj.hide_render=visibility[obj.name]
    center=Vector((0,-.035,0));camera.location=center+Vector((0,0,1.2));camera.rotation_euler=(center-camera.location).to_track_quat('-Z','Y').to_euler();camera.data.ortho_scale=.68
    scene.render.resolution_x=1600;scene.render.resolution_y=1300;scene.cycles.samples=24
    bpy.context.preferences.filepaths.save_version=0
    path=out/'bilateral_hands_proportions.blend';bpy.ops.wm.save_as_mainfile(filepath=str(path),check_existing=False,relative_remap=False)
    report['blend_sha256']=sha(path);assert sha(original)==source_sha
    (out/'build_report.json').write_text(json.dumps(report,indent=2))
    print('PROPORTIONS_BUILD_COMPLETE',flush=True)

if __name__=='__main__':main()
