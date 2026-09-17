"""Blender background-only export of the recorded production motion.

No new movement is authored. Six scenes contain the 34 recorded samples each.
Source GLBs/manifests and all game files are read-only.
"""
from pathlib import Path
import hashlib, importlib.util, json, math, sys
import bpy
from mathutils import Matrix, Vector

STAGE = Path(__file__).resolve().parents[1]
ROOT = Path(__file__).resolve().parents[4]
SOURCE = STAGE / "source"
OUT = STAGE / "editable"
OUT.mkdir(exist_ok=True)
spec = importlib.util.spec_from_file_location("glb_preservation_math", ROOT / "asset-staging/sword_shield_single_pose/proportioned_hands/proportion_hands.py")
gm = importlib.util.module_from_spec(spec); spec.loader.exec_module(gm)
manifest_bytes = (SOURCE / "capture_manifest.json").read_bytes()
manifest = json.loads(manifest_bytes)
C = Matrix(((1,0,0,0),(0,0,-1,0),(0,1,0,0),(0,0,0,1)))
CI = C.inverted()
material_cache = {}
bundles = []
report = {"blender_version": bpy.app.version_string, "source_manifest_sha256": hashlib.sha256(manifest_bytes).hexdigest(), "fps": 30, "frames_per_action": 34, "clips": [], "source_sha256": {}, "limitations": ["Baked editable FK animation; no new IK/control rig or procedural combat logic.", "The first-person camera is recorded. Blender lighting is a neutral editing studio, not a Godot renderer recreation."]}


def matrix(record):
    result = Matrix.Identity(4)
    for row in range(3):
        for col in range(3): result[row][col] = record["basis"][col][row]
        result[row][3] = record["origin"][row]
    return result


def converted(value): return C @ value @ CI


def segment_frame(start, end):
    direction = (end - start).normalized()
    reference = Vector((0,1,0)) if abs(direction.y) < .95 else Vector((0,0,-1))
    lateral = reference.cross(direction).normalized()
    result = Matrix((lateral, direction, lateral.cross(direction).normalized())).transposed().to_4x4()
    result.translation = start
    return result


def fit_segment(rest_start, rest_end, target_start, target_end):
    scale = Matrix.Diagonal((1, (target_start-target_end).length/(rest_start-rest_end).length, 1, 1))
    return segment_frame(target_start,target_end) @ scale @ segment_frame(rest_start,rest_end).inverted()


def fit_rigid(record):
    hand = matrix(record["wrist_transform"])
    elbow = hand.inverted() @ Vector(record["elbow"])
    shoulder = hand.inverted() @ Vector(record["shoulder"])
    forearm = fit_segment(Vector((0,0,.26)),Vector(),elbow,Vector())
    upper = fit_segment(Vector((0,0,.60)),Vector((0,0,.26)),shoulder,elbow)
    cuff = forearm.to_3x3().normalized().to_4x4()
    return hand, {"Forearm":forearm,"UpperArm":upper,"WristCuff":cuff}


def image(name):
    paths = [ROOT/"godot-game/assets/ai/sword_shield"/name, ROOT/"godot-game/assets/3d/player/sword_shield/textures"/name, ROOT/"godot-game/assets/ai/materials"/name]
    source = next(p for p in paths if p.exists())
    for existing in bpy.data.images:
        if existing.get("source_filename") == name: return existing
    result = bpy.data.images.load(str(source), check_existing=True)
    result["source_filename"] = name
    result.pack()
    result.filepath = "//../Textures/" + name
    return result


def prepare_material(source):
    name = source.name.split(".")[0]
    old = source.node_tree.nodes.get("Principled BSDF") if source.use_nodes else None
    rough = float(old.inputs["Roughness"].default_value) if old else source.roughness
    metal = float(old.inputs["Metallic"].default_value) if old else source.metallic
    tint = tuple(old.inputs["Base Color"].default_value[:3]) if old else tuple(source.diffuse_color[:3])
    texture = normal = None; strength = 0.; uv = 1.; ao = False
    weapon = {
      "FP_SwordBlade":((1,1,1),.62,.48,.22),"FP_SwordFurniture":((1,1,1),.62,.48,.22),
      "FP_SwordEdge":((1.2,1.22,1.23),.62,.38,.22),"FP_SwordFuller":((.55,.57,.59),.62,.48,.22),
      "FP_SwordLeather":((.35,.32,.29),0,.67,.22),"FP_ShieldOak":((.46,.43,.40),0,.86,.45),
      "FP_ShieldIron":((1,1,1),.68,.48,.28),"FP_ShieldEdge":((.68,.70,.71),.62,.44,.20),
      "FP_ShieldEnarmes":((.35,.32,.29),0,.67,.45),"FP_ShieldLeatherEdge":((.60,.45,.34),0,.67,.45),
      "FP_ShieldStitch":((1.3,1.14,.89),0,.67,.45)}
    if name in weapon:
        tint,metal,rough,strength = weapon[name]; texture="weapon_material_atlas_v2.png"; normal="weapon_material_normal_v2.png"; ao=True
    elif name == "FP_Skin": tint=(.75,.75,.75);metal=0;rough=.72;texture="weathered_hand_skin.png";uv=2
    elif name in ("FP_WornLeather","FP_LayeredVambrace","FP_SleeveStrap"):
        tint,rough,strength={"FP_WornLeather":((.62,.58,.52),.66,.20),"FP_LayeredVambrace":((.60,.54,.45),.74,.15),"FP_SleeveStrap":((.25,.21,.17),.82,.15)}[name]
        metal=0;texture="worn_charcoal_leather.png";normal="leather_normal.jpg";uv=.5
    elif name == "FP_QuiltedLinen": tint=(.12,.105,.085);metal=0;rough=.94;texture="linen_albedo.jpg";normal="linen_normal.jpg";strength=.38
    elif name == "FP_SleeveBuckles": tint=(.20,.21,.20);metal=.55;rough=.72
    elif name == "FP_LeatherEdge": tint=(.17,.14,.11);metal=0
    elif name == "FP_WaxedThread": tint=(.23,.20,.17);metal=0
    elif name == "FP_AgedSteel": tint=(.52,.55,.58);metal=.45;rough=.42;texture="concept_forged_steel.png"
    key=(name,tint,metal,rough,strength,uv)
    if key in material_cache:return material_cache[key]
    material=bpy.data.materials.new(name+"__GameMaterial");material.use_nodes=True
    nodes=material.node_tree.nodes;links=material.node_tree.links;nodes.clear()
    output=nodes.new("ShaderNodeOutputMaterial");shader=nodes.new("ShaderNodeBsdfPrincipled")
    links.new(shader.outputs["BSDF"],output.inputs["Surface"])
    shader.inputs["Base Color"].default_value=(*tint,1);shader.inputs["Metallic"].default_value=metal;shader.inputs["Roughness"].default_value=rough
    shader.inputs["Specular IOR Level"].default_value=.75 if name=="FP_AgedSteel" else .5
    if texture:
        texcoord=nodes.new("ShaderNodeTexCoord");mapping=nodes.new("ShaderNodeMapping");mapping.inputs["Scale"].default_value=(uv,uv,1);links.new(texcoord.outputs["UV"],mapping.inputs["Vector"])
        tex=nodes.new("ShaderNodeTexImage");tex.image=image(texture);links.new(mapping.outputs["Vector"],tex.inputs["Vector"])
        multiply=nodes.new("ShaderNodeMixRGB");multiply.blend_type="MULTIPLY";multiply.inputs[0].default_value=1;links.new(tex.outputs["Color"],multiply.inputs[1]);multiply.inputs[2].default_value=(*tint,1)
        result=multiply.outputs["Color"]
        if ao:
            color=nodes.new("ShaderNodeVertexColor");color.layer_name="Color"
            mix=nodes.new("ShaderNodeMixRGB");mix.blend_type="MULTIPLY";mix.inputs[0].default_value=1;links.new(result,mix.inputs[1]);links.new(color.outputs["Color"],mix.inputs[2]);result=mix.outputs[0]
        links.new(result,shader.inputs["Base Color"])
        if normal:
            tex=nodes.new("ShaderNodeTexImage");tex.image=image(normal);tex.image.colorspace_settings.name="Non-Color";links.new(mapping.outputs["Vector"],tex.inputs["Vector"])
            normal_map=nodes.new("ShaderNodeNormalMap");normal_map.inputs["Strength"].default_value=strength;links.new(tex.outputs["Color"],normal_map.inputs["Color"]);links.new(normal_map.outputs["Normal"],shader.inputs["Normal"])
    material["godot_material"]=name;material["original_uvs_unchanged"]=True
    material_cache[key]=material
    return material


def import_bundle(scene, clip, label, filename):
    prior=set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=str(SOURCE/filename), merge_vertices=False)
    imported=set(bpy.data.objects)-prior
    document=gm.GLB((SOURCE/filename).read_bytes())
    root_name=document.doc["nodes"][document.doc["scenes"][0]["nodes"][0]]["name"]
    root=next(o for o in imported if o.name.startswith(root_name) and o.parent is None)
    objects=[root]+list(root.children_recursive)
    original_names={o:o.name for o in objects}
    container=bpy.data.objects.new(clip+"__"+label,None);scene.collection.objects.link(container);root.parent=container
    for obj in objects:
        obj["source_node"]=original_names[obj]
        obj.name=clip+"__"+label+"__"+original_names[obj]
        if obj.type=="MESH":
            for slot in obj.material_slots:slot.material=prepare_material(slot.material)
            if obj.data.color_attributes:
                obj.data.color_attributes[0].name="Color"
    result={"container":container,"root":root,"objects":objects,"document":document,"names":original_names,"filename":filename}
    if label.endswith("Hand"):
        armature=next(o for o in objects if o.type=="ARMATURE")
        result["armature"]=armature
        result["rest_object"]=armature.matrix_world.copy()
        result["rests"]={bone.name:bone.matrix_local.copy() for bone in armature.data.bones}
        globals_=gm.globals_for(document.doc)
        result["game_rests"]={node["name"]:Matrix(globals_[i]) for i,node in enumerate(document.doc["nodes"]) if node["name"] in result["rests"]}
        result["rigid"]={key:next(o for o in objects if o.type=="EMPTY" and original_names[o].startswith(key)) for key in ("Forearm","UpperArm","WristCuff")}
        result["skin"]=next(o for o in objects if o.type=="MESH" and original_names[o].startswith("ContinuousAnatomicalHand"))
        armature.show_in_front=True;armature.data.display_type="OCTAHEDRAL"
    return result


def key_transform(obj, transform, frame):
    obj.rotation_mode="QUATERNION";obj.matrix_basis=transform
    for path in ("location","rotation_quaternion","scale"):obj.keyframe_insert(data_path=path,frame=frame,group="Captured transform")


def apply_arm(bundle, record, frame):
    hand,rigid=fit_rigid(record)
    key_transform(bundle["container"],converted(hand),frame)
    for label,transform in rigid.items():key_transform(bundle["rigid"][label],converted(transform),frame)
    armature=bundle["armature"];A=bundle["rest_object"]
    targets={}
    for bone in record["bones"]:
        name=bone["name"]
        delta=converted(hand.inverted() @ matrix(bone["world_pose"]) @ bundle["game_rests"][name].inverted())
        targets[name]=A.inverted() @ delta @ A @ bundle["rests"][name]
    for bone in armature.pose.bones:
        rest=bundle["rests"][bone.name]
        if bone.parent: basis=rest.inverted() @ bundle["rests"][bone.parent.name] @ targets[bone.parent.name].inverted() @ targets[bone.name]
        else:basis=rest.inverted() @ targets[bone.name]
        bone.rotation_mode="QUATERNION";bone.matrix_basis=basis
        for path in ("location","rotation_quaternion","scale"):bone.keyframe_insert(data_path=path,frame=frame,group=bone.name)


def expected_skin(bundle, record, source_index):
    document=bundle["document"];node=next(n for n in document.doc["nodes"] if n["name"].startswith("ContinuousAnatomicalHand"))
    attrs=document.doc["meshes"][node["mesh"]]["primitives"][0]["attributes"]
    if "raw_skin" not in bundle: bundle["raw_skin"]={key:document.read(attrs[key]) for key in ("POSITION","JOINTS_0","WEIGHTS_0")}
    raw=bundle["raw_skin"];point=Vector(raw["POSITION"][source_index]);js=raw["JOINTS_0"][source_index];ws=raw["WEIGHTS_0"][source_index]
    skin=document.doc["skins"][node["skin"]]
    if "raw_binds" not in bundle:bundle["raw_binds"]=document.read(skin["inverseBindMatrices"])
    binds=bundle["raw_binds"];poses={b["name"]:matrix(b["world_pose"]) for b in record["bones"]}
    result=Vector()
    for joint,weight in zip(js,ws):
        if weight>0:result+=(poses[document.doc["nodes"][skin["joints"][joint]]["name"]] @ Matrix(gm.from_glb(binds[joint])) @ point)*weight
    return C @ result


def verify_scene(scene, data, sequence):
    metrics={"max_skin_vertex_error_m":0.,"max_bone_deformation_error":0.,"max_rigid_transform_error":0.,"sample_frames":[0,6,11,17,33],"skin_samples":0}
    for source_frame in metrics["sample_frames"]:
        scene.frame_set(source_frame+1);bpy.context.view_layer.update();graph=bpy.context.evaluated_depsgraph_get();record=sequence["pov"][source_frame]
        for side,label in (("left","LeftHand"),("right","RightHand")):
            bundle=data[label];hand=matrix(record["arm_landmarks"][side]["wrist_transform"])
            for bone in record["arm_landmarks"][side]["bones"]:
                name=bone["name"];pose=bundle["armature"].matrix_world @ bundle["armature"].pose.bones[name].matrix
                original_rest=bundle["rest_object"] @ bundle["rests"][name]
                actual_delta=pose @ original_rest.inverted()
                expected_delta=converted(matrix(bone["world_pose"]) @ bundle["game_rests"][name].inverted())
                metrics["max_bone_deformation_error"]=max(metrics["max_bone_deformation_error"],max(abs(actual_delta[r][c]-expected_delta[r][c]) for r in range(4) for c in range(4)))
            skin=bundle["skin"];evaluated=skin.evaluated_get(graph);mesh=evaluated.to_mesh()
            indices=sorted(set([0,len(mesh.vertices)-1]+[round(i*(len(mesh.vertices)-1)/39) for i in range(40)]))
            for index in indices:
                actual=evaluated.matrix_world @ mesh.vertices[index].co;expected=expected_skin(bundle,record["arm_landmarks"][side],index)
                metrics["max_skin_vertex_error_m"]=max(metrics["max_skin_vertex_error_m"],(actual-expected).length);metrics["skin_samples"]+=1
            evaluated.to_mesh_clear()
            _,rigid=fit_rigid(record["arm_landmarks"][side])
            for label,transform in rigid.items():
                actual=bundle["rigid"][label].matrix_world;expected=converted(hand @ transform)
                metrics["max_rigid_transform_error"]=max(metrics["max_rigid_transform_error"],max(abs(actual[r][c]-expected[r][c]) for r in range(4) for c in range(4)))
        for label,key in (("Sword","sword_transform"),("Shield","shield_transform")):
            actual=data[label]["container"].matrix_world;expected=converted(matrix(record[key]))
            metrics["max_rigid_transform_error"]=max(metrics["max_rigid_transform_error"],max(abs(actual[r][c]-expected[r][c]) for r in range(4) for c in range(4)))
    assert metrics["max_skin_vertex_error_m"]<.00002,metrics
    assert metrics["max_bone_deformation_error"]<.00002,metrics
    assert metrics["max_rigid_transform_error"]<.00002,metrics
    return metrics


def linear_keys():
    for action in bpy.data.actions:
        curves=list(action.fcurves) if hasattr(action,"fcurves") else [curve for layer in action.layers for strip in layer.strips for bag in strip.channelbags for curve in bag.fcurves]
        for curve in curves:
            for key in curve.keyframe_points:key.interpolation="LINEAR"


def main():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    for filename in ("left_arm.glb","right_arm.glb","longsword.glb","round_shield.glb"):
        report["source_sha256"][filename]=hashlib.sha256((SOURCE/filename).read_bytes()).hexdigest()
    for clip_index,sequence in enumerate(manifest["sequences"]):
        clip=sequence["id"];assert sequence["frame_count"]==34 and len(sequence["pov"])==34
        scene=bpy.context.scene if clip_index==0 else bpy.data.scenes.new(clip)
        scene.name=clip;bpy.context.window.scene=scene;scene.render.fps=30;scene.frame_start=1;scene.frame_end=34
        scene.render.resolution_x=1280;scene.render.resolution_y=720;scene.render.resolution_percentage=100
        scene.unit_settings.system="METRIC";scene.unit_settings.scale_length=1
        data={label:import_bundle(scene,clip,label,filename) for label,filename in (("Sword","longsword.glb"),("Shield","round_shield.glb"),("LeftHand","left_arm.glb"),("RightHand","right_arm.glb"))}
        camera_data=bpy.data.cameras.new(clip+"__CapturedCamera");camera=bpy.data.objects.new(clip+"__CapturedCamera",camera_data);scene.collection.objects.link(camera)
        camera_data.sensor_fit="VERTICAL";camera_data.sensor_height=24;camera_data.lens=12/math.tan(math.radians(76)/2);camera_data.clip_start=.01;camera_data.clip_end=100
        scene.camera=camera
        for i,record in enumerate(sequence["pov"]):
            frame=i+1;scene.frame_set(frame)
            for side,label in (("left","LeftHand"),("right","RightHand")):apply_arm(data[label],record["arm_landmarks"][side],frame)
            for label,key in (("Sword","sword_transform"),("Shield","shield_transform")):key_transform(data[label]["container"],converted(matrix(record[key])),frame)
            key_transform(camera,C @ matrix(record["view_camera_transform"]),frame)
        linear_keys();metrics=verify_scene(scene,data,sequence);scene.frame_set(1)
        for frame,label in ((1,"Recorded start"),(7,"Windup / raise"),(12,"Contact"),(18,"Follow-through"),(34,"Recorded end")):scene.timeline_markers.new(label,frame=frame)
        scene["source_capture_action"]=clip;scene["source_fps"]=30;scene["source_samples"]=34
        bpy.ops.object.select_all(action="DESELECT")
        for bundle in data.values():
            bundle["container"].select_set(True)
            for obj in bundle["objects"]:obj.select_set(True)
        camera.select_set(True);bpy.context.view_layer.objects.active=data["RightHand"]["armature"]
        path=OUT/(clip+".glb")
        options={"filepath":str(path),"export_format":"GLB","use_selection":True,"use_active_scene":True,"export_vertex_color":"ACTIVE","export_anim_scene_split_object":False,"export_yup":True,"export_materials":"EXPORT","export_image_format":"AUTO","export_cameras":True,"export_animations":True,"export_animation_mode":"SCENE","export_frame_range":True,"export_frame_step":1,"export_force_sampling":True,"export_optimize_animation_size":False,"export_anim_slide_to_zero":True,"export_skins":True,"export_extras":True}
        valid=bpy.ops.export_scene.gltf.get_rna_type().properties.keys();bpy.ops.export_scene.gltf(**{k:v for k,v in options.items() if k in valid})
        finalize_spec=importlib.util.spec_from_file_location("gltf_albedo",STAGE/"tools/finalize_glb_materials.py")
        finalize_module=importlib.util.module_from_spec(finalize_spec);finalize_spec.loader.exec_module(finalize_module)
        finalize_module.finalize(path)
        output=gm.GLB(path.read_bytes());assert len(output.doc.get("animations",[]))>=1
        assert len(output.doc.get("skins",[]))==2 and all(len(skin["joints"])==16 for skin in output.doc["skins"])
        assert all("bufferView" in im and "uri" not in im for im in output.doc.get("images",[]))
        report["clips"].append({"action":clip,"file":path.name,"scene":scene.name,"frames":[1,34],"duration_seconds":1.1,"embedded_images":len(output.doc.get("images",[])),"animation_count":len(output.doc["animations"]),"sha256":hashlib.sha256(path.read_bytes()).hexdigest(),"validation":metrics})
        bundles.append((scene,data,sequence))
        print("BAKED",clip,metrics,flush=True)
    bpy.context.window.scene=bundles[0][0];bpy.context.scene.frame_set(1)
    for image_ in bpy.data.images:
        if image_.get("source_filename"):assert image_.packed_file is not None and image_.filepath.startswith("//")
    text=bpy.data.texts.new("START_HERE")
    text.write("Recorded sword and shield motion — editable FK bake\n\nChoose one of the six scenes from the Scene selector. Every scene is 30fps, frames1–34 (capture frames0–33). Select LeftHand/RightHand HandRig in the Outliner and enter Pose Mode to edit the16 real bones. Sword, shield, forearm, upper arm and cuff have separate baked object tracks. Camera is the recorded first-person view. Textures are packed; no external files are required. No IK controls or game combat logic are included.\n")
    for screen in bpy.data.screens:
        for area in screen.areas:
            if area.type=="VIEW_3D":area.spaces.active.region_3d.view_perspective="CAMERA"
    blend=OUT/"Sword_Shield_Captured_Motion.blend";bpy.ops.wm.save_as_mainfile(filepath=str(blend))
    report["blend"]={"file":blend.name,"sha256":hashlib.sha256(blend.read_bytes()).hexdigest(),"scenes":len(bundles),"packed_images":sum(bool(i.packed_file) for i in bpy.data.images if i.get("source_filename"))}
    (STAGE/"animation_export_report.json").write_text(json.dumps(report,indent=2)+"\n")
    print("EXPORT_COMPLETE",json.dumps(report["blend"]),flush=True)


if __name__=="__main__":main()
