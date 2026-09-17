"""Preserve engine albedo multipliers as standard glTF material factors.

Blender's exporter preserves the image/vertex AO but does not recognize the
entire multiplier graph. This changes JSON material factors only: no geometry,
animation, texture bytes or skin weights are changed.
"""
from pathlib import Path
import importlib.util, json, hashlib

STAGE=Path(__file__).resolve().parents[1]
ROOT=Path(__file__).resolve().parents[4]
spec=importlib.util.spec_from_file_location("preserved_glb",ROOT/"asset-staging/sword_shield_single_pose/corrected_sword/correct_longsword.py")
helper=importlib.util.module_from_spec(spec);spec.loader.exec_module(helper)
TINTS={
 "FP_SwordBlade":(1,1,1),"FP_SwordFurniture":(1,1,1),"FP_SwordEdge":(1.2,1.22,1.23),"FP_SwordFuller":(.55,.57,.59),"FP_SwordLeather":(.35,.32,.29),
 "FP_ShieldOak":(.46,.43,.40),"FP_ShieldIron":(1,1,1),"FP_ShieldEdge":(.68,.70,.71),"FP_ShieldEnarmes":(.35,.32,.29),"FP_ShieldLeatherEdge":(.60,.45,.34),"FP_ShieldStitch":(1.3,1.14,.89),
 "FP_Skin":(.75,.75,.75),"FP_WornLeather":(.62,.58,.52),"FP_LayeredVambrace":(.60,.54,.45),"FP_SleeveStrap":(.25,.21,.17),"FP_QuiltedLinen":(.12,.105,.085),
 "FP_SleeveBuckles":(.20,.21,.20),"FP_LeatherEdge":(.17,.14,.11),"FP_WaxedThread":(.23,.20,.17),"FP_AgedSteel":(.52,.55,.58),"FP_WornRivets":(.29,.22,.13)}


def finalize(path):
    glb=helper.GLB(path.read_bytes());binary=bytes(glb.bin)
    for material in glb.doc["materials"]:
        name=material.get("extras",{}).get("godot_material",material["name"].split("__")[0])
        tint=TINTS[name]
        material["pbrMetallicRoughness"]["baseColorFactor"]=[min(1.,max(0.,v)) for v in tint]+[1.]
        material.setdefault("extras",{})["original_engine_albedo_multiplier"]=list(tint)
    assert bytes(glb.bin)==binary
    path.write_bytes(glb.encode())


if __name__=="__main__":
    for path in (STAGE/"editable").glob("*.glb"):finalize(path)
    report=json.loads((STAGE/"animation_export_report.json").read_text())
    for clip in report["clips"]:clip["sha256"]=hashlib.sha256((STAGE/"editable"/clip["file"]).read_bytes()).hexdigest()
    report["material_export"]={"engine_tints_explicitly_preserved":True,"geometry_animation_and_embedded_image_bytes_unchanged":True,"native_blend_preserves_engine_hdr_tints":True,"gltf_hdr_tint_policy":"Only factors above1 on sword-edge and stitch are clamped to the glTF0..1 albedo range; original values retained in material extras."}
    (STAGE/"animation_export_report.json").write_text(json.dumps(report,indent=2)+"\n")
