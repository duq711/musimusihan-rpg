"""Background material/geometry QA of the actual authored mine assemblies."""
import json
import sys
from pathlib import Path

import bpy
from mathutils import Vector

ROOT=Path(__file__).resolve().parent
sys.path.insert(0,str(ROOT))
import mine_props

bpy.ops.object.select_all(action="SELECT")
bpy.ops.object.delete(use_global=False)
collection=bpy.data.collections.new("MinePropsCloseupQA")
bpy.context.scene.collection.children.link(collection)


def scan(name,scan_name,scale,metallic=0):
    material=bpy.data.materials.new(name)
    material.use_nodes=True
    nodes=material.node_tree.nodes
    links=material.node_tree.links
    shader=nodes.get("Principled BSDF")
    shader.inputs["Metallic"].default_value=metallic
    uv=nodes.new("ShaderNodeTexCoord")
    mapping=nodes.new("ShaderNodeMapping")
    mapping.inputs["Scale"].default_value=(scale,scale,scale)
    links.new(uv.outputs["UV"],mapping.inputs["Vector"])
    for suffix,socket in [("albedo","Base Color"),("roughness","Roughness"),("normal_gl",None)]:
        path=ROOT/"material_sources"/"originals"/f"{scan_name}_{suffix}_2k.jpg"
        image=bpy.data.images.load(str(path),check_existing=True)
        if suffix!="albedo":
            image.colorspace_settings.name="Non-Color"
        texture=nodes.new("ShaderNodeTexImage")
        texture.image=image
        links.new(mapping.outputs["Vector"],texture.inputs["Vector"])
        if suffix=="normal_gl":
            normal=nodes.new("ShaderNodeNormalMap")
            normal.inputs["Strength"].default_value=.75
            links.new(texture.outputs["Color"],normal.inputs["Color"])
            links.new(normal.outputs["Normal"],shader.inputs["Normal"])
        else:
            links.new(texture.outputs["Color"],shader.inputs[socket])
    return material


materials={"wood":scan("QA_ScannedHewnWood","rough_wood",2),
           "metal":scan("QA_ScannedRust","rust_coarse_01",1/2.2,.62),
           "rock":scan("QA_ScannedRock","rock_boulder_dry",1/1.8),
           "rock_dark":scan("QA_ScannedOre","dark_rock_02",.5),
           "ground":scan("QA_ScannedMud","brown_mud_rocks_01",1/1.3)}
layout=json.loads((ROOT/"layout.json").read_text())
props=mine_props.Props(layout,materials,collection,None,None)
for kind,position,angle,callback in [
    ("manual_hoist",(0,0),0,props.winch),
    ("overturned_cart",(-3.5,.1),.15,lambda:props.cart(True)),
    ("timber_support",(-3.9,-3.2),.1,lambda:props.support(3.6,3.4)),
    ("workbench",(3.2,.1),-.12,props.workbench),
    ("stacked_crates",(3.2,-2.1),.15,lambda:(props.crate(),props.crate((.92,.12,0),(.75,.65,.60),True))),
    ("barrels",(2.8,1.7),0,lambda:(props.barrel(),props.barrel((.75,.2,0),.8))),
    ("hand_tools",(4.7,.4),.6,lambda:(props.pickaxe(),props.shovel((.6,0,0)))),
]:
    props.begin(kind,"closeup_qa",position,angle)
    callback()
    props.finish()
mine_props.add_light_fixtures(layout,materials,collection,[{"id":"fixture_sample","position":[-1.75,2.1,.2]}])
props.begin("qa_ground","closeup_qa",(0,0))
props.mesh("QA_MudGround",[(-20,-20,-.03),(20,-20,-.03),(20,20,-.03),(-20,20,-.03)],[(0,1,2,3)],"ground")
props.finish()

scene=bpy.context.scene
scene.render.engine="CYCLES"
scene.cycles.device="CPU"
scene.cycles.samples=12
scene.cycles.use_denoising=True
scene.cycles.max_bounces=4
scene.render.threads_mode="FIXED"
scene.render.threads=2
scene.render.resolution_x=1100
scene.render.resolution_y=760
scene.render.resolution_percentage=100
scene.world.use_nodes=True
scene.world.node_tree.nodes["Background"].inputs["Color"].default_value=(.23,.28,.34,1)
scene.world.node_tree.nodes["Background"].inputs["Strength"].default_value=.25
scene.view_settings.view_transform="AgX"
scene.view_settings.exposure=.2
for name,position,energy,size,color in [("Key",(1,-5,8),1700,6,(1,.80,.57)),("Fill",(-7,-1,5),1200,5,(.55,.72,1)),("Rim",(1,6,7),1700,5,(1,.65,.36))]:
    data=bpy.data.lights.new(name,"AREA")
    data.energy=energy
    data.shape="DISK"
    data.size=size
    data.color=color
    light=bpy.data.objects.new(name,data)
    collection.objects.link(light)
    light.location=position
    light.rotation_euler=(Vector((0,0,1))-light.location).to_track_quat("-Z","Y").to_euler()
camera_data=bpy.data.cameras.new("MinePropsQACamera")
camera=bpy.data.objects.new("MinePropsQACamera",camera_data)
collection.objects.link(camera)
camera.location=(10,-13.6,8.6)
camera.rotation_euler=(Vector((0,.1,1.5))-camera.location).to_track_quat("-Z","Y").to_euler()
camera_data.lens=42
scene.camera=camera
scene.render.image_settings.file_format="PNG"
scene.render.filepath=str(ROOT/"mine_props_closeup.png")
bpy.ops.wm.save_as_mainfile(filepath=str(ROOT/"mine_props_closeup.blend"))
bpy.ops.render.render(write_still=True)
print("MINE PROPS CLOSEUP QA: "+scene.render.filepath,flush=True)
