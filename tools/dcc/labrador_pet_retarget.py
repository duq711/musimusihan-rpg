"""Measured-rig BVH retarget primitives for the local Labrador production tool.

Run inside Blender. Source joint names and target bone names must be supplied
from inspected assets; this module makes no breed-specific naming assumptions.
Neutral calibration is explicit, and IK residuals are reported instead of
stretching limbs to hide unreachable targets. All coordinates use target
armature space, with one uniform source scale.
"""
from dataclasses import dataclass
from math import sqrt

import bpy
from mathutils import Matrix, Quaternion, Vector


@dataclass(frozen=True)
class BoneMap:
    source: str
    target: str
    rotation_weight: float = 1.0


def update():
    bpy.context.view_layer.update()


def pose_snapshot(rig):
    update()
    return {bone.name: bone.matrix.copy() for bone in rig.pose.bones}


def set_world_pose(bone, matrix):
    """Convert an armature-space matrix using actual parent/rest settings."""
    kwargs = {}
    if bone.parent:
        kwargs["parent_matrix"] = bone.parent.matrix
        kwargs["parent_matrix_local"] = bone.parent.bone.matrix_local
    bone.matrix_basis = bone.bone.convert_local_to_pose(
        matrix, bone.bone.matrix_local, invert=True, **kwargs)
    update()


def validate_mapping(rig, source_neutral, mapping):
    if rig.type != "ARMATURE":
        raise TypeError("Expected the inspected Labrador armature")
    target_names = [entry.target for entry in mapping]
    if len(set(target_names)) != len(target_names):
        raise ValueError("A target bone occurs more than once in the mapping")
    for entry in mapping:
        if entry.source not in source_neutral:
            raise ValueError("Missing capture joint: " + entry.source)
        if entry.target not in rig.pose.bones:
            raise ValueError("Missing Labrador bone: " + entry.target)
        if not 0 <= entry.rotation_weight <= 1:
            raise ValueError("Rotation weights must lie in [0, 1]")
        if rig.pose.bones[entry.target].constraints:
            raise ValueError("Bake target constraints before retargeting: " + entry.target)


def retarget_pose(rig, source_pose, source_neutral, target_neutral, mapping,
                  coordinate=None, root_target=None, root_source=None,
                  source_scale=1.0, in_place=True):
    """Transfer measured world rotation deltas, calibrated to a neutral pose.

    ``source_pose`` and ``source_neutral`` are unconverted BVH joint matrices.
    ``coordinate`` is a pure rotation into target armature space. Target bone
    lengths and skin transforms are retained. A separately mapped root carries
    measured vertical movement and optionally planar displacement.
    """
    coordinate = coordinate or Matrix.Identity(4)
    rotation = coordinate.to_quaternion()
    mapping = list(mapping)
    validate_mapping(rig, source_neutral, mapping)
    depth = lambda bone: len(bone.parent_recursive)
    ordered = sorted(mapping, key=lambda entry: depth(rig.pose.bones[entry.target]))
    # Reset the pose in hierarchy order so previous animation frames cannot
    # contribute a residual to an unmapped chain.
    for bone in sorted(rig.pose.bones, key=depth):
        set_world_pose(bone, target_neutral[bone.name])
    root_delta = Vector((0, 0, 0))
    if root_target:
        if root_source not in source_pose:
            raise ValueError("Missing root capture joint: " + str(root_source))
        root_delta = rotation @ (source_pose[root_source].translation - source_neutral[root_source].translation)
        root_delta *= source_scale
        if in_place:
            root_delta.x = root_delta.y = 0
    for entry in ordered:
        bone = rig.pose.bones[entry.target]
        neutral_rotation = target_neutral[entry.target].to_quaternion()
        source_delta = source_pose[entry.source].to_quaternion() @ source_neutral[entry.source].to_quaternion().inverted()
        delta = rotation @ source_delta @ rotation.inverted()
        delta = Quaternion((1, 0, 0, 0)).slerp(delta, entry.rotation_weight)
        desired = Matrix.LocRotScale(bone.matrix.translation, delta @ neutral_rotation,
                                    target_neutral[entry.target].to_scale())
        if entry.target == root_target:
            desired.translation = target_neutral[entry.target].translation + root_delta
        set_world_pose(bone, desired)
    if root_target and root_target not in {entry.target for entry in mapping}:
        bone = rig.pose.bones[root_target]
        desired = bone.matrix.copy()
        desired.translation = target_neutral[root_target].translation + root_delta
        set_world_pose(bone, desired)


def _aim(reference, old_vector, new_vector, head):
    if min(old_vector.length, new_vector.length) < 1e-9:
        raise ValueError("Cannot aim a zero-length limb segment")
    swing = old_vector.normalized().rotation_difference(new_vector.normalized())
    matrix = (swing.to_matrix() @ reference.to_3x3()).to_4x4()
    matrix.translation = head
    return matrix


def solve_two_bone(rig, names, goal, pole_point, reference=None):
    """Fit a measured ankle target without changing any limb segment length.

    ``names`` are inspected upper/lower/foot target bones in direct hierarchy.
    The returned unreachable/contact residual must be included in production QA.
    It is never silently converted into a passing contact result.
    """
    upper, lower, foot = [rig.pose.bones[name] for name in names]
    if lower.parent != upper or foot.parent != lower:
        raise ValueError("Two-bone chain does not match the inspected hierarchy")
    update()
    reference = reference or {bone.name: bone.matrix.copy() for bone in (upper, lower, foot)}
    a = upper.matrix.translation.copy()
    ref_upper = reference[upper.name]; ref_lower = reference[lower.name]
    uv = ref_lower.translation - ref_upper.translation
    lv = reference[foot.name].translation - ref_lower.translation
    l1, l2 = uv.length, lv.length
    if min(l1, l2) < 1e-9:
        raise ValueError("Two-bone chain has a zero-length segment")
    requested = Vector(goal); axis = requested - a
    requested_distance = axis.length
    if requested_distance < 1e-9:
        axis = uv + lv
    axis.normalize()
    distance = max(1e-8, min(max(requested_distance, abs(l1-l2)), l1+l2))
    actual = a + axis * distance
    pole = Vector(pole_point) - a
    pole -= axis * pole.dot(axis)
    if pole.length < 1e-9:
        pole = ref_lower.translation - a
        pole -= axis * pole.dot(axis)
    if pole.length < 1e-9:
        raise ValueError("Measured knee pole is collinear with the ankle target")
    pole.normalize()
    along = (l1*l1-l2*l2+distance*distance)/(2*distance)
    knee = a + axis*along + pole*sqrt(max(0, l1*l1-along*along))
    set_world_pose(upper, _aim(ref_upper, uv, knee-a, a))
    set_world_pose(lower, _aim(ref_lower, lv, actual-knee, knee))
    foot_matrix = reference[foot.name].copy(); foot_matrix.translation = actual
    set_world_pose(foot, foot_matrix)
    update()
    residual = (foot.matrix.translation-requested).length
    return {
        "reachable": residual <= 1e-5, "residual": residual,
        "requested": list(requested), "actual": list(foot.matrix.translation),
        "segment_error": max(abs((lower.matrix.translation-upper.matrix.translation).length-l1),
                             abs((foot.matrix.translation-lower.matrix.translation).length-l2)),
    }
