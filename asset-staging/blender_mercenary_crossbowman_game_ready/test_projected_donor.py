import bpy
import math
import os
from mathutils import Vector


ROOT = os.path.dirname(os.path.abspath(__file__))
source_320 = os.path.join(ROOT, "triposr", "mercenary_tpose_triposr_raw_320.glb")
source = source_320 if os.path.isfile(source_320) else os.path.join(ROOT, "triposr", "mercenary_tpose_triposr_raw.glb")
out = os.path.join(ROOT, "triposr", "projected_previews")
os.makedirs(out, exist_ok=True)

bpy.ops.object.select_all(action="SELECT")
bpy.ops.object.delete(use_global=False)
bpy.ops.import_scene.gltf(filepath=source)
mesh = max((o for o in bpy.context.scene.objects if o.type == "MESH"), key=lambda o: len(o.data.vertices))
points = [mesh.matrix_world @ v.co for v in mesh.data.vertices]
xmin, xmax = min(p.x for p in points), max(p.x for p in points)
ymin, ymax = min(p.y for p in points), max(p.y for p in points)
zmin, zmax = min(p.z for p in points), max(p.z for p in points)
scale = 1.78 / (zmax - zmin)
cx, cy = (xmin + xmax) * 0.5, (ymin + ymax) * 0.5
for v, p in zip(mesh.data.vertices, points):
    v.co = (-(p.x - cx) * scale, -(p.y - cy) * scale, (p.z - zmin) * scale)
mesh.matrix_world.identity()
mesh.data.update()
for other in [o for o in bpy.context.scene.objects if o.type == "MESH" and o != mesh]:
    bpy.data.objects.remove(other, do_unlink=True)
for poly in mesh.data.polygons:
    poly.use_smooth = True

def material(name, filename):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    nodes = mat.node_tree.nodes
    bsdf = nodes.get("Principled BSDF")
    tex = nodes.new("ShaderNodeTexImage")
    tex.image = bpy.data.images.load(os.path.join(ROOT, "textures", filename), check_existing=True)
    mat.node_tree.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
    bsdf.inputs["Roughness"].default_value = 0.68
    return mat

front = material("MAT_Project_Front", "reference_projection_front_basecolor_4k.png")
back = material("MAT_Project_Back", "reference_projection_back_basecolor_4k.png")
mesh.data.materials.clear()
mesh.data.materials.append(front)
mesh.data.materials.append(back)
uv = mesh.data.uv_layers.get("UVMap") or mesh.data.uv_layers.new(name="UVMap")
xmin = min(v.co.x for v in mesh.data.vertices)
xmax = max(v.co.x for v in mesh.data.vertices)
zmin = min(v.co.z for v in mesh.data.vertices)
zmax = max(v.co.z for v in mesh.data.vertices)
mesh.data.calc_loop_triangles()
for poly in mesh.data.polygons:
    poly.material_index = 0 if poly.normal.y < 0.0 else 1
    if poly.material_index == 0:
        u0, u1, v0, v1 = 417 / 4096, 3677 / 4096, 1 - 3860 / 4096, 1 - 241 / 4096
    else:
        u0, u1, v0, v1 = 358 / 4096, 3740 / 4096, 1 - 3854 / 4096, 1 - 239 / 4096
    for loop_index in poly.loop_indices:
        co = mesh.data.vertices[mesh.data.loops[loop_index].vertex_index].co
        norm_x = (co.x - xmin) / (xmax - xmin)
        norm_z = (co.z - zmin) / (zmax - zmin)
        uv.data[loop_index].uv = (u0 + (1.0 - norm_x) * (u1 - u0), v0 + norm_z * (v1 - v0))

scene = bpy.context.scene
scene.render.engine = "BLENDER_EEVEE"
scene.render.resolution_x = 900
scene.render.resolution_y = 1100
scene.render.resolution_percentage = 100
scene.render.image_settings.file_format = "PNG"
scene.world.color = (0.015, 0.015, 0.018)
bpy.ops.mesh.primitive_plane_add(size=8, location=(0, 0, -0.01))

def look(obj, target):
    obj.rotation_euler = (Vector(target) - obj.location).to_track_quat("-Z", "Y").to_euler()

for name, loc, energy, size in (("Key",(-2.5,-3,3),1100,2.5),("Fill",(2.8,-2,2.4),700,2.5),("Rim",(0,3,3),900,2.0)):
    data=bpy.data.lights.new(name,"AREA"); data.energy=energy; data.size=size
    light=bpy.data.objects.new(name,data); scene.collection.objects.link(light); light.location=loc; look(light,(0,0,.95))
camdata=bpy.data.cameras.new("Camera"); cam=bpy.data.objects.new("Camera",camdata); scene.collection.objects.link(cam); scene.camera=cam
camdata.type="ORTHO"; camdata.ortho_scale=2.04
for name, loc in (("front",(0,-4,.9)),("back",(0,4,.9)),("side",(-4,0,.9)),("three_quarter",(2.8,-2.8,1.25))):
    cam.location=loc; look(cam,(0,0,.88)); scene.render.filepath=os.path.join(out,f"projected_{name}.png"); bpy.ops.render.render(write_still=True)
    print("RENDERED",scene.render.filepath)
