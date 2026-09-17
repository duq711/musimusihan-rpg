"""Optional untextured CPU construction diagram; not a gameplay screenshot."""
from pathlib import Path
from PIL import Image, ImageDraw
from extend_gloves import GLB

stage = Path(__file__).resolve().parent
glb = GLB((stage / "right_arm.glb").read_bytes())
image = Image.new("RGB", (1400, 800), (240, 241, 242))
draw = ImageDraw.Draw(image)
for panel, sign in enumerate((1, -1)):
    triangles = []
    for node in glb.doc["nodes"]:
        name = node.get("name", "").split(".")[0]
        if name not in ("ContinuousAnatomicalHand", "FingerlessLeatherGlove", "ProximalFingerlessLeatherExtensions"):
            continue
        color = (160,110,82) if name.startswith("Continuous") else (45,40,36) if name.startswith("Fingerless") else (116,134,155)
        for primitive in glb.doc["meshes"][node["mesh"]]["primitives"]:
            vertices = glb.read(primitive["attributes"]["POSITION"])
            normals = glb.read(primitive["attributes"]["NORMAL"])
            indices = [i[0] for i in glb.read(primitive["indices"])]
            for offset in range(0, len(indices), 3):
                ids = indices[offset:offset+3]
                points = [vertices[i] for i in ids]
                normal_y = sum(normals[i][1] for i in ids)/3
                if normal_y*sign < -.15: continue
                light = .40+.60*max(0, normal_y*sign)
                xy = [(panel*700+350+p[0]*sign*2400,180-p[2]*2400) for p in points]
                triangles.append((sum(p[1]*sign for p in points), xy, tuple(int(c*light) for c in color)))
    for _, xy, fill in sorted(triangles): draw.polygon(xy, fill=fill)
    draw.text((panel*700+30,30), "CPU rest geometry only: "+("back" if sign > 0 else "palm")+" / blue = added leather", fill=(20,20,20))
image.save(stage / "rest_geometry_diagnostic.png")
