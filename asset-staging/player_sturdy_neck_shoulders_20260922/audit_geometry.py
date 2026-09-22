"""Independent read-only comparison against the accepted trousers-only source.

Run with Blender -b --python audit_geometry.py. Only geometry_audit.json is written.
The build module is intentionally not imported: this checks output invariants.
"""
from pathlib import Path
import bpy, hashlib, json, math, struct
from mathutils import Vector
from mathutils.bvhtree import BVHTree

HERE = Path(__file__).resolve().parent
SOURCE = HERE.parent / 'player_trousers_only_20260922/Gravebound_Trousers_Only.blend'
RESULT = HERE / 'Gravebound_Sturdy_Neck_Shoulders.blend'
SOURCE_GLB = SOURCE.with_name('gravebound_player_trousers_only.glb')
RESULT_GLB = HERE / 'gravebound_player_sturdy_neck_shoulders.glb'
HEAD = 'Gravebound_AnatomicalHead'
TORSO = 'Gravebound_QuiltedTorso'
LIMBS = ['Gravebound_FP_' + side + '_' + part for side in ['L', 'R'] for part in ['Arm', 'Hand']]
failures = []
def check(condition, message):
    if not condition:
        failures.append(message)
def digest(value):
    return hashlib.sha256(json.dumps(value, sort_keys=True).encode()).hexdigest()
def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()
def snapshot(path):
    bpy.ops.wm.open_mainfile(filepath=str(path))
    result = {}
    for obj in bpy.context.scene.objects:
        if obj.type != 'MESH':
            continue
        mesh = obj.data
        mesh.calc_loop_triangles()
        vertices = [list(v.co) for v in mesh.vertices]
        normals = [list(n.vector) for n in mesh.corner_normals]
        local = {
            'vertices': vertices,
            'faces': [list(f.vertices) for f in mesh.polygons],
            'face_materials': [f.material_index for f in mesh.polygons],
            'smooth': [f.use_smooth for f in mesh.polygons],
            'uv': [[list(u.uv) for u in layer.data] for layer in mesh.uv_layers],
            'materials': [m.name if m else None for m in mesh.materials],
            'normals': normals,
        }
        per_vertex_normals = {}
        normal_matrix = obj.matrix_world.to_3x3().inverted().transposed()
        for loop, normal in zip(mesh.loops, normals):
            per_vertex_normals.setdefault(loop.vertex_index, list((normal_matrix @ Vector(normal)).normalized()))
        result[obj.name] = {
            'local': local,
            'local_hash': digest(local),
            'world_matrix': [list(row) for row in obj.matrix_world],
            'world_vertices': [list(obj.matrix_world @ v.co) for v in mesh.vertices],
            'world_normals': per_vertex_normals,
            'triangles': [list(t.vertices) for t in mesh.loop_triangles],
            'edges': [list(e.vertices) for e in mesh.edges],
        }
    return result

def glb_mesh_hashes(path):
    data = path.read_bytes()
    json_length = struct.unpack_from('<I', data, 12)[0]
    doc = json.loads(data[20:20 + json_length])
    blob = data[28 + json_length:]
    def accessor(index):
        a = doc['accessors'][index]
        view = doc['bufferViews'][a['bufferView']]
        count = {'SCALAR':1, 'VEC2':2, 'VEC3':3, 'VEC4':4}[a['type']]
        component_bytes = {5120:1, 5121:1, 5122:2, 5123:2, 5125:4, 5126:4}[a['componentType']]
        size = count * component_bytes
        start = view.get('byteOffset', 0) + a.get('byteOffset', 0)
        stride = view.get('byteStride', size)
        packed = b''.join(blob[start + i*stride:start + i*stride + size] for i in range(a['count']))
        return [a['count'], a['type'], a['componentType'], hashlib.sha256(packed).hexdigest()]
    result = {}
    for node in doc['nodes']:
        if 'mesh' not in node:
            continue
        parts = []
        for primitive in doc['meshes'][node['mesh']]['primitives']:
            attrs = {name: accessor(index) for name, index in primitive['attributes'].items()}
            material = doc.get('materials', [])[primitive['material']].get('name') if 'material' in primitive else None
            parts.append({'attributes':attrs, 'indices':accessor(primitive['indices']), 'material':material})
        result[node['name']] = digest(parts)
    image_hashes = []
    for image in doc.get('images', []):
        if 'bufferView' in image:
            view = doc['bufferViews'][image['bufferView']]
            start = view.get('byteOffset', 0)
            image_hashes.append(hashlib.sha256(blob[start:start+view['byteLength']]).hexdigest())
    return result, sorted(image_hashes)

def section(mesh, height):
    vertices = mesh['world_vertices']
    points = []
    for i, j in mesh['edges']:
        a, b = vertices[i], vertices[j]
        if (a[2]-height)*(b[2]-height) > 0 or abs(b[2]-a[2]) < 1e-10:
            continue
        t = (height-a[2])/(b[2]-a[2])
        points.append([a[k] + t*(b[k]-a[k]) for k in range(3)])
    return {'width_m':max(p[0] for p in points)-min(p[0] for p in points),
            'depth_m':max(p[1] for p in points)-min(p[1] for p in points),
            'samples':len(points)}

def neck_probes(mesh):
    tree = BVHTree.FromPolygons([Vector(p) for p in mesh['world_vertices']], mesh['triangles'], all_triangles=True)
    points = [(0., .007)] + [(math.cos(i*math.tau/8)*r, .007+math.sin(i*math.tau/8)*r) for r in [.035, .050] for i in range(8)]
    rows = []
    for x, y in points:
        hit, normal, index, distance = tree.ray_cast(Vector((x, y, 1.55)), Vector((0, 0, -1)), .3)
        rows.append({'x_m':x, 'y_m':y, 'first_surface_z_m':hit.z if hit else None})
    return rows

source, result = snapshot(SOURCE), snapshot(RESULT)
check(set(source) == set(result) and len(result) == 20, 'Mesh names/count changed unexpectedly')
preserved = sorted(set(source) - {HEAD, TORSO} - set(LIMBS))
check(len(preserved) == 14, 'Expected fourteen entirely preserved meshes')
for name in preserved:
    check(source[name]['local_hash'] == result[name]['local_hash'], name + ': local geometry, topology, normals, UV or materials changed')
    check(source[name]['world_matrix'] == result[name]['world_matrix'], name + ': transform changed')

limb_report = {}
for name in LIMBS:
    a, b = source[name], result[name]
    check(a['local_hash'] == b['local_hash'], name + ': local arm/hand shape or surface data changed')
    sign = 1 if sum(p[0] for p in a['world_vertices']) > 0 else -1
    wanted = Vector((sign*.018, 0, 0))
    error = max((Vector(q)-Vector(p)-wanted).length for p,q in zip(a['world_vertices'], b['world_vertices']))
    check(error < 1e-6, name + ': is not a pure 18mm lateral translation')
    limb_report[name] = {'local_data_exactly_preserved':a['local_hash']==b['local_hash'], 'world_translation_m':list(wanted), 'maximum_translation_residual_m':error}
for side in ['L','R']:
    check(limb_report['Gravebound_FP_'+side+'_Arm']['world_translation_m'] == limb_report['Gravebound_FP_'+side+'_Hand']['world_translation_m'], side + ': cuff relationship changed')

for name in [HEAD,TORSO]:
    for key in ['faces', 'face_materials', 'smooth', 'uv', 'materials']:
        check(source[name]['local'][key] == result[name]['local'][key], name + ': ' + key + ' changed')
    check(len(source[name]['world_vertices']) == len(result[name]['world_vertices']), name + ': vertex count changed')
face_errors = [(Vector(q)-Vector(p)).length for p,q in zip(source[HEAD]['world_vertices'],result[HEAD]['world_vertices']) if p[2]>=1.51]
check(len(face_errors)>4000 and max(face_errors)<1e-7, 'Face/scalp geometry at or above 1.51m changed')
sections = []
for height in [1.470,1.475,1.480,1.490,1.500,1.510]:
    a,b = section(source[HEAD],height), section(result[HEAD],height)
    sections.append({'height_m':height,'source':a,'result':b,'width_ratio':b['width_m']/a['width_m'],'depth_ratio':b['depth_m']/a['depth_m']})
check(1.14 < sections[0]['width_ratio'] < 1.17, 'Lower neck width not moderately thickened')
check(1.10 < sections[0]['depth_ratio'] < 1.13, 'Lower neck depth not moderately thickened')

seams = {}
for side in ['L','R']:
    limb = 'Gravebound_FP_'+side+'_Arm'
    torso_map = {tuple(round(value,6) for value in p):i for i,p in enumerate(source[TORSO]['world_vertices']) if p[2]>1.30}
    pairs = [(torso_map[tuple(round(value,6) for value in p)],j) for j,p in enumerate(source[limb]['world_vertices']) if p[2]>1.30 and tuple(round(value,6) for value in p) in torso_map]
    check(len(pairs)>=20, side+': baseline join was not located')
    gaps = [(Vector(result[TORSO]['world_vertices'][i])-Vector(result[limb]['world_vertices'][j])).length for i,j in pairs]
    dots = [Vector(result[TORSO]['world_normals'][i]).dot(Vector(result[limb]['world_normals'][j])) for i,j in pairs]
    seams[side] = {'source_shared_join_vertex_pairs':len(pairs),'maximum_result_gap_m':max(gaps),'minimum_normal_dot':min(dots)}
    check(max(gaps)<1e-6, side+': shoulder join separates')
    check(min(dots)>.985, side+': shoulder join develops a shading break')

probes = neck_probes(result[TORSO])
check(all(p['first_surface_z_m'] is not None and p['first_surface_z_m']<1.445 for p in probes), 'A torso cap intersects the neck interior')
source_glb,result_glb = glb_mesh_hashes(SOURCE_GLB),glb_mesh_hashes(RESULT_GLB)
for name in preserved+LIMBS:
    check(source_glb[0][name] == result_glb[0][name], name+': exported GLB local geometry/material data differs')
check(source_glb[1] == result_glb[1], 'Embedded texture bytes changed')
report = {
    'source_blend_sha256':sha(SOURCE), 'result_blend_sha256':sha(RESULT),
    'source_glb_sha256':sha(SOURCE_GLB), 'result_glb_sha256':sha(RESULT_GLB),
    'mesh_count':len(result),'entirely_preserved_meshes':preserved,
    'limbs':limb_report,'preserved_face_vertex_count':len(face_errors),'maximum_face_vertex_displacement_m':max(face_errors),
    'head_and_torso_topology_uv_materials_preserved':True,
    'neck_sections':sections,'shoulder_joins':seams,'neck_interior_probes':probes,
    'exported_preserved_meshes_and_limb_local_data_match':all(source_glb[0][name]==result_glb[0][name] for name in preserved+LIMBS),
    'embedded_texture_bytes_unchanged':source_glb[1]==result_glb[1],
    'failures':failures,'pass':not failures,
}
(HERE/'geometry_audit.json').write_text(json.dumps(report,indent=2)+'\n')
print('INDEPENDENT STURDY GEOMETRY AUDIT', 'PASS' if not failures else 'FAIL', json.dumps(failures), flush=True)
if failures:
    raise SystemExit(1)
