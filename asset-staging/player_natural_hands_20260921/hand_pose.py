"""Relax only the baked third-person hands with the original FP skin weights.

Run apply_hand_pose() in the loaded matching-sleeve production scene. No files
are exported and the first-person rig, sleeve meshes, UVs and materials stay put.
"""
import math
from pathlib import Path
import json
import bpy
from mathutils import Matrix, Vector, Quaternion

ROOT = Path(__file__).resolve().parents[2]
G = Matrix(((1,0,0,0),(0,0,-1,0),(0,1,0,0),(0,0,0,1)))
DIGITS = ('little','ring','middle','index','thumb')
BASE_GRIP = .12  # export_pose.gd: set_relaxed_pose(.25)
# Slightly different flexion makes the fingers settle into a soft arc.
GRIPS = {'index': .23, 'middle': .27, 'ring': .29, 'little': .31, 'thumb': .20}
PALM_CUP_DEGREES = 5.0


def _angles(digit, amount):
    lo, hi = ((-.12,-.25,-.22),(.30,.35,.48)) if digit=='thumb' else ((-.48,-.82,-.48),(.48,.42,.32))
    return [a+(b-a)*amount for a,b in zip(lo,hi)]


def apply_hand_pose(root=None):
    global ROOT
    if root is not None:
        ROOT = Path(root)
    pose = json.loads((ROOT/'asset-staging/player_fullbody_fp_arms_20260920/pose.json').read_text())
    rig_info = json.loads((ROOT/'godot-game/assets/3d/player/fp_arms/rig.json').read_text())
    report = {'method':'original joint weights; per-digit relaxed curl; 5 degree ulnar palm cup',
              'grips': GRIPS, 'palm_cup_degrees': PALM_CUP_DEGREES, 'sides': {}}
    originals = list(bpy.data.objects)
    sleeve_vertices = {o.name:[v.co.copy() for v in o.data.vertices] for o in originals
                       if o.type=='MESH' and o.name.startswith('Gravebound_FP_') and o.name.endswith('_Arm')}
    for side in ('L','R'):
        sign = -1 if side=='L' else 1
        target = bpy.data.objects['Gravebound_FP_'+side+'_Hand']
        original_coordinates = [target.matrix_world@v.co for v in target.data.vertices]
        old_objects = set(bpy.data.objects)
        source = ROOT/'godot-game/assets/3d/player/fp_arms'/('left.glb' if side=='L' else 'right.glb')
        bpy.ops.import_scene.gltf(filepath=str(source))
        imported = [o for o in bpy.data.objects if o not in old_objects]
        rig = next(o for o in imported if o.type=='ARMATURE')
        hand = next(o for o in imported if o.type=='MESH' and '_Hand' in o.name)
        old_pose = {k:Matrix(v) for k,v in pose[side]['bones'].items()}
        rest = {k:Matrix(v) for k,v in pose[side]['rest'].items()}
        roots = G@Matrix(pose[side]['root'])@G.inverted()
        wrist = Vector((sign*.31,.075,.94))
        def fit(v):
            v = wrist+(v-wrist)*.82
            v.x -= sign*.02
            v.z -= .07
            return v
        def evaluate(global_pose):
            for bone in rig.pose.bones:
                bone.matrix = G@global_pose[bone.name]@rest[bone.name].inverted()@G.inverted()@bone.bone.matrix_local
                bpy.context.view_layer.update()
            dg = bpy.context.evaluated_depsgraph_get()
            evaluated = bpy.data.meshes.new_from_object(hand.evaluated_get(dg),preserve_all_data_layers=True,depsgraph=dg)
            evaluated.transform(roots@hand.matrix_world)
            positions = [fit(v.co) for v in evaluated.vertices]
            bpy.data.meshes.remove(evaluated)
            return positions
        baseline = evaluate(old_pose)
        assert len(baseline)==len(original_coordinates), (side,'Vertex mapping changed')
        source_error = max((a-b).length for a,b in zip(baseline,original_coordinates))
        assert source_error < 1e-6, (side,'Current hand no longer matches original pose',source_error)
        # Work in the canonical Godot skeleton space. Retain each bone's original
        # parent-relative origin and basis, adding only a hinge-angle delta.
        # This avoids changing canonical rest transforms or baking an approximation.
        new_pose = {}
        for bone in rig.data.bones:
            key = bone.name
            parent = bone.parent.name if bone.parent else None
            local = old_pose[parent].inverted()@old_pose[key] if parent else old_pose[key].copy()
            digit = next((d for d in DIGITS if key in (d+'0',d+'1',d+'2')),None)
            if digit:
                joint = int(key[-1])
                old_amount = BASE_GRIP*(.92 if digit=='index' else 1.0)
                delta = _angles(digit,GRIPS[digit])[joint]-_angles(digit,old_amount)[joint]
                axis = (rest[key].to_3x3().inverted()@Vector(rig_info['sides'][side]['hinges'][key])).normalized()
                local = local@Quaternion(axis,delta).to_matrix().to_4x4()
            elif key=='palm':
                # Palm-facing fold about its lengthwise axis. Mirrored axes keep
                # the left/right ulnar edges folding in the same anatomical way.
                axis = (rest[key].to_3x3().inverted()@Vector((0,0,-sign))).normalized()
                local = local@Quaternion(axis,math.radians(PALM_CUP_DEGREES)).to_matrix().to_4x4()
            new_pose[key] = new_pose[parent]@local if parent else local
        relaxed = evaluate(new_pose)
        # The original palm weights reach faintly into the upper glove cuff.
        # Anchor that attachment exactly, fading only its sub-millimetre rig
        # displacement in the cuff. Fingers and palm use the full bone result.
        for i,(position,old_position) in enumerate(zip(relaxed,original_coordinates)):
            cuff_weight = max(0.0,min(1.0,(.86-old_position.z)/.025))
            cuff_weight = cuff_weight*cuff_weight*(3.0-2.0*cuff_weight)
            relaxed[i] = old_position+(position-old_position)*cuff_weight
        displacement = [(a-b).length for a,b in zip(relaxed,original_coordinates)]
        # Audit the fixed upper cuff before writing any production vertices.
        seam_indices = [i for i,p in enumerate(original_coordinates) if p.z>=.86]
        seam_error = max(displacement[i] for i in seam_indices)
        assert seam_error<1e-6, (side,'Wrist seam moved',seam_error)
        inverse = target.matrix_world.inverted()
        for vertex,position,old_position in zip(target.data.vertices,relaxed,original_coordinates):
            # Preserve numerically identical wrist/cuff coordinates exactly.
            vertex.co = inverse@(old_position if (position-old_position).length<1e-6 else position)
        target.data.update()
        if target.data.has_custom_normals:
            target.data.normals_split_custom_set_from_vertices([v.normal for v in target.data.vertices])
        report['sides'][side] = {'vertex_count':len(baseline),'source_reconstruction_error_m':source_error,
            'maximum_displacement_m':max(displacement),'changed_vertices':sum(d>=1e-6 for d in displacement),
            'wrist_seam_vertices':len(seam_indices),'wrist_seam_maximum_displacement_m':seam_error,
            'wrist':list(fit((G@Matrix(pose[side]['root'])@old_pose['wrist']).translation))}
        for obj in imported:
            bpy.data.objects.remove(obj,do_unlink=True)
    for name,coordinates in sleeve_vertices.items():
        obj = bpy.data.objects[name]
        assert all((v.co-p).length==0.0 for v,p in zip(obj.data.vertices,coordinates)), name
    report['sleeves_unchanged'] = True
    return report
