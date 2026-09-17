#!/usr/bin/env python3
"""Normalize and render a downloaded image-to-3D GLB for visual QA."""

from __future__ import annotations

import math
import sys
from pathlib import Path

import bpy
from mathutils import Vector


def look_at(obj: bpy.types.Object, target: Vector) -> None:
    obj.rotation_euler = (target - obj.location).to_track_quat("-Z", "Y").to_euler()


def world_bounds(objects: list[bpy.types.Object]) -> tuple[Vector, Vector]:
    points = [obj.matrix_world @ Vector(corner) for obj in objects for corner in obj.bound_box]
    return (
        Vector((min(p.x for p in points), min(p.y for p in points), min(p.z for p in points))),
        Vector((max(p.x for p in points), max(p.y for p in points), max(p.z for p in points))),
    )


def main() -> None:
    args = sys.argv[sys.argv.index("--") + 1 :]
    source = Path(args[0]).resolve()
    output = Path(args[1]).resolve()
    output.mkdir(parents=True, exist_ok=True)

    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)
    bpy.ops.import_scene.gltf(filepath=str(source))
    meshes = [obj for obj in bpy.context.scene.objects if obj.type == "MESH"]
    lower, upper = world_bounds(meshes)
    center = (lower + upper) * 0.5
    scale = 1.78 / max(1e-5, upper.z - lower.z)
    root = bpy.data.objects.new("QA_Root", None)
    bpy.context.scene.collection.objects.link(root)
    for obj in meshes:
        world = obj.matrix_world.copy()
        obj.parent = root
        obj.matrix_world = world
    root.scale = (scale, scale, scale)
    root.location = Vector((-center.x * scale, -center.y * scale, -lower.z * scale))
    bpy.context.view_layer.update()

    scene = bpy.context.scene
    scene.render.engine = "BLENDER_EEVEE"
    scene.render.resolution_x = 900
    scene.render.resolution_y = 1100
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    scene.render.film_transparent = False
    scene.world.color = (0.018, 0.018, 0.022)

    bpy.ops.mesh.primitive_plane_add(size=8, location=(0, 0, -0.012))
    floor = bpy.context.object
    mat = bpy.data.materials.new("QA_Floor")
    mat.diffuse_color = (0.055, 0.050, 0.047, 1)
    floor.data.materials.append(mat)

    for name, location, energy, size, color in (
        ("Key", (-2.4, -3.0, 3.2), 1300, 2.2, (1.0, 0.84, 0.70)),
        ("Fill", (2.6, -1.5, 2.4), 850, 2.0, (0.68, 0.80, 1.0)),
        ("Rim", (0.0, 2.4, 3.1), 1050, 1.8, (0.80, 0.86, 1.0)),
    ):
        data = bpy.data.lights.new(name, "AREA")
        data.energy = energy
        data.shape = "DISK"
        data.size = size
        data.color = color
        lamp = bpy.data.objects.new(name, data)
        scene.collection.objects.link(lamp)
        lamp.location = location
        look_at(lamp, Vector((0, 0, 0.95)))

    camera_data = bpy.data.cameras.new("QA_Camera")
    camera = bpy.data.objects.new("QA_Camera", camera_data)
    scene.collection.objects.link(camera)
    scene.camera = camera
    camera_data.type = "ORTHO"
    camera_data.ortho_scale = 2.02
    target = Vector((0.0, 0.0, 0.88))
    views = {
        "front": Vector((0.0, -4.0, 0.92)),
        "back": Vector((0.0, 4.0, 0.92)),
        "left": Vector((-4.0, 0.0, 0.92)),
        "three_quarter": Vector((-2.9, -2.9, 1.22)),
    }
    for name, location in views.items():
        camera.location = location
        look_at(camera, target)
        scene.render.filepath = str(output / f"{source.stem}_{name}.png")
        bpy.ops.render.render(write_still=True)
        print("RENDERED", scene.render.filepath)


if __name__ == "__main__":
    main()
