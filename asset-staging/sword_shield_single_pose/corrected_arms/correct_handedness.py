"""Stage anatomically correct hands without rebuilding skin or rigid sleeves.

The original canonical mesh is a left hand (dorsal +Y, fingers -Z, thumb +X).
The old exporter labelled it right, and labelled its mirror left. This builder
transplants only the opposite HandRig subtree into each arm. All skin payloads
are copied byte-for-byte; the recipient's fitted sleeves remain untouched.
No Blender or Godot process is used, and production assets are never written.
"""
from __future__ import annotations

import copy
import hashlib
import json
from pathlib import Path
import struct

STAGE = Path(__file__).resolve().parent
ROOT = STAGE.parents[2]
LIVE = ROOT / "godot-game/assets/3d/player/sword_shield"
SOURCES = STAGE / "source_before_handedness"


def read_glb(path):
    data = path.read_bytes()
    assert struct.unpack_from("<III",data) == (0x46546C67,2,len(data))
    length,kind = struct.unpack_from("<II",data,12)
    assert kind == 0x4E4F534A
    document = json.loads(data[20:20+length])
    bin_length,bin_kind = struct.unpack_from("<II",data,20+length)
    assert bin_kind == 0x004E4942
    return document,data[28+length:28+length+bin_length]


def write_glb(path,document,binary):
    text = json.dumps(document,ensure_ascii=False,separators=(",",":")).encode()
    text += b" "*(-len(text)%4)
    binary += b"\0"*(-len(binary)%4)
    payload = struct.pack("<III",0x46546C67,2,28+len(text)+len(binary))
    payload += struct.pack("<II",len(text),0x4E4F534A)+text
    payload += struct.pack("<II",len(binary),0x004E4942)+binary
    path.write_bytes(payload)


def node_key(node):
    return node["name"].split(".")[0]


def hand_nodes(document):
    roots = [i for i,n in enumerate(document["nodes"]) if node_key(n)=="HandRig"]
    assert len(roots)==1
    pending=roots[:]
    result={}
    while pending:
        index=pending.pop()
        node=document["nodes"][index]
        assert node_key(node) not in result
        result[node_key(node)]=index
        pending.extend(node.get("children",[]))
    return result


def accessor_payload(document,binary,index):
    accessor=document["accessors"][index]
    view=document["bufferViews"][accessor["bufferView"]]
    component_bytes={5121:1,5123:2,5125:4,5126:4}[accessor["componentType"]]
    components={"SCALAR":1,"VEC2":2,"VEC3":3,"VEC4":4,"MAT4":16}[accessor["type"]]
    size=component_bytes*components
    stride=view.get("byteStride",size)
    start=view.get("byteOffset",0)+accessor.get("byteOffset",0)
    assert "sparse" not in accessor
    return b"".join(binary[start+i*stride:start+i*stride+size] for i in range(accessor["count"]))


def hand_signature(document,binary):
    digest=hashlib.sha256()
    for name,index in sorted(hand_nodes(document).items()):
        node=document["nodes"][index]
        digest.update(name.encode())
        transforms={k:node[k] for k in ("rotation","translation","scale","matrix") if k in node}
        digest.update(json.dumps(transforms,sort_keys=True).encode())
        if "mesh" not in node:
            continue
        mesh=document["meshes"][node["mesh"]]
        for primitive in mesh["primitives"]:
            attrs=dict(primitive["attributes"],INDICES=primitive["indices"])
            for semantic,accessor_index in sorted(attrs.items()):
                digest.update(semantic.encode())
                accessor=document["accessors"][accessor_index]
                digest.update(json.dumps({k:accessor[k] for k in ("componentType","count","type","normalized") if k in accessor},sort_keys=True).encode())
                digest.update(accessor_payload(document,binary,accessor_index))
        skin=document["skins"][node["skin"]]
        digest.update(accessor_payload(document,binary,skin["inverseBindMatrices"]))
        digest.update(json.dumps([node_key(document["nodes"][j]) for j in skin["joints"]]).encode())
    return digest.hexdigest()


def stage_arm(side,recipient,recipient_bin,donor,donor_bin):
    result=copy.deepcopy(recipient)
    binary=bytearray(recipient_bin)
    recipient_nodes=hand_nodes(result)
    donor_nodes=hand_nodes(donor)
    assert set(recipient_nodes)==set(donor_nodes)
    node_map={donor_nodes[key]:recipient_nodes[key] for key in donor_nodes}
    accessors,views,meshes,skins={}, {}, {}, {}

    def copy_accessor(index):
        if index in accessors:return accessors[index]
        accessor=copy.deepcopy(donor["accessors"][index])
        source_view=accessor["bufferView"]
        if source_view not in views:
            view=copy.deepcopy(donor["bufferViews"][source_view])
            assert view["buffer"]==0
            start=view.get("byteOffset",0)
            binary.extend(b"\0"*(-len(binary)%4))
            view["byteOffset"]=len(binary)
            binary.extend(donor_bin[start:start+view["byteLength"]])
            views[source_view]=len(result["bufferViews"])
            result["bufferViews"].append(view)
        accessor["bufferView"]=views[source_view]
        accessors[index]=len(result["accessors"])
        result["accessors"].append(accessor)
        return accessors[index]

    def copy_mesh(index):
        if index in meshes:return meshes[index]
        mesh=copy.deepcopy(donor["meshes"][index])
        for primitive in mesh["primitives"]:
            primitive["indices"]=copy_accessor(primitive["indices"])
            primitive["attributes"]={k:copy_accessor(v) for k,v in primitive["attributes"].items()}
            material=donor["materials"][primitive["material"]]
            matches=[i for i,m in enumerate(result["materials"]) if m==material]
            if not matches:
                matches=[len(result["materials"])]
                result["materials"].append(copy.deepcopy(material))
            primitive["material"]=matches[0]
        meshes[index]=len(result["meshes"])
        result["meshes"].append(mesh)
        return meshes[index]

    def copy_skin(index):
        if index in skins:return skins[index]
        skin=copy.deepcopy(donor["skins"][index])
        skin["joints"]=[node_map[j] for j in skin["joints"]]
        if "skeleton" in skin:skin["skeleton"]=node_map[skin["skeleton"]]
        skin["inverseBindMatrices"]=copy_accessor(skin["inverseBindMatrices"])
        # Replace the old skin record, too: an unreferenced opposite-handed
        # skin sharing these joint nodes must not confuse an engine importer.
        recipient_skin=recipient["nodes"][recipient_nodes["ContinuousAnatomicalHand"]]["skin"]
        skins[index]=recipient_skin
        result["skins"][recipient_skin]=skin
        return skins[index]

    for source_index,target_index in node_map.items():
        node=copy.deepcopy(donor["nodes"][source_index])
        node["name"]=recipient["nodes"][target_index]["name"]
        if "children" in node:node["children"]=[node_map[c] for c in node["children"]]
        if "mesh" in node:node["mesh"]=copy_mesh(node["mesh"])
        if "skin" in node:node["skin"]=copy_skin(node["skin"])
        result["nodes"][target_index]=node
    binary.extend(b"\0"*(-len(binary)%4))
    result["buffers"][0]["byteLength"]=len(binary)
    assert binary[:len(recipient_bin)]==recipient_bin
    for index,node in enumerate(recipient["nodes"]):
        if index not in node_map.values():assert result["nodes"][index]==node
    assert len(result["nodes"])==len(recipient["nodes"])
    thumb_x=result["nodes"][recipient_nodes["thumb0"]]["translation"][0]
    assert thumb_x<-.01 if side=="right" else thumb_x>.01
    expected=hand_signature(donor,donor_bin)
    assert hand_signature(result,binary)==expected
    path=STAGE/f"{side}_arm.glb"
    write_glb(path,result,bytes(binary))
    saved,saved_bin=read_glb(path)
    assert hand_signature(saved,saved_bin)==expected
    return {"file":path.name,"source_hand_file":("left" if side=="right" else "right")+"_arm.glb",
            "anatomical_side":side,"thumb_rest_x":thumb_x,"skin_bones":16,
            "unchanged_donor_hand_sha256":expected,"recipient_rigid_binary_unchanged":True,
            "appended_hand_bytes":len(binary)-len(recipient_bin)}


def main():
    SOURCES.mkdir(parents=True,exist_ok=True)
    arms={}
    for side in ("left","right"):
        source=SOURCES/f"{side}_arm.glb"
        if not source.exists():source.write_bytes((LIVE/source.name).read_bytes())
        arms[side]=read_glb(source)
        thumb=arms[side][0]["nodes"][hand_nodes(arms[side][0])["thumb0"]]
        expected_sign=1 if side=="right" else -1
        assert thumb["translation"][0]*expected_sign>.01,"Input is already corrected; do not swap twice"
    report={"source_defect":"Canonical left dorsal hand was labelled right by build_assets.py",
            "coordinate_convention":{"fingers":"-Z","dorsal_normal":"+Y","right_thumb":"-X","left_thumb":"+X"},
            "arms":[stage_arm(side,*arms[side],*arms["left" if side=="right" else "right"]) for side in ("left","right")]}
    (STAGE/"handedness_report.json").write_text(json.dumps(report,indent=2)+"\n")
    print(json.dumps(report,indent=2))


if __name__=="__main__":main()
