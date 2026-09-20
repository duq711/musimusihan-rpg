"""Close the missing shoulder cloth between the existing front and rear mantle."""
import bpy
import bmesh
import hashlib
import importlib.util
import json
from pathlib import Path

import numpy as np

WORK = Path(__file__).resolve().parent
ROOT = WORK.parents[1]
SOURCE = ROOT / 'asset-staging/player_hood_redesign_20260921/Gravebound_Rebuilt_Hood.blend'
bpy.ops.wm.open_mainfile(filepath=str(SOURCE))
original_objects = list(bpy.data.objects)
mantle = bpy.data.objects['Gravebound_MantleBack']


def signature(obj):
    payload = {
        'vertices': [list(v.co) for v in obj.data.vertices],
        'faces': [list(f.vertices) for f in obj.data.polygons],
        'uv': [[list(v.uv) for v in layer.data] for layer in obj.data.uv_layers],
        'matrix': [list(row) for row in obj.matrix_world],
    }
    return hashlib.sha256(json.dumps(payload, sort_keys=True).encode()).hexdigest()


preserved = {o.name: signature(o) for o in original_objects if o.type == 'MESH' and o != mantle}
spec = importlib.util.spec_from_file_location('shoulder_geometry', WORK / 'geometry.py')
geometry = importlib.util.module_from_spec(spec)
spec.loader.exec_module(geometry)
bridges = geometry.create_bridges()
assert len(bridges) == 2
bpy.ops.object.select_all(action='DESELECT')
for obj in bridges:
    obj.select_set(True)
bpy.context.view_layer.objects.active = bridges[0]
bpy.ops.object.join()
bridge = bpy.context.object
bridge.name = 'ShoulderClothBake'

outer = bpy.data.materials.new('ShoulderClothBake')
outer.use_nodes = True
inner = bpy.data.materials.new('ShoulderLiningBake')
inner.use_nodes = True
bridge.data.materials.clear()
bridge.data.materials.append(outer)
bridge.data.materials.append(inner)
solid = bridge.modifiers.new('SewnClothThickness', 'SOLIDIFY')
solid.thickness = .004
solid.offset = -1
solid.use_even_offset = True
solid.material_offset = 1
solid.material_offset_rim = 0
bpy.ops.object.modifier_apply(modifier=solid.name)
for polygon in bridge.data.polygons:
    polygon.use_smooth = True

# Reuse the outfit's cloth reference, with seamless scale on the connecting fabric.
reference = bpy.data.images.load(str(ROOT / 'concept-art/player_gravebound/concept_back.png'), check_existing=True)
pixels = np.array(reference.pixels[:], dtype=np.float32).reshape(reference.size[1], reference.size[0], 4)
patch = pixels[reference.size[1] - 390:reference.size[1] - 320, 438:590].copy()
row = np.concatenate([patch, patch[:, ::-1]], axis=1)
tile = np.concatenate([row, row[::-1]], axis=0)
cloth = bpy.data.images.new('Shoulder_Cloth_Source', width=tile.shape[1], height=tile.shape[0], alpha=False)
cloth.pixels.foreach_set(tile.ravel())
cloth.pack()
nodes = outer.node_tree.nodes
links = outer.node_tree.links
nodes.clear()
out = nodes.new('ShaderNodeOutputMaterial')
emission = nodes.new('ShaderNodeEmission')
links.new(emission.outputs[0], out.inputs['Surface'])
coords = nodes.new('ShaderNodeTexCoord')
scale = nodes.new('ShaderNodeVectorMath')
scale.operation = 'MULTIPLY'
scale.inputs[1].default_value = (3.4, 1.8, 1.8)
links.new(coords.outputs['Generated'], scale.inputs[0])
texture = nodes.new('ShaderNodeTexImage')
texture.image = cloth
texture.projection = 'BOX'
texture.projection_blend = .35
texture.extension = 'REPEAT'
links.new(scale.outputs[0], texture.inputs['Vector'])
links.new(texture.outputs['Color'], emission.inputs['Color'])
nodes = inner.node_tree.nodes
nodes.clear()
out = nodes.new('ShaderNodeOutputMaterial')
emission = nodes.new('ShaderNodeEmission')
emission.inputs[0].default_value = (.010, .011, .013, 1)
inner.node_tree.links.new(emission.outputs[0], out.inputs['Surface'])

mesh = bridge.data
mesh.uv_layers.new(name='UVMap')
mesh.uv_layers.active_index = 0
mesh.uv_layers[0].active_render = True
bpy.ops.object.mode_set(mode='EDIT')
bpy.ops.mesh.select_all(action='SELECT')
bpy.ops.uv.smart_project(angle_limit=1.12, island_margin=.025, area_weight=.5)
bpy.ops.object.mode_set(mode='OBJECT')
atlas = bpy.data.images.new('Gravebound_Shoulder_Cloth_Albedo', width=2048, height=2048, alpha=False)
for material in (outer, inner):
    target = material.node_tree.nodes.new('ShaderNodeTexImage')
    target.image = atlas
    material.node_tree.nodes.active = target
scene = bpy.context.scene
scene.render.engine = 'CYCLES'
scene.cycles.samples = 1
scene.render.bake.use_clear = True
scene.render.bake.margin = 12
scene.render.bake.use_selected_to_active = False
bpy.ops.object.bake(type='EMIT')
atlas.filepath_raw = str(WORK / 'Gravebound_Shoulder_Cloth_Albedo.png')
atlas.file_format = 'PNG'
atlas.save()
atlas.pack()
material = bpy.data.materials.new('Gravebound_Shoulder_Cloth')
material.use_nodes = True
principled = material.node_tree.nodes.get('Principled BSDF')
principled.inputs['Roughness'].default_value = .92
principled.inputs['Specular IOR Level'].default_value = .25
texture = material.node_tree.nodes.new('ShaderNodeTexImage')
texture.image = atlas
material.node_tree.links.new(texture.outputs['Color'], principled.inputs['Base Color'])
mesh.materials.clear()
mesh.materials.append(material)
for polygon in mesh.polygons:
    polygon.material_index = 0
bm = bmesh.new()
bm.from_mesh(mesh)
boundary_edges = sum(e.is_boundary for e in bm.edges)
nonmanifold_edges = sum(not e.is_manifold for e in bm.edges)
bm.free()
assert boundary_edges == 0 and nonmanifold_edges == 0
bridge_vertices = len(mesh.vertices)

# Keep the established 28-node model contract and all original mantle geometry.
# Matching UV-layer names is essential when joining the new material surface.
assert len(mantle.data.uv_layers) == 1
mesh.uv_layers[0].name = mantle.data.uv_layers[0].name
previous_mantle_vertices = len(mantle.data.vertices)
bpy.ops.object.select_all(action='DESELECT')
bridge.select_set(True)
mantle.select_set(True)
bpy.context.view_layer.objects.active = mantle
bpy.ops.object.join()
assert len(mantle.data.uv_layers) == 1
assert preserved == {o.name: signature(o) for o in original_objects if o.type == 'MESH' and o != mantle}
assert sum(o.type == 'MESH' for o in bpy.data.objects) == 28
bpy.ops.object.select_all(action='DESELECT')
for obj in original_objects:
    obj.select_set(True)
bpy.context.view_layer.objects.active = bpy.data.objects['GraveboundPlayer']
bpy.data.orphans_purge(do_recursive=True)
blend = WORK / 'Gravebound_Closed_Shoulder_Hood.blend'
bpy.ops.wm.save_as_mainfile(filepath=str(blend), compress=True)
output = WORK / 'gravebound_player_closed_shoulder_hood.glb'
bpy.ops.export_scene.gltf(filepath=str(output), export_format='GLB', use_selection=True,
                          export_animations=False, export_skins=False, export_extras=True,
                          export_tangents=True, export_yup=True)
report = {
    'source_sha256': hashlib.sha256(SOURCE.read_bytes()).hexdigest(),
    'output_sha256': hashlib.sha256(output.read_bytes()).hexdigest(),
    'other_27_meshes_unchanged': True,
    'original_mantle_vertices': previous_mantle_vertices,
    'added_bridge_vertices': bridge_vertices,
    'bridge_boundary_edges': boundary_edges,
    'bridge_nonmanifold_edges': nonmanifold_edges,
    'cloth_thickness_m': .004,
    'mesh_count': 28,
}
(WORK / 'build_report.json').write_text(json.dumps(report, indent=2))
print('SHOULDER CLOSURE BUILD PASS', json.dumps(report))
