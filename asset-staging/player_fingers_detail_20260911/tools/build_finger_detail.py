"""Build a separate finger-detail candidate from the approved gloved proportions."""
import argparse,hashlib,json,sys,shutil
from pathlib import Path
import bpy
from mathutils import Vector
sys.path.insert(0,str(Path(__file__).resolve().parent))
from reference_export import descendants,export_native,bone_signature
from finger_sculpt import sculpt_hand,fit_nail_surfaces,reposition_thumb_nail

def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()

def collect(scene):
    hands={}
    for side in ('left','right'):
        holder=scene.objects[side.upper()+'_PreviewTranslationOnly'];objects=descendants(holder)
        hands[side]={'holder':holder,'objects':objects,'rig':next(o for o in objects if o.type=='ARMATURE'),
                     'skin':next(o for o in objects if o.type=='MESH' and 'Anatomical' in o.name)}
    return hands

def frozen(hand):
    result={}
    for obj in hand['objects']:
        entry={'basis':[list(r) for r in obj.matrix_basis],'parent':obj.parent.name if obj.parent else None,'properties':dict(obj.items())}
        if obj.type=='ARMATURE':entry['bones']=bone_signature(obj)
        if obj.type=='MESH':
            mesh=obj.data
            entry.update({'polygons':[(list(p.vertices),p.material_index) for p in mesh.polygons],
              'vertex_groups':[g.name for g in obj.vertex_groups],'weights':[[(g.group,g.weight) for g in v.groups] for v in mesh.vertices],
              'uv':{u.name:[list(v.uv) for v in u.data] for u in mesh.uv_layers}})
            if obj!=hand['skin'] and 'Nail_' not in obj.name:entry['points']=[list(v.co) for v in mesh.vertices]
        result[obj.name]=entry
    return hashlib.sha256(json.dumps(result,sort_keys=True,default=str).encode()).hexdigest()

def main():
    p=argparse.ArgumentParser();p.add_argument('--source',type=Path,required=True);p.add_argument('--output-dir',type=Path,required=True)
    p.add_argument('--sculpt-strength',type=float,default=1.);p.add_argument('--material-strength',type=float,default=1.)
    p.add_argument('--skip-bake',action='store_true');p.add_argument('--samples',type=int,default=32);p.add_argument('--bake-samples',type=int,default=4)
    a=p.parse_args(sys.argv[sys.argv.index('--')+1:]);source=a.source.resolve();out=a.output_dir.resolve()
    assert bpy.app.background and not out.exists();out.mkdir(parents=True);source_sha=sha(source)
    bpy.ops.wm.open_mainfile(filepath=str(source));scene=bpy.data.scenes['Bilateral_Realistic_Review'];bpy.context.window.scene=scene
    hands=collect(scene);before={s:frozen(h) for s,h in hands.items()}
    report={'status':'candidate_pending_independent_and_visual_review','source':str(source),'source_sha256':source_sha,
       'reference_strategy':'One digit and one face per image, ten separate AI references; no composite reference matching.',
       'hands':{s:sculpt_hand(h,a.sculpt_strength) for s,h in hands.items()},'renders':{}}
    assert all(frozen(h)==before[s] for s,h in hands.items()),'Protected non-skin geometry or topology/UV/rig changed'
    for s,h in hands.items():
        report['hands'][s]['thumb_nail_placement']=reposition_thumb_nail(h)
        report['hands'][s]['nail_surface_fit']=fit_nail_surfaces(h)
    if a.skip_bake:
        for name in ('realistic_hands_basecolor.png','realistic_hands_normal.png','realistic_hands_roughness.png'):
            shutil.copy2(source.parent/name,out/name)
        report['bake']='skipped_geometry_review_only'
    else:
        from detail_materials import bake_finger_detail
        report['bake']=bake_finger_detail(scene,hands,out,resolution=4096,samples=a.bake_samples,strength=a.material_strength)
        assert all(frozen(h)==before[s] for s,h in hands.items()),'Baking changed protected native mesh/rig payload'
    for s,h in hands.items():report['hands'][s]['export']=export_native(scene,h['objects'],h['holder'],out/f'{s}_hand_finger_detail.glb')
    camera=scene.camera;visibility={o.name:o.hide_render for o in scene.objects}
    for o in hands['right']['objects']:o.hide_render=True
    for name,center,direction,scale in [('preview_finger_dorsum',(0,.135,.005),(0,-.08,1),.205),('hand_dorsum',(0,.075,0),(0,0,1),.295)]:
        center=hands['left']['holder'].matrix_world@Vector(center);camera.location=center+Vector(direction).normalized()*1.2
        camera.rotation_euler=(center-camera.location).to_track_quat('-Z','Y').to_euler();camera.data.ortho_scale=scale
        scene.render.resolution_x=1400;scene.render.resolution_y=1200;scene.render.resolution_percentage=100
        scene.cycles.samples=a.samples;scene.cycles.use_denoising=True;scene.render.filepath=str(out/(name+'.png'))
        bpy.ops.render.render(write_still=True);report['renders'][name]={'file':name+'.png','sha256':sha(out/(name+'.png')),'actual_blender_render':True}
    for o in scene.objects:o.hide_render=visibility[o.name]
    center=Vector((0,-.035,0));camera.location=center+Vector((0,0,1.2));camera.rotation_euler=(center-camera.location).to_track_quat('-Z','Y').to_euler();camera.data.ortho_scale=.68
    scene.render.resolution_x=1600;scene.render.resolution_y=1300
    bpy.context.preferences.filepaths.save_version=0;target=out/'bilateral_hands_finger_detail.blend'
    bpy.ops.wm.save_as_mainfile(filepath=str(target),check_existing=False,relative_remap=False)
    report['blend_sha256']=sha(target);report['protected_payload_before_sha256']=before;report['protected_payload_after_sha256']={s:frozen(h) for s,h in hands.items()}
    report['texture_sha256']={name:sha(out/name) for name in ('realistic_hands_basecolor.png','realistic_hands_normal.png','realistic_hands_roughness.png')}
    assert sha(source)==source_sha;(out/'build_report.json').write_text(json.dumps(report,indent=2));print('FINGER_DETAIL_BUILD_COMPLETE',out,flush=True)

if __name__=='__main__':main()
