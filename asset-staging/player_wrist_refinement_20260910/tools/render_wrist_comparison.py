"""Render the preserved original and refined wrists with identical real Blender views."""
import argparse
import hashlib
import json
import sys
from pathlib import Path
import bpy
from mathutils import Vector

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--input-dir', type=Path, required=True)
parser.add_argument('--output-dir', type=Path, required=True)
args = parser.parse_args(sys.argv[sys.argv.index('--') + 1:])
assert bpy.app.background
source = args.input_dir.resolve() / 'bilateral_hands_articulated.blend'
output = args.output_dir.resolve()
refined = output / 'bilateral_hands_wrist_refined.blend'
assert source.is_file() and refined.is_file()
report_path = output / 'build_report.json'
report = json.loads(report_path.read_text())
settings = None
comparison = {}
for label, path, scene_name in (
    ('after', refined, 'Bilateral_Wrist_Refined_Review'),
    ('before', source, 'Bilateral_Articulated_Review'),
):
    bpy.ops.wm.open_mainfile(filepath=str(path))
    scene = bpy.data.scenes[scene_name]
    bpy.context.window.scene = scene
    left = scene.objects['LEFT_PreviewTranslationOnly']
    for obj in scene.objects:
        top = obj
        while top.parent:
            top = top.parent
        if top.name == 'RIGHT_PreviewTranslationOnly' or (obj.type == 'MESH' and 'upperarm' in obj.name.lower()):
            obj.hide_render = True
    camera = scene.camera
    center = left.matrix_world @ Vector((0, -.0444, .001))
    camera.location = center + Vector((0, 0, 1.2))
    camera.rotation_euler = (center - camera.location).to_track_quat('-Z', 'Y').to_euler()
    camera.data.ortho_scale = .205
    scene.cycles.samples = 40
    scene.render.resolution_x, scene.render.resolution_y = 1400, 1100
    scene.render.resolution_percentage = 100
    bpy.context.view_layer.update()
    actual = {'camera_world': [list(row) for row in camera.matrix_world],
              'orthographic_scale_m': camera.data.ortho_scale,
              'lights': {obj.name: {'matrix': [list(row) for row in obj.matrix_world],
                                  'energy': obj.data.energy, 'color': list(obj.data.color)}
                         for obj in scene.objects if obj.type == 'LIGHT'},
              'samples': scene.cycles.samples, 'resolution': [1400, 1100],
              'pose': 'neutral, every joint rotation and corrective morph is zero'}
    if settings is None:
        settings = actual
    else:
        assert settings == actual, 'Before and after camera/light/pose settings diverged'
    destination = output / f'wrist_dorsum_{label}.png'
    assert not destination.exists(), 'Preserve existing render'
    scene.render.filepath = str(destination)
    bpy.ops.render.render(write_still=True)
    comparison[label] = {'file': destination.name, 'source': str(path),
                          'sha256': hashlib.sha256(destination.read_bytes()).hexdigest()}
    report['outputs'][destination.name] = {'bytes': destination.stat().st_size,
                                         'sha256': comparison[label]['sha256']}
report['comparison'] = {'method': 'Two direct Blender renders; no image compositing or AI generation',
                        'identical_view_settings': settings, 'renders': comparison}
report_path.write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding='utf-8')
print('WRIST_BEFORE_AFTER_RENDER_COMPLETE', output)
