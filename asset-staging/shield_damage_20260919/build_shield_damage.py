"""Mac Blender: fracture copies of the actual shield; retain source and grip markers."""
import bpy, bmesh, math, json, hashlib
from pathlib import Path
from mathutils import Vector

ROOT = Path(__file__).resolve().parents[2]
STAGE = Path(__file__).resolve().parent
SOURCE = ROOT / 'godot-game/assets/3d/player/sword_shield/round_shield.glb'
OUT = ROOT / 'godot-game/assets/3d/player/shield_damage'

def material(name, color, roughness, metal=0):
    m=bpy.data.materials.new(name); m.diffuse_color=(*color,1);m.use_nodes=True
    p=m.node_tree.nodes.get('Principled BSDF')
    p.inputs['Base Color'].default_value=(*color,1)
    p.inputs['Roughness'].default_value=roughness;p.inputs['Metallic'].default_value=metal
    return m

def cutter(poly):
    # Extruded X/Z polygon through the wood and both metal lips, not the straps.
    n=len(poly);v=[(x,y,z) for y in [-.12,.07] for x,z in poly]
    f=[tuple(range(n-1,-1,-1)),tuple(range(n,n*2))]
    f += [(i,(i+1)%n,(i+1)%n+n,i+n) for i in range(n)]
    mesh=bpy.data.meshes.new('fracture_cutter');mesh.from_pydata(v,[],f);mesh.update()
    obj=bpy.data.objects.new('fracture_cutter',mesh);bpy.context.collection.objects.link(obj)
    bm=bmesh.new();bm.from_mesh(mesh);bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces));bm.to_mesh(mesh);bm.free()
    return obj

def split_material(source, names, name):
    obj=source.copy();obj.data=source.data.copy();bpy.context.collection.objects.link(obj);obj.name=name
    bm=bmesh.new();bm.from_mesh(obj.data)
    remove=[f for f in bm.faces if obj.data.materials[f.material_index].name not in names]
    bmesh.ops.delete(bm,geom=remove,context='FACES')
    bmesh.ops.remove_doubles(bm,verts=list(bm.verts),dist=.000008)
    bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces));bm.to_mesh(obj.data);bm.free()
    return obj

def cut(obj, poly, mat):
    tool=cutter(poly)
    obj.data.materials.append(mat)
    # Boolean-generated fracture walls receive the new exposed material.
    for old in obj.data.materials:tool.data.materials.append(old)
    for face in tool.data.polygons:face.material_index=len(obj.data.materials)-1
    mod=obj.modifiers.new('Splintered edge','BOOLEAN');mod.operation='DIFFERENCE';mod.solver='EXACT';mod.object=tool
    bpy.context.view_layer.objects.active=obj
    bpy.ops.object.modifier_apply(modifier=mod.name)
    bpy.data.objects.remove(tool,do_unlink=True)

def build(level):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=str(SOURCE))
    surface=bpy.data.objects['SwordsmanRoundShield_Surface'];root=surface.parent
    source_materials=[m.name for m in surface.data.materials]
    wood=split_material(surface,{'FP_ShieldOak'},'FracturedOak')
    metal=split_material(surface,{'FP_ShieldIron','FP_ShieldEdge'},'TornIron')
    leather=split_material(surface,{'FP_ShieldEnarmes','FP_ShieldLeatherEdge','FP_ShieldStitch'},'RetainedGrip')
    bpy.data.objects.remove(surface,do_unlink=True)
    raw=material('FP_ShieldFractureOak',(.34,.21,.105),.96)
    torn=material('FP_ShieldFractureIron',(.20,.21,.20),.72,.72)
    # Main damage is in the upper-left 105-120-degree arc, visible in both
    # the unmodified first-person carry and centered guard camera poses.
    medium=[(-.265,.52),(-.265,.339),(-.242,.350),(-.230,.314),(-.212,.331),(-.204,.269),(-.188,.302),(-.177,.282),(-.165,.322),(-.143,.301),(-.133,.358),(-.112,.346),(-.104,.52)]
    low=[(-.375,.52),(-.375,.269),(-.352,.291),(-.335,.223),(-.312,.246),(-.296,.201),(-.278,.251),(-.255,.217),(-.239,.273),(-.216,.231),(-.200,.165),(-.183,.204),(-.161,.179),(-.147,.255),(-.125,.216),(-.107,.288),(-.086,.266),(-.066,.321),(-.039,.295),(-.021,.356),(.006,.342),(.019,.52)]
    polygons=[medium if level=='medium' else low]
    if level=='low':
        polygons.append([(-.60,.12),(-.368,.12),(-.348,.096),(-.327,.078),(-.364,.058),(-.347,.016),(-.383,-.006),(-.363,-.048),(-.60,-.078)])
        polygons.append([(.275,.55),(.275,.301),(.294,.284),(.308,.232),(.327,.253),(.340,.188),(.375,.214),(.55,.19),(.55,.55)])
    else:
        polygons.append([(.298,.49),(.299,.283),(.315,.267),(.321,.298),(.336,.268),(.35,.49)])
    for p in polygons:
        cut(wood,p,raw);cut(metal,p,torn)
    # The original rolled rim is an open U-shaped metal sheet. Exact boolean
    # can classify a cutter's exterior as an interior cap on this open mesh.
    # Retain only original metal-sheet faces; the severed thin ends stay open.
    bm=bmesh.new();bm.from_mesh(metal.data)
    bmesh.ops.delete(bm,geom=[f for f in bm.faces if metal.data.materials[f.material_index].name.startswith('FP_ShieldFractureIron')],context='FACES')
    bm.to_mesh(metal.data);bm.free()
    # Narrow branching wood splits are real openings and remain visible from
    # the back. Their irregular width avoids clean saw-cut slots.
    cracks=[ [(-.205,.32),(-.199,.235),(-.212,.189),(-.204,.158),(-.209,.109),(-.199,.163),(-.202,.190),(-.190,.235),(-.193,.32)] ]
    if level=='low':cracks += [[(-.129,.28),(-.119,.139),(-.131,.092),(-.123,.019),(-.116,.091),(-.106,.133),(-.116,.28)],[(.286,.29),(.279,.178),(.268,.12),(.271,.035),(.280,.123),(.29,.177),(.298,.29)]]
    for p in cracks:cut(wood,p,raw)
    # Small uneven deformation near each severed rim end reads as bent iron.
    for v in metal.data.vertices:
        x,y,z=v.co
        if z>.17 and x<-.03 and math.sqrt(x*x+z*z)>.38:
            a=math.atan2(z,x)
            influence=math.exp(-((a-math.radians(129 if level=='medium' else 151))/.12)**2)
            v.co.y += (.018 if level=='medium' else .032)*influence
    # Merge all components into the original surface name, retaining the four
    # exact imported contact markers and the original transform hierarchy.
    bpy.ops.object.select_all(action='DESELECT')
    for ob in [wood,metal,leather]:ob.select_set(True)
    bpy.context.view_layer.objects.active=wood;bpy.ops.object.join()
    wood.name='SwordsmanRoundShield_Surface';wood.data.name='ShieldDamage_'+level
    assert all(math.hypot(v.co.x,v.co.z)<.435 for v in wood.data.vertices), 'Cutter geometry escaped the original shield silhouette'
    root['damage_stage']=level
    root['source_sha256']=hashlib.sha256(SOURCE.read_bytes()).hexdigest()
    # Keep sharp fracture walls; original smooth faces remain smooth.
    bpy.ops.wm.save_as_mainfile(filepath=str(STAGE/('shield_'+level+'.blend')))
    target=OUT/('round_shield_'+level+'.glb')
    bpy.ops.export_scene.gltf(filepath=str(target),export_format='GLB',export_yup=True,export_animations=False,export_extras=True,export_materials='EXPORT',export_vertex_color='ACTIVE')
    return {'stage':level,'file':str(target.relative_to(ROOT)),'vertices':len(wood.data.vertices),'triangles':sum(len(p.vertices)-2 for p in wood.data.polygons),'bytes':target.stat().st_size,'materials':source_materials,'sha256':hashlib.sha256(target.read_bytes()).hexdigest()}

original=hashlib.sha256(SOURCE.read_bytes()).hexdigest()
OUT.mkdir(parents=True,exist_ok=True)
results=[build(level) for level in ['medium','low']]
assert hashlib.sha256(SOURCE.read_bytes()).hexdigest()==original
(STAGE/'build_report.json').write_text(json.dumps({'host':'MacBook','source_sha256':original,'variants':results},indent=2)+'\n')
print('SHIELD DAMAGE BUILD PASS:',json.dumps(results))
