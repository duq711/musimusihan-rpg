"""Correct thumb axial opposition in a separately saved, previously baked model.

The actual skin, nail, custom normals and corrective vectors move together.
Existing tangent-space detail consequently follows the surface without rebaking.
"""
import argparse,hashlib,json,math,shutil,sys
from pathlib import Path
import bpy
from mathutils import Matrix,Vector
from mathutils.kdtree import KDTree
sys.path.insert(0,str(Path(__file__).resolve().parent))
from build_finger_detail import collect,frozen
from finger_sculpt import weights,make_frames,geometric_normals,smooth
from reference_export import export_native

def sha(p):return hashlib.sha256(Path(p).read_bytes()).hexdigest()

def rotate_thumb(hand,degrees):
    holder,rig,skin=hand['holder'],hand['rig'],hand['skin'];mesh=skin.data
    frames=make_frames(holder,rig,skin);origin,axis,dorsal,cross,*_=frames['thumb'][2]
    sm=holder.matrix_world.inverted()@skin.matrix_world;inv=sm.inverted()
    points=[sm@v.co for v in mesh.vertices];own=weights(skin)
    eligible=set();protected=set()
    for face in mesh.polygons:
        (eligible if mesh.materials[face.material_index].name=='Detailed_Skin' else protected).update(face.vertices)
    eligible={i for i in eligible-protected if i<12036 and own[i]['thumb']>.95}
    boundary=[i for i in protected if i<12036 and own[i]['thumb']>.5]
    start=max((points[i]-origin).dot(axis) for i in boundary)+.0008
    end=-.002
    assert end-start>.010,(start,end)
    angles=[math.radians(degrees)*smooth(start,end,(p-origin).dot(axis)) if i in eligible else 0. for i,p in enumerate(points)]
    tree=KDTree(12036)
    for i,p in enumerate(points[:12036]):tree.insert(p,i)
    tree.balance();seen=set()
    for i,p in enumerate(points[:12036]):
        if i in seen:continue
        group={j for _,j,_ in tree.find_range(p,.000001)};frontier=list(group)
        while frontier:
            j=frontier.pop()
            for _,k,_ in tree.find_range(points[j],.000001):
                if k not in group:group.add(k);frontier.append(k)
        seen.update(group)
        angle=min((angles[j] for j in group),key=abs)
        for j in group:angles[j]=angle
    rotations=[Matrix.Rotation(a,3,axis) for a in angles]
    new=[origin+r@(p-origin) if a else p.copy() for p,r,a in zip(points,rotations,angles)]
    oldlocal=[v.co.copy() for v in mesh.vertices];newlocal=[inv@p for p in new]
    oldgeo=geometric_normals(mesh,oldlocal);newgeo=geometric_normals(mesh,newlocal)
    custom=[n.vector.copy() for n in mesh.corner_normals];moved=[i for i,a in enumerate(angles) if abs(a)>1e-12]
    for i in moved:
        base=mesh.shape_keys.key_blocks[0].data[i].co.copy()
        localrot=inv.to_3x3()@rotations[i]@sm.to_3x3()
        for key in mesh.shape_keys.key_blocks:
            key.data[i].co=newlocal[i]+localrot@(key.data[i].co-base)
        mesh.vertices[i].co=newlocal[i]
    mesh.update();result=[]
    for loop,n in zip(mesh.loops,custom):
        i=loop.vertex_index
        if abs(angles[i])>1e-12:n=oldgeo[i].rotation_difference(newgeo[i])@n
        result.append(n.normalized())
    mesh.normals_split_custom_set(result)
    nail=next(o for o in hand['objects'] if o.type=='MESH' and o.name.startswith('Nail_thumb'))
    nm=holder.matrix_world.inverted()@nail.matrix_world;ni=nm.inverted();nr=Matrix.Rotation(math.radians(degrees),3,axis)
    nailpoints=[nm@v.co for v in nail.data.vertices]
    assert min((p-origin).dot(axis) for p in nailpoints)>end+.002
    normals=[n.vector.copy() for n in nail.data.corner_normals];localrot=ni.to_3x3()@nr@nm.to_3x3()
    for v,p in zip(nail.data.vertices,nailpoints):v.co=ni@(origin+nr@(p-origin))
    nail.data.update();nail.data.normals_split_custom_set([(localrot@n).normalized() for n in normals])
    return {'pivot_native':list(origin),'axis_native':list(axis),'angle_degrees':degrees,
      'transition_start_m':start,'transition_end_m':end,'vertex_angles_radians':angles,
      'changed_skin_vertices':len(moved),'maximum_skin_displacement_m':max((a-b).length for a,b in zip(points,new)),
      'old_dorsal_native':list(dorsal),'new_dorsal_native':list(nr@dorsal),
      'nail_rigid_rotation':True,'corrective_vectors_rotated_with_skin':True,
      'maps_unchanged':'Already baked tangent-space details rotate with actual UV surface; no rebake.'}

def main():
    p=argparse.ArgumentParser();p.add_argument('--source-dir',type=Path,required=True);p.add_argument('--output-dir',type=Path,required=True);p.add_argument('--degrees',type=float,default=75.);a=p.parse_args(sys.argv[sys.argv.index('--')+1:])
    src=a.source_dir.resolve();out=a.output_dir.resolve();assert not out.exists();out.mkdir();source=src/'bilateral_hands_finger_detail.blend';original=sha(source)
    bpy.ops.wm.open_mainfile(filepath=str(source));scene=bpy.data.scenes['Bilateral_Realistic_Review'];bpy.context.window.scene=scene
    hands=collect(scene);before={s:frozen(h) for s,h in hands.items()}
    report={'source':str(source),'source_sha256':original,'reason':'User corrected thumbnail axial direction; it must differ from the four fingers.','hands':{}}
    for side,h in hands.items():report['hands'][side]=rotate_thumb(h,a.degrees if side=='left' else -a.degrees)
    assert all(frozen(h)==before[s] for s,h in hands.items())
    for name in ('basecolor','normal','roughness'):shutil.copy2(src/f'realistic_hands_{name}.png',out/f'realistic_hands_{name}.png')
    for side,h in hands.items():report['hands'][side]['export']=export_native(scene,h['objects'],h['holder'],out/f'{side}_hand_finger_detail.glb')
    visibility={o.name:o.hide_render for o in scene.objects};camera=scene.camera
    for o in hands['right']['objects']:o.hide_render=True
    report['renders']={}
    for name,center,direction,scale in [('preview_finger_dorsum',(0,.135,.005),(0,-.08,1),.205),('hand_dorsum',(0,.075,0),(0,0,1),.295),('hand_palmar',(0,.075,0),(0,0,-1),.295),('thumb_radial',(0.082,.090,-.020),(.85,-.32,.38),.100)]:
        center=hands['left']['holder'].matrix_world@Vector(center);camera.location=center+Vector(direction).normalized()*1.2;camera.rotation_euler=(center-camera.location).to_track_quat('-Z','Y').to_euler();camera.data.ortho_scale=scale
        scene.render.resolution_x=1400;scene.render.resolution_y=1200;scene.render.resolution_percentage=100;scene.cycles.samples=32;scene.cycles.use_denoising=True;scene.render.filepath=str(out/(name+'.png'))
        bpy.ops.render.render(write_still=True);report['renders'][name]={'file':name+'.png','sha256':sha(out/(name+'.png')),'actual_blender_render':True}
    for o in scene.objects:o.hide_render=visibility[o.name]
    center=Vector((0,-.035,0));camera.location=center+Vector((0,0,1.2));camera.rotation_euler=(center-camera.location).to_track_quat('-Z','Y').to_euler();camera.data.ortho_scale=.68;scene.render.resolution_x=1600;scene.render.resolution_y=1300
    bpy.context.preferences.filepaths.save_version=0;target=out/'bilateral_hands_finger_detail.blend';bpy.ops.wm.save_as_mainfile(filepath=str(target),check_existing=False,relative_remap=False)
    report['blend_sha256']=sha(target);assert sha(source)==original
    (out/'thumb_rotation_report.json').write_text(json.dumps(report,indent=2));shutil.copy2(src/'build_report.json',out/'prior_detail_build_report.json');shutil.copy2(src/'verification_report.json',out/'prior_detail_verification_report.json')
    print('THUMB_ORIENTATION_COMPLETE',out,flush=True)
if __name__=='__main__':main()
