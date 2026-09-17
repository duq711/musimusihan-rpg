"""Small, deterministic clay hand detailing helpers; Blender background only."""
import math
import bpy
import bmesh
from mathutils import Vector, Matrix
from mathutils.bvhtree import BVHTree
from mathutils.kdtree import KDTree

FINGERS = ("thumb", "index", "middle", "ring", "little")
UP = Vector((0, 0, 1))


def frame(rig, name):
    bone = rig.data.bones[name]
    matrix = rig.matrix_world @ bone.matrix_local
    axis = matrix.to_3x3().col[1].normalized()
    dorsal = (UP - axis * UP.dot(axis)).normalized()
    return matrix.translation.copy(), axis, axis.cross(dorsal).normalized(), dorsal


def surface(obj):
    points = [obj.matrix_world @ v.co for v in obj.data.vertices]
    tree = BVHTree.FromPolygons(points, [list(p.vertices) for p in obj.data.polygons], all_triangles=False)
    kd = KDTree(len(points))
    for i, point in enumerate(points):
        kd.insert(point, i)
    kd.balance()
    return tree, kd


def cast_top(tree, x, y):
    point, normal, unused, distance = tree.ray_cast(Vector((x, y, .4)), -UP, .8)
    if point is None:
        return None
    return point, normal.normalized()


def closest_weights(source, kd, point):
    total = {}
    for co, index, distance in kd.find_n(point, 3):
        gain = 1 / max(distance, .00005) ** 2
        for group in source.data.vertices[index].groups:
            name = source.vertex_groups[group.group].name
            if name == "wrist" or any(name.startswith(finger) for finger in FINGERS):
                total[name] = total.get(name, 0) + gain * group.weight
    scale = sum(total.values())
    if scale <= 0:
        raise RuntimeError("Detail point has no anatomical skin weights")
    return {name: value / scale for name, value in total.items() if value / scale > 1e-6}


def make_mesh(name, points, faces, material, source=None, rig=None, bone=None, kd=None):
    mesh = bpy.data.meshes.new(name + "Mesh")
    inverse = (source.matrix_world if source else rig.matrix_world).inverted()
    mesh.from_pydata([inverse @ point for point in points], [], faces)
    mesh.materials.append(material)
    mesh.update()
    # All added plates and thread sections are closed solids. Orient every
    # connected component outward before smooth shading and glTF backface culling.
    bm = bmesh.new()
    bm.from_mesh(mesh)
    bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
    bm.to_mesh(mesh)
    bm.free()
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.scene.collection.objects.link(obj)
    obj.matrix_world = source.matrix_world.copy() if source else rig.matrix_world.copy()
    for polygon in mesh.polygons:
        polygon.use_smooth = True
    if rig:
        if bone:
            obj.vertex_groups.new(name=bone).add(list(range(len(points))), 1, "REPLACE")
        else:
            groups = {name: obj.vertex_groups.new(name=name) for name in rig.data.bones.keys()}
            for i, point in enumerate(points):
                for name, weight in closest_weights(source, kd, point).items():
                    groups[name].add([i], weight, "REPLACE")
        modifier = obj.modifiers.new("DetailSkin", "ARMATURE")
        modifier.object = rig
        obj.parent = rig
        obj.matrix_parent_inverse = Matrix.Identity(4)
        obj.matrix_basis = Matrix.Identity(4) if source is None else rig.matrix_world.inverted() @ source.matrix_world
    return obj


def join_into(source, additions):
    if not additions:
        return
    bpy.ops.object.select_all(action="DESELECT")
    source.select_set(True)
    for obj in additions:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = source
    bpy.ops.object.join()
    bpy.context.view_layer.update()


def tube(points, normals, width=.0004, height=.00018, sides=6, closed=False):
    verts, faces = [], []
    count = len(points)
    for i, (point, normal) in enumerate(zip(points, normals)):
        tangent = points[(i + 1) % count] - points[(i - 1) % count] if closed else points[min(i + 1, count - 1)] - points[max(i - 1, 0)]
        lateral = tangent.normalized().cross(normal).normalized()
        for j in range(sides):
            angle = math.tau * j / sides
            verts.append(point + lateral * (width * math.cos(angle)) + normal * (height * math.sin(angle)))
    for i in range(count if closed else count - 1):
        for j in range(sides):
            a, b = i * sides + j, i * sides + (j + 1) % sides
            c, d = ((i + 1) % count) * sides + (j + 1) % sides, ((i + 1) % count) * sides + j
            faces.append((a, b, c, d))
    if not closed:
        faces.extend([tuple(reversed(range(sides))), tuple((count - 1) * sides + j for j in range(sides))])
    return verts, faces


def append_geometry(container, points, faces):
    offset = len(container[0])
    container[0].extend(points)
    container[1].extend(tuple(offset + i for i in face) for face in faces)


def sample_path(tree, xy_points, spacing=.0018, lift=.00012):
    points, normals = [], []
    for start, end in zip(xy_points, xy_points[1:]):
        delta = Vector(end) - Vector(start)
        count = max(2, math.ceil(delta.length / spacing))
        for i in range(count):
            xy = Vector(start).lerp(Vector(end), i / count)
            hit = cast_top(tree, xy.x, xy.y)
            if hit:
                point, normal = hit
                points.append(point + normal * lift)
                normals.append(normal)
    return points, normals


def sculpt_hand(obj, rig, side):
    """Shallow knuckle masses, transverse skin folds, and incised glove panels."""
    inv3 = obj.matrix_world.to_3x3().inverted()
    matrix = obj.matrix_world.to_3x3()
    group_names = {g.index: g.name for g in obj.vertex_groups}
    sign = 1 if side == "left" else -1
    panel = [[(sign * x, y) for x, y in path] for path in (
        [(-.018, -.022), (-.029, .010), (-.031, .045), (-.017, .068)],
        [(.018, -.022), (.030, .008), (.030, .040), (.017, .068)],
        [(-.017, .068), (0, .077), (.017, .068)],
    )]
    altered, maximum = 0, 0.0
    landmarks = {finger: [frame(rig, finger + str(i)) for i in range(3)] for finger in FINGERS}
    for vertex in obj.data.vertices:
        world = obj.matrix_world @ vertex.co
        normal = (matrix @ vertex.normal).normalized()
        dominant = max(vertex.groups, key=lambda g: g.weight, default=None)
        name = group_names[dominant.group] if dominant else "wrist"
        finger = next((f for f in FINGERS if name.startswith(f)), None)
        amount = 0.0
        if finger:
            for joint_index, (joint, axis, cross, dorsal) in enumerate(landmarks[finger]):
                distance = (world - joint).dot(axis)
                radial = (world - joint - axis * distance).length
                gate = math.exp(-(radial / .023) ** 4)
                dorsal_gate = max(0, normal.dot(dorsal)) ** 2
                palm_gate = max(0, -normal.dot(dorsal)) ** 2
                # The knuckle mass is broad; the skin fold is a restrained pair of incisions.
                amount += gate * dorsal_gate * (.00065 * math.exp(-(distance / .0055) ** 2)
                    - .00036 * math.exp(-((distance - .002) / .00085) ** 2))
                if joint_index > 0:
                    amount -= gate * palm_gate * (.00042 * math.exp(-(distance / .00125) ** 2)
                        + .00020 * math.exp(-((distance + .0035) / .00095) ** 2))
        if -.027 < world.y < .082 and normal.z > .25:
            p = Vector((world.x, world.y))
            nearest = 1.0
            for path in panel:
                for a, b in zip(path, path[1:]):
                    a, b = Vector(a), Vector(b)
                    t = max(0, min(1, (p - a).dot(b - a) / (b - a).length_squared))
                    nearest = min(nearest, (p - a.lerp(b, t)).length)
            amount -= .00040 * math.exp(-(nearest / .0011) ** 2) * normal.z ** 2
        if abs(amount) > 1e-7:
            vertex.co += inv3 @ (normal * amount)
            altered += 1
            maximum = max(maximum, abs(amount))
    obj.data.update()
    return {"sculpted_vertices": altered, "maximum_skin_displacement_m": maximum,
            "knuckle_landmarks": 15, "paired_palmar_joint_folds": 10,
            "dorsal_panel_groove_paths": 3}, panel


def add_nails(obj, rig, palette):
    tree, kd = surface(obj)
    result, reports = [], []
    for finger in FINGERS:
        base, axis, cross, dorsal = frame(rig, finger + "2")
        group = obj.vertex_groups.get(finger + "2")
        candidates = [obj.matrix_world @ v.co for v in obj.data.vertices
                      if any(g.group == group.index and g.weight > .45 for g in v.groups)]
        extent = max((p - base).dot(axis) for p in candidates)
        center = base + axis * (extent * .50)
        length = extent * .76
        section = [(p - center).dot(cross) for p in candidates if abs((p - center).dot(axis)) < length * .22]
        # Authored distal bones are motion pivots, not exact cross-section centers.
        # Fit the plate to the measured skin section and keep a clear side margin.
        center += cross * ((min(section) + max(section)) / 2)
        width = (max(section) - min(section)) * .56
        segments, rings = 32, 5
        top, normals = [], []
        for radius in [0] + [i / rings for i in range(1, rings + 1)]:
            for j in range(1 if radius == 0 else segments):
                angle = math.tau * j / segments
                along = math.copysign(abs(math.cos(angle)) ** (2 / 2.6), math.cos(angle)) * radius
                sideways = math.copysign(abs(math.sin(angle)) ** (2 / 2.6), math.sin(angle)) * radius
                position = center + axis * (along * length / 2) + cross * (sideways * width / 2 * (1 - .08 * along))
                # Cast along the distal bone's dorsal normal, not a planar floating nail.
                hit, normal, face, unused = tree.ray_cast(position + dorsal * .045, -dorsal, .09)
                if hit is None:
                    raise RuntimeError(f"Nail projection misses {finger} skin: position={list(position)} base={list(base)} extent={extent} width={width} candidates={len(candidates)}")
                lift = .00018 + .00014 * (1 - radius * radius)
                top.append(hit + normal * lift)
                normals.append(normal)
        points = top + [point - normal * .00020 for point, normal in zip(top, normals)]
        faces = []
        for j in range(segments):
            faces.append((0, 1 + j, 1 + (j + 1) % segments))
        for ring in range(rings - 1):
            for j in range(segments):
                a = 1 + ring * segments + j
                b = 1 + ring * segments + (j + 1) % segments
                faces.append((a, b, b + segments, a + segments))
        count = len(top)
        faces += [tuple(count + i for i in reversed(face)) for face in list(faces)]
        for j in range(segments):
            a = 1 + (rings - 1) * segments + j
            b = 1 + (rings - 1) * segments + (j + 1) % segments
            faces.append((a, a + count, b + count, b))
        nail = make_mesh("Nail_" + finger, points, faces, palette[3], rig=rig, bone=finger + "2")
        nail["detail_role"] = "Anatomically projected thin nail plate"
        result.append(nail)
        reports.append({"finger": finger, "object": nail.name, "bone": finger + "2",
                        "width_m": width, "length_m": length, "max_surface_lift_m": .00032,
                        "outline": "superellipse exponent 2.6, thin projected plate",
                        "triangles": sum(len(f) - 2 for f in faces)})
    return result, reports


def add_hand_trim(obj, rig, palette, panel_paths):
    tree, kd = surface(obj)
    roll, thread = ([], []), ([], [])
    rings_count, stitch_count = 0, 0
    # Follow the actual skin/glove material boundary. Bone planes can cross the
    # finger webs even when the visible glove holes are independent.
    edge_materials, positions = {}, {}
    for polygon in obj.data.polygons:
        keys = []
        for index in polygon.vertices:
            point = obj.matrix_world @ obj.data.vertices[index].co
            key = tuple(round(value, 6) for value in point)
            positions[key] = point
            keys.append(key)
        for a, b in zip(keys, keys[1:] + keys[:1]):
            edge_materials.setdefault(tuple(sorted((a, b))), set()).add(polygon.material_index)
    graph = {}
    for (a, b), materials in edge_materials.items():
        if materials == {0, 1}:
            graph.setdefault(a, set()).add(b)
            graph.setdefault(b, set()).add(a)
    contours, remaining = [], set(graph)
    while remaining:
        seed = remaining.pop()
        component, pending = [seed], [seed]
        while pending:
            key = pending.pop()
            for neighbor in graph[key]:
                if neighbor in remaining:
                    remaining.remove(neighbor)
                    component.append(neighbor)
                    pending.append(neighbor)
        if len(component) < 8:
            continue
        ordered, visited = [component[0]], {component[0]}
        while len(ordered) < len(component):
            options = graph[ordered[-1]] - visited
            if not options:
                break
            key = min(options)
            ordered.append(key)
            visited.add(key)
        if len(ordered) >= 8:
            contours.append([positions[key] for key in ordered])
    if len(contours) != 5:
        raise RuntimeError(f"Expected five exposed-finger material boundary loops, found {len(contours)}")
    for finger in FINGERS:
        start, end = ("1", "2") if finger == "thumb" else ("0", "1")
        base, axis, cross, dorsal = frame(rig, finger + start)
        tip = rig.matrix_world @ rig.data.bones[finger + end].head_local
        center = base.lerp(tip, .5)
        contour = min(contours, key=lambda pts: (sum(pts, Vector()) / len(pts) - center).length)
        contours.remove(contour)
        contour = [point.lerp((contour[(i - 1) % len(contour)] + contour[(i + 1) % len(contour)]) * .5, .22)
                   for i, point in enumerate(contour)]
        contour.append(contour[0])
        lengths = [(b - a).length for a, b in zip(contour, contour[1:])]
        perimeter = sum(lengths)
        points, normals = [], []
        for i in range(48):
            distance = perimeter * i / 48
            for index, length in enumerate(lengths):
                if distance <= length:
                    hit = contour[index].lerp(contour[index + 1], distance / max(length, 1e-9))
                    nearest, normal, unused, unused2 = tree.find_nearest(hit)
                    points.append(nearest + normal * .00043)
                    normals.append(normal)
                    break
                distance -= length
        append_geometry(roll, *tube(points, normals, .00045, .00024, closed=True))
        rings_count += 1
        for i in range(0, 48, 4):
            target = points[i] - axis * .0021
            radial = normals[i]
            ends, ns = [], []
            for offset in (-.00080, 0, .00080):
                point = target + axis * offset
                hit, normal, face, unused = tree.find_nearest(point)
                if hit is not None:
                    ends.append(hit + normal * (.00017 if offset else .00025))
                    ns.append(normal)
            if len(ends) == 3:
                append_geometry(thread, *tube(ends, ns, .00024, .00013, sides=4))
                stitch_count += 1
    for path in panel_paths:
        points, normals = sample_path(tree, path, .0017, .00008)
        append_geometry(thread, *tube(points, normals, .00024, .00012, sides=4))
        for i in range(3, len(points) - 2, 4):
            tangent = (points[i + 1] - points[i - 1]).normalized()
            across = tangent.cross(normals[i]).normalized()
            center = points[i] + across * .00135
            ends = [center - tangent * .0006, center + tangent * .0006]
            append_geometry(thread, *tube(ends, [normals[i]] * 2, .00021, .00011, sides=4))
            stitch_count += 1
    additions = []
    for name, geometry, mat in (("Glove_RolledEdges", roll, palette[1]), ("Glove_StitchedSeams", thread, palette[4])):
        addition = make_mesh(name, *geometry, mat, source=obj, rig=rig, kd=kd)
        additions.append(addition)
    added_triangles = sum(len(p.vertices) - 2 for addition in additions for p in addition.data.polygons)
    join_into(obj, additions)
    return {"finger_glove_rolled_edges": rings_count, "individual_hand_stitches": stitch_count,
            "joined_skinned_trim_triangles": added_triangles, "trim_material": palette[4].name}


def detail_arm(obj, palette):
    label = obj.name.lower()
    report = {"object": obj.name}
    if "upperarm" in label:
        matrix, inverse = obj.matrix_world.to_3x3(), obj.matrix_world.to_3x3().inverted()
        moved, maximum = 0, 0.0
        for vertex in obj.data.vertices:
            point = obj.matrix_world @ vertex.co
            normal = (matrix @ vertex.normal).normalized()
            theta = math.atan2(point.z, point.x)
            amount = .00115 * math.sin((point.y + .28) * 185 + theta * 1.8) * math.exp(-((point.y + .292) / .065) ** 2)
            vertex.co += inverse @ (normal * amount)
            moved += abs(amount) > .00001
            maximum = max(maximum, abs(amount))
        obj.data.update()
        report.update({"cloth_fold_sculpt_vertices": moved, "maximum_fold_displacement_m": maximum})
    if "forearm" not in label and "upperarm" not in label:
        return report
    tree, unused = surface(obj)
    details, stitches = ([], []), 0
    if "forearm" in label:
        paths = [[(x, -.215), (x * .88, -.16), (x * .80, -.07)] for x in (-.026, .026)]
        paths += [[(-.014, -.128), (0, -.140), (.014, -.128)], [(-.012, -.122), (0, -.132), (.012, -.122)]]
    else:
        paths = [[(-.034, -.54), (-.032, -.43), (-.028, -.345)]]
    for path in paths:
        points, normals = sample_path(tree, path, .0032, .00015)
        if len(points) > 2:
            append_geometry(details, *tube(points, normals, .00035, .00013, sides=4))
        for i in range(2, len(points) - 2, 3):
            tangent = (points[i + 1] - points[i - 1]).normalized()
            across = tangent.cross(normals[i]).normalized()
            center = points[i] + across * .0018
            ends = [center - tangent * .0009, center + tangent * .0009]
            append_geometry(details, *tube(ends, [normals[i]] * 2, .00028, .00013, sides=4))
            stitches += 1
    if details[0]:
        addition = make_mesh(obj.name + "_TailoredTrim", *details, palette[4], source=obj)
        report["joined_arm_detail_triangles"] = sum(len(p.vertices) - 2 for p in addition.data.polygons)
        join_into(obj, [addition])
    report["tailored_stitches"] = stitches
    return report


def refine_hand_set(objects, rig, palette, side):
    skin = next(obj for obj in objects if obj.type == "MESH" and "anatomicalhand" in obj.name.lower())
    sculpt, panels = sculpt_hand(skin, rig, side)
    nails, nail_report = add_nails(skin, rig, palette)
    trim = add_hand_trim(skin, rig, palette, panels)
    arm = [detail_arm(obj, palette) for obj in objects if obj.type == "MESH" and obj != skin]
    return nails, {"anatomical_sculpt": sculpt, "nails": nail_report, "hand_trim": trim, "arm_detail": arm}
