"""Six-view longsword geometry for build_assets.py's Blender helper namespace.

Call ``build_sword_v2(globals())`` in place of the previous build_sword().
The function builds and exports only longsword.glb; it never loads a scene or
changes the arm/shield builders. Blender +Z becomes Godot +Y on export.

UV conventions (all UVMap, no image nodes or embedded textures):
* Blade/fuller: U is physical blade width / .062 m, V is length / 1.045 m.
  Thus longitudinal brushing follows V on both faces.
* Furniture: U follows circumference or the quillon cross-section; V follows
  pommel height or quillon span. The broad guard's length follows V.
* GripLeather: U circumference 0..1, V length 0..1.
* GripBinding: U across the broad leather ribbon, V along all eight turns 0..1.
"""

import math


def _get(api, name):
    return api[name] if isinstance(api, dict) else getattr(api, name)


def _blade_geometry():
    # The last coordinate is groove depth, not a separate decorative ridge.
    # Both sides have a depressed floor with shoulders meeting the blade face.
    rows = [
        (-.010, .0310, .0045, 0.00),
        (.024, .0307, .0045, 0.00),
        (.046, .0304, .0044, 0.52),
        (.077, .0300, .0043, 1.00),
        (.160, .0291, .0041, 1.00),
        (.440, .0263, .0037, 1.00),
        (.710, .0223, .0032, 1.00),
        (.880, .0174, .0027, .96),
        (.947, .0122, .0021, .76),
        (.988, .0074, .0015, .22),
        (1.014, .0038, .0009, 0.00),
        (1.035, .0001, .0001, 0.00),
    ]
    vertices, uvs, faces, channels, materials = [], [], [], [], []
    for z, width, thickness, groove in rows:
        floor = thickness * (1.0 - .47 * groove)
        shoulder = thickness * (1.0 - .40 * groove)
        profile = [
            (-width, 0), (-width * .76, -thickness),
            (-width * .32, -thickness), (-width * .20, -shoulder),
            (0, -floor), (width * .20, -shoulder),
            (width * .32, -thickness), (width * .76, -thickness),
            (width, 0), (width * .76, thickness),
            (width * .32, thickness), (width * .20, shoulder),
            (0, floor), (-width * .20, shoulder),
            (-width * .32, thickness), (-width * .76, thickness),
        ]
        for x, y in profile:
            vertices.append((x, y, z))
            uvs.append((x / .062 + .5, (z + .010) / 1.045))
    for row in range(len(rows) - 1):
        for side in range(16):
            face = (row * 16 + side, row * 16 + (side + 1) % 16,
                    (row + 1) * 16 + (side + 1) % 16, (row + 1) * 16 + side)
            # Separate the actual groove floor for existing smithing material
            # replacement. It shares exact boundary vertices with the blade:
            # no duplicate face, floating insert, or coplanar overlay.
            if side in (3, 4, 11, 12) and 1 <= row <= 8:
                channels.append(face)
            else:
                faces.append(face)
                materials.append(1 if side in (0, 7, 8, 15) else 0)
    for row, direction in ((0, -1), (len(rows) - 1, 1)):
        center = len(vertices)
        vertices.append((0, 0, rows[row][0]))
        uvs.append((.5, (rows[row][0] + .010) / 1.045))
        for side in range(16):
            triangle = (center, row * 16 + side, row * 16 + (side + 1) % 16)
            faces.append(triangle if direction > 0 else tuple(reversed(triangle)))
            materials.append(1 if row else 0)
    return vertices, faces, channels, uvs, materials


def _compact(vertices, faces, uvs):
    used = sorted({index for face in faces for index in face})
    remap = {old: new for new, old in enumerate(used)}
    return ([vertices[index] for index in used],
            [tuple(remap[index] for index in face) for face in faces],
            [uvs[index] for index in used])


def _lathe(mesh_obj, name, rows, material, parent, segments=48, smooth=True):
    """Ascending Z rows of (z, X radius, Y radius); genuine elliptical caps."""
    vertices, faces, uvs = [], [], []
    low, high = rows[0][0], rows[-1][0]
    for z, rx, ry in rows:
        for index in range(segments + 1):
            angle = math.tau * index / segments
            vertices.append((math.cos(angle) * rx, math.sin(angle) * ry, z))
            uvs.append((index / segments, (z - low) / (high - low)))
    stride = segments + 1
    for row in range(len(rows) - 1):
        for index in range(segments):
            a = row * stride + index
            faces.append((a, a + 1, a + stride + 1, a + stride))
    faces.append(tuple(reversed(range(segments))))
    last = (len(rows) - 1) * stride
    faces.append(tuple(last + index for index in range(segments)))
    return mesh_obj(name, vertices, faces, material, parent, uvs, smooth)


def _guard_geometry():
    vertices, faces, uvs = [], [], []
    # Symmetric, shallow upward sweep, with squared quillon ends. Each ring is
    # a flattened chamfered rectangle rather than a circular tube.
    samples = [-.152, -.151, -.139, -.116, -.084, -.050, -.025, 0,
               .025, .050, .084, .116, .139, .151, .152]
    for x in samples:
        ratio = abs(x) / .152
        center_z = -.009 + .025 * ratio * ratio
        half_height = .0084 - .0024 * ratio + .0014 * ratio ** 6
        half_depth = .0056 - .0017 * ratio
        end_chamfer = .00075 if abs(x) > .1515 else 0
        h, d = half_height - end_chamfer, half_depth - end_chamfer
        bevel = min(.0011, d * .35)
        section = [(-d + bevel, -h), (d - bevel, -h),
                   (d, -h + bevel), (d, h - bevel),
                   (d - bevel, h), (-d + bevel, h),
                   (-d, h - bevel), (-d, -h + bevel)]
        for index, (y, z) in enumerate(section):
            vertices.append((x, y, center_z + z))
            uvs.append((index / 8, (x + .152) / .304))
    for row in range(len(samples) - 1):
        for index in range(8):
            faces.append((row * 8 + index, row * 8 + (index + 1) % 8,
                          (row + 1) * 8 + (index + 1) % 8, (row + 1) * 8 + index))
    faces.extend([tuple(reversed(range(8))),
                  tuple((len(samples) - 1) * 8 + index for index in range(8))])
    return vertices, faces, uvs


def _grip_radii(z):
    ratio = max(0.0, min(1.0, (z + .267) / .241))
    # Slight palm swell; the side view stays visibly oval and narrow.
    return (1.28*(.0148 + .0020 * ratio + .0010 * math.sin(ratio * math.pi)),
            1.22*(.0107 + .0013 * ratio + .0005 * math.sin(ratio * math.pi)))


def _ribbon_geometry():
    vertices, faces, uvs = [], [], []
    steps, columns, turns = 512, 6, 8
    stride = columns + 1
    # A broad, flat overlapping leather tape, not a raised rope wound eighteen
    # times. The half-millimetre folded lip catches light without a bulky coil.
    for underside in (False, True):
        for step in range(steps + 1):
            ratio = step / steps
            angle = math.pi / 2 + ratio * math.tau * turns
            center_z = -.038 - .217 * ratio
            for across in range(columns + 1):
                u = across / columns
                z = center_z + (u - .5) * .030
                rx, ry = _grip_radii(z)
                folded_edge = .00028 * math.exp(-((u - .93) / .12) ** 2)
                lift = .00012 if underside else .00052 + folded_edge
                vertices.append((math.cos(angle) * (rx + lift),
                                 math.sin(angle) * (ry + lift), z))
                uvs.append((u, ratio))
    surface = (steps + 1) * stride
    for step in range(steps):
        for across in range(columns):
            a = step * stride + across
            # Longitudinal angle direction crossed with vertical tape width
            # gives the outward surface normal.
            faces.append((a, a + stride, a + stride + 1, a + 1))
            faces.append((surface + a + 1, surface + a + stride + 1,
                          surface + a + stride, surface + a))
        for across in (0, columns):
            a, b = step * stride + across, (step + 1) * stride + across
            face = (a, surface + a, surface + b, b)
            faces.append(face if across == 0 else tuple(reversed(face)))
    for step in (0, steps):
        for across in range(columns):
            a = step * stride + across
            face = (a, a + 1, surface + a + 1, surface + a)
            faces.append(face if step == 0 else tuple(reversed(face)))
    return vertices, faces, uvs


def build_sword_v2(api):
    empty = _get(api, "empty")
    mesh_obj = _get(api, "mesh_obj")
    material = _get(api, "material")
    export = _get(api, "export")
    blade_mat = material("FP_SwordBlade", (.39, .415, .43), .32, .91)
    edge_mat = material("FP_SwordEdge", (.58, .61, .62), .22, .94)
    furniture = material("FP_SwordFurniture", (.37, .39, .40), .29, .92)
    fuller_mat = material("FP_SwordFuller", (.285, .305, .32), .37, .88)
    leather_mat = material("FP_SwordLeather", (.090, .061, .039), .70, 0)
    root = empty("SwordsmanLongsword")
    root["geometry_reference"] = "sword_shield_multiview/sword_views_v2.png"
    root["geometry_version"] = "six_view_forged_fuller_v2"
    root["blade_length_m"] = 1.045
    root["grip_wrap_turns"] = 8

    vertices, faces, channel_faces, uvs, slots = _blade_geometry()
    v, f, uv = _compact(vertices, faces, uvs)
    blade = mesh_obj("PittedBlade", v, f, blade_mat, root, uv, False)
    blade.data.materials.append(edge_mat)
    for polygon, index in zip(blade.data.polygons, slots):
        polygon.material_index = index
    v, f, uv = _compact(vertices, channel_faces, uvs)
    mesh_obj("FullerPolishedChannel", v, f, fuller_mat, root, uv, False)

    v, f, uv = _guard_geometry()
    guard = mesh_obj("SymmetricSweptQuillons", v, f, furniture, root, uv, False)
    guard.data.materials.append(edge_mat)
    for face in guard.data.polygons:
        if face.index % 8 in (1, 3, 5, 7):
            face.material_index = 1
    _lathe(mesh_obj, "GuardCollar", [
        (-.027, .0190, .0123), (-.024, .0227, .0140),
        (-.005, .0227, .0140), (.001, .0170, .0100),
    ], furniture, root, 32, False)
    grip_rows = []
    for index in range(25):
        z = -.267 + .241 * index / 24
        grip_rows.append((z, *_grip_radii(z)))
    _lathe(mesh_obj, "GripLeather", grip_rows, leather_mat, root, 64)
    v, f, uv = _ribbon_geometry()
    mesh_obj("GripBinding", v, f, leather_mat, root, uv, True)
    _lathe(mesh_obj, "PommelFerrule", [
        (-.271, .0188, .0134), (-.269, .0206, .0146),
        (-.262, .0206, .0146), (-.260, .0188, .0133),
    ], furniture, root, 48)
    pommel = _lathe(mesh_obj, "PearPommel", [
        (-.349, .0010, .0008), (-.346, .0080, .0061),
        (-.337, .0180, .0135), (-.326, .0260, .0194),
        (-.314, .0290, .0215), (-.309, .0283, .0210),
        (-.295, .0224, .0166), (-.281, .0175, .0129),
        (-.270, .0150, .0110),
    ], furniture, root, 32, True)
    pommel.data.materials.append(edge_mat)
    # The selected reference's pear weighs out the long blade: about 8 cm
    # across. Widen its belly without widening the actual hand grip or neck.
    for vertex in pommel.data.vertices:
        belly=max(0.0,1.0-abs(vertex.co.z+.316)/.046)
        vertex.co.x*=1.0+.43*belly
        vertex.co.y*=1.0+.25*belly
    for face in pommel.data.polygons:
        if face.index // 32 in (0, 3, 7):
            face.material_index = 1
    _lathe(mesh_obj, "FlushTangPeen", [
        (-.350, .0020, .0016), (-.348, .0033, .0026),
        (-.346, .0030, .0024),
    ], edge_mat, root, 12, False)

    grip = empty("HandGrip", root)
    grip.location = (0, -.002, -.108)
    tip = empty("BladeTip", root)
    tip.location = (0, 0, 1.035)
    return export(root, "longsword.glb")
