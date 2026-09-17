"""Create twelve closed, chipped bedrock fragments for the real Godot mine.

Run with Blender --background --threads 2 --python build_rock_kit.py.
The editable .blend contains a spaced inspection arrangement. The GLB has
identity object transforms and normalized x/y [-.5,.5], z [0,1] geometry;
the Godot import converts its z-up space to y-up automatically.
"""
from __future__ import annotations

import json
import math
from pathlib import Path
import random
import sys
from collections import Counter

import bpy
import bmesh
from mathutils import Euler, Vector, noise

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
OUTPUT = ROOT / "godot-game/assets/3d/abandoned_mine/art_rock_kit.glb"


def apply_modifier(obj, modifier):
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.modifier_apply(modifier=modifier.name)


def clip(bm, normal, distance):
    normal = Vector(normal).normalized()
    center = Vector((0, 0, .5))
    result = bmesh.ops.bisect_plane(
        bm, geom=list(bm.verts) + list(bm.edges) + list(bm.faces),
        plane_co=center + normal * distance, plane_no=normal,
        clear_outer=True, clear_inner=False, dist=1e-6,
    )
    boundary = [edge for edge in result["geom_cut"]
                if isinstance(edge, bmesh.types.BMEdge) and edge.is_boundary]
    if boundary:
        bmesh.ops.holes_fill(bm, edges=boundary, sides=0)
    bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))


def make_rock(index, material, attempt=0):
    variant_seed = 650170 + (index + attempt * 12) * 197
    rng = random.Random(variant_seed)
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    for vertex in bm.verts:
        vertex.co.z += .5
    rotation = Euler((rng.uniform(-.38,.38), rng.uniform(-.38,.38), rng.uniform(-math.pi, math.pi))).to_matrix()
    bmesh.ops.rotate(bm, cent=Vector((0,0,.5)), matrix=rotation, verts=list(bm.verts))
    clip(bm, (0, 0, -1), .5)
    # Unequal fracture planes preserve broad stone faces, unlike an
    # icosphere. The crown breaks obliquely instead of ending in a cone.
    clip(bm, (rng.uniform(-.34, .34), rng.uniform(-.34, .34), 1), rng.uniform(.29, .43))
    for cut in range(rng.randint(7, 10)):
        angle = (cut + rng.uniform(-.30, .30)) * math.tau / 9
        normal = (math.cos(angle), math.sin(angle), rng.uniform(-.65, .85))
        clip(bm, normal, rng.uniform(.39, .57))
    bm.normal_update()
    mesh = bpy.data.meshes.new(f"ErodedBedrock_{index:02d}_Mesh")
    bm.to_mesh(mesh)
    bm.free()
    obj = bpy.data.objects.new(f"ErodedBedrock_{index:02d}", mesh)
    bpy.context.collection.objects.link(obj)
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)
    bevel = obj.modifiers.new("Weathered fracture arrises", "BEVEL")
    bevel.width = rng.uniform(.035, .071)
    bevel.segments = 2
    bevel.affect = "EDGES"
    bevel.limit_method = "ANGLE"
    bevel.angle_limit = math.radians(15)
    apply_modifier(obj, bevel)
    triangulate = obj.modifiers.new("Fracture surface triangles", "TRIANGULATE")
    apply_modifier(obj, triangulate)
    # One subdivision gives erosion enough vertices while retaining the
    # original large fracture planes and a low runtime triangle budget.
    subdiv = obj.modifiers.new("Erosion sampling", "SUBSURF")
    subdiv.subdivision_type = "SIMPLE"
    subdiv.levels = 1
    apply_modifier(obj, subdiv)
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    bm.normal_update()
    offset = Vector((rng.uniform(-100, 100), rng.uniform(-100, 100), rng.uniform(-100, 100)))
    for vertex in bm.verts:
        p = vertex.co.copy()
        # Fine erosion rounds/chips the arrises without a golf-ball noise
        # pattern. The lowest bearing face stays truly coplanar.
        weight = min(1.0, max(0.0, (p.z - .028) / .10))
        broad = noise.noise(p * 3.8 + offset, noise_basis="PERLIN_ORIGINAL")
        fine = noise.noise(p * 15.0 + offset, noise_basis="PERLIN_ORIGINAL")
        grain = noise.noise(p * 37.0 + offset, noise_basis="PERLIN_ORIGINAL")
        vertex.co += vertex.normal * weight * (broad * .105 + fine * .043 + grain * .012)
    minimum = Vector(tuple(min(v.co[axis] for v in bm.verts) for axis in range(3)))
    maximum = Vector(tuple(max(v.co[axis] for v in bm.verts) for axis in range(3)))
    extent = maximum - minimum
    for vertex in bm.verts:
        vertex.co = Vector(((vertex.co.x - minimum.x) / extent.x - .5,
                            (vertex.co.y - minimum.y) / extent.y - .5,
                            (vertex.co.z - minimum.z) / extent.z))
        if vertex.co.z < .003:
            vertex.co.z = 0
    bmesh.ops.triangulate(bm, faces=list(bm.faces))
    bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
    nonmanifold = sum(not e.is_manifold for e in bm.edges)
    assert nonmanifold == 0, (obj.name, nonmanifold)
    foundation = [list(v.co) for v in bm.verts if v.co.z < 1e-6]
    assert len(foundation) >= 3, (obj.name, "no stable bearing plane")
    triangles = len(bm.faces)
    bm.to_mesh(obj.data)
    bm.free()
    simplify = obj.modifiers.new("Game-ready eroded silhouette", "DECIMATE")
    simplify.ratio = min(1.0, rng.randint(630, 810) / triangles)
    simplify.use_collapse_triangulate = True
    apply_modifier(obj, simplify)
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    # Edge collapse may lift a tiny flat-face vertex. Cut and cap a fresh
    # bearing plane in the final game mesh instead of relying on epsilon.
    clip(bm, (0,0,-1), .474)
    minimum = Vector(tuple(min(v.co[axis] for v in bm.verts) for axis in range(3)))
    maximum = Vector(tuple(max(v.co[axis] for v in bm.verts) for axis in range(3)))
    extent = maximum - minimum
    for vertex in bm.verts:
        vertex.co = Vector(((vertex.co.x-minimum.x)/extent.x-.5,
                            (vertex.co.y-minimum.y)/extent.y-.5,
                            (vertex.co.z-minimum.z)/extent.z))
    # Capping can put a new vertex within a few micrometres of an existing
    # cut edge. Weld before export so float32/import quantization cannot
    # turn a nominally manifold indexed mesh into degenerate triangles.
    bmesh.ops.remove_doubles(bm, verts=list(bm.verts), dist=.0001)
    bmesh.ops.triangulate(bm, faces=list(bm.faces))
    bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
    assert all(edge.is_manifold for edge in bm.edges), (obj.name,
        [(len(edge.link_faces), [list(v.co) for v in edge.verts]) for edge in bm.edges if not edge.is_manifold])
    coordinate_edges = Counter()
    for face in bm.faces:
        assert face.calc_area() > 1e-10, (obj.name, "degenerate triangle")
        for loop in face.loops:
            a = tuple(round(float(v), 6) for v in loop.vert.co)
            b = tuple(round(float(v), 6) for v in loop.link_loop_next.vert.co)
            assert a != b, (obj.name, "coincident edge")
            coordinate_edges[tuple(sorted((a,b)))] += 1
    assert all(count == 2 for count in coordinate_edges.values()), obj.name
    foundation = [list(v.co) for v in bm.verts if abs(v.co.z) < 1e-6]
    assert len(foundation) >= 3, (obj.name, "simplified bearing plane")
    triangles = len(bm.faces)
    bm.to_mesh(obj.data)
    bm.free()
    for polygon in obj.data.polygons:
        polygon.use_smooth = True
    # Smooth adjacent erosion triangles, while the modeled bevel still
    # controls the larger fracture edge. Artificial planar custom normals
    # would erase the physical erosion introduced above.
    obj.data.materials.append(material)
    obj["asset_role"] = "closed_grounded_bedrock_fragment"
    obj["variant_seed"] = variant_seed
    obj["bearing_plane"] = "local Blender z=0; Godot y=0"
    obj.select_set(False)
    return obj, {"name": obj.name, "seed": variant_seed, "triangles": triangles,
                 "vertices": len(obj.data.vertices), "manifold": True,
                 "foundation_vertices": len(foundation), "foundation": foundation}


def main():
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)
    material = bpy.data.materials.new("NeutralDampBedrockPreview")
    material.diffuse_color = (.14, .165, .17, 1)
    material.use_nodes = True
    material.node_tree.nodes.get("Principled BSDF").inputs["Base Color"].default_value = (.14, .165, .17, 1)
    material.node_tree.nodes.get("Principled BSDF").inputs["Roughness"].default_value = .74
    rocks, report = [], []
    for index in range(12):
        # Reject rare microscopic bevel/decimation folds outright. An
        # independent deterministic seed is preferable to hiding or
        # hand-patching an invalid decorative stone.
        for attempt in range(12):
            try:
                obj, row = make_rock(index, material, attempt)
                break
            except AssertionError as error:
                print("REJECTED_ROCK_SEED", index, attempt, str(error), flush=True)
                for invalid in list(bpy.data.objects):
                    if invalid.name.startswith(f"ErodedBedrock_{index:02d}"):
                        mesh = invalid.data
                        bpy.data.objects.remove(invalid, do_unlink=True)
                        if mesh.users == 0:
                            bpy.data.meshes.remove(mesh)
        else:
            raise RuntimeError(f"No valid manifold stone for variant {index}")
        rocks.append(obj)
        report.append(row)
    for obj in rocks:
        obj.select_set(True)
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.export_scene.gltf(filepath=str(OUTPUT), export_format="GLB", use_selection=True,
                              export_extras=True, export_normals=True, export_tangents=False,
                              export_materials="EXPORT")
    for i, obj in enumerate(rocks):
        obj.location = ((i % 4) * 1.7, (i // 4) * 1.7, 0)
    scene = bpy.context.scene
    scene.unit_settings.system = "METRIC"
    scene.world.color = (.15, .15, .15)
    scene.render.engine = "CYCLES"
    scene.cycles.samples = 24
    scene.cycles.use_denoising = True
    scene.render.resolution_x = 1152
    scene.render.resolution_y = 800
    scene.render.resolution_percentage = 100
    # Inspection camera and area lamps live only in the editable source.
    bpy.ops.object.camera_add(location=(7.6, -9, 9.5))
    camera = bpy.context.object
    camera.rotation_euler = (Vector((2.55, 1.7, .4)) - camera.location).to_track_quat("-Z", "Y").to_euler()
    camera.data.type = "ORTHO"
    camera.data.ortho_scale = 9.4
    scene.camera = camera
    for name, location, power, size, color in [
        ("Soft oblique inspection light", (0, -3, 7), 1600, 5, (1,.91,.80)),
        ("Cool rim", (7, 5, 5), 950, 4, (.65,.8,1)),
        ("Fill", (-3, 4, 2), 500, 4, (.84,.89,1)),
    ]:
        data = bpy.data.lights.new(name, "AREA")
        data.energy, data.shape, data.size, data.color = power, "DISK", size, color
        obj = bpy.data.objects.new(name, data)
        bpy.context.collection.objects.link(obj)
        obj.location = location
        obj.rotation_euler = (Vector((2.55,1.7,.3)) - obj.location).to_track_quat("-Z","Y").to_euler()
    bpy.ops.mesh.primitive_plane_add(size=200, location=(0,0,-.03))
    ground = bpy.context.object
    ground.name = "Inspection ground (not exported)"
    ground_material = bpy.data.materials.new("Inspection ground")
    ground_material.diffuse_color = (.045,.055,.062,1)
    ground.data.materials.append(ground_material)
    scene.render.filepath = str(HERE / "rock_kit_inspection.png")
    bpy.ops.wm.save_as_mainfile(filepath=str(HERE / "art_rock_kit.blend"))
    (HERE / "rock_kit_manifest.json").write_text(json.dumps({"generator": Path(__file__).name,
        "normalized_Godot_bounds": [[-.5,0,-.5],[.5,1,.5]], "variants": report}, indent=2))
    if "--skip-render" not in sys.argv:
        bpy.ops.render.render(write_still=True)
    print("ROCK_KIT_COMPLETE", json.dumps({"variants": len(report),
        "triangles": [row["triangles"] for row in report], "glb": str(OUTPUT)}))


if __name__ == "__main__":
    main()
