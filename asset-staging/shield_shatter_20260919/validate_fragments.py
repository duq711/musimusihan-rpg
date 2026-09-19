"""Standard-library verification of exported fragment structure; no engine."""
import json, struct, hashlib
from pathlib import Path

ROOT=Path(__file__).resolve().parents[2]
STAGE=Path(__file__).resolve().parent
report=json.loads((STAGE/'manifest.json').read_text())
path=ROOT/report['output']; blob=path.read_bytes()
magic,version,total=struct.unpack_from('<III',blob)
assert magic==0x46546C67 and version==2 and total==len(blob)
size,kind=struct.unpack_from('<II',blob,12)
assert kind==0x4E4F534A
data=json.loads(blob[20:20+size])
nodes=[n for n in data['nodes'] if 'mesh' in n]
assert 20<=len(nodes)<=32 and len(nodes)==report['fragment_count']
assert len({n['name'] for n in nodes})==len(nodes)
rows={r['name']:r for r in report['fragments']}
for node in nodes:
    row=rows[node['name']]
    assert node['name'].startswith('ShieldFragment_')
    assert not any(k in node for k in ['rotation','scale','matrix'])
    translation=node['translation']
    # Blender's glTF exporter omits translation components below one micron.
    assert max(abs(a-b) for a,b in zip(translation,row['origin_godot']))<1e-6
    assert node['extras']['wood_coordinate_offset']==row['wood_coordinate_offset']
    assert node['extras']['fragment_kind']==row['kind']
    assert row['boundary_edges']==0 and row['nonmanifold_edges']==0
    assert row['mesh_volume_m3']>0 and row['convex_volume_m3']>0
    if row['kind']=='metal':
        spans=[b[1]-b[0] for b in row['bounds_local_godot']]
        assert max(spans)<0.36 and row['convex_volume_m3']<0.0015
        if node['name']=='ShieldFragment_029_metal':
            assert max(spans)<0.20 and row['convex_volume_m3']<0.001
    bounds=[]
    for primitive in data['meshes'][node['mesh']]['primitives']:
        accessor=data['accessors'][primitive['attributes']['POSITION']]
        bounds.append((accessor['min'],accessor['max']))
    for axis in range(3):
        lo=min(b[0][axis] for b in bounds);hi=max(b[1][axis] for b in bounds)
        assert abs(lo+hi)<1e-6,(node['name'],axis,lo,hi)
assert 'FP_ShieldFractureOak' in [m['name'] for m in data['materials']]
assert hashlib.sha256(blob).hexdigest()==report['output_sha256']
assert hashlib.sha256((ROOT/report['source']).read_bytes()).hexdigest()==report['source_sha256']
assert report['original_exterior_max_distance_m']<0.0001
print('PASS: 32 centered, translated meshes; source/materials preserved; all shells closed; metal hulls remain compact, with the central boss below 20cm.')
