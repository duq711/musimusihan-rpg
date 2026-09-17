"""Read-only portable glTF checks; no Blender/Godot runtime needed."""
import hashlib
import json
import math
import struct
from pathlib import Path

ROOT = Path(__file__).resolve().parent
PROJECT = ROOT.parent.parent
report = json.loads((ROOT / "build_report.json").read_text())
checks = []
for entry in report["assets"]:
    path = PROJECT / entry["file"]
    raw = path.read_bytes()
    magic, version, length = struct.unpack_from("<4sII", raw)
    assert magic == b"glTF" and version == 2 and length == len(raw), entry["name"]
    json_len, json_type = struct.unpack_from("<II", raw, 12)
    assert json_type == 0x4e4f534a
    document = json.loads(raw[20:20+json_len])
    assert not document.get("animations") and not document.get("cameras")
    assert "KHR_lights_punctual" not in document.get("extensions", {})
    assert len(document["meshes"]) == 1
    assert len(document["nodes"]) == 1
    assert not document["nodes"][0].get("translation")
    assert not document["nodes"][0].get("rotation")
    assert not document["nodes"][0].get("scale")
    assert hashlib.sha256(raw).hexdigest() == entry["sha256"]
    triangles = 0
    for primitive in document["meshes"][0]["primitives"]:
        assert primitive.get("mode", 4) == 4
        assert "POSITION" in primitive["attributes"]
        assert "NORMAL" in primitive["attributes"]
        assert "TEXCOORD_0" in primitive["attributes"]
        assert "COLOR_0" in primitive["attributes"]
        positions = document["accessors"][primitive["attributes"]["POSITION"]]
        assert all(math.isfinite(n) for n in positions["min"]+positions["max"])
        triangles += document["accessors"][primitive["indices"]]["count"]//3
    assert triangles == entry["triangles"]
    checks.append({"asset":entry["name"], "triangles":triangles,
                   "primitives":len(document["meshes"][0]["primitives"]),
                   "bytes":len(raw), "portable_vertex_color_uv":True})
assert report["total_triangles"] < 18000
(ROOT/"export_audit.json").write_text(json.dumps({"passed":True,"checks":checks},indent=2))
print("HIDEOUT RUINS EXPORT AUDIT PASS: %d meshes, %d triangles, no lights/cameras/animations"%
      (len(checks),sum(e["triangles"] for e in checks)))
