"""Blender source authoring and portable PBR/glTF production for Blackwater Mine.

Run with Blender --background --factory-startup --threads 2 --python this_file.
The scene contains the final actual mesh/materials; renders use this .blend.
"""
import json
import math
import os
import sys
import time
from collections import defaultdict
from pathlib import Path

import bpy
import bmesh
import numpy as np
from mathutils import Vector, noise

ROOT = Path(__file__).resolve().parent
PROJECT = ROOT.parents[1] / "godot-game"
ASSETS = PROJECT / "assets/3d/abandoned_mine"
sys.path.insert(0, str(ROOT))
layout = json.loads((ROOT / "layout.json").read_text())
data = np.load(ROOT / "terrain_mesh.npz")
rng = np.random.default_rng(131139)
started = time.time()
bpy.ops.object.select_all(action="SELECT")
bpy.ops.object.delete(use_global=False)
scene = bpy.context.scene
scene.unit_settings.system = "METRIC"
scene.unit_settings.scale_length = 1.0
scene.render.engine = "CYCLES"
scene.cycles.device = "CPU"
scene.cycles.samples = 28
scene.cycles.use_denoising = True
scene.render.threads_mode = "FIXED"
scene.render.threads = 2
scene.world.use_nodes = True
scene.world.node_tree.nodes["Background"].inputs["Color"].default_value = (0.12,0.16,0.21,1)
scene.world.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.10
scene.view_settings.view_transform = "AgX"
scene.view_settings.exposure = 0.7


def collection(name):
    c = bpy.data.collections.new(name)
    scene.collection.children.link(c)
    return c


terrain_collection = collection("01_CarvedGeology")
formations_collection = collection("02_NaturalFormations")
props_collection = collection("03_AbandonedMine")
lights_collection = collection("04_LanternsAndSeepage")
collision_collection = collection("05_CollisionProxies")
material_manifest = json.loads((ASSETS / "material_manifest.json").read_text())


def pbr_material(source_id, label, normal_strength=0.6, roughness_bias=None):
    item = next(x for x in material_manifest["materials"] if x["id"] == source_id)
    mat = bpy.data.materials.new(label)
    mat.use_nodes = True
    nodes, links = mat.node_tree.nodes, mat.node_tree.links
    principled = nodes.get("Principled BSDF")
    principled.inputs["Roughness"].default_value = 0.8
    if source_id == "rust_coarse_01":
        principled.inputs["Metallic"].default_value = 0.45
    uv = nodes.new("ShaderNodeTexCoord")
    mapping = nodes.new("ShaderNodeVectorMath")
    mapping.operation = "SCALE"
    mapping.inputs["Scale"].default_value = 1.0 / item["physical_size_m"][0]
    # Mesh UVs are metres so the same channels match the real scanned scale.
    links.new(uv.outputs["UV"], mapping.inputs[0])
    images = {}
    for channel in ["albedo", "roughness", "normal_gl"]:
        tex = nodes.new("ShaderNodeTexImage")
        tex.name = label + "_" + channel
        path = PROJECT / item["channels"][channel].replace("res://", "")
        tex.image = bpy.data.images.load(str(path), check_existing=True)
        tex.image.colorspace_settings.name = "sRGB" if channel == "albedo" else "Non-Color"
        tex.interpolation = "Linear"
        tex.extension = "REPEAT"
        links.new(mapping.outputs["Vector"], tex.inputs["Vector"])
        images[channel] = tex
    links.new(images["albedo"].outputs["Color"], principled.inputs["Base Color"])
    if roughness_bias is None:
        links.new(images["roughness"].outputs["Color"], principled.inputs["Roughness"])
    else:
        principled.inputs["Roughness"].default_value = roughness_bias
    normal_map = nodes.new("ShaderNodeNormalMap")
    normal_map.inputs["Strength"].default_value = normal_strength
    links.new(images["normal_gl"].outputs["Color"], normal_map.inputs["Color"])
    links.new(normal_map.outputs["Normal"], principled.inputs["Normal"])
    mat["scan_id"] = source_id
    mat["scan_tile_m"] = item["physical_size_m"][0]
    mat["license"] = "CC0-1.0"
    return mat


materials = {
    "rock": pbr_material("rock_boulder_dry", "Mine_Limestone", 0.63),
    "rock_dark": pbr_material("dark_rock_02", "Mine_DarkGallery", 0.58),
    "ground": pbr_material("brown_mud_rocks_01", "Mine_GravelMud", 0.58),
    "wood": pbr_material("rough_wood", "Mine_AgedOak", 0.7),
    "metal": pbr_material("rust_coarse_01", "Mine_RustedIron", 0.55),
    "calcite": pbr_material("rock_boulder_dry", "Mine_Calcite", 0.24, 0.42),
    "mined": pbr_material("dark_rock_02", "Mine_PickCutRock", 0.60),
}
slots = [materials["rock"],materials["calcite"],materials["rock_dark"],materials["mined"],materials["ground"]]


def assign_uv(mesh, coords=None):
    """Metric box projection with per-chunk rotation, UVs exported to Godot."""
    vertices = np.array([v.co for v in mesh.vertices], dtype=np.float32) if coords is None else coords
    uv = mesh.uv_layers.new(name="Mine_MetricUV")
    loop_vid = np.zeros(len(mesh.loops),dtype=np.int32)
    mesh.loops.foreach_get("vertex_index",loop_vid)
    normals = np.zeros(len(mesh.polygons)*3,dtype=np.float32)
    mesh.polygons.foreach_get("normal",normals)
    normals = normals.reshape(-1,3)
    starts = np.zeros(len(mesh.polygons),dtype=np.int32)
    counts = np.zeros(len(mesh.polygons),dtype=np.int32)
    mesh.polygons.foreach_get("loop_start",starts)
    mesh.polygons.foreach_get("loop_total",counts)
    dominant = np.repeat(np.argmax(np.abs(normals),axis=1),counts)
    loop_coords = vertices[loop_vid]
    result = np.empty((len(mesh.loops),2),dtype=np.float32)
    # Coordinate ordering keeps vertical wood/stone features upright.
    result[dominant==0] = loop_coords[dominant==0][:,[1,2]]
    result[dominant==1] = loop_coords[dominant==1][:,[0,2]]
    result[dominant==2] = loop_coords[dominant==2][:,[0,1]]
    if coords is None:
        result += rng.uniform(-12,12,2)
    uv.data.foreach_set("uv",result.ravel())


vertices = data["vertices"].copy()
faces = data["faces"]
face_materials = data["material_ids"]
# Blender's own solid Noise texture supplies the last 4cm of sculpt displacement.
# Keep the actual walking floor untouched and preserve macro cavities from SDF.
for i in range(len(vertices)):
    p = vertices[i]
    if p[2] > 0.45:
        n = noise.noise_vector(Vector((p[0]*1.35,p[1]*1.35,p[2]*1.35)),noise_basis="PERLIN_ORIGINAL")
        vertices[i] += np.asarray(n,dtype=np.float32) * 0.035

centers = vertices[faces].mean(axis=1)
chunks = defaultdict(list)
for i, center in enumerate(centers):
    chunks[(int(math.floor((center[0]+65.5)/12)),int(math.floor((center[1]+69.5)/12)))].append(i)
print("BLENDER SCULPT", len(vertices), "vertices", len(faces),"faces",len(chunks),"spatial chunks",flush=True)
for key, selected_faces in chunks.items():
    selected_faces = np.asarray(selected_faces,dtype=np.int32)
    old_faces = faces[selected_faces]
    unique, inverse = np.unique(old_faces,return_inverse=True)
    coords = vertices[unique]
    mesh = bpy.data.meshes.new("SculptedRock_%02d_%02d" % key)
    mesh.from_pydata(coords.tolist(),[],inverse.reshape(-1,3).tolist())
    mesh.update()
    for mat in slots:
        mesh.materials.append(mat)
    mesh.polygons.foreach_set("material_index",face_materials[selected_faces].astype(np.int32))
    mesh.polygons.foreach_set("use_smooth",np.ones(len(mesh.polygons),dtype=bool))
    assign_uv(mesh,coords)
    obj = bpy.data.objects.new("Terrain_%02d_%02d" % key,mesh)
    terrain_collection.objects.link(obj)

xs,zs = data["xs"],data["zs"]


def sample_grid(grid,x,z):
    ix = int(np.clip(round((x-xs[0])/(xs[1]-xs[0])),0,len(xs)-1))
    iz = int(np.clip(round((z-zs[0])/(zs[1]-zs[0])),0,len(zs)-1))
    return float(grid[iz,ix])


def floor_height(x,z):
    return sample_grid(data["floor"],x,z)


def ceiling_height(x,z):
    return sample_grid(data["ceiling"],x,z)


segments = []
for link in layout["corridors"]:
    for a,b in zip(link["points"][:-1],link["points"][1:]):
        segments.append((np.array(a),np.array(b)))
reserved = [(np.array(v["position"])[[0,2]],2.0) for group in layout["gameplay"].values() for v in group]
reserved += [(np.array(layout["spawn"])[[0,2]],2.0),(np.array(layout["extraction"])[[0,2]],3.0)]


def route_distance(x,z):
    p = np.array([x,z])
    result=1000
    for a,b in segments:
        v=b-a
        t=np.clip(np.dot(p-a,v)/max(0.001,np.dot(v,v)),0,1)
        result=min(result,float(np.linalg.norm(p-a-t*v)))
    return result


def clear(x,z,radius):
    if abs(x)+radius>64.8 or abs(z)+radius>68.8:
        return False
    if sample_grid(data["signed_distance"],x,z) < max(0.1,radius*0.3):
        return False
    if route_distance(x,z) < radius+1.35:
        return False
    for p,r in reserved:
        if np.linalg.norm(p-np.array([x,z])) < r+radius:
            return False
    return True


def mesh_object(label,verts,triangles,mat,coll=formations_collection):
    mesh=bpy.data.meshes.new(label)
    mesh.from_pydata(verts,[],triangles)
    mesh.update()
    obj=bpy.data.objects.new(label,mesh)
    coll.objects.link(obj)
    mesh.materials.append(mat)
    for poly in mesh.polygons:
        poly.use_smooth=True
    assign_uv(mesh)
    return obj


def formation(label,x,z,y,length,radius,hanging=True):
    """Bent asymmetric calcite taper with fused lobes, never a straight cone."""
    rings=11
    sides=10
    verts=[]
    bend=rng.uniform(-0.28,0.28,2)
    phases=rng.uniform(0,math.tau,3)
    for j in range(rings):
        t=j/(rings-1)
        r=radius*(0.02+(1-t)**1.45)
        for k in range(sides):
            a=k/sides*math.tau
            lobe=1+0.14*math.sin(a*3+phases[0])+0.09*math.cos(a*5+phases[1])+rng.uniform(-0.025,0.025)
            verts.append((x+bend[0]*t*t+math.cos(a)*r*lobe,-z+bend[1]*t*t+math.sin(a)*r*lobe,y+(-1 if hanging else 1)*length*t))
    tris=[]
    for j in range(rings-1):
        for k in range(sides):
            a=j*sides+k;b=j*sides+(k+1)%sides;c=(j+1)*sides+(k+1)%sides;d=(j+1)*sides+k
            tris.extend([(a,b,c),(a,c,d)] if not hanging else [(c,b,a),(d,c,a)])
    tris.append(tuple(range(sides-1,-1,-1)))
    obj=mesh_object(label,verts,tris,materials["calcite"])
    return obj


# A few mineral provinces have dense soda straws; other rooms have none.
formation_count=0
for room in layout["rooms"]:
    if room["geology"] not in ["flowstone","fractured_limestone"]:
        continue
    points=np.array(room["polygon"])
    lo,hi=points.min(axis=0),points.max(axis=0)
    count=95 if room["geology"]=="flowstone" else 12
    for attempt in range(count):
        x,z=rng.uniform(lo,hi)
        distance=sample_grid(data["signed_distance"],x,z)
        if distance<0.5:
            continue
        ceiling_y=ceiling_height(x,z)-0.14
        length=float(rng.uniform(0.25,1.4) if attempt%4 else rng.uniform(1.3,3.0))
        if ceiling_y-length<3.0:
            length=ceiling_y-3.0
        if length<0.2:
            continue
        formation("CalciteCeiling_%04d"%formation_count,x,z,ceiling_y,length,float(rng.uniform(0.045,0.32)),True)
        formation_count+=1
        if attempt%7==0 and clear(x,z,0.65):
            formation("RockFormation_%04d"%formation_count,x,z,floor_height(x,z)-0.06,float(rng.uniform(0.5,1.7)),float(rng.uniform(0.2,0.48)),False)
            formation_count+=1


# Photogrammetric cliff fragments introduce true chipped silhouettes and joints.
scan_templates=[]
for scan_id in ["rock_face_01","rock_face_02"]:
    source=ROOT/"material_sources"/(scan_id+"_scan")/(scan_id+"_1k.gltf")
    if not source.exists():
        continue
    before=set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=str(source))
    imported=[o for o in bpy.data.objects if o not in before]
    for obj in imported:
        if obj.type!="MESH":
            continue
        # Preserve scan materials and UVs. Bake transforms before recentering.
        bpy.context.view_layer.objects.active=obj
        bpy.ops.object.select_all(action="DESELECT")
        obj.select_set(True)
        bpy.ops.object.transform_apply(location=False,rotation=True,scale=True)
        coords=np.array([v.co for v in obj.data.vertices])
        lo,hi=coords.min(axis=0),coords.max(axis=0)
        center=np.array([(lo[0]+hi[0])/2,(lo[1]+hi[1])/2,lo[2]])
        for v in obj.data.vertices:
            v.co-=Vector(center)
        decimate=obj.modifiers.new("GameScanReduction","DECIMATE")
        decimate.ratio=0.38
        bpy.ops.object.modifier_apply(modifier=decimate.name)
        obj.data.name="ScanTemplate_"+scan_id
        scan_templates.append(obj.data.copy())
    for obj in imported:
        bpy.data.objects.remove(obj,do_unlink=True)
scan_count=0
for room in layout["rooms"]:
    boundary=np.array(room["polygon"])
    room_center=np.array(room["center"])
    for i in range(0,len(boundary),max(3,len(boundary)//4)):
        if not scan_templates:
            break
        a,b=boundary[i],boundary[(i+1)%len(boundary)]
        pos=(a+b)/2
        inward=room_center-pos
        inward/=max(0.001,np.linalg.norm(inward))
        pos+=inward*0.65
        if route_distance(*pos)<3.3 or abs(pos[0])>60 or abs(pos[1])>64:
            continue
        scan=scan_templates[scan_count%len(scan_templates)]
        obj=bpy.data.objects.new("RockScan_%03d"%scan_count,scan)
        formations_collection.objects.link(obj)
        obj.location=(pos[0],-pos[1],floor_height(*pos)-0.15)
        obj.rotation_euler[2]=math.atan2(-inward[1],inward[0])+math.pi/2
        obj.scale=(float(rng.uniform(0.65,1.15)),float(rng.uniform(0.45,0.70)),float(rng.uniform(0.85,1.5)))
        scan_count+=1


# Broken scree gathers at walls, never evenly spaced across the entire floor.
for room in layout["rooms"]:
    boundary=np.array(room["polygon"])
    center=np.array(room["center"])
    for _ in range(28):
        idx=int(rng.integers(len(boundary)))
        p=boundary[idx]*0.82+center*0.18+rng.normal(0,0.45,2)
        r=float(rng.uniform(0.07,0.33))
        if not clear(*p,r+0.1):
            continue
        bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=1,radius=1,location=(p[0],-p[1],floor_height(*p)+r*0.2))
        obj=bpy.context.object
        obj.name="Scree_"+room["id"]
        obj.scale=(r*1.4,r,r*0.65)
        obj.rotation_euler=(rng.random(),rng.random(),rng.random()*math.tau)
        for coll in list(obj.users_collection):
            coll.objects.unlink(obj)
        formations_collection.objects.link(obj)
        obj.data.materials.append(materials["rock"])
        assign_uv(obj.data)


# Purpose-built mine equipment authored in its independent Blender module.
import mine_props
props_report=mine_props.build_props(layout,materials,props_collection,clearance_fn=clear,ground_height_fn=floor_height)
import bone_props
bones_report=bone_props.build_monster_remains(layout,materials,props_collection,clearance_fn=clear,ground_height_fn=floor_height)


# Lantern positions are data, so Godot uses the same fixtures and physical places.
light_markers=[]
for room in layout["rooms"]:
    pts=np.array(room["polygon"])
    center=np.array(room["center"])
    for index in [0,len(pts)//2]:
        p=pts[index]*0.72+center*0.28
        if sample_grid(data["signed_distance"],*p)<0.7:
            p=pts[index]*0.55+center*0.45
        light_markers.append({"position":[float(p[0]),2.25,float(p[1])],"energy":1.8,"range":10.5,"kind":"lantern"})
for index,link in enumerate(layout["corridors"]):
    if index%2:
        continue
    points=np.array(link["points"])
    mid=points[len(points)//2]
    v=points[-1]-points[0]
    v/=max(0.001,np.linalg.norm(v))
    p=mid+np.array([-v[1],v[0]])*(link["width"]*.5-.35)
    light_markers.append({"position":[float(p[0]),2.0,float(p[1])],"energy":1.35,"range":8.0,"kind":"lantern"})
for i,entry in enumerate(light_markers):
    x,y,z=entry["position"]
    light_data=bpy.data.lights.new("Lantern_%03d"%i,"POINT")
    light_data.color=(1.0,0.72,0.43)
    light_data.energy=120.0 if entry["energy"]>1.5 else 85.0
    light_data.shadow_soft_size=.11
    obj=bpy.data.objects.new("MineLight_%03d"%i,light_data)
    lights_collection.objects.link(obj)
    obj.location=(x,-z,y)
    marker=bpy.data.objects.new("LightMarker_%03d"%i,None)
    lights_collection.objects.link(marker)
    marker.location=obj.location
    # A soot-black bracket/post anchors the portable miner lantern in space.
architecture_report=mine_props.add_stone_architecture(layout,materials,props_collection,clearance_fn=clear,ground_height_fn=floor_height) if hasattr(mine_props,"add_stone_architecture") else {}
fixture_report=mine_props.add_light_fixtures(layout,materials,props_collection,light_markers,ground_height_fn=floor_height)


# Calm water follows the six authored lake outlines and their irregular islands.
water=bpy.data.materials.new("Mine_Blackwater")
water.use_nodes=True
pbs=water.node_tree.nodes.get("Principled BSDF")
pbs.inputs["Base Color"].default_value=(0.018,0.043,0.036,1)
pbs.inputs["Roughness"].default_value=.23
pbs.inputs["Metallic"].default_value=.2
for i,pool in enumerate(layout["pools"]):
    from mathutils.geometry import tessellate_polygon
    poly=[Vector((x,-z,0.005)) for x,z in pool["polygon"]]
    tris=tessellate_polygon([poly])
    verts=[];faces_water=[]
    for triangle in tris:
        tri = [poly[v] if isinstance(v, int) else v for v in triangle]
        idx=len(verts)
        verts.extend([tuple(p) for p in tri])
        faces_water.append((idx,idx+1,idx+2) if (tri[1]-tri[0]).cross(tri[2]-tri[0]).z>0 else (idx,idx+2,idx+1))
    obj=mesh_object("Water_%02d"%i,verts,faces_water,water)
    obj["shallow_water"]=True


# Bake all metric UV scaling into UV coordinates before glTF serialization.
# glTF supports the maps directly; no opaque procedural rock shader is required.
for mesh in bpy.data.meshes:
    if not mesh.uv_layers or not mesh.materials:
        continue
    layer=mesh.uv_layers.active
    for poly in mesh.polygons:
        if poly.material_index>=len(mesh.materials):
            continue
        mat=mesh.materials[poly.material_index]
        if mat and "scan_tile_m" in mat:
            inv=1.0/float(mat["scan_tile_m"])
            for loop_index in poly.loop_indices:
                layer.data[loop_index].uv*=inv
for mat in materials.values():
    for node in mat.node_tree.nodes:
        if node.type=="VECT_MATH" and node.operation=="SCALE":
            node.inputs["Scale"].default_value=1.0


# Merge tiny mineral objects per spatial tile/material without losing geometry.
merge_groups=defaultdict(list)
for obj in list(formations_collection.objects):
    if obj.type=="MESH" and obj.name.startswith(("CalciteCeiling_","Scree_")):
        center=obj.matrix_world @ (sum((Vector(corner) for corner in obj.bound_box),Vector())/8)
        merge_groups[(int(center.x//16),int(center.y//16),obj.data.materials[0].name)].append(obj)
for index,objects in enumerate(merge_groups.values()):
    if len(objects)<2:
        continue
    bpy.ops.object.select_all(action="DESELECT")
    for obj in objects:
        obj.select_set(True)
    bpy.context.view_layer.objects.active=objects[0]
    bpy.ops.object.join()
    bpy.context.object.name="MineralCluster_%03d"%index


# glTF tangents require triangles/quads; mineral cap n-gons are triangulated
# with their UVs preserved before both source save and portable export.
for mesh in bpy.data.meshes:
    if not any(len(face.vertices)>4 for face in mesh.polygons):
        continue
    bm=bmesh.new()
    bm.from_mesh(mesh)
    bmesh.ops.triangulate(bm,faces=[face for face in bm.faces if len(face.verts)>4])
    bm.to_mesh(mesh)
    bm.free()
    mesh.update()

report={"pipeline":"Blender-authored 3D sculpt + CC0 photogrammetry PBR + physically modeled mining equipment","width_m":131,"depth_m":139,"rooms":len(layout["rooms"]),"corridors":len(layout["corridors"]),"terrain_triangles":len(faces),"scan_outcrops":scan_count,"mineral_formations":formation_count,"lights":light_markers,"props":props_report,"bones":bones_report,"architecture":architecture_report,"fixtures":fixture_report,"blender_version":bpy.app.version_string}
import scene_polish
report=scene_polish.finish_scene(layout,report)

# Full .blend is the source of truth for visual review, with packed scan textures.
bpy.ops.object.select_all(action="DESELECT")
scene["MineFootprintMetres"]=[131.0,139.0]
scene["Narrative"]="A working mine abandoned after monsters overwhelmed the miners; years of water, collapse and calcite growth."
scene["ReferenceLayout"]="layout.json: 18 chambers, 31 authored connecting routes"
bpy.ops.file.pack_all()
bpy.ops.wm.save_as_mainfile(filepath=str(ROOT/"blackwater_abandoned_mine.blend"))
export_temp=ROOT/"abandoned_mine_export.glb"
kwargs=dict(filepath=str(export_temp),export_format="GLB",export_apply=True,export_yup=True,export_normals=True,export_tangents=True,export_materials="EXPORT",export_animations=False,export_cameras=False,export_lights=False,export_extras=True,export_image_format="AUTO")
bpy.ops.export_scene.gltf(**kwargs)
ASSETS.mkdir(parents=True,exist_ok=True)
os.replace(export_temp,ASSETS/"abandoned_mine.glb")
report['build_seconds']=round(time.time()-started,1)
(ASSETS/"build_manifest.json").write_text(json.dumps(report,indent=2,default=str))
(ROOT/"build_report.json").write_text(json.dumps(report,indent=2,default=str))
print("MINE BUILD COMPLETE",json.dumps({k:v for k,v in report.items() if k not in ["props","lights","fixtures","architecture","bones"]}),flush=True)
