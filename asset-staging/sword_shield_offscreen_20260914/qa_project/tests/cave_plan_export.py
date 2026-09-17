"""Draw a labelled survey plan from the exported ACTUAL cave floor triangles."""
import json
import re
import struct
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

PROJECT = Path(__file__).resolve().parents[1]
OUT = PROJECT / "artifacts/visual_qa/cave_offline"
raw = (OUT / "cave_geometry.glb").read_bytes()
json_length = struct.unpack_from("<I", raw, 12)[0]
document = json.loads(raw[20:20 + json_length])
binary_start = 20 + json_length + 8
binary = raw[binary_start:]


def accessor(index):
    item = document["accessors"][index]
    view = document["bufferViews"][item["bufferView"]]
    fmt = {5126: "f", 5125: "I", 5123: "H", 5121: "B"}[item["componentType"]]
    width = {"VEC3": 3, "SCALAR": 1}[item["type"]]
    stride = view.get("byteStride", struct.calcsize(fmt) * width)
    offset = view.get("byteOffset", 0) + item.get("byteOffset", 0)
    return [struct.unpack_from("<" + fmt * width, binary, offset + i * stride) for i in range(item["count"])]


floor = next(node for node in document["nodes"] if node.get("name") == "CavernFloor")
floor_mesh = next(document["nodes"][i]["mesh"] for i in floor["children"] if "mesh" in document["nodes"][i])
primitive = document["meshes"][floor_mesh]["primitives"][0]
positions = accessor(primitive["attributes"]["POSITION"])
indices = [v[0] for v in accessor(primitive["indices"])]
S = 2
canvas = Image.new("RGB", (1160 * S, 1240 * S), "#101718")
draw = ImageDraw.Draw(canvas)
font_path = str(PROJECT / "assets/fonts/NotoSansKR-Variable.ttf")


def font(size):
    face = ImageFont.truetype(font_path, size * S)
    face.set_variation_by_axes([600 if size >= 28 else 400])
    return face


def xy(x, z):
    return ((580 + x * 6) * S, (645 + z * 6) * S)


def text(x, y, value, size, color="#e4dbcb", anchor="mm"):
    draw.text((x * S, y * S), value, font=font(size), fill=color, anchor=anchor)


def line(points, color, width=1):
    draw.line([(x * S, y * S) for x, y in points], fill=color, width=width * S)


text(580, 49, "검은 물길 동굴", 36)
text(580, 101, "9개 공동  ·  14개 연결 통로  ·  남쪽 진입 / 북쪽 귀환", 16, "#a5aaa3")
left, top = 187, 228
right, bottom = 973, 1062
draw.rectangle((left*S, top*S, right*S, bottom*S), fill="#182020", outline="#596258", width=S)
for x in range(-60, 61, 10):
    line([(580 + x*6, top), (580+x*6, bottom)], "#222b29")
for z in range(-60, 61, 10):
    line([(left, 645+z*6), (right, 645+z*6)], "#222b29")
for offset in range(0, len(indices), 3):
    draw.polygon([xy(positions[indices[offset+j]][0], positions[indices[offset+j]][2]) for j in range(3)], fill="#695846")

# Chamber labels are read from the same layout source as the playable dungeon.
layout_source = (PROJECT / "scripts/cave_layout.gd").read_text()
rooms = re.findall(r'"id": "([^"]+)", "title": "([^"]+)", "center": Vector2\(([-\d.]+), ([-\d.]+)\)', layout_source)
for room_id, title, x, z in rooms:
    px, py = xy(float(x), float(z))
    bounds = draw.textbbox((px, py), title, font=font(16), anchor="mm")
    draw.rounded_rectangle((bounds[0]-10*S,bounds[1]-7*S,bounds[2]+10*S,bounds[3]+7*S), radius=5*S, fill="#202520")
    draw.text((px, py), title, font=font(16), fill="#ece2cd", anchor="mm")

line([(left, 196), (right,196)], "#c2a574", 2)
for x in [left, right]:
    line([(x,186),(x,213)], "#c2a574", 2)
text(580, 171, "가로 131 m", 22, "#d5b77f")
line([(147,top),(147,bottom)], "#c2a574",2)
for y in [top,bottom]:
    line([(137,y),(164,y)], "#c2a574",2)
text(96,625,"세로",19,"#d5b77f")
text(96,657,"139 m",20,"#d5b77f")
text(1026,239,"N",21,"#c5d5cb")
draw.polygon([(1026*S,256*S),(1019*S,275*S),(1033*S,275*S)],fill="#c5d5cb")

for pos, label, color in [((0,61),"입구", "#b7c887"),((0,-60),"귀환문", "#70c7bb")]:
    x,y=xy(*pos)
    draw.ellipse((x-5*S,y-5*S,x+5*S,y+5*S),fill=color)
    draw.text((x+12*S,y),label,font=font(13),fill=color,anchor="lm")

text(580, 1120, "실제 바닥 메시 기반 평면도", 18)
text(580, 1151, "어두운 암벽 영역을 포함한 전체 외곽 131m × 139m · 격자 간격 10m", 14, "#a5aaa3")
text(580, 1194, "은신처 M → 검은 물길 동굴     |     테스트룸 → 장면 → 검은 물길 동굴", 14, "#cab68f")
canvas.resize((1160,1240),Image.Resampling.LANCZOS).save(OUT / "cave_floor_plan.png")
print(OUT / "cave_floor_plan.png")
