"""Broaden the restored player's neck/shoulders without resculpting the arms."""
from pathlib import Path
import bpy, math, json, hashlib, shutil, struct
from mathutils import Vector, Matrix

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
SOURCE = HERE.parent / 'player_trousers_only_20260922/Gravebound_Trousers_Only.blend'
ARM_SHIFT = .018
bpy.ops.wm.open_mainfile(filepath=str(SOURCE))

def smooth(t):
    t = max(0., min(1., t))
    return t*t*(3.-2.*t)

def signature(obj):
    return hashlib.sha256(json.dumps({
        'v': [list(v.co) for v in obj.data.vertices],
        'f': [list(f.vertices) for f in obj.data.polygons],
        'uv': [[list(u.uv) for u in layer.data] for layer in obj.data.uv_layers],
        'world': [list(row) for row in obj.matrix_world],
        'materials': [m.name for m in obj.data.materials],
    }, sort_keys=True).encode()).hexdigest()

TARGETS = ['Gravebound_AnatomicalHead', 'Gravebound_QuiltedTorso']
LIMBS = ['Gravebound_FP_' + side + '_' + part for side in ['L','R'] for part in ['Arm','Hand']]
preserved = {o.name: signature(o) for o in bpy.context.scene.objects if o.type == 'MESH' and o.name not in TARGETS + LIMBS}

def deform_neck(p):
    # Fade out before the lower jaw becomes facial geometry. Every vertex at
    # or above 1.51m, including the supplied face and scalp, stays unchanged.
    weight = 1.-smooth((p.z-1.475)/.035)
    return Vector((p.x*(1.+.16*weight), .007+(p.y-.007)*(1.+.12*weight), p.z))

def deform_torso(p):
    x, y, z = abs(p.x), p.y, p.z
    radius = math.hypot(p.x, p.y-.007)
    neck = smooth((z-1.36)/.070)*(1.-smooth((radius-.088)/.052))
    lateral = ARM_SHIFT*smooth((x-.095)/.070)*smooth((z-1.02)/.250)
    # A small trapezius lift blends out before the rigid sleeve boundary.
    trap = math.sin(math.pi*smooth((x-.065)/.100)) if .065 < x < .165 else 0.
    opening = math.sqrt((p.x/.0635)**2+((p.y-.007)/.064)**2)
    lift = .009*trap*smooth((z-1.37)/.050)*smooth((opening-1.)/.35)*math.exp(-(y/.09)**4)
    return Vector((p.x*(1.+.16*neck)+math.copysign(lateral,p.x), .007+(y-.007)*(1.+.12*neck), z+lift))

report = {'source': str(SOURCE.relative_to(ROOT)), 'preserved_meshes': preserved, 'arm_translation_m': {}, 'deformed_meshes': TARGETS, 'mesh_metrics': {}}
for name, deform in [(TARGETS[0],deform_neck),(TARGETS[1],deform_torso)]:
    obj = bpy.data.objects[name]
    world = obj.matrix_world.copy(); inv = world.inverted()
    before = [world@v.co for v in obj.data.vertices]
    old_normals = [n.vector.copy() for n in obj.data.corner_normals]
    normal_world = world.to_3x3().inverted().transposed()
    normal_local = world.to_3x3().transposed()
    transformed_normals = []
    jacobians = []
    for p in before:
        columns = []
        for axis in range(3):
            delta = Vector(); delta[axis] = .00001
            columns.append((deform(p+delta)-deform(p-delta))/.00002)
        jacobian = Matrix(columns).transposed()
        assert jacobian.determinant() > .4, (name, tuple(p), jacobian.determinant())
        jacobians.append(jacobian.inverted().transposed())
    for loop, normal in zip(obj.data.loops,old_normals):
        transformed_normals.append((normal_local @ jacobians[loop.vertex_index] @ normal_world @ normal).normalized())
    for vertex,p in zip(obj.data.vertices,before):
        vertex.co = inv @ deform(p)
    obj.data.update()
    obj.data.normals_split_custom_set(transformed_normals)
    obj['sturdy_revision'] = 'Localized neck thickening and shoulder breadth; existing topology and UV retained'
    report['mesh_metrics'][name] = {'vertices':len(before),'maximum_vertex_displacement_m':max((deform(p)-p).length for p in before)}

for name in LIMBS:
    obj = bpy.data.objects[name]
    sign = 1 if sum((obj.matrix_world@v.co).x for v in obj.data.vertices)>0 else -1
    matrix = obj.matrix_world.copy(); matrix.translation.x += sign*ARM_SHIFT
    obj.matrix_world = matrix
    obj['sturdy_revision'] = 'Rigid lateral translation only; sleeve/hand shape, normals and UV preserved'
    report['arm_translation_m'][name] = sign*ARM_SHIFT

assert preserved == {o.name:signature(o) for o in bpy.context.scene.objects if o.type=='MESH' and o.name not in TARGETS+LIMBS}
bpy.context.preferences.filepaths.save_version=0
bpy.ops.object.select_all(action='SELECT')
bpy.context.view_layer.objects.active=bpy.data.objects['GraveboundPlayer']
bpy.ops.wm.save_as_mainfile(filepath=str(HERE/'Gravebound_Sturdy_Neck_Shoulders.blend'),compress=True)
out=HERE/'gravebound_player_sturdy_neck_shoulders.glb'
bpy.ops.export_scene.gltf(filepath=str(out),export_format='GLB',use_selection=True,export_animations=False,export_skins=False,export_extras=True,export_tangents=True,export_yup=True)
data=out.read_bytes(); assert data[:4]==b'glTF' and struct.unpack_from('<I',data,8)[0]==len(data)
shutil.copy2(out,ROOT/'godot-game/assets/3d/player/gravebound_player.glb')
report.update({'output_sha256':hashlib.sha256(data).hexdigest(),'neck_width_factor':1.16,'neck_depth_factor':1.12,'shoulder_width_added_m':ARM_SHIFT*2,'maximum_trapezius_lift_m':.009,'preserved_mesh_count':len(preserved),'pass':True})
(HERE/'build_report.json').write_text(json.dumps(report,indent=2)+'\n')
print('STURDY NECK SHOULDERS BUILD PASS',report['output_sha256'],flush=True)
