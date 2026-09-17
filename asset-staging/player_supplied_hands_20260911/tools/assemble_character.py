"""Replace the static character's old hand parts with evaluated supplied hands.

Run inside the final rigged hand build. Original source files are read-only.
The twenty-eight non-hand character objects and their atlas remain untouched.
"""
import bpy,hashlib,json,math
from pathlib import Path
from mathutils import Matrix,Vector

def sha(p):return hashlib.sha256(Path(p).read_bytes()).hexdigest()
def signature(obj):
    m=obj.data
    record={'points':[list(v.co) for v in m.vertices],
      'polygons':[list(p.vertices) for p in m.polygons],
      'uv':[[list(v.uv) for v in u.data] for u in m.uv_layers],
      'matrix_basis':[list(r) for r in obj.matrix_basis]}
    return hashlib.sha256(json.dumps(record,sort_keys=True).encode()).hexdigest()

def assemble_character(hands,source,out):
    """hands: left/right dicts with holder, skin/body, nails and rig objects."""
    source=Path(source).resolve();out=Path(out).resolve();out.mkdir(parents=True,exist_ok=True)
    original_sha=sha(source);hand_scene=bpy.context.scene
    # Evaluate neutral supplied meshes before appending the original character.
    static={}
    for side,h in hands.items():
        static[side]=[];h['rig'].pose.bones.update() if hasattr(h['rig'].pose.bones,'update') else None
        for bone in h['rig'].pose.bones:bone.matrix_basis=Matrix.Identity(4)
        body=h.get('body',h.get('skin'))
        if body.data.shape_keys:
            for key in body.data.shape_keys.key_blocks:key.value=0
        bpy.context.view_layer.update();dg=bpy.context.evaluated_depsgraph_get()
        for label,obj in [('Hand',body)]+[(f'Nail_{d}',o) for d,o in h['nails'].items()]:
            mesh=bpy.data.meshes.new_from_object(obj.evaluated_get(dg),preserve_all_data_layers=True,depsgraph=dg)
            native=h['holder'].matrix_world.inverted()@obj.matrix_world
            mesh.transform(native)
            static[side].append((label,mesh))
    with bpy.data.libraries.load(str(source),link=False) as (src,dst):
        dst.scenes=[src.scenes[0]]
    scene=dst.scenes[0];scene.name='Character_SuppliedHands_Review';bpy.context.window.scene=scene
    parent=next(o for o in scene.objects if o.name.startswith('GraveboundPlayer') and o.type=='EMPTY')
    meshes=[o for o in scene.objects if o.type=='MESH' and o.parent==parent]
    obsolete=[o for o in meshes if o.name.startswith('Gravebound_FingerlessGlove_') or o.name.startswith('Gravebound_Finger_')]
    assert len(obsolete)==22,('Unexpected old character hand set',len(obsolete))
    protected=[o for o in meshes if o not in obsolete];before={o.name:signature(o) for o in protected}
    removed=[o.name for o in obsolete]
    for o in obsolete:bpy.data.objects.remove(o,do_unlink=True)
    scale=1.78/1392
    def point(px,py,depth):return Vector(((px-512)*scale,depth,(1454-py)*scale))
    # Original suffixes refer to the artwork: R is anatomical left after the
    # established 180-degree export root rotation.
    targets={'left':('R',point(722,730,-.078),point(719,582,-.025)),
             'right':('L',point(281,718,-.074),point(300,573,-.013))}
    placements={};added=[]
    for side,(suffix,wrist,elbow) in targets.items():
        forward=(wrist-elbow).normalized()
        dorsal=Vector((0,-1,0));dorsal=(dorsal-forward*dorsal.dot(forward)).normalized()
        lateral=forward.cross(dorsal).normalized()
        basis=Matrix((lateral,forward,dorsal)).transposed()
        # The capped source wrist sits 14 mm inside the existing leather bracer.
        # The complete supplied hand is scaled uniformly for the full-body view.
        factor=.84;cap=Vector((0,-.05625,0));anchor=wrist-forward*.014
        transform=(basis*factor).to_4x4();transform.translation=anchor-transform.to_3x3()@cap
        placements[side]={'suffix':suffix,'wrist_world':list(wrist),'cap_inside_bracer_m':.014,
          'uniform_fullbody_scale':factor,'native_to_character':[list(r) for r in transform]}
        for label,mesh in static[side]:
            name='Gravebound_SuppliedHand_'+suffix if label=='Hand' else 'Gravebound_SuppliedNail_'+suffix+'_'+label.removeprefix('Nail_')
            obj=bpy.data.objects.new(name,mesh);scene.collection.objects.link(obj);obj.parent=parent;obj.matrix_basis=transform
            obj['source_mesh']='user_supplied_hand1_OBJ';obj['anatomical_side']=side;added.append(obj)
    assert all(signature(o)==before[o.name] for o in protected),'Non-hand character geometry changed'
    bpy.context.view_layer.update()
    bpy.ops.object.select_all(action='DESELECT');parent.select_set(True)
    for o in protected+added:o.select_set(True)
    bpy.context.view_layer.objects.active=parent
    rotation=parent.rotation_euler.copy();parent.rotation_euler.z=math.pi;bpy.context.view_layer.update()
    glb=out/'gravebound_player_supplied_hands.glb'
    options={'filepath':str(glb),'export_format':'GLB','use_selection':True,'export_yup':True,
      'export_materials':'EXPORT','export_animations':False,'export_skins':False,'export_extras':True,
      'export_image_format':'AUTO','export_tangents':True}
    props=bpy.ops.export_scene.gltf.get_rna_type().properties.keys();bpy.ops.export_scene.gltf(**{k:v for k,v in options.items() if k in props})
    parent.rotation_euler=rotation;bpy.context.view_layer.update()
    assert sha(source)==original_sha
    report={'source':str(source),'source_sha256':original_sha,'removed_old_hand_objects':removed,
      'added_supplied_objects':[o.name for o in added],'preserved_non_hand_meshes':len(protected),
      'preserved_geometry_sha256':before,'placements':placements,'glb_sha256':sha(glb)}
    (out/'character_replacement_report.json').write_text(json.dumps(report,indent=2))
    bpy.context.window.scene=hand_scene
    return scene,report
