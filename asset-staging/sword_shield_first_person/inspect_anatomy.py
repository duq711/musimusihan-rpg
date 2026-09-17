import bpy, json
from pathlib import Path
root = Path(__file__).resolve().parents[2]
source = root / 'asset-staging/blender_mercenary_crossbowman_photoreal/resources/human-base-meshes-bundle-v1.4.1/human_base_meshes_bundle.blend'
bpy.ops.wm.read_factory_settings(use_empty=True)
with bpy.data.libraries.load(str(source), link=False) as (src, dst):
    print('ANATOMY_COLLECTIONS', json.dumps(src.collections))
    print('ANATOMY_OBJECTS', json.dumps([n for n in src.objects if 'hand' in n.lower()]))
    dst.collections = ['Body Male - Realistic']
report = []
for loaded in dst.collections:
    if not loaded: continue
    bpy.context.scene.collection.children.link(loaded)
    for obj in loaded.all_objects:
        row = {'name': obj.name, 'type': obj.type}
        if obj.type == 'MESH':
            points = [obj.matrix_world @ v.co for v in obj.data.vertices]
            row.update(vertices=len(points), min=[min(p[i] for p in points) for i in range(3)], max=[max(p[i] for p in points) for i in range(3)], groups=[g.name for g in obj.vertex_groups])
        if obj.type == 'ARMATURE':
            row['bones'] = {b.name: {'head':list(b.head_local),'tail':list(b.tail_local)} for b in obj.data.bones}
        report.append(row)
print('ANATOMY_REPORT', json.dumps(report))
(Path(__file__).parent/'anatomy_report.json').write_text(json.dumps(report, indent=2))
bpy.ops.wm.save_as_mainfile(filepath=str(Path(__file__).parent/'anatomy_source.blend'))
