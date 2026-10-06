"""Render each unique frame of the final Labrador Run, without saving the source.

Mac background usage:
  blender -b --python tools/dcc/labrador_pet_sprint_frames.py -- \
    --source path/to/LabradorPet_SprintRepair.blend \
    --manifest path/to/sprint-repair-manifest.json --output path/to/export/frames
"""
import argparse
import hashlib
import json
import sys
from pathlib import Path

import bpy
from bpy_extras.object_utils import world_to_camera_view
from mathutils import Vector

sys.path.insert(0, str(Path(__file__).resolve().parent))
from labrador_pet import set_action
from labrador_pet_preview import stage

FINAL_SOURCE_SHA = '136aaccdf9817bff8479b75ddd1984139c2c13b58941361088497abc0ff646c8'
FINAL_MANIFEST_SHA = '901af882ac01ab737171132798e9a4983a2b7d73d233c66e4114f17d4218a6ef'


def sha256(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def camera_bounds(scene, camera, original_meshes):
    """Actual deformed original vertices; exclude the added floor and caption."""
    depsgraph = bpy.context.evaluated_depsgraph_get()
    low = [float('inf'), float('inf')]
    high = [float('-inf'), float('-inf')]
    count = 0
    for obj in original_meshes:
        evaluated = obj.evaluated_get(depsgraph)
        mesh = evaluated.to_mesh()
        try:
            for vertex in mesh.vertices:
                point = world_to_camera_view(scene, camera, evaluated.matrix_world @ vertex.co)
                if point.z <= 0:
                    raise RuntimeError('Original mesh vertex is behind the camera')
                for axis in (0, 1):
                    low[axis] = min(low[axis], point[axis])
                    high[axis] = max(high[axis], point[axis])
                count += 1
        finally:
            evaluated.to_mesh_clear()
    if not count or min(low) < .02 or max(high) > .98:
        raise RuntimeError(f'Dog framing is cropped: {low}, {high}, {count}')
    return {'minimum_xy': low, 'maximum_xy': high, 'deformed_vertex_count': count}


def add_caption(scene, camera):
    material = bpy.data.materials.new('RunFrameCaption')
    material.use_nodes = True
    material.node_tree.nodes.clear()
    emission = material.node_tree.nodes.new('ShaderNodeEmission')
    emission.inputs['Color'].default_value = (.018, .024, .034, 1)
    output = material.node_tree.nodes.new('ShaderNodeOutputMaterial')
    material.node_tree.links.new(emission.outputs[0], output.inputs['Surface'])
    data = bpy.data.curves.new('RunFrameCaption', 'FONT')
    data.size = .031
    data.align_x = 'CENTER'
    data.align_y = 'CENTER'
    data.materials.append(material)
    obj = bpy.data.objects.new('RunFrameCaption', data)
    scene.collection.objects.link(obj)
    obj.parent = camera
    obj.location = (0, .675, -1)
    obj.visible_shadow = False
    return data


def render(source, manifest_path, output, expected_source_sha, expected_manifest_sha):
    source_sha = sha256(source)
    manifest_sha = sha256(manifest_path)
    if source_sha != expected_source_sha or manifest_sha != expected_manifest_sha:
        raise RuntimeError('Source or animation manifest differs from the approved final version')
    if output.exists() and any(output.iterdir()):
        raise RuntimeError('Use an empty output directory; existing frame images are preserved')
    output.mkdir(parents=True, exist_ok=True)
    manifest = json.loads(manifest_path.read_text())
    spec = next(clip for clip in manifest['clips'] if clip['name'] == 'Run')
    start, repeated_end = spec['frames']
    fps = spec['fps']
    count = repeated_end - start
    if start != 1 or repeated_end != 43 or fps != 60 or count != 42:
        raise RuntimeError('The final Run must contain 42 unique frames and a repeated endpoint')

    bpy.ops.wm.open_mainfile(filepath=str(source))
    rig = bpy.data.objects[manifest['rigRoot']]
    scene = bpy.context.scene
    original_meshes = [obj for obj in scene.objects if obj.type == 'MESH' and not obj.hide_render]
    set_action(rig, bpy.data.actions['Run'])
    camera = stage(scene)
    camera.location = (2.2, .04, .68)
    camera.rotation_euler = (Vector((0, .025, .45)) - camera.location).to_track_quat('-Z', 'Y').to_euler()
    camera.data.ortho_scale = 2.30
    scene.render.resolution_x = 1280
    scene.render.resolution_y = 854
    scene.render.resolution_percentage = 100
    scene.render.fps = fps
    scene.render.fps_base = 1
    scene.eevee.taa_render_samples = 32
    scene.render.image_settings.file_format = 'PNG'
    scene.render.image_settings.color_mode = 'RGB'
    scene.render.image_settings.color_depth = '8'
    scene.render.image_settings.compression = 15
    scene.render.film_transparent = False
    if hasattr(scene.render, 'use_motion_blur'):
        scene.render.use_motion_blur = False
    if hasattr(scene.eevee, 'use_motion_blur'):
        scene.eevee.use_motion_blur = False
    caption = add_caption(scene, camera)
    frames = []
    print('LABRADOR_RUN_FRAMES_BEGIN', count, source_sha, flush=True)
    for index, source_frame in enumerate(range(start, repeated_end), start=1):
        scene.frame_set(source_frame)
        bpy.context.view_layer.update()
        time_s = (source_frame - start) / fps
        phase = (source_frame - start) / count
        caption.body = f'Run  {index:03d} / {count:03d}  |  {time_s:.3f} s'
        bounds = camera_bounds(scene, camera, original_meshes)
        path = output / f'Run_{index:03d}.png'
        scene.render.filepath = str(path)
        bpy.ops.render.render(write_still=True)
        if not path.is_file():
            raise RuntimeError(f'Frame was not written: {path}')
        frames.append({'file': str(path.relative_to(output.parent.parent)), 'index': index,
                       'source_scene_frame': source_frame, 'time_seconds': time_s,
                       'phase': phase, 'width': 1280, 'height': 854,
                       'bytes': path.stat().st_size, 'sha256': sha256(path),
                       'camera_bounds': bounds})
        print('LABRADOR_RUN_FRAME_COMPLETE', index, path.name, flush=True)
    source_unchanged = sha256(source) == source_sha
    manifest_unchanged = sha256(manifest_path) == manifest_sha
    if not source_unchanged or not manifest_unchanged:
        raise RuntimeError('Source changed during rendering')
    summary = {'status': 'Passed', 'clip': 'Run', 'source': str(source),
               'source_sha256': source_sha, 'animation_manifest': str(manifest_path),
               'animation_manifest_sha256': manifest_sha, 'manifest_sha256': manifest_sha,
               'source_unchanged': source_unchanged,
               'animation_manifest_unchanged': manifest_unchanged,
               'source_scene_frames': [start, repeated_end - 1],
               'excluded_repeated_endpoint': repeated_end,
               'frame_count': count, 'fps': fps, 'cycle_duration_seconds': count / fps,
               'duration_seconds': count / fps, 'resolution': [1280, 854],
               'render': {'blender_version': bpy.app.version_string, 'platform': 'Mac',
                          'engine': scene.render.engine, 'samples': 32,
                          'width': 1280, 'height': 854, 'motion_blur': False,
                          'camera': {'location': list(camera.location),
                                     'look_at': [0, .025, .45], 'orthographic_scale': 2.30},
                          'lighting': 'Fixed studio lights from labrador_pet_preview.stage',
                          'background': 'Neutral studio and minimal static floor'},
               'scope_ko': '최종 수정된 Run 모션의 고유 42프레임을 같은 옆면 카메라와 조명으로 렌더했습니다. 반복 끝점 43은 제외하고 원본 파일은 보존했습니다.',
               'scope_en': 'Rendered all 42 unique frames of the final repaired Run with one fixed side camera and lighting. Repeated endpoint 43 is excluded; original files are preserved.',
               'frames': frames}
    receipt = output.parent.parent / 'run-frames-render.json'
    receipt.write_text(json.dumps(summary, ensure_ascii=False, indent=2) + '\n')
    print('LABRADOR_RUN_FRAMES_COMPLETE', receipt, flush=True)


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--source', type=Path, required=True)
    parser.add_argument('--manifest', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--expected-source-sha', default=FINAL_SOURCE_SHA)
    parser.add_argument('--expected-manifest-sha', default=FINAL_MANIFEST_SHA)
    args = parser.parse_args(sys.argv[sys.argv.index('--') + 1:])
    render(args.source.resolve(), args.manifest.resolve(), args.output.resolve(),
           args.expected_source_sha, args.expected_manifest_sha)
