"""Measure preserved forearm body and wrist-edge protrusions in saved Blender data."""
import argparse
import json
import math
import sys
from pathlib import Path
import bpy
from mathutils import Vector
from mathutils.bvhtree import BVHTree
sys.path.insert(0, str(Path(__file__).resolve().parent))
from wrist_geometry import native_points, radial_hit
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--input-dir', type=Path, required=True)
parser.add_argument('--output-dir', type=Path, required=True)
args = parser.parse_args(sys.argv[sys.argv.index('--') + 1:])
assert bpy.app.background
output = args.output_dir.resolve()
report_path = output / 'build_report.json'
report = json.loads(report_path.read_text())
bpy.ops.wm.open_mainfile(filepath=str(args.input_dir.resolve() / 'bilateral_hands_articulated.blend'))
scene = bpy.data.scenes['Bilateral_Articulated_Review']; bpy.context.window.scene = scene
source = {}
for side in ('left', 'right'):
    holder = scene.objects[side.upper() + '_PreviewTranslationOnly']
    arm = scene.objects[next(name for name in report['hands'][side]['source_bounds'] if 'forearm' in name.lower())]
    source[side] = native_points(arm, holder)
bpy.ops.wm.open_mainfile(filepath=str(output / 'bilateral_hands_wrist_refined.blend'))
scene = bpy.data.scenes['Bilateral_Wrist_Refined_Review']; bpy.context.window.scene = scene
for side in ('left', 'right'):
    hand = report['hands'][side]
    holder = scene.objects[side.upper() + '_PreviewTranslationOnly']
    arm = scene.objects[next(name for name in hand['source_bounds'] if 'forearm' in name.lower())]
    actual = native_points(arm, holder)
    preserved = [i for i, point in enumerate(source[side]) if -point.y >= .100]
    error = max(((actual[i] - source[side][i]).length for i in preserved), default=0)
    assert error == 0.0
    changed = hand['forearm_refinement']['changed_vertex_indices']
    hand['forearm_refinement'].update({'changed_vertices': len(changed), 'preserved_vertices': len(preserved),
        'preserved_z_ge_100mm_max_error_m': error,
        'maximum_displacement_m': max((actual[i] - source[side][i]).length for i in changed)})
    skin, cuff = scene.objects[hand['skin_object']], scene.objects[hand['cuff_object']]
    tree = BVHTree.FromPolygons(native_points(cuff, holder), [list(p.vertices) for p in cuff.data.polygons])
    protrusions, gaps = [], []
    for vertex, point in zip(skin.data.vertices, native_points(skin, holder)):
        if -.0208 < point.y < -.0108:
            hit = radial_hit(tree, point.y, math.atan2(point.z - .001, point.x))
            assert hit is not None
            gap = Vector((point.x, 0, point.z - .001)).length - hit[3]
            gaps.append(gap)
            if gap > .00025:
                protrusions.append({'index': vertex.index, 'outward_gap_m': gap})
    hand['saved_mesh_audit'] = {'method': 'Radial comparison to actual cuff mesh over original terminal skin cut band',
        'sample_count': len(gaps), 'protrusions_over_0_25mm': protrusions,
        'maximum_outward_gap_m': max(gaps), 'forearm_preservation_samples': len(preserved)}
    assert not protrusions, f'{side} retains wrist-edge protrusions'
    print(side, 'forearm preserved', len(preserved), 'error', error, 'protrusions', len(protrusions), 'sampled', len(gaps))
report_path.write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding='utf-8')
