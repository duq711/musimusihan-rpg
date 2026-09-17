"""Second candidate: fit only FPV cuff and hidden static character attachment."""
import bpy,json,sys,hashlib,shutil,math
from pathlib import Path
from mathutils import Vector
stage=Path(__file__).resolve().parents[1];project=stage.parents[1]
sys.path.insert(0,str(stage/'tools'));sys.path.insert(0,str(project/'asset-staging/player_mercenary_gloves_20260911/tools'))
from reference_export import export_native,descendants
from fit_supplied_cuff import fit_cuff
from assemble_character import signature
old=stage/'mac_output/iteration_01';out=stage/'mac_output/iteration_02';out.mkdir(parents=True,exist_ok=False)
bpy.ops.wm.open_mainfile(filepath=str(old/'bilateral_supplied_hands.blend'))
scene=bpy.data.scenes['Bilateral_SuppliedHands_Review'];bpy.context.window.scene=scene
hands={side:{'holder':bpy.data.objects[side.upper()+'_PreviewTranslationOnly'],
             'body':bpy.data.objects['Supplied_AnatomicalHand_'+side],
             'rig':bpy.data.objects['Supplied_HandRig_'+side],
             'nails':{d:bpy.data.objects['Nail_'+d+'_'+side] for d in ('thumb','index','middle','ring','little')}} for side in ('left','right')}
report={'source_blend_sha256':hashlib.sha256((old/'bilateral_supplied_hands.blend').read_bytes()).hexdigest(), 'fpv_cuff':fit_cuff(hands),'hands':{},'character':{}}
for p in old.glob('*.png'):shutil.copy2(p,out/p.name)
for side,h in hands.items():report['hands'][side]=export_native(scene,descendants(h['holder']),h['holder'],out/(side+'_hand_supplied.glb'))
char=bpy.data.scenes['Character_SuppliedHands_Review'];bpy.context.window.scene=char
parent=next(o for o in char.objects if o.name.startswith('GraveboundPlayer') and o.type=='EMPTY')
protected=[o for o in char.objects if o.type=='MESH' and not o.name.startswith('Gravebound_Supplied')]
before={o.name:signature(o) for o in protected}
for side,suffix in (('left','R'),('right','L')):
    body=bpy.data.objects['Gravebound_SuppliedHand_'+suffix];m=body.data;changed=0;maximum=0
    for v in m.vertices:
        p=v.co.copy();t=max(0.,min(1.,(-.025-p.y)/.027));t=t*t*(3.-2.*t)
        if t==0:continue
        # Taper only the buried proximal stump; palm and digits stay identical.
        fraction=max(0.,min(1.,(p.y+.05625)/.04125))
        center=Vector((.0008549*(1 if side=='left' else -1)*fraction,p.y,.0134522*fraction))
        delta=p-center;v.co=center+Vector((delta.x*(1-.40*t),0,delta.z*(1-.40*t)))
        changed+=1;maximum=max(maximum,(v.co-p).length)
    if m.has_custom_normals:m.normals_split_custom_set([(0,0,0)]*len(m.loops))
    m.update()
    # Slide hand and original nails together 8 mm farther into the fixed sleeve.
    forward=body.matrix_basis.to_3x3().col[1].normalized()
    for obj in char.objects:
        if obj.name=='Gravebound_SuppliedHand_'+suffix or obj.name.startswith('Gravebound_SuppliedNail_'+suffix+'_'):
            obj.location-=forward*.008
    report['character'][side]={'hidden_stump_vertices_adjusted':changed,'maximum_hidden_stump_displacement_m':maximum,'unchanged_palm_and_digits_from_y_m':-.025,'additional_sleeve_insertion_m':.008}
assert len(protected)==28 and all(signature(o)==before[o.name] for o in protected)
bpy.context.view_layer.update();bpy.ops.object.select_all(action='DESELECT');parent.select_set(True)
for o in char.objects:
    if o.type=='MESH':o.select_set(True)
rot=parent.rotation_euler.copy();parent.rotation_euler.z=math.pi;bpy.context.view_layer.update()
bpy.ops.export_scene.gltf(filepath=str(out/'gravebound_player_supplied_hands.glb'),export_format='GLB',use_selection=True,export_yup=True,export_materials='EXPORT',export_animations=False,export_skins=False,export_extras=True,export_tangents=True)
parent.rotation_euler=rot;bpy.context.view_layer.update();bpy.context.window.scene=scene
bpy.context.preferences.filepaths.save_version=0
bpy.ops.wm.save_as_mainfile(filepath=str(out/'bilateral_supplied_hands.blend'),check_existing=False)
report['blend_sha256']=hashlib.sha256((out/'bilateral_supplied_hands.blend').read_bytes()).hexdigest()
report['preserved_non_hand_character_meshes']=28
(out/'attachment_report.json').write_text(json.dumps(report,indent=2))
print('SUPPLIED_ATTACHMENTS_COMPLETE',flush=True)
