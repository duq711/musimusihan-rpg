"""Deterministic, editable Blender ruin accents for the Godot hideout.

Run with Blender --background --factory-startup --python this_file.py.
Coordinates in this script are Godot meters: X right, Y up, Z depth.
No external downloads, add-ons, original scene changes, or UI required.
"""
import bpy
import math
import random
import json
import hashlib
from pathlib import Path
from mathutils import Vector

STAGING = Path(__file__).resolve().parent
PROJECT = STAGING.parent.parent
OUTPUT = PROJECT / "godot-game/assets/3d/hideout_ruins"
SEED = 2026090803
rng = random.Random(SEED)
OUTPUT.mkdir(parents=True, exist_ok=True)
bpy.ops.object.select_all(action="SELECT")
bpy.ops.object.delete(use_global=False)
for collection in list(bpy.data.collections):
    if collection.name != "Collection":
        bpy.data.collections.remove(collection)


def p(v):
    return Vector((v[0], -v[2], v[1]))


def material(name, color, roughness=0.96):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    nodes = mat.node_tree.nodes
    bsdf = nodes.get("Principled BSDF")
    bsdf.inputs["Base Color"].default_value = (*color, 1)
    bsdf.inputs["Roughness"].default_value = roughness
    attr = nodes.new("ShaderNodeVertexColor")
    attr.layer_name = "RuinTint"
    mat.node_tree.links.new(attr.outputs["Color"], bsdf.inputs["Base Color"])
    mat.diffuse_color = (*color, 1)
    mat.use_backface_culling = False
    return mat


STONE = material("ruin_stone", (0.26, 0.275, 0.23))
WOOD = material("ruin_timber", (0.15, 0.105, 0.065))
MOSS = material("ruin_moss", (0.115, 0.17, 0.052))
ROOT = material("ruin_root", (0.13, 0.115, 0.085))
LIME = material("ruin_mortar", (0.34, 0.345, 0.27))
BASE_COLORS = {STONE.name: (0.26, 0.275, 0.23), WOOD.name: (0.15, 0.105, 0.065),
               MOSS.name: (0.115, 0.17, 0.052), ROOT.name: (0.13, 0.115, 0.085),
               LIME.name: (0.34, 0.345, 0.27)}


def mesh(name, vertices, faces, mat, tint=1.0):
    data = bpy.data.meshes.new(name + "Mesh")
    data.from_pydata([p(v) for v in vertices], [], faces)
    data.materials.append(mat)
    data.update()
    obj = bpy.data.objects.new(name, data)
    bpy.context.collection.objects.link(obj)
    colors = data.color_attributes.new(name="RuinTint", type="FLOAT_COLOR", domain="POINT")
    base = BASE_COLORS[mat.name]
    for idx, vert in enumerate(vertices):
        # Low-contrast mineral/color variation remains portable in glTF COLOR_0.
        broad = 0.90 + 0.13 * math.sin(vert[0] * 7.3 + vert[1] * 4.1 + vert[2] * 5.7)
        variation = tint * broad * rng.uniform(0.88, 1.10)
        colors.data[idx].color = (*(min(0.95, c * variation) for c in base), 1)
    return obj


def stone(name, center, size, yaw=0.0, tilt=0.0, mat=STONE, tint=1.0):
    """Four irregular eight-sided rings create worn corners and chipped ledges."""
    w, h, d = size
    vertices = []
    outline = [(-.38, -.5), (.35, -.5), (.5, -.36), (.5, .37),
               (.36, .5), (-.38, .5), (-.5, .34), (-.5, -.34)]
    broken_corner = rng.randrange(8)
    chip = rng.uniform(.13, .33)
    for ring, vertical in enumerate((0.0, 0.10, 0.91, 1.0)):
        inset = rng.uniform(.89, .97) if ring in (0, 3) else 1.0
        for point_index, (x, z) in enumerate(outline):
            lx = x * w * inset + rng.uniform(-.055, .055) * w
            lz = z * d * inset + rng.uniform(-.045, .045) * d
            ly = (vertical - .5) * h + rng.uniform(-.035, .035) * h
            if ring >= 2 and point_index in (broken_corner, (broken_corner+1)%8):
                # A fractured corner removes a real wedge from the top/side silhouette.
                ly -= chip*h*(1.0 if ring == 3 else .42)
                lx *= 1.0-chip*.9
                lz *= 1.0-chip*.9
            yy = ly * math.cos(tilt) - lx * math.sin(tilt)
            xx = lx * math.cos(tilt) + ly * math.sin(tilt)
            vertices.append((center[0] + xx * math.cos(yaw) + lz * math.sin(yaw),
                             center[1] + yy,
                             center[2] - xx * math.sin(yaw) + lz * math.cos(yaw)))
    faces = [tuple(reversed(range(8))), tuple(range(24, 32))]
    for j in range(3):
        for i in range(8):
            a = j * 8 + i
            b = j * 8 + (i + 1) % 8
            c, e = b + 8, a + 8
            # Some cracked faces have an actual slight ridge, rather than texture-only damage.
            if rng.random() < .25:
                faces.extend([(a, b, c), (a, c, e)])
            else:
                faces.append((a, b, c, e))
    return mesh(name, vertices, faces, mat, tint)


def shard(name, center, size, yaw=0.0, mat=STONE, tint=1.0):
    """Broken slate fragment: unequal polygon footprint and sloping fracture plane."""
    count = rng.randint(5, 7)
    outline = []
    for i in range(count):
        angle = i*math.tau/count + rng.uniform(-.18,.18)
        radius = rng.uniform(.61,1.12)
        outline.append((math.cos(angle)*radius, math.sin(angle)*radius))
    vertices = []
    for layer in range(2):
        for i,(x,z) in enumerate(outline):
            inset = rng.uniform(.5,.87) if layer else 1
            xx, zz = x*size[0]*.5*inset, z*size[2]*.5*inset
            yy = (layer-.5)*size[1]+rng.uniform(-.2,.2)*size[1]
            if layer:
                yy += x*size[1]*.22
            vertices.append((center[0]+xx*math.cos(yaw)+zz*math.sin(yaw),center[1]+yy,
                             center[2]-xx*math.sin(yaw)+zz*math.cos(yaw)))
    faces=[tuple(reversed(range(count))),tuple(range(count,count*2))]
    faces += [(i,(i+1)%count,(i+1)%count+count,i+count) for i in range(count)]
    return mesh(name,vertices,faces,mat,tint)


def tube(name, points, radii, mat=ROOT, sides=6, tint=1.0):
    vertices, faces = [], []
    for i, point in enumerate(points):
        previous = Vector(points[max(0, i - 1)])
        after = Vector(points[min(len(points) - 1, i + 1)])
        tangent = (after - previous).normalized()
        axis = tangent.cross(Vector((0, 0, 1)))
        if axis.length < .1:
            axis = tangent.cross(Vector((1, 0, 0)))
        axis.normalize()
        cross = tangent.cross(axis).normalized()
        for j in range(sides):
            angle = 2 * math.pi * j / sides
            radial = axis * math.cos(angle) + cross * math.sin(angle)
            vertices.append(tuple(Vector(point) + radial * radii[i] * rng.uniform(.9, 1.1)))
    faces.extend([tuple(reversed(range(sides))),
                  tuple(range((len(points)-1)*sides, len(points)*sides))])
    for i in range(len(points) - 1):
        for j in range(sides):
            faces.append((i*sides+j, i*sides+(j+1)%sides,
                          (i+1)*sides+(j+1)%sides, (i+1)*sides+j))
    return mesh(name, vertices, faces, mat, tint)


def moss_patch(name, center, width, depth, height=.12, tuft_count=14):
    vertices = [(center[0], center[1] + height, center[2])]
    count = 17
    radial = [rng.uniform(.67, 1.12) for _ in range(count)]
    for ring in (.43, 1.0):
        for i in range(count):
            angle = math.tau * i / count
            vertices.append((center[0]+math.cos(angle)*width*.5*ring*radial[i],
                             center[1]+height*(1-ring**1.7)*rng.uniform(.6, 1.15),
                             center[2]+math.sin(angle)*depth*.5*ring*radial[i]))
    faces = [(0, 1+i, 1+(i+1)%count) for i in range(count)]
    for i in range(count):
        faces.append((1+i, count+1+i, count+1+(i+1)%count, 1+(i+1)%count))
    for _ in range(tuft_count):
        angle, dist = rng.random()*math.tau, rng.random()*.43
        bx, bz = center[0]+math.cos(angle)*width*dist, center[2]+math.sin(angle)*depth*dist
        by = center[1]+height*rng.uniform(.25, .85)
        leaf_h = rng.uniform(.025, .09)
        leaf_w = rng.uniform(.008, .018)
        for theta in (rng.random()*math.tau, rng.random()*math.tau):
            dx, dz = math.cos(theta)*leaf_w, math.sin(theta)*leaf_w
            start = len(vertices)
            vertices.extend([(bx-dx, by, bz-dz), (bx+dx, by, bz+dz),
                             (bx+dx*.3, by+leaf_h, bz+dz*.3)])
            faces.append((start, start+1, start+2))
    return mesh(name, vertices, faces, MOSS, rng.uniform(.8, 1.3))


def new_asset(name):
    collection = bpy.data.collections.new(name)
    bpy.context.scene.collection.children.link(collection)
    return collection, set(bpy.data.objects)


def finish_asset(name, collection, before, origin_top=False):
    objects = [obj for obj in bpy.data.objects if obj not in before]
    bpy.ops.object.select_all(action="DESELECT")
    for obj in objects:
        for old in list(obj.users_collection):
            old.objects.unlink(obj)
        collection.objects.link(obj)
        obj.select_set(True)
    bpy.context.view_layer.objects.active = objects[0]
    bpy.ops.object.join()
    obj = bpy.context.object
    obj.name = name
    obj.data.name = name + "_Mesh"
    # Keep mesh origin exactly at (0,0,0); geometry is already in meters.
    bpy.context.scene.cursor.location = (0, 0, 0)
    bpy.ops.object.origin_set(type="ORIGIN_CURSOR")
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    # UVs allow game materials to replace neutral imported slots later.
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.mesh.normals_make_consistent(inside=False) if hasattr(bpy.ops.mesh, "normals_make_consistent") else None
    bpy.ops.uv.smart_project(angle_limit=1.1519, island_margin=.018)
    bpy.ops.object.mode_set(mode="OBJECT")
    obj["asset_usage"] = "Static decorative ruin geometry; collision is authored in Godot."
    obj["origin"] = "top anchor; geometry hangs down" if origin_top else "floor center"
    obj["seed"] = SEED
    bpy.ops.export_scene.gltf(filepath=str(OUTPUT / (name + ".glb")), export_format="GLB",
                              use_selection=True, export_yup=True, export_apply=True,
                              export_materials="EXPORT",
                              export_extras=True, export_animations=False)
    obj.data.calc_loop_triangles()
    bounds = [obj.matrix_world @ Vector(corner) for corner in obj.bound_box]
    godot = [(v.x, v.z, -v.y) for v in bounds]
    return {"name": name, "file": str((OUTPUT/(name+".glb")).relative_to(PROJECT)),
            "origin": obj["origin"], "origin_kind": "root_top" if origin_top else "floor_center",
            "vertices": len(obj.data.vertices),
            "triangles": len(obj.data.loop_triangles),
            "materials": [m.name for m in obj.data.materials],
            "min_xyz": [round(min(v[i] for v in godot), 4) for i in range(3)],
            "max_xyz": [round(max(v[i] for v in godot), 4) for i in range(3)],
            "sha256": hashlib.sha256((OUTPUT/(name+".glb")).read_bytes()).hexdigest()}


assets = []

collection, before = new_asset("broken_masonry_edge")
for row in range(7):
    for column in range(5):
        if row > [6, 5, 4, 2, 0][column] or (column == 1 and row == 3):
            continue
        w, h, d = rng.uniform(.5, .7), rng.uniform(.42, .49), rng.uniform(.65, .92)
        x = -1.31 + column * .6 + (.13 if row % 2 else 0)
        stone("ErodedLimestone", (x, row*.48+h*.5, rng.uniform(-.06, .06)),
              (w, h, d), rng.uniform(-.07, .07), rng.uniform(-.035, .035), tint=rng.uniform(.7, 1.18))
for i in range(7):
    moss_patch("WallFootMoss", (rng.uniform(-1.6, 1.4), .02, rng.uniform(-.55, .45)), .65, .4, .055, 8)
assets.append(finish_asset("broken_masonry_edge", collection, before))

collection, before = new_asset("collapsed_arch")
for side in (-1, 1):
    for row in range(3 if side < 0 else 1):
        stone("CrackedArchFoot", (side*1.92, .19+row*.37, rng.uniform(-.1, .1)),
              (.65, .37, .74), rng.uniform(-.12, .12), tint=rng.uniform(.8, 1.15))
# A recognizable detached curved run of voussoirs, slumped among the debris.
for i in range(8):
    angle = math.radians(15+i*19)
    center = (-.1+math.cos(angle)*1.58, .23+math.sin(angle)*.26, .2+math.sin(angle)*.75)
    stone("FallenVoussoir", center, (.58, .42, .82), rng.uniform(-.16, .16),
          (angle-math.pi*.5)*.6, tint=rng.uniform(.75, 1.1))
for i in range(24):
    size = rng.uniform(.1, .43)
    shard("ArchSplinter", (rng.uniform(-2.2, 2.2), size*.30, rng.uniform(-.85, .94)),
          (size*1.7, size*.55, size), rng.random()*math.tau, tint=rng.uniform(.6, 1.2))
for i in range(6):
    moss_patch("ArchMoss", (rng.uniform(-2.15, 1.9), .02, rng.uniform(-.85, .8)), .6, .3, .045, 7)
assets.append(finish_asset("collapsed_arch", collection, before))

collection, before = new_asset("rubble_pile")
for i in range(54):
    angle, radius = rng.random()*math.tau, math.sqrt(rng.random())
    x, z = math.cos(angle)*1.55*radius, math.sin(angle)*.96*radius
    size = rng.uniform(.13, .50) * (1.15-radius*.35)
    y = max(.03, (1-radius)*.58) + size*.28
    if i % 3:
        shard("FracturedRubble", (x,y,z), (size*1.9,size*.67,size*1.3),
              rng.random()*math.tau,tint=rng.uniform(.68,1.25))
    else:
        stone("FracturedMasonry", (x,y,z), (size*1.6,size*.73,size),
              rng.random()*math.tau,rng.uniform(-.5,.5),tint=rng.uniform(.68,1.25))
for i in range(11):
    moss_patch("RubbleMoss", (rng.uniform(-1.5, 1.5), .018, rng.uniform(-.85, .85)), .5, .35, .045, 5)
assets.append(finish_asset("rubble_pile", collection, before))

collection, before = new_asset("snapped_timber")
# Ragged splintered longitudinal strips leave a genuinely broken end profile.
for row in range(3):
    for column in range(4):
        length = rng.uniform(2.8, 3.65)
        xstart = -1.8 + rng.uniform(-.1, .08)
        y, z = .085+row*.11, -.21+column*.12
        points = [(xstart, y, z), (-.6, y+rng.uniform(-.025,.025), z),
                  (.6, y+rng.uniform(-.04,.02), z+rng.uniform(-.015,.015)),
                  (xstart+length-.18, y+.005, z),
                  (xstart+length, y+rng.uniform(-.035,.045), z+rng.uniform(-.035,.035))]
        tube("RottenTimberSplinter", points, [.077,.072,.067,.058,.007], WOOD, 5, rng.uniform(.7,1.35))
for i in range(3):
    moss_patch("TimberMoss", (rng.uniform(-1.3,.5), .38, rng.uniform(-.1,.1)), .7,.25,.03,8)
assets.append(finish_asset("snapped_timber", collection, before))

collection, before = new_asset("hanging_roots")
for i in range(17):
    x0, z0 = rng.uniform(-1.2, 1.2), rng.uniform(-.28,.28)
    length = rng.uniform(.45,2.25)
    bend = rng.uniform(-.36,.36)
    points = [(x0+bend*t/9+math.sin(t*.85+i)*.08*(t/9), -length*t/9,
               z0+math.sin(t*.63+i)*.08*(t/9)) for t in range(10)]
    radius = rng.uniform(.012,.035)
    tube("CeilingRoot", points, [radius*(1-t/11) for t in range(10)], ROOT, 5, rng.uniform(.7,1.3))
    if i%2 == 0:
        attach = Vector(points[4])
        direction = rng.choice((-1,1))
        branch = [tuple(attach+Vector((direction*.045*t,-.10*t,math.sin(t)*.015))) for t in range(5)]
        tube("RootFork", branch, [.016,.012,.01,.006,.002], ROOT, 5)
for i in range(5):
    stone("CeilingPeat", (rng.uniform(-1.1,1.1), -.04, rng.uniform(-.22,.22)),
          (rng.uniform(.2,.6), .10, .28), mat=ROOT, tint=rng.uniform(.8,1.15))
assets.append(finish_asset("hanging_roots", collection, before, True))

collection, before = new_asset("moss_clump")
for i in range(13):
    angle, radius = rng.random()*math.tau, rng.random()
    moss_patch("IrregularMossLobe", (math.cos(angle)*.67*radius, .007,
                                    math.sin(angle)*.37*radius),
               rng.uniform(.28,.75), rng.uniform(.2,.5), rng.uniform(.035,.13), 18)
assets.append(finish_asset("moss_clump", collection, before))

collection, before = new_asset("ceiling_spall")
for i in range(15):
    angle, radius = rng.random()*math.tau, math.sqrt(rng.random())
    x, z = math.cos(angle)*1.72*radius, math.sin(angle)*.95*radius
    stone("DelaminatedCeiling", (x, -.065-rng.random()*.12, z),
          (rng.uniform(.55,1.1), rng.uniform(.07,.2), rng.uniform(.28,.65)),
          rng.uniform(-.35,.35), rng.uniform(-.14,.14), LIME, rng.uniform(.65,1.12))
for i in range(12):
    x,z=rng.uniform(-1.55,1.55),rng.uniform(-.8,.8)
    tube("CalciteDripstone", [(x,-.12,z),(x+.02,-.25,z-.02),(x+.03,-rng.uniform(.34,.72),z+.01)],
         [.048,.026,.004], LIME, 5, rng.uniform(.75,1.3))
assets.append(finish_asset("ceiling_spall", collection, before, True))

# Editable library stays together at true insertion coordinates, organized per collection.
# Collections are individually selectable/exportable; no active original Blender scene is touched.
bpy.ops.object.select_all(action="DESELECT")
bpy.context.scene.unit_settings.system = "METRIC"
bpy.context.scene.unit_settings.scale_length = 1
bpy.ops.wm.save_as_mainfile(filepath=str(STAGING / "hideout_ruins_kit.blend"))
report = {"seed":SEED,"generator":"build_ruin_kit.py", "blender":bpy.app.version_string,
          "coordinates":"Godot glTF Y-up, meters; +Z depth", "assets":assets,
          "total_triangles":sum(a["triangles"] for a in assets)}
(STAGING/"build_report.json").write_text(json.dumps(report,indent=2), encoding="utf-8")
print("HIDEOUT RUINS KIT PASS: %d editable assets, %d triangles"%(len(assets),report["total_triangles"]))
