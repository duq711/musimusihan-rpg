"""Contact preservation for the downloaded RetroStyle German Shepherd rig.

Run inside Blender. All matrices, positions, offsets and errors use armature
space (centimetres in this source); the armature object's 0.01 scale is untouched.
This module adds no constraints, changes no rest bones, saves no blend, and never
stretches a chain to disguise an unreachable target.

    contacts = capture_contacts(rig, use_rest=True)
    # Apply the body pose, then update the dependency graph.
    contacts["hind.L"]["offset"] = (0, -10, 0)  # forward is -Y
    result = apply_contacts(rig, contacts)

Capture evaluated source poses with use_rest=False before applying overlays to
preserve a gait's own stance. Do not pin swing feet; pass only contacting limbs.
"""

from math import sqrt

import bpy
from mathutils import Matrix, Vector


CHAINS = {
    "front.L": ("DEF-front_thigh.L", "DEF-front_shin.L", "DEF-front_foot.L", "DEF-front_toe.L"),
    "front.R": ("DEF-front_thigh.R", "DEF-front_shin.R", "DEF-front_foot.R", "DEF-front_toe.R"),
    "hind.L": ("DEF-thigh.L", "DEF-shin.L", "DEF-foot.L", "DEF-toe.L"),
    "hind.R": ("DEF-thigh.R", "DEF-shin.R", "DEF-foot.R", "DEF-toe.R"),
}
_EPSILON = 1e-8


def _update():
    bpy.context.view_layer.update()


def _validate_rig(rig):
    if rig.type != "ARMATURE":
        raise TypeError("Expected an armature object")
    missing = [name for names in CHAINS.values() for name in names if name not in rig.pose.bones]
    if missing:
        raise ValueError("Missing Shepherd bones: " + ", ".join(missing))
    for names in CHAINS.values():
        for parent_name, child_name in zip(names, names[1:]):
            if rig.pose.bones[child_name].parent != rig.pose.bones[parent_name]:
                raise ValueError("Unexpected hierarchy: " + child_name)
        for name in names:
            if rig.pose.bones[name].constraints:
                raise ValueError("Bake/remove existing constraints before contact solve: " + name)


def _project_perpendicular(vector, axis):
    return vector - axis * vector.dot(axis)


def _reference_pole(a, b, c, fallback):
    axis = c - a
    if axis.length < _EPSILON:
        axis = Vector((0, 0, -1))
    axis.normalize()
    pole = _project_perpendicular(b - a, axis)
    if pole.length < _EPSILON:
        pole = _project_perpendicular(fallback, axis)
    if pole.length < _EPSILON:
        pole = _project_perpendicular(Vector((0, 1, 0)), axis)
    if pole.length < _EPSILON:
        pole = _project_perpendicular(Vector((1, 0, 0)), axis)
    return pole.normalized()


def capture_contacts(rig, use_rest=False, limbs=None):
    """Return independent contact dictionaries; copies can be edited per frame.

    foot/toe matrices are in armature space. Optional target fields are:
      offset: (x,y,z), added to foot and toe translations together;
      pole: bend-side direction, projected perpendicular to the target axis;
      pole_point: absolute armature-space point overriding pole.
    upper/lower reference matrices and vectors preserve source bone roll.
    """
    _validate_rig(rig)
    _update()
    result = {}
    for limb in limbs or CHAINS:
        names = CHAINS[limb]
        bones = [rig.pose.bones[name] for name in names]
        matrices = [bone.bone.matrix_local.copy() if use_rest else bone.matrix.copy() for bone in bones]
        a, b, c = [matrix.translation for matrix in matrices[:3]]
        upper_vector, lower_vector = b - a, c - b
        if min(upper_vector.length, lower_vector.length) < _EPSILON:
            raise ValueError("Zero-length chain: " + limb)
        result[limb] = {
            "foot": matrices[2],
            "toe": matrices[3],
            "upper_reference": matrices[0],
            "lower_reference": matrices[1],
            "upper_vector": upper_vector,
            "lower_vector": lower_vector,
            "pole": _reference_pole(a, b, c, matrices[0].to_3x3().col[0]),
        }
    return result


def _set_armature_matrix(pose_bone, matrix):
    """Respect Blender local-location and inherit-scale options, parent first."""
    kwargs = {}
    if pose_bone.parent:
        kwargs["parent_matrix"] = pose_bone.parent.matrix
        kwargs["parent_matrix_local"] = pose_bone.parent.bone.matrix_local
    pose_bone.matrix_basis = pose_bone.bone.convert_local_to_pose(
        matrix, pose_bone.bone.matrix_local, invert=True, **kwargs
    )
    _update()


def _aim_reference(reference, reference_vector, desired_vector, head):
    """Minimal swing preserves the captured bone's twist and scale."""
    swing = reference_vector.normalized().rotation_difference(desired_vector.normalized())
    matrix = (swing.to_matrix() @ reference.to_3x3()).to_4x4()
    matrix.translation = head
    return matrix


def _matrix_orientation_error(a, b):
    return a.to_quaternion().rotation_difference(b.to_quaternion()).angle


def apply_contacts(rig, targets):
    """Solve selected two-bone chains after body changes, without stretching.

    Call with dictionaries from capture_contacts. For bare foot/toe matrices,
    omitted reference fields default to the rest rig. Root/body are not modified.
    The upper bone head follows the current shoulder/pelvis parent. Unreachable
    targets use the nearest reachable ankle and shift foot and toe by the same
    residual, preserving their relative pose and avoiding disconnected skin.

    Reports include requested/actual ankle positions, reach residual, actual
    contact error, segment length error and foot/toe orientation error. A report
    marked unreachable is not a contact validation pass.
    """
    _validate_rig(rig)
    _update()
    rest = capture_contacts(rig, use_rest=True, limbs=targets.keys())
    reports = {}
    for limb, supplied in targets.items():
        target = dict(rest[limb])
        target.update(supplied)
        upper, lower, foot, toe = [rig.pose.bones[name] for name in CHAINS[limb]]
        a = upper.matrix.translation.copy()
        foot_goal, toe_goal = Matrix(target["foot"]).copy(), Matrix(target["toe"]).copy()
        offset = Vector(target.get("offset", (0, 0, 0)))
        foot_goal.translation += offset
        toe_goal.translation += offset
        requested = foot_goal.translation.copy()
        uv, lv = Vector(target["upper_vector"]), Vector(target["lower_vector"])
        l1, l2 = uv.length, lv.length
        if min(l1, l2) < _EPSILON:
            raise ValueError("Zero-length chain: " + limb)
        axis = requested - a
        requested_distance = axis.length
        if requested_distance < _EPSILON:
            axis = uv + lv
            if axis.length < _EPSILON:
                axis = Vector((0, 0, -1))
        axis.normalize()
        minimum, maximum = abs(l1 - l2), l1 + l2
        distance = min(max(requested_distance, minimum), maximum)
        # Equal segment lengths can fold onto their shared root. A tiny numerical
        # interval avoids division by zero and is reported as residual.
        distance = max(distance, _EPSILON)
        actual = a + axis * distance
        along = (l1 * l1 - l2 * l2 + distance * distance) / (2 * distance)
        height = sqrt(max(l1 * l1 - along * along, 0.0))
        raw_pole = Vector(target["pole_point"]) - a if "pole_point" in target else Vector(target["pole"])
        pole = _project_perpendicular(raw_pole, axis)
        if pole.length < _EPSILON:
            pole = _project_perpendicular(Vector(rest[limb]["pole"]), axis)
        if pole.length < _EPSILON:
            pole = _reference_pole(a, a + uv, actual, upper.bone.matrix_local.to_3x3().col[0])
        pole.normalize()
        knee = a + axis * along + pole * height
        _set_armature_matrix(upper, _aim_reference(Matrix(target["upper_reference"]), uv, knee - a, a))
        _set_armature_matrix(lower, _aim_reference(Matrix(target["lower_reference"]), lv, actual - knee, knee))
        residual = actual - requested
        solved_foot, solved_toe = foot_goal.copy(), toe_goal.copy()
        solved_foot.translation += residual
        solved_toe.translation += residual
        _set_armature_matrix(foot, solved_foot)
        _set_armature_matrix(toe, solved_toe)
        final_a, final_b, final_c = upper.matrix.translation, lower.matrix.translation, foot.matrix.translation
        actual_contact_error = (final_c - requested).length
        reports[limb] = {
            "reachable": residual.length <= 1e-5,
            "requested_ankle_cm": list(requested),
            "actual_ankle_cm": list(final_c),
            "reach_residual_cm": residual.length,
            "contact_error_cm": actual_contact_error,
            "toe_contact_error_cm": (toe.matrix.translation - toe_goal.translation).length,
            "segment_length_error_cm": max(abs((final_b - final_a).length - l1), abs((final_c - final_b).length - l2)),
            "foot_orientation_error_radians": _matrix_orientation_error(foot.matrix, foot_goal),
            "toe_orientation_error_radians": _matrix_orientation_error(toe.matrix, toe_goal),
            "bone_names": list(CHAINS[limb]),
        }
    return reports


def contact_bones(limbs=None):
    """Names whose location/rotation/scale must be keyed after each solve."""
    return [bone for limb in limbs or CHAINS for bone in CHAINS[limb]]
