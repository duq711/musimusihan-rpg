"""Noninteractive anatomy and mesh QA; run with Blender --background --threads 2."""
import json
import math
import numpy as np
import sys
from pathlib import Path
import bpy
import bmesh
from mathutils import Vector
ROOT=Path(__file__).resolve().parent
sys.path.insert(0,str(ROOT))
import bone_props
bpy.ops.object.select_all(action="SELECT")
bpy.ops.object.delete(use_global=False)
collection=bpy.data.collections.new("MonsterRemainsQA")
bpy.context.scene.collection.children.link(collection)
layout=json.loads((ROOT/"layout.json").read_text())
terrain=np.load(ROOT/"terrain_mesh.npz")
xs,zs=terrain["xs"],terrain["zs"]
def sample_grid(grid,x,z):
    ix=int(np.clip(round((x-xs[0])/(xs[1]-xs[0])),0,len(xs)-1))
    iz=int(np.clip(round((z-zs[0])/(zs[1]-zs[0])),0,len(zs)-1))
    return float(grid[iz,ix])
segments=[(a,b) for link in layout["corridors"] for a,b in zip(link["points"],link["points"][1:])]
reserved=[((v["position"][0],v["position"][2]),2) for group in layout["gameplay"].values() for v in group]
def clearance(x,z,radius):
    if abs(x)+radius>64.8 or abs(z)+radius>68.8:
        return False
    if sample_grid(terrain["signed_distance"],x,z)<max(.1,radius*.3):
        return False
    for a,b in segments:
        vx,vz=b[0]-a[0],b[1]-a[1]
        t=max(0,min(1,((x-a[0])*vx+(z-a[1])*vz)/max(.001,vx*vx+vz*vz)))
        if math.hypot(x-a[0]-t*vx,z-a[1]-t*vz)<radius+1.35:
            return False
    return all(math.hypot(x-p[0],z-p[1])>=radius+r for p,r in reserved)
report=bone_props.build_monster_remains(layout,{},collection,clearance,lambda x,z:sample_grid(terrain["floor"],x,z))
assert report["counts"].get("monster_skeleton")==1, report
assert report["assets"][0]["skull_eye_sockets"]==2
assert report["assets"][0]["anatomical_parts"]["intact_rib"]==19
assert report["assets"][0]["anatomical_parts"]["broken_rib"]==5
for obj in collection.objects:
    if obj.type=="MESH":
        assert obj.data.uv_layers and len(obj.data.materials)>0
        assert all(len(set(p.vertices))==len(p.vertices) for p in obj.data.polygons)
        assert all(v.co.length<100 for v in obj.data.vertices)
report["qa_checks"]=["two perforated orbital sockets","19 intact and 5 fractured ribs","UVs and bone material present","finite mesh vertices","all footprint samples pass real terrain, corridor and reserved-gameplay clearance"]
# Tests explicit rejection without generating any geometry or silently placing
# an oversized skeleton across an occupied passage.
blocked=bone_props.build_monster_remains(layout,{},collection,lambda x,z,r:False)
assert blocked["assets"]==[] and blocked["skipped"]
report["qa_checks"].append("blocked clearance returns explicit skipped asset")
group=bpy.data.objects.get("Mine_bone_cavern_monster_skeleton")
group.location=(0,0,-.055)
group.rotation_euler.z=0
scene=bpy.context.scene
scene.render.engine="CYCLES"
scene.cycles.device="CPU"
scene.cycles.samples=16
scene.cycles.use_denoising=True
scene.cycles.max_bounces=4
scene.render.threads_mode="FIXED"
scene.render.threads=2
scene.render.resolution_x=1200
scene.render.resolution_y=850
scene.render.resolution_percentage=100
scene.world.use_nodes=True
scene.world.node_tree.nodes["Background"].inputs["Color"].default_value=(.22,.25,.29,1)
scene.world.node_tree.nodes["Background"].inputs["Strength"].default_value=.30
scene.view_settings.view_transform="AgX"
mat=bpy.data.materials.new("QA_SlateFloor")
mat.diffuse_color=(.065,.059,.051,1)
mat.use_nodes=True
mat.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value=mat.diffuse_color
mat.node_tree.nodes["Principled BSDF"].inputs["Roughness"].default_value=.97
bpy.ops.mesh.primitive_plane_add(size=200,location=(0,0,-.06))
bpy.context.object.data.materials.append(mat)
for name,position,energy,size,color in [("Key",(1,-5,8),2200,6,(1,.86,.69)),("Fill",(-7,-1,5),1600,5,(.61,.73,1)),("Rim",(1,6,7),2200,5,(1,.71,.43))]:
    data=bpy.data.lights.new(name,"AREA")
    data.energy=energy
    data.shape="DISK"
    data.size=size
    data.color=color
    obj=bpy.data.objects.new(name,data)
    scene.collection.objects.link(obj)
    obj.location=position
    obj.rotation_euler=(Vector((0,0,.6))-obj.location).to_track_quat("-Z","Y").to_euler()
data=bpy.data.cameras.new("AnatomicalQA")
camera=bpy.data.objects.new("AnatomicalQA",data)
scene.collection.objects.link(camera)
scene.camera=camera
camera.location=(9,-13,9)
camera.rotation_euler=(Vector((0,-.25,.85))-camera.location).to_track_quat("-Z","Y").to_euler()
data.type="ORTHO"
data.ortho_scale=15.0
out=ROOT/"qa"
out.mkdir(exist_ok=True)
(out/"monster_remains_report.json").write_text(json.dumps(report,indent=2))
scene.render.filepath=str(out/"monster_remains_anatomy.png")
bpy.ops.render.render(write_still=True)
print("MONSTER_REMAINS_QA "+json.dumps(report))
