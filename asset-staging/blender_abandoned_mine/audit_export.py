"""Check the portable GLB structure, scan maps, real survey size and source link."""
import json, struct, hashlib
from pathlib import Path
ROOT=Path(__file__).resolve().parent
ASSETS=ROOT.parents[1]/'godot-game/assets/3d/abandoned_mine'
p=ASSETS/'abandoned_mine.glb'
b=p.read_bytes()
magic,version,length=struct.unpack_from('<4sII',b)
assert magic==b'glTF' and version==2 and length==len(b)
size,kind=struct.unpack_from('<II',b,12)
assert kind==0x4e4f534a
j=json.loads(b[20:20+size])
assert not any('uri' in image and not image['uri'].startswith('data:') for image in j.get('images',[])), 'GLB image must be embedded'
assert len(j['images'])>=15, 'Photographic material channels must be packed'
assert any(n.get('name','').startswith('Terrain_') for n in j['nodes'])
assert any(n.get('name','').startswith('collision_') for n in j['nodes'])
meshes=0; triangles=0; pbr_count=0
for mesh in j['meshes']:
    meshes+=1
    for primitive in mesh['primitives']:
        attrs=primitive['attributes']
        assert 'NORMAL' in attrs
        # Hidden collision proxies intentionally need no visible texture UVs.
        if not mesh.get('name','').startswith('collision_'):
            assert 'TEXCOORD_0' in attrs, mesh.get('name')
        triangles += j['accessors'][primitive['indices']]['count']//3
for material in j['materials']:
    if material.get('normalTexture') and material.get('pbrMetallicRoughness',{}).get('baseColorTexture'):
        pbr_count+=1
assert pbr_count>=7
manifest=json.loads((ASSETS/'build_manifest.json').read_text())
assert [manifest['width_m'],manifest['depth_m']]==[131,139]
assert manifest['rooms']==18 and manifest['corridors']==31
assert (ROOT/'blackwater_abandoned_mine.blend').is_file()
assert (ROOT/'layout.json').read_bytes()==(ASSETS/'layout.json').read_bytes()
report={'result':'PASS','mesh_assets':meshes,'triangles':triangles,'embedded_images':len(j['images']),'photographic_pbr_materials':pbr_count,'glb_bytes':len(b),'glb_sha256':hashlib.sha256(b).hexdigest(),'layout_sha256':hashlib.sha256((ASSETS/'layout.json').read_bytes()).hexdigest()}
(ROOT/'export_audit.json').write_text(json.dumps(report,indent=2))
print(json.dumps(report))
