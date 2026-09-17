"""Render the existing mine as a true orthographic ceiling cutaway.

Only the in-memory review scene is changed. The playable .blend and GLB stay intact.
Blender XY = Godot X,-Z, so north is +Y and appears at the top of the image.
"""
import bpy
import bmesh
import json
import math
import os
import time
from pathlib import Path
from mathutils import Vector

ROOT = Path(__file__).resolve().parent
OUT = ROOT.parents[1] / 'godot-game/artifacts/visual_qa/abandoned_mine/overhead'
OUT.mkdir(parents=True, exist_ok=True)
SOURCE = ROOT / 'blackwater_abandoned_mine.blend'
bpy.ops.wm.open_mainfile(filepath=str(SOURCE))
scene = bpy.context.scene
CUT_HEIGHT = 2.8
cut_objects = []
hidden_objects = []

def cut_above(obj, height):
    """Bisect locally while preserving photograph UVs and geological vertex colors."""
    obj.data = obj.data.copy()  # Linked rock instances must not modify each other.
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    inv = obj.matrix_world.inverted()
    point = inv @ Vector((0, 0, height))
    normal = obj.matrix_world.to_3x3().transposed() @ Vector((0, 0, 1))
    bmesh.ops.bisect_plane(
        bm, geom=list(bm.verts) + list(bm.edges) + list(bm.faces),
        dist=0.00001, plane_co=point, plane_no=normal.normalized(),
        clear_outer=True, clear_inner=False,
    )
    bm.to_mesh(obj.data)
    bm.free()
    obj.data.update()
    cut_objects.append(obj.name)

for obj in list(scene.objects):
    if obj.name.startswith('collision_') or obj.get('collision_only', False):
        obj.hide_render = True
        continue
    if obj.type != 'MESH':
        continue
    if obj.name.startswith(('Terrain_', 'MineralCluster_', 'CalciteCeiling_', 'RockScan_')):
        heights = [(obj.matrix_world @ Vector(p)).z for p in obj.bound_box]
        if min(heights) >= CUT_HEIGHT:
            obj.hide_render = True
            hidden_objects.append(obj.name)
        elif max(heights) > CUT_HEIGHT:
            cut_above(obj, CUT_HEIGHT)

def flat_material(name, color):
    mat = bpy.data.materials.new(name)
    mat.diffuse_color = (*color, 1)
    mat.use_nodes = True
    shader = mat.node_tree.nodes.get('Principled BSDF')
    shader.inputs['Base Color'].default_value = (*color, 1)
    shader.inputs['Roughness'].default_value = .94
    return mat

backdrop = flat_material('Overhead_UnexcavatedRock', (.024, .022, .018))
ink = flat_material('Overhead_Dimensions', (.62, .56, .42))
bpy.ops.mesh.primitive_plane_add(size=1000, location=(0, 0, -3))
bpy.context.object.name = 'Overhead_Backdrop'
bpy.context.object.data.materials.append(backdrop)

def line(name, points, width=.027):
    curve = bpy.data.curves.new(name, 'CURVE')
    curve.dimensions = '3D'
    curve.bevel_depth = width
    curve.bevel_resolution = 0
    spline = curve.splines.new('POLY')
    spline.points.add(len(points) - 1)
    for dest, src in zip(spline.points, points):
        dest.co = (*src, 1)
    obj = bpy.data.objects.new(name, curve)
    scene.collection.objects.link(obj)
    obj.data.materials.append(ink)

def label(name, body, location, size=1.7, angle=0):
    text = bpy.data.curves.new(name, 'FONT')
    text.body = body
    text.size = size
    text.align_x = 'CENTER'
    text.align_y = 'CENTER'
    obj = bpy.data.objects.new(name, text)
    scene.collection.objects.link(obj)
    obj.location = location
    obj.rotation_euler.z = angle
    obj.data.materials.append(ink)

line('Width', [(-65.5, 73, 1), (65.5, 73, 1)])
for x in (-65.5, 65.5):
    line('WidthTick', [(x, 71.9, 1), (x, 74.1, 1)])
label('WidthLabel', '131 m', (0, 75.5, 1))
line('Depth', [(70, -69.5, 1), (70, 69.5, 1)])
for y in (-69.5, 69.5):
    line('DepthTick', [(68.9, y, 1), (71.1, y, 1)])
label('DepthLabel', '139 m', (72.2, 0, 1), angle=math.pi / 2)
line('NorthStem', [(-70, 61, 1), (-70, 67, 1)], .06)
line('NorthArrow', [(-71, 65, 1), (-70, 67, 1), (-69, 65, 1)], .06)
label('NorthLabel', 'N', (-70, 69, 1), 1.8)
label('Footer', 'BLACKWATER  /  ABANDONED MINE', (0, -74.2, 1), 1.25)
label('FooterNote', 'ORTHOGRAPHIC CUTAWAY', (0, -76.4, 1), .8)

camera_data = bpy.data.cameras.new('Overhead_Orthographic')
camera_data.type = 'ORTHO'
camera_data.sensor_fit = 'HORIZONTAL'
camera_data.ortho_scale = 151
camera_data.clip_start = .1
camera_data.clip_end = 500
camera = bpy.data.objects.new('Overhead_Orthographic', camera_data)
scene.collection.objects.link(camera)
camera.location = (0, 0, 180)
camera.rotation_euler = (0, 0, 0)
scene.camera = camera

# A separate inspection lighting setup exposes the layout at map scale.
for obj in scene.objects:
    if obj.type == 'LIGHT':
        obj.hide_render = True
scene.world.use_nodes = True
background = scene.world.node_tree.nodes.get('Background')
background.inputs['Color'].default_value = (.66, .73, .82, 1)
background.inputs['Strength'].default_value = .55
sun_data = bpy.data.lights.new('Overhead_SoftDaylight', 'SUN')
sun_data.energy = 2.2
sun_data.angle = math.radians(20)
sun = bpy.data.objects.new(sun_data.name, sun_data)
scene.collection.objects.link(sun)
sun.rotation_euler = (math.radians(20), math.radians(-25), math.radians(-15))
scene.render.engine = 'CYCLES'
scene.cycles.device = 'CPU'
scene.cycles.samples = int(os.environ.get('MINE_OVERHEAD_SAMPLES', '24'))
scene.cycles.use_denoising = True
scene.cycles.max_bounces = 4
scene.cycles.diffuse_bounces = 2
scene.cycles.glossy_bounces = 2
scene.render.threads_mode = 'FIXED'
scene.render.threads = 2
scene.render.resolution_x = int(os.environ.get('MINE_OVERHEAD_WIDTH', '1900'))
scene.render.resolution_y = round(scene.render.resolution_x * 160 / 151)
scene.render.resolution_percentage = 100
scene.render.image_settings.file_format = 'PNG'
scene.render.film_transparent = False
scene.view_settings.view_transform = 'AgX'
scene.view_settings.exposure = .5
tag = os.environ.get('MINE_OVERHEAD_TAG', 'mine_overhead')
scene.render.filepath = str(OUT / (tag + '.png'))
started = time.time()
print('OVERHEAD_READY', len(cut_objects), 'cut meshes;', len(hidden_objects), 'hidden ceiling meshes', flush=True)
bpy.ops.render.render(write_still=True)
(OUT / (tag + '.json')).write_text(json.dumps({
    'source': str(SOURCE), 'source_modified': False,
    'renderer': bpy.app.version_string + ' Cycles CPU',
    'projection': 'orthographic', 'north': 'image up',
    'map_width_m': 131, 'map_depth_m': 139,
    'ceiling_cut_height_m': CUT_HEIGHT,
    'note': 'Actual Blender environment model with ceiling cut away and neutral inspection lighting. Gameplay HUD and dynamically spawned enemies are omitted.',
    'cut_meshes': len(cut_objects), 'hidden_ceiling_meshes': len(hidden_objects),
    'render_seconds': round(time.time() - started, 2),
}, indent=2))
print('OVERHEAD_COMPLETE', scene.render.filepath, flush=True)
