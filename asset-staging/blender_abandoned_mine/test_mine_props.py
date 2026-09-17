"""Quiet background construction QA; writes only to this staging directory."""
import json
import sys
from pathlib import Path

import bpy

ROOT=Path(__file__).resolve().parent
sys.path.insert(0,str(ROOT))
import mine_props

bpy.ops.object.select_all(action="SELECT")
bpy.ops.object.delete(use_global=False)
collection=bpy.data.collections.new("MinePropsValidation")
bpy.context.scene.collection.children.link(collection)
layout=json.loads((ROOT/"layout.json").read_text())
materials={
    "rock":mine_props._plain_material("QA_Rock",(.12,.095,.07)),
    "rock_dark":mine_props._plain_material("QA_Ore",(.055,.045,.03),.71),
    "ground":mine_props._plain_material("QA_Ground",(.08,.055,.035)),
    "wood":mine_props._plain_material("QA_Wood",(.13,.075,.033)),
    "metal":mine_props._plain_material("QA_Metal",(.067,.045,.025),.68,.7),
}
metadata=mine_props.build_props(layout,materials,collection)
lights=[{"id":f"fixture_{i}","room_id":"entrance","position":[-3+i*1.3,2.2,57]} for i in range(6)]
fixtures=mine_props.add_light_fixtures(layout,materials,collection,lights)
architecture=mine_props.add_stone_architecture(layout,materials,collection)
visible=[obj for obj in collection.all_objects if obj.type=="MESH" and not obj.hide_render]
assert metadata["counts"].get("manual_hoist",0)==1,metadata["skipped"]
assert metadata["counts"].get("weathered_footbridge",0)==2
assert metadata["counts"].get("short_disused_rail",0)==3
assert len(fixtures["assets"])==6
assert architecture["counts"].get("stone_pillar",0)==13,architecture
assert architecture["counts"].get("ruined_shrine",0)==1,architecture
assert architecture["counts"].get("ruined_altar",0)==1,architecture
assert not architecture["skipped"],architecture["skipped"]
assert all(len(obj.data.uv_layers)>0 for obj in visible)
assert all(len(obj.data.polygons)>0 for obj in visible)
assert all(all(len(set(poly.vertices))>=3 for poly in obj.data.polygons) for obj in visible)
assert len(visible)<200,len(visible)
bridge_boxes=[p for p in metadata["collision_proxies"] if "bridge_deck_board" in p["name"]]
assert all(p["center_godot"][1]+p["size_godot"][1]/2<=.06 for p in bridge_boxes)
report={"props":metadata,"fixtures":fixtures,"architecture":architecture,"visible_meshes":len(visible),
        "vertices":sum(len(obj.data.vertices) for obj in visible),
        "polygons":sum(len(obj.data.polygons) for obj in visible)}
(ROOT/"props_validation.json").write_text(json.dumps(report,indent=2))
bpy.ops.wm.save_as_mainfile(filepath=str(ROOT/"mine_props_validation.blend"))
print("MINE PROPS PASS",json.dumps({key:report[key] for key in ("visible_meshes","vertices","polygons")}),flush=True)
