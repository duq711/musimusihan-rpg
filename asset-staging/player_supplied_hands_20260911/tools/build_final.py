"""Assemble the directly supplied hands, existing sleeves and actual character."""
import bpy,json,sys,hashlib
from pathlib import Path
from mathutils import Matrix,Vector
stage=Path(__file__).resolve().parents[1];project=stage.parents[1]
sys.path.insert(0,str(stage/'tools'))
sys.path.insert(0,str(project/'asset-staging/player_mercenary_gloves_20260911/tools'))
from reference_export import descendants,export_native
from assemble_character import assemble_character
DIGITS=('thumb','index','middle','ring','little')
out=stage/'mac_output/iteration_01'
bpy.ops.wm.open_mainfile(filepath=str(out/'supplied_left_baked.blend'))
scene=bpy.context.scene;scene.name='Bilateral_SuppliedHands_Review'
left={'body':bpy.data.objects['Supplied_AnatomicalHand'],'rig':bpy.data.objects['Supplied_HandRig_left'],
      'nails':{d:bpy.data.objects['Nail_'+d] for d in DIGITS}}
with bpy.data.libraries.load(str(stage/'geometry/supplied_right_rigged.blend'),link=False) as (src,dst):
    dst.objects=[n for n in src.objects if n in ['Supplied_AnatomicalHand_Right','Supplied_HandRig_right'] or n.startswith('Nail_') and n.endswith('_Right')]
for obj in dst.objects:
    if obj.name not in scene.objects:scene.collection.objects.link(obj)
right={'body':next(o for o in dst.objects if 'AnatomicalHand' in o.name),
       'rig':next(o for o in dst.objects if o.type=='ARMATURE'),
       'nails':{d:next(o for o in dst.objects if o.name.startswith('Nail_'+d+'_')) for d in DIGITS}}
hands={'left':left,'right':right}
for side,h in hands.items():
    holder=bpy.data.objects.new(side.upper()+'_PreviewTranslationOnly',None);scene.collection.objects.link(holder)
    h['holder']=holder
    for role,obj in [('body',h['body']),('rig',h['rig'])]+[(d,o) for d,o in h['nails'].items()]:
        if obj.name not in scene.collection.objects:scene.collection.objects.link(obj)
        for c in list(obj.users_collection):
            if c!=scene.collection:c.objects.unlink(obj)
        obj.hide_set(False);obj.hide_viewport=False;obj.hide_render=False
        if role=='rig':obj.parent=holder;obj.matrix_parent_inverse=Matrix.Identity(4);obj.matrix_basis=Matrix.Identity(4)
        if obj.type=='MESH':
            obj.name=('Supplied_AnatomicalHand_' if role=='body' else 'Nail_'+role+'_')+side
            obj.data.materials.clear();obj.data.materials.append(bpy.data.materials['Supplied_Skin' if role=='body' else 'Supplied_Nail'])
            for p in obj.data.polygons:p.material_index=0
            obj['source_mesh']='user_supplied_hand1_OBJ';obj['anatomical_side']=side
    holder.location.x=-.14 if side=='left' else .14
    bpy.context.view_layer.update()

oldpath=project/'asset-staging/player_mercenary_gloves_20260911/mac_output/iteration_02/bilateral_mercenary_gloves.blend'
with bpy.data.libraries.load(str(oldpath),link=False) as (src,dst):dst.scenes=['Bilateral_Realistic_Review']
oldscene=dst.scenes[0];bpy.context.window.scene=oldscene;bpy.context.view_layer.update()
clothes={}
for side,h in hands.items():
    oldholder=oldscene.objects[side.upper()+'_PreviewTranslationOnly.001'] if side.upper()+'_PreviewTranslationOnly.001' in oldscene.objects else next(o for o in oldscene.objects if o.name.startswith(side.upper()+'_PreviewTranslationOnly'))
    objs=descendants(oldholder);clothes[side]=[]
    for role in ('Forearm','UpperArm','WristCuff'):
        old=next(o for o in objs if o.type=='EMPTY' and o.name.startswith(role))
        new=bpy.data.objects.new(role+'_'+side,None);scene.collection.objects.link(new)
        new.parent=h['holder'];new.matrix_basis=oldholder.matrix_world.inverted()@old.matrix_world
        for k in old.keys():new[k]=old[k]
        for oldmesh in descendants(old):
            if oldmesh.type!='MESH':continue
            newmesh=bpy.data.objects.new(role+'_Surface_'+side,oldmesh.data.copy());scene.collection.objects.link(newmesh)
            newmesh.parent=new;newmesh.matrix_basis=old.matrix_world.inverted()@oldmesh.matrix_world
            for k in oldmesh.keys():newmesh[k]=oldmesh[k]
            clothes[side].append(newmesh.name)
for o in list(oldscene.objects):bpy.data.objects.remove(o,do_unlink=True)
bpy.context.window.scene=scene;bpy.data.scenes.remove(oldscene)
for mode in ('basecolor','normal','roughness'):
    m=bpy.data.materials.get('Detailed_Glove')
    if m:
        im=m.node_tree.nodes['Baked_'+mode].image
        (out/('realistic_hands_'+mode+'.png')).write_bytes(bytes(im.packed_file.data))
for o in list(scene.objects):
    if o.type in ('CAMERA','LIGHT'):bpy.data.objects.remove(o,do_unlink=True)
bpy.context.view_layer.update()
report={'source':'user supplied hand1.OBJ','source_obj_sha256':hashlib.sha256((stage/'input/hand1.OBJ').read_bytes()).hexdigest(),'clothes':clothes,'hands':{}}
for side,h in hands.items():
    h['objects']=descendants(h['holder'])
    report['hands'][side]=export_native(scene,h['objects'],h['holder'],out/(side+'_hand_supplied.glb'))
character,report['character']=assemble_character(hands,project/'asset-staging/player_gravebound/gravebound_player.blend',out)
bpy.context.window.scene=scene
bpy.context.preferences.filepaths.save_version=0
bpy.ops.wm.save_as_mainfile(filepath=str(out/'bilateral_supplied_hands.blend'),check_existing=False)
report['blend_sha256']=hashlib.sha256((out/'bilateral_supplied_hands.blend').read_bytes()).hexdigest()
(out/'build_report.json').write_text(json.dumps(report,indent=2))
print('SUPPLIED_BUILD_COMPLETE',flush=True)
