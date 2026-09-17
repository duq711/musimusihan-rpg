"""Two-stage native Blender revision: review geometry before baking actual PBR maps."""
import argparse,hashlib,json,sys,math,platform,subprocess,shutil
from pathlib import Path
from datetime import datetime,timezone
import bpy
from mathutils import Vector,Quaternion
sys.path.insert(0,str(Path(__file__).resolve().parent))
from reference_export import activate,descendants,export_native,bone_signature

DIGITS=('thumb','index','middle','ring','little')
def digest(p):return hashlib.sha256(Path(p).read_bytes()).hexdigest()
def collect(scene):
    result={}
    for side in ('left','right'):
        holder=scene.objects[side.upper()+'_PreviewTranslationOnly']
        objects=descendants(holder)
        rig=next(o for o in objects if o.type=='ARMATURE')
        skin=next(o for o in objects if o.type=='MESH' and 'Anatomical' in o.name)
        nails=[o for o in objects if o.type=='MESH' and 'Nail_' in o.name]
        result[side]=(holder,objects,rig,skin,nails)
    return result

def neutral(hands):
    for holder,objects,rig,skin,nails in hands.values():
        for bone in rig.pose.bones:bone.rotation_mode='XYZ';bone.rotation_euler=(0,0,0)
        for key in skin.data.shape_keys.key_blocks:key.value=0
    bpy.context.view_layer.update()

def configure(scene):
    scene.render.engine='CYCLES';scene.cycles.samples=24;scene.cycles.use_denoising=True
    scene.render.resolution_percentage=100
    scene.view_settings.view_transform='AgX';scene.view_settings.exposure=0
    scene.render.image_settings.file_format='PNG';scene.render.film_transparent=False
    if scene.world and scene.world.use_nodes:
        bg=next((n for n in scene.world.node_tree.nodes if n.type=='BACKGROUND'),None)
        if bg:bg.inputs['Color'].default_value=(.8,.8,.8,1);bg.inputs['Strength'].default_value=.45
    for obj in scene.objects:
        if obj.type=='LIGHT' and obj.data.type=='AREA':
            obj.data.color=(1,1,1)

def render_views(scene,hands,output,clay=False):
    configure(scene);neutral(hands);camera=scene.camera
    holder,objects,rig,skin,nails=hands['left']
    visibility={o.name:o.hide_render for o in scene.objects}
    for o in hands['right'][1]:o.hide_render=True
    for o in objects:
        if o.type=='MESH' and any(n in o.name for n in ('UpperArm','Forearm')):o.hide_render=True
    material=None
    if clay:
        material=bpy.data.materials.new('Reference_Clay_Inspection');material.diffuse_color=(.55,.55,.55,1)
        material.use_nodes=True;p=material.node_tree.nodes.get('Principled BSDF')
        p.inputs['Base Color'].default_value=(.55,.55,.55,1);p.inputs['Roughness'].default_value=.68
        scene.view_layers[0].material_override=material
    output.mkdir(parents=True,exist_ok=True);report={}
    views=[('dorsum',(0,.068,0),(0,0,1),.31),('palm',(0,.068,0),(0,0,-1),.31),
        ('side',(0,.064,0),(1,.05,.18),.31)]
    if not clay:views += [('dorsum_closeup',(0,.095,.005),(0,-.1,1),.215),('palm_closeup',(0,.077,0),(0,.02,-1),.235)]
    for name,center,direction,scale in views:
        world=holder.matrix_world@Vector(center);direction=Vector(direction).normalized()
        camera.location=world+direction*1.2;rotation=(world-camera.location).to_track_quat('-Z','Y')
        if direction.z<-.5 and (rotation@Vector((0,1,0))).y<0:rotation=rotation@Quaternion((0,0,1),math.pi)
        camera.rotation_euler=rotation.to_euler();camera.data.ortho_scale=.35 if name=='side' else scale
        scene.render.resolution_x=1400 if name=='side' else 1200;scene.render.resolution_y=1100 if name=='side' else 1400;scene.cycles.samples=12 if clay else 32
        path=output/(name+'.png');scene.render.filepath=str(path)
        bpy.ops.render.render(write_still=True)
        report[name]={'image':str(path.name),'sha256':digest(path),'center_native':center,'direction':list(direction),'ortho_scale':scale,'clay_override':clay,'actual_blender_render':True}
        print('REFERENCE_RENDER',name,flush=True)
    scene.view_layers[0].material_override=None
    for o in scene.objects:
        if o.name in visibility:o.hide_render=visibility[o.name]
    if material:bpy.data.materials.remove(material)
    return report

def presentation(scene,hands):
    neutral(hands);configure(scene)
    camera=scene.camera;center=Vector((0,.01,0));camera.location=center+Vector((0,0,1.2))
    camera.rotation_euler=(center-camera.location).to_track_quat('-Z','Y').to_euler();camera.data.ortho_scale=.67
    scene.render.resolution_x=1600;scene.render.resolution_y=1300;scene.cycles.samples=24
    for screen in bpy.data.screens:
        for area in screen.areas:
            if area.type=='VIEW_3D':
                space=area.spaces.active;space.shading.type='MATERIAL';space.shading.use_scene_world=True;space.shading.use_scene_lights=True
                space.overlay.show_overlays=False;space.region_3d.view_perspective='CAMERA'

def render_reference_pair(source_scene,hands,output):
    """Show the same actual right hand from both sides, as in the supplied photograph."""
    scene=bpy.data.scenes.new('Photo_Reference_Palm_And_Dorsum')
    scene.render.engine='CYCLES';scene.cycles.samples=32;scene.cycles.use_denoising=True
    scene.view_settings.view_transform='AgX';scene.render.resolution_x=1600;scene.render.resolution_y=1150
    scene.render.resolution_percentage=100;scene.render.image_settings.file_format='PNG'
    world=bpy.data.worlds.new('Reference_White_Studio');world.use_nodes=True;scene.world=world
    nodes=world.node_tree.nodes;nodes.clear();links=world.node_tree.links
    out=nodes.new('ShaderNodeOutputWorld');mix=nodes.new('ShaderNodeMixShader');ray=nodes.new('ShaderNodeLightPath')
    ambient=nodes.new('ShaderNodeBackground');ambient.inputs['Color'].default_value=(1,1,1,1);ambient.inputs['Strength'].default_value=.12
    white=nodes.new('ShaderNodeBackground');white.inputs['Color'].default_value=(1,1,1,1);white.inputs['Strength'].default_value=20
    links.new(ray.outputs['Is Camera Ray'],mix.inputs[0]);links.new(ambient.outputs[0],mix.inputs[1]);links.new(white.outputs[0],mix.inputs[2]);links.new(mix.outputs[0],out.inputs[0])
    holder,objects,rig,skin,nails=hands['right']
    for label,x,turn in [('Palm',-.112,math.pi),('Dorsum',.112,0.)]:
        originals=[holder,*objects];copies={o:o.copy() for o in originals}
        for original,copy in copies.items():
            copy.name=label+'_'+original.name;scene.collection.objects.link(copy)
            copy.parent=copies.get(original.parent,original.parent)
            copy.matrix_basis=original.matrix_basis.copy()
            if copy.type=='ARMATURE':copy.data=original.data.copy()
            for modifier in copy.modifiers:
                if modifier.type=='ARMATURE' and modifier.object in copies:modifier.object=copies[modifier.object]
            if copy.type=='MESH':copy.hide_render=any(n in original.name for n in ('UpperArm','Forearm'))
        root=copies[holder];root.location=(x,0,0);root.rotation_euler=(0,turn,0)
    camera_data=bpy.data.cameras.new('Photo_Reference_Camera');camera=bpy.data.objects.new(camera_data.name,camera_data)
    scene.collection.objects.link(camera);scene.camera=camera;camera_data.type='ORTHO';camera_data.ortho_scale=.46
    center=Vector((0,.095,0));camera.location=center+Vector((0,0,1.2));camera.rotation_euler=(center-camera.location).to_track_quat('-Z','Y').to_euler()
    for name,location,power,size in [('Key',(-.35,.32,.60),13.,.42),('Fill',(.45,-.10,.45),3.8,.65),('Top',(.10,.45,.30),2.2,.40)]:
        data=bpy.data.lights.new('Reference_'+name,'AREA');data.energy=power;data.shape='DISK';data.size=size
        obj=bpy.data.objects.new(data.name,data);obj.location=location;obj.rotation_euler=(center-obj.location).to_track_quat('-Z','Y').to_euler();scene.collection.objects.link(obj)
    activate(scene);path=output/'reference_palm_and_dorsum.png';scene.render.filepath=str(path)
    bpy.ops.render.render(write_still=True);activate(source_scene)
    return {'image':path.name,'sha256':digest(path),'actual_blender_render':True,'source':'Same right-hand model shown from palm and dorsal sides, matching the photographic comparison; both game hand assets are supplied.','lighting':'Dedicated neutral white studio; not game lighting.'}

def clean_delivery_scene(scene):
    """Keep the new editable asset and its photo review; older source files stay untouched."""
    removed=[]
    for other in list(bpy.data.scenes):
        if other!=scene and other.name!='Photo_Reference_Palm_And_Dorsum':
            removed.append(other.name);bpy.data.scenes.remove(other)
    used={obj for s in bpy.data.scenes for obj in s.objects}
    for obj in list(bpy.data.objects):
        if obj not in used:bpy.data.objects.remove(obj,do_unlink=True)
    bpy.ops.outliner.orphans_purge(do_local_ids=True,do_linked_ids=True,do_recursive=True)
    reference=Path(__file__).resolve().parents[1]/'reference/user_hand_photo.png'
    image=bpy.data.images.load(str(reference),check_existing=True);image.pack()
    guide=bpy.data.objects.new('User_Photo_Reference',None);guide.empty_display_type='IMAGE';guide.data=image
    guide.location=(.65,.07,0);guide.empty_display_size=.45;guide.hide_render=True;scene.collection.objects.link(guide)
    return {'kept_scenes':[s.name for s in bpy.data.scenes],'removed_old_scenes_from_new_copy_only':removed,'reference_image_packed':True}

def main():
    parser=argparse.ArgumentParser();parser.add_argument('--phase',choices=['geometry','material','lookdev','render'],required=True)
    parser.add_argument('--source',type=Path,required=True);parser.add_argument('--output',type=Path,required=True)
    parser.add_argument('--padding-python',default='/Users/duq711gmail.com/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/bin/python3')
    args=parser.parse_args(sys.argv[sys.argv.index('--')+1:]);source=args.source.resolve();output=args.output.resolve()
    assert bpy.app.background and source.is_file();output.mkdir(exist_ok=True,parents=True)
    source_sha=digest(source);bpy.ops.wm.open_mainfile(filepath=str(source))
    scene=next(s for s in bpy.data.scenes if s.name in ('Bilateral_Realistic_Review','Bilateral_Reference_Review'))
    scene.name='Bilateral_Reference_Review';activate(scene);hands=collect(scene);neutral(hands)
    report={'status':'building','phase':args.phase,'source':str(source),'source_sha256':source_sha,
        'created_utc':datetime.now(timezone.utc).isoformat(),'blender':bpy.app.version_string,'host':platform.platform(),'hands':{}}
    if args.phase=='geometry':
        from reference_geometry import refine_hand
        for side,(holder,objects,rig,skin,nails) in hands.items():
            bones_before=bone_signature(rig)
            report['hands'][side]=refine_hand(skin,rig,holder,nails)
            report['hands'][side]['bones_before']=bones_before;report['hands'][side]['bones_after']=bone_signature(rig)
            for obj in objects:
                if obj.type=='MESH' and 'WristCuff' in obj.name:
                    obj.data.materials.clear();obj.data.materials.append(bpy.data.materials['Detailed_Skin'])
                    for polygon in obj.data.polygons:polygon.material_index=0
        hands=collect(scene);presentation(scene,hands)
        target=output/'bilateral_hands_reference_geometry.blend'
        bpy.ops.wm.save_as_mainfile(filepath=str(target));report['geometry_blend_sha256']=digest(target)
        report['renders']=render_views(scene,hands,output/'clay',True)
    elif args.phase in ('material','lookdev'):
        from reference_materials import prepare_fields,prepare_part,procedural_materials
        from reference_bake import unwrap,bake
        meshes=[]
        for side,(holder,objects,rig,skin,nails) in hands.items():
            report['hands'][side]={'fields':prepare_fields(skin,rig,holder,nails)}
            for obj in objects:
                if obj.type!='MESH':continue
                meshes.append(obj)
                if obj!=skin:prepare_part(obj,rig,holder)
        if args.phase=='lookdev':
            procedural_materials(scene)
            report['reference_pair']=render_reference_pair(scene,hands,output)
            report['status']='procedural_lookdev_only_not_baked_game_asset'
            assert digest(source)==source_sha
            (output/'lookdev_report.json').write_text(json.dumps(report,indent=2,ensure_ascii=False))
            print('REFERENCE_LOOKDEV_COMPLETE',flush=True);return
        report['uv']=unwrap(meshes);print('REFERENCE_UV_READY',flush=True)
        report['textures']=bake(scene,meshes,output)
        checkpoint=output/'checkpoint';checkpoint.mkdir(exist_ok=True)
        bpy.ops.wm.save_as_mainfile(filepath=str(checkpoint/'baked.blend'))
        (checkpoint/'bake_report.json').write_text(json.dumps(report,indent=2,ensure_ascii=False))
        raw=output/'unfilled_atlas';raw.mkdir(exist_ok=True)
        for channel in ('basecolor','normal','roughness'):
            name=f'reference_hands_{channel}.png';shutil.move(str(output/name),str(raw/name))
        subprocess.run([args.padding_python,str(Path(__file__).with_name('pad_reference_textures.py')),'--source',str(raw),'--output',str(output)],check=True)
        for channel in ('basecolor','normal','roughness'):
            name=f'reference_hands_{channel}';image=bpy.data.images[name]
            if image.packed_file:image.unpack(method='REMOVE')
            image.filepath_raw=str(output/(name+'.png'));image.reload();image.pack()
            assert hashlib.sha256(image.packed_file.data).hexdigest()==digest(output/(name+'.png'))
        report['texture_padding']='atlas_padding_report.json'
        for side,(holder,objects,rig,skin,nails) in hands.items():
            report['hands'][side]['export']=export_native(scene,objects,holder,output/f'{side}_hand_reference.glb')
        presentation(scene,hands);target=output/'bilateral_hands_reference.blend'
        bpy.ops.wm.save_as_mainfile(filepath=str(target));report['blend_sha256']=digest(target)
        report['renders']=render_views(scene,hands,output,False)
        report['reference_pair']=render_reference_pair(scene,hands,output)
        report['delivery_scene']=clean_delivery_scene(scene)
        presentation(scene,hands);bpy.context.preferences.filepaths.save_version=0
        bpy.ops.wm.save_as_mainfile(filepath=str(target));report['blend_sha256']=digest(target)
    else:report['renders']=render_views(scene,hands,output,False)
    assert digest(source)==source_sha
    report['status']='built_pending_visual_review'
    (output/(args.phase+'_report.json')).write_text(json.dumps(report,indent=2,ensure_ascii=False))
    print('REFERENCE_PHASE_COMPLETE',args.phase,flush=True)

if __name__=='__main__':main()
