"""Reopen the saved native file and round-trip each animated GLB, background only."""
import hashlib, importlib.util, json
from pathlib import Path
import bpy
from mathutils import Matrix
from mathutils.kdtree import KDTree

STAGE=Path(__file__).resolve().parents[1]
spec=importlib.util.spec_from_file_location("capture_bake",STAGE/"tools/bake_captured_motion.py")
bake=importlib.util.module_from_spec(spec);spec.loader.exec_module(bake)
OUT=STAGE/"editable"
report={"native_reopen":[],"glb_roundtrip":[],"tolerance_m":.00002}


def bundle_from_scene(scene,clip,label,filename):
    container=scene.objects[clip+"__"+label]
    objects=list(container.children_recursive)
    document=bake.gm.GLB((STAGE/"source"/filename).read_bytes())
    result={"container":container,"objects":objects,"document":document}
    if label.endswith("Hand"):
        rig=next(o for o in objects if o.type=="ARMATURE")
        result["armature"]=rig;result["rest_object"]=Matrix.Identity(4)
        result["rests"]={bone.name:bone.matrix_local.copy() for bone in rig.data.bones}
        globals_=bake.gm.globals_for(document.doc)
        result["game_rests"]={n["name"]:Matrix(globals_[i]) for i,n in enumerate(document.doc["nodes"]) if n["name"] in result["rests"]}
        result["rigid"]={key:next(o for o in objects if o.type=="EMPTY" and str(o.get("source_node","")).startswith(key)) for key in ("Forearm","UpperArm","WristCuff")}
        result["skin"]=next(o for o in objects if o.type=="MESH" and str(o.get("source_node","")).startswith("ContinuousAnatomicalHand"))
    return result


def main():
    blend=OUT/"Sword_Shield_Captured_Motion.blend"
    bpy.ops.wm.open_mainfile(filepath=str(blend))
    assert len(bpy.data.scenes)==6
    images=[image for image in bpy.data.images if image.get("source_filename")]
    assert len(images)==7 and all(image.packed_file and image.filepath.startswith("//") for image in images)
    for sequence in bake.manifest["sequences"]:
        clip=sequence["id"];scene=bpy.data.scenes[clip];bpy.context.window.scene=scene
        assert scene.render.fps==30 and scene.frame_start==1 and scene.frame_end==34
        data={label:bundle_from_scene(scene,clip,label,filename) for label,filename in (("Sword","longsword.glb"),("Shield","round_shield.glb"),("LeftHand","left_arm.glb"),("RightHand","right_arm.glb"))}
        metrics=bake.verify_scene(scene,data,sequence)
        scene.frame_set(7);bpy.context.view_layer.update()
        camera_error=max(abs(scene.camera.matrix_world[r][c]-(bake.C @ bake.matrix(sequence["pov"][6]["view_camera_transform"]))[r][c]) for r in range(4) for c in range(4))
        assert camera_error<.000002
        report["native_reopen"].append({"action":clip,**metrics,"camera_matrix_max_error":camera_error,"editable_hand_bones":32})
    # Independently re-import each final glTF. Export/import may change vertex
    # order, so compare actual posed geometry by nearest corresponding surface
    # point rather than assuming exporter-specific numbering.
    for sequence in bake.manifest["sequences"]:
        clip=sequence["id"];bpy.ops.wm.read_factory_settings(use_empty=True)
        scene=bpy.context.scene;scene.render.fps=30
        bpy.ops.import_scene.gltf(filepath=str(OUT/(clip+".glb")),merge_vertices=False)
        rigs=[o for o in scene.objects if o.type=="ARMATURE"]
        assert len(rigs)==2 and all(len(rig.data.bones)==16 for rig in rigs)
        maximum=0.;samples=0
        for source_frame in (0,6,11,17,33):
            scene.frame_set(source_frame);bpy.context.view_layer.update();graph=bpy.context.evaluated_depsgraph_get()
            for side,label in (("left","LeftHand"),("right","RightHand")):
                skin=next(o for o in scene.objects if o.type=="MESH" and label in o.name and str(o.get("source_node","")).startswith("ContinuousAnatomicalHand"))
                evaluated=skin.evaluated_get(graph);mesh=evaluated.to_mesh();tree=KDTree(len(mesh.vertices))
                for i,v in enumerate(mesh.vertices):tree.insert(evaluated.matrix_world @ v.co,i)
                tree.balance()
                bundle={"document":bake.gm.GLB((STAGE/"source"/(side+"_arm.glb")).read_bytes())}
                node=next(n for n in bundle["document"].doc["nodes"] if n["name"].startswith("ContinuousAnatomicalHand"))
                primitive=bundle["document"].doc["meshes"][node["mesh"]]["primitives"][0]
                count=bundle["document"].doc["accessors"][primitive["attributes"]["POSITION"]]["count"]
                for i in range(40):
                    expected=bake.expected_skin(bundle,sequence["pov"][source_frame]["arm_landmarks"][side],round(i*(count-1)/39))
                    _,_,distance=tree.find(expected);maximum=max(maximum,distance);samples+=1
                evaluated.to_mesh_clear()
        assert maximum<.00002,(clip,maximum)
        report["glb_roundtrip"].append({"action":clip,"max_skin_surface_sample_error_m":maximum,"skin_samples":samples,"editable_hand_bones":32})
        print("ROUNDTRIP_PASS",clip,maximum,flush=True)
    report["passed"]=True
    (STAGE/"reopen_validation.json").write_text(json.dumps(report,indent=2)+"\n")
    print("REOPEN_VALIDATION_PASS",flush=True)


if __name__=="__main__":main()
