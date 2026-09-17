"""Independent read-only validation of local finger detail on the gloved source.

Geometry and function are checked separately from the ten image comparisons.
This verifier imports no sculpt/bake implementation and never saves a model.
"""
import argparse
import hashlib
import importlib.util
import json
import math
import sys
import tempfile
import traceback
from pathlib import Path

import bpy
import numpy as np
from mathutils import Matrix, Vector
from mathutils.bvhtree import BVHTree
from mathutils.geometry import intersect_ray_tri

DIGITS = ("thumb", "index", "middle", "ring", "little")
KEYS = [f"Joint_{digit}_{joint}" for digit in DIGITS for joint in range(3)]
ROLES = {"Detailed_Skin", "Detailed_Glove", "Detailed_Trim", "Detailed_Nail", "Detailed_Sleeve"}
legacy = generic = core = None


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def module(path, name):
    spec = importlib.util.spec_from_file_location(name, path)
    result = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(result)
    return result


def activate(name="Bilateral_Realistic_Review"):
    scene = bpy.data.scenes[name]
    core.activate(scene)
    rigs = sorted((o for o in scene.objects if o.type == "ARMATURE"), key=lambda o: core.wrist_world(o).x)
    assert len(rigs) == 2
    return scene, dict(zip(("left", "right"), rigs))


def capture(scene, rig):
    result = generic.capture(scene, rig)
    objects = []
    def visit(obj):
        objects.append(obj)
        for child in obj.children: visit(child)
    visit(rig.parent if rig.parent is not None else rig)
    result["objects"] = {o.name: {"parent": o.parent.name if o.parent else None,
        "matrix_basis": [list(r) for r in o.matrix_basis], "matrix_parent_inverse": [list(r) for r in o.matrix_parent_inverse],
        "matrix_world": [list(r) for r in o.matrix_world]} for o in objects if o is not None}
    for label, obj in legacy.parts_for(scene, rig).items():
        obj.data.calc_loop_triangles()
        part = result["parts"][label]
        part["triangles"] = [tuple(t.vertices) for t in obj.data.loop_triangles]
        part["uv_active"] = obj.data.uv_layers.active_index
        part["uv_render"] = [u.active_render for u in obj.data.uv_layers]
        part["smooth_faces"] = [p.use_smooth for p in obj.data.polygons]
        part["relative_keys"] = [(k.name,k.relative_key.name) for k in obj.data.shape_keys.key_blocks] if obj.data.shape_keys else []
    return result


def triangle_hit(first, second):
    """Actual non-adjacent triangle intersection, not merely a BVH box hit."""
    a, b = [Vector(v) for v in first], [Vector(v) for v in second]
    for start_triangle, target in ((a, b), (b, a)):
        for p, q in zip(start_triangle, start_triangle[1:] + start_triangle[:1]):
            ray = q - p
            hit = intersect_ray_tri(*target, ray, p, True)
            if hit is not None and ray.length_squared > 1e-20:
                fraction = (hit - p).dot(ray) / ray.length_squared
                if 1e-7 < fraction < 1.0 - 1e-7:
                    return True
    normal = (a[1]-a[0]).cross(a[2]-a[0])
    if normal.length < 1e-14:
        return False
    normal.normalize()
    if max(abs((p-a[0]).dot(normal)) for p in b) > 1e-8:
        return False
    # Strict coplanar interior tests exclude coincident/touching boundaries.
    omit = max(range(3), key=lambda k: abs(normal[k]))
    axes = [k for k in range(3) if k != omit]
    aa = [(p[axes[0]], p[axes[1]]) for p in a]
    bb = [(p[axes[0]], p[axes[1]]) for p in b]
    def cross(p, q, r):
        return (q[0]-p[0])*(r[1]-p[1])-(q[1]-p[1])*(r[0]-p[0])
    def inside(p, tri):
        values = [cross(u,v,p) for u,v in zip(tri, tri[1:]+tri[:1])]
        return min(values) > 1e-13 or max(values) < -1e-13
    if any(inside(p, bb) for p in aa) or any(inside(p, aa) for p in bb):
        return True
    for p,q in zip(aa,aa[1:]+aa[:1]):
        for u,v in zip(bb,bb[1:]+bb[:1]):
            if cross(p,q,u)*cross(p,q,v) < -1e-24 and cross(u,v,p)*cross(u,v,q) < -1e-24:
                return True
    return False


def inspect_surface(old, new, changed):
    faces = [f for f in old["triangles"] if max(f) < 12036]
    triangles = np.asarray(faces, dtype=np.int64)
    touched = np.any(changed[triangles], axis=1)
    p, q = old["points"][triangles], new["points"][triangles]
    before = np.cross(p[:,1]-p[:,0],p[:,2]-p[:,0])
    after = np.cross(q[:,1]-q[:,0],q[:,2]-q[:,0])
    size0, size1 = np.linalg.norm(before,axis=1), np.linalg.norm(after,axis=1)
    assert np.isfinite(q).all()
    assert np.all(size1[touched] > 1e-14), "Detail collapsed an actual physical triangle"
    alignment = np.sum(before[touched]*after[touched],axis=1)/(size0[touched]*size1[touched])
    assert float(alignment.min()) > 0.0, "Detail reversed a triangle relative to its original surface"
    tree = BVHTree.FromPolygons([Vector(v) for v in new["points"]], faces, all_triangles=True)
    candidates = {(min(a,b),max(a,b)) for a,b in tree.overlap(tree) if a != b and (touched[a] or touched[b])}
    inherited = 0
    new_intersections = []
    evaluated = 0
    for a,b in sorted(candidates):
        if set(faces[a]) & set(faces[b]):
            continue
        # UV or material splits may duplicate the same geometric edge.
        if any(np.linalg.norm(x-y) < 1e-7 for x in p[a] for y in p[b]):
            continue
        evaluated += 1
        if triangle_hit(q[a],q[b]):
            if triangle_hit(p[a],p[b]):
                inherited += 1
            else:
                new_intersections.append([a,b])
    assert not new_intersections, "New non-adjacent physical skin intersection: " + str(new_intersections[:8])
    return {"changed_physical_triangles": int(touched.sum()), "minimum_source_normal_alignment": float(alignment.min()),
        "minimum_changed_area_ratio": float((size1[touched]/size0[touched]).min()), "bvh_candidates": len(candidates),
        "actual_triangle_pairs_tested": evaluated, "inherited_intersections": inherited, "new_intersections": new_intersections}


def inspect_changes(old, new):
    assert old["rest"] == new["rest"], "The approved sixteen bone rest transforms changed"
    assert old["objects"] == new["objects"], "An existing model object/parent transform changed"
    assert old["parts"].keys() == new["parts"].keys()
    rows = {}
    for label, a in old["parts"].items():
        b = new["parts"][label]
        for field in ("faces", "weights", "materials", "face_materials", "uv_layers", "uv_active", "uv_render", "smooth_faces", "flex", "relative_keys"):
            assert a[field] == b[field], f"Protected {field} changed: {label}"
        assert a["points"].shape == b["points"].shape
        assert list(a["deltas"]) == list(b["deltas"])
        distance = np.linalg.norm(b["points"]-a["points"], axis=1)
        if label.startswith("nail_"):
            digit = label.removeprefix("nail_")
            assert len(distance) == 322 and not b["deltas"]
            assert all(weights == {digit+"2":1.0} for weights in b["weights"])
            bone = old["bone_points"][digit+"2"]
            axis = np.asarray(bone["tail"])-np.asarray(bone["head"])
            axis /= np.linalg.norm(axis)
            dorsal = np.asarray((0.,0.,1.))-axis*axis[2]
            dorsal /= np.linalg.norm(dorsal)
            offset = b["points"]-a["points"]
            lift = offset@dorsal
            tangential = offset-lift[:,None]*dorsal
            tangent_error = float(np.linalg.norm(tangential,axis=1).max())
            paired_error = float(np.linalg.norm(offset[:161]-offset[161:],axis=1).max())
            if digit == "thumb":
                # User explicitly corrected the long, low, off-center thumb nail.
                # Check the new physical footprint and seating, not old placement.
                cross=np.cross(axis,dorsal);cross/=np.linalg.norm(cross)
                old_axial=a['points']@axis;new_axial=b['points']@axis
                length_ratio=float(np.ptp(new_axial)/np.ptp(old_axial))
                width_error=abs(float(np.ptp(b['points']@cross)-np.ptp(a['points']@cross)))
                skin=new['parts']['hand'];owned=[i for i,w in enumerate(skin['weights']) if i<12036 and sum(v for k,v in w.items() if k.startswith('thumb'))>.95]
                tip=float(np.max(skin['points'][owned]@axis));tip_margin=tip-float(new_axial.max())
                assert .70<length_ratio<.78 and width_error<4e-8
                assert .0015<tip_margin<.0036, 'Thumb nail does not approach the actual tip safely'
                assert float(new_axial.min()-old_axial.min())>.005, 'Thumb nail base remains too close to the IP joint'
                paired_old=a['points'][:161]-a['points'][161:]
                paired_expected=paired_old+(length_ratio-1)*(paired_old@axis)[:,None]*axis
                shell_error=float(np.linalg.norm((b['points'][:161]-b['points'][161:])-paired_expected,axis=1).max())
                assert shell_error<4e-8 and float(np.abs(lift).max())<.009
                rows[label]={'vertices':322,'user_requested_new_placement':True,'axial_length_ratio':length_ratio,'width_error_m':width_error,'actual_skin_tip_margin_m':tip_margin,'paired_shell_error_m':shell_error,'topology_uv_rigid_weights_exact':True}
                continue
            assert tangent_error < 4e-8, "Nail repair changed the protected axial/cross-plane silhouette: "+digit
            assert paired_error < 4e-8, "Paired nail top and bottom received different displacement: "+digit
            assert float(lift.min()) >= -4e-8 and float(lift.max()) <= .00060+4e-8
            rows[label] = {"vertices":322,"top_count":161,"paired_bottom_offset":161,
                "outward_direction_native":dorsal.tolist(),"maximum_lift_m":float(lift.max()),
                "minimum_lift_m":float(lift.min()),"maximum_tangential_error_m":tangent_error,
                "maximum_top_bottom_offset_error_m":paired_error,"topology_uv_rigid_weights_exact":True}
            continue
        if label != "hand":
            assert np.array_equal(a["points"], b["points"]), "Protected non-skin geometry changed: " + label
            rows[label] = {"vertices": len(distance), "geometry_and_contract_exact": True}
            continue
        assert len(distance) == 14988 and list(b["deltas"]) == KEYS
        eligible = np.zeros(len(distance), dtype=bool)
        protected = np.zeros(len(distance), dtype=bool)
        for face, material_index in zip(a["faces"], a["face_materials"]):
            role = a["materials"][material_index].split(".")[0]
            (eligible if role == "Detailed_Skin" else protected)[list(face)] = True
        eligible &= ~protected
        eligible[12036:] = False
        eligible[a["points"][:,1] <= .010] = False
        vertices, faces = [], []
        for digit in DIGITS:
            nail = old["parts"]["nail_"+digit]
            offset = len(vertices)
            vertices.extend(Vector(v) for v in nail["points"])
            faces.extend(tuple(offset+i for i in f) for f in nail["faces"])
        nailtree = BVHTree.FromPolygons(vertices, faces)
        nail_distance = np.asarray([nailtree.find_nearest(Vector(p))[3] for p in a["points"]])
        nail_protected = nail_distance <= .0012
        eligible &= ~nail_protected
        changed = distance > 0
        assert not np.any(changed & ~eligible), "Moved a glove-shared, wrist, trim or protected nail-bed vertex"
        assert float(distance.max()) <= .00085 + 3e-8, "Physical detail exceeds the approved 0.85mm displacement"
        digits = {d: [] for d in DIGITS}
        for index in np.flatnonzero(distance >= 1e-6):
            influence = {d: sum(w for n,w in a["weights"][index].items() if n.startswith(d)) for d in DIGITS}
            digit = max(influence, key=influence.get)
            assert influence[digit] > 0, "Finger detail moved a vertex with no finger influence"
            digits[digit].append(int(index))
        assert all(len(indices) >= 5 for indices in digits.values()), "All five fingers require actual measurable skin detail"
        corrections = {}
        for key, delta in b["deltas"].items():
            error = np.linalg.norm(delta-a["deltas"][key],axis=1)
            assert float(error.max()) < 4e-8, "Original corrective vector changed beyond float32 addition rounding: " + key
            untouched = ~changed
            assert np.array_equal(delta[untouched], a["deltas"][key][untouched])
            corrections[key] = {"maximum_delta_preservation_error_m": float(error.max()), "untouched_delta_exact": True}
        rows[label] = {"vertices": len(distance), "eligible_vertices": int(eligible.sum()), "changed_vertices": int(changed.sum()),
            "maximum_displacement_m": float(distance.max()), "changed_by_digit": {d:len(v) for d,v in digits.items()},
            "protected_nail_bed_vertices": int(nail_protected.sum()), "minimum_changed_nail_surface_distance_m": float(nail_distance[changed].min()),
            "corrective_vectors": corrections, "surface": inspect_surface(a,b,changed)}
    return rows


def inspect_key_locality(snapshot):
    hand = snapshot["parts"]["hand"]
    results = {}
    for key, delta in hand["deltas"].items():
        digit, joint = key.split("_")[1:]
        bone = snapshot["bone_points"][digit+joint]
        head, tail = np.asarray(bone["head"]), np.asarray(bone["tail"])
        axis = (tail-head)/np.linalg.norm(tail-head)
        magnitude = np.linalg.norm(delta,axis=1)
        active = magnitude >= 1e-6
        owned = np.asarray([max(w,key=w.get).startswith(digit) if w else False for w in hand["weights"]])
        influence = np.asarray([any(n.startswith(digit) and weight > 0 for n,weight in w.items()) for w in hand["weights"]])
        assert np.array_equal(delta[~influence], np.zeros_like(delta[~influence])), "A corrective moved an unrelated finger"
        local = hand["points"]-head
        axial = local@axis
        section = owned & (np.abs(axial)<.004)
        assert int(section.sum()) >= 8
        x = np.asarray(bone["x"])
        z = np.cross(x,axis)
        section_coords = np.column_stack((local[section]@x, local[section]@z))
        center = (section_coords.min(axis=0)+section_coords.max(axis=0))*.5
        radial_distance = np.linalg.norm(local[active]-x*center[0]-z*center[1],axis=1)
        limit = .015 if joint == "1" and digit in ("middle","ring") else .0142
        extent = float(np.abs(axial[active]).max())
        assert int(active.sum()) >= 5 and 1e-5 < float(magnitude.max()) < .0015
        assert extent < limit and float(radial_distance.max()) < .04, "Corrective escaped its existing joint region: " + key
        results[key] = {"active_vertices":int(active.sum()), "axial_m":extent, "axial_limit_m":limit,
            "maximum_delta_m":float(magnitude.max()), "skin_section_radius_m":float(radial_distance.max()), "pure_other_delta_exact_zero":True}
    return results


def nail_measurements(scene, rig):
    """Vertex and top-face interior witnesses in actual evaluated armature poses."""
    parts = legacy.parts_for(scene,rig)
    hand = parts["hand"]
    groups = {g.index:g.name for g in hand.vertex_groups}
    targets = {}
    for digit in DIGITS:
        # Seating is measured against the distal nail bed. Including the entire
        # digit let a ray strike ring0/little0 webbing when the ring curled fully,
        # in both the unchanged source and candidate (audit/nail_ray_source.json).
        # Keep the same ray, gap and intrusion thresholds on the anatomical bed.
        owned = {v.index for v in hand.data.vertices if sum(g.weight for g in v.groups if groups[g.group] == digit+"2")>.25}
        targets[digit] = [tuple(p.vertices) for p in hand.data.polygons if all(i in owned for i in p.vertices)
            and legacy.role(hand.data.materials[p.material_index]) in ("Detailed_Skin","Detailed_Glove")]
        assert targets[digit]
    saved = {b.name:b.matrix_basis.copy() for b in rig.pose.bones}
    cases = {"neutral":[], "all_full_flex":[(d,j) for d in DIGITS for j in range(3)], "thumb_middle_full":[("thumb",1)]}
    cases.update({d+"_tip_full":[(d,2)] for d in DIGITS})
    top_faces, local_dorsal = {}, {}
    for digit in DIGITS:
        nail = parts["nail_"+digit]
        assert len(nail.data.vertices) == 322
        nail.data.calc_loop_triangles()
        top_faces[digit] = [tuple(t.vertices) for t in nail.data.loop_triangles if max(t.vertices)<161]
        assert len(top_faces[digit]) >= 8
        rest = rig.matrix_world @ rig.data.bones[digit+"2"].matrix_local
        axis = (legacy.native_matrix(rig,rig).to_3x3() @ rig.data.bones[digit+"2"].matrix_local.to_3x3().col[1]).normalized()
        dorsal_native = (Vector((0,0,1))-axis*axis.z).normalized()
        holder_basis = rig.parent.matrix_world.to_3x3() if rig.parent else Matrix.Identity(3)
        local_dorsal[digit] = rest.to_3x3().inverted() @ (holder_basis @ dorsal_native)
    result = {}
    try:
        for label, selected in cases.items():
            for b in rig.pose.bones:b.matrix_basis=saved[b.name]
            for key in hand.data.shape_keys.key_blocks[1:]:key.value=0
            for digit,joint in selected:
                degrees = ((60,70,80) if digit=="thumb" else (90,110,80))[joint]
                bone = rig.pose.bones[digit+str(joint)]
                bone.matrix_basis=saved[bone.name]@Matrix.Rotation(-math.radians(degrees),4,"X")
                hand.data.shape_keys.key_blocks[f"Joint_{digit}_{joint}"].value=1
            bpy.context.view_layer.update()
            skin = core.evaluated_points(hand)
            row = {}
            for digit in DIGITS:
                tree = BVHTree.FromPolygons(skin,targets[digit])
                nail = core.evaluated_points(parts["nail_"+digit])
                distances = [tree.find_nearest(p)[3] for p in nail]
                signed_top, ray_top = [], []
                dorsal = ((rig.matrix_world @ rig.pose.bones[digit+"2"].matrix).to_3x3() @ local_dorsal[digit]).normalized()
                for face in top_faces[digit]:
                    a,b,c=[nail[i] for i in face]
                    for p in ((a+b+c)/3, a*.6+b*.2+c*.2, a*.2+b*.6+c*.2, a*.2+b*.2+c*.6):
                        point,normal,index,distance=tree.find_nearest(p)
                        distances.append(distance)
                        signed_top.append((p-point).dot(normal))
                        hit = tree.ray_cast(p+dorsal*.002,-dorsal,.004)
                        ray_top.append((p-hit[0]).dot(dorsal) if hit[0] is not None else float("nan"))
                row[digit]={"distances":np.asarray(distances), "signed_top":np.asarray(signed_top), "ray_top":np.asarray(ray_top)}
            result[label]=row
    finally:
        for b in rig.pose.bones:b.matrix_basis=saved[b.name]
        for key in hand.data.shape_keys.key_blocks[1:]:key.value=0
        bpy.context.view_layer.update()
    return result


def compare_nails(current, original):
    result = {}
    for pose, digits in current.items():
        result[pose]={}
        for digit,new in digits.items():
            old=original[pose][digit]
            assert new["distances"].shape==old["distances"].shape and new["signed_top"].shape==old["signed_top"].shape
            assert np.isfinite(new["ray_top"]).all(), f"Candidate nail top witness has no nearby actual skin ray hit: {pose}/{digit}"
            old_ray = old["ray_top"][np.isfinite(old["ray_top"])]
            maximum=float(new["distances"].max())
            added=float((new["distances"]-old["distances"]).max())
            intrusion=float((old["signed_top"]-new["signed_top"]).max())
            row={"witnesses":len(new["distances"]), "source_maximum_gap_m":float(old["distances"].max()),
                "maximum_gap_m":maximum,"maximum_added_gap_m":added,"maximum_added_top_intrusion_m":intrusion,
                "source_minimum_signed_top_m":float(old["signed_top"].min()),"minimum_signed_top_m":float(new["signed_top"].min()),
                "source_minimum_ray_clearance_m":float(old_ray.min()) if len(old_ray) else None,
                "source_ray_miss_count":int(np.count_nonzero(~np.isfinite(old["ray_top"]))),
                "minimum_ray_clearance_m":float(new["ray_top"].min())}
            result[pose][digit]=row
            assert maximum < .0008, f"Actual nail gap exceeds existing 0.8mm contract ({pose}/{digit}): "+json.dumps(row)
            required_clearance = .00008 if pose == "neutral" else -.00002
            assert float(new["ray_top"].min()) >= required_clearance, f"Nail top still crosses its actual skin surface ({pose}/{digit}): "+json.dumps(row)
            # The approved nail repair intentionally increases gap to remove
            # inherited penetration; exact source seating is not required.
            if digit == 'thumb':
                assert float(new['signed_top'].min())>=-.00002, f"Repositioned thumb nail intrudes on its new nail bed ({pose}): "+json.dumps(row)
            else:
                assert intrusion < .00002, f"Nail repair made an actual top-face intrusion worse ({pose}/{digit}): "+json.dumps(row)
    return result


def texture_surface_samples(scene):
    uv, unused = legacy.uv_samples(scene.objects)
    material = bpy.data.materials["Detailed_Skin"]
    result = {}
    for semantic in ("basecolor", "normal", "roughness"):
        image = material.node_tree.nodes["Baked_"+semantic].image
        assert image and image.packed_file is not None and tuple(image.size) == (4096,4096)
        pixels = np.empty(len(image.pixels), dtype=np.float32)
        image.pixels.foreach_get(pixels)
        pixels = pixels.reshape(4096,4096,image.channels)
        row = {}
        for role, points in uv.items():
            x = np.clip((np.mod(points[:,0],1)*4096).astype(np.int64),0,4095)
            y = np.clip((np.mod(points[:,1],1)*4096).astype(np.int64),0,4095)
            row[role] = pixels[y,x,:3].copy()
        result[semantic] = row
    return result


def compare_texture_surfaces(current, source):
    result = {}
    for semantic, roles in current.items():
        result[semantic] = {}
        for role, values in roles.items():
            old = source[semantic][role]
            assert values.shape == old.shape and np.isfinite(values).all()
            delta = np.abs(values-old)
            maximum = float(delta.max())
            changed = int(np.count_nonzero(np.any(delta>1e-6,axis=1)))
            if role in ("Detailed_Glove", "Detailed_Trim", "Detailed_Sleeve"):
                assert maximum < 1e-6, f"Protected non-skin {semantic} changed on actual UV face centers: {role}/{maximum}"
            result[semantic][role] = {"actual_uv_face_center_samples":len(values),"maximum_pixel_difference":maximum,"changed_samples":changed}
    return result


def packed_atlases(scene, output):
    material=next(m for m in bpy.data.materials if m.name=="Detailed_Skin")
    result, evidence = {}, {}
    for semantic in ("basecolor","normal","roughness"):
        image=material.node_tree.nodes["Baked_"+semantic].image
        assert image and image.packed_file is not None and tuple(image.size)==(4096,4096)
        disk = output / ("realistic_hands_"+semantic+".png")
        packed_sha = hashlib.sha256(image.packed_file.data).hexdigest()
        assert packed_sha == sha(disk), "Packed image retains stale bytes instead of actual new PNG: "+semantic
        evidence[semantic] = {"image":image.name,"saved_png_sha256":sha(disk),"packed_sha256":packed_sha,"packed_bytes_equal_new_png":True}
        for role in ROLES:
            bound = bpy.data.materials[role].node_tree.nodes["Baked_"+semantic].image
            assert bound == image, "A production role still references a different/old atlas: "+role+"/"+semantic
        pixels=np.empty(len(image.pixels),dtype=np.float32)
        image.pixels.foreach_get(pixels)
        assert np.isfinite(pixels).all()
        result[semantic]=pixels.reshape(4096,4096,image.channels)[:,:,:3].copy()
    return result, evidence


def embedded_pixels(path, original_path, atlases):
    document, binary = legacy.glb_chunks(path)
    old_doc, old_binary = legacy.glb_chunks(original_path)
    def binding(material, semantic):
        if semantic == "normal": return material["normalTexture"]
        pbr = material["pbrMetallicRoughness"]
        return pbr["baseColorTexture" if semantic == "basecolor" else "metallicRoughnessTexture"]
    def payload(doc, data, texture):
        image_index = doc["textures"][texture["index"]]["source"]
        image = doc["images"][image_index]
        view = doc["bufferViews"][image["bufferView"]]
        raw = data[view.get("byteOffset",0):view.get("byteOffset",0)+view["byteLength"]]
        return image_index, raw
    def decode(raw, semantic, directory, name):
        image_path = Path(directory)/(name+".png")
        image_path.write_bytes(raw)
        image = bpy.data.images.load(str(image_path),check_existing=False)
        try:
            image.colorspace_settings.name = "sRGB" if semantic=="basecolor" else "Non-Color"
            assert tuple(image.size)==(4096,4096)
            pixels=np.empty(len(image.pixels),dtype=np.float32)
            image.pixels.foreach_get(pixels)
            return pixels.reshape(4096,4096,image.channels)[:,:,:3].copy()
        finally: bpy.data.images.remove(image)
    report = {}
    with tempfile.TemporaryDirectory(prefix="finger_embedded_verify_") as directory:
        for semantic in ("basecolor","normal","roughness"):
            bindings = [(m,payload(document,binary,binding(m,semantic))) for m in document["materials"]]
            assert len({item[1][0] for item in bindings}) == 1, "Production roles disagree on the shared atlas binding: "+semantic
            index, raw = bindings[0][1]
            values=decode(raw,semantic,directory,"new_"+semantic)
            expected=atlases[semantic]
            channels = [1] if semantic=="roughness" else [0,1,2]
            assert np.array_equal(values[:,:,channels],expected[:,:,channels]), "Actual glTF material binds stale/wrong embedded pixels: "+semantic
            row={"image_index":index,"embedded_blob_sha256":hashlib.sha256(raw).hexdigest(),
                "verified_actual_material_roles":[m["name"] for m,_ in bindings],"matches_new_png_and_packed_pixels":True,
                "channels":"G" if semantic=="roughness" else "RGB"}
            if semantic=="roughness":
                old_skin=next(m for m in old_doc["materials"] if m["name"].split(".")[0]=="Detailed_Skin")
                unused, old_raw=payload(old_doc,old_binary,binding(old_skin,semantic))
                old=decode(old_raw,semantic,directory,"old_roughness")
                assert np.array_equal(values[:,:,[0,2]],old[:,:,[0,2]]), "Unchanged occlusion/metallic channels changed"
                row["occlusion_metallic_channels_preserved"]=True
            report[semantic]=row
    return report


def main():
    global legacy,generic,core
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source-dir",type=Path,required=True)
    parser.add_argument("--output-dir",type=Path,required=True)
    parser.add_argument("--blend-name",default="bilateral_hands_finger_detail.blend")
    parser.add_argument("--scene",default="Bilateral_Realistic_Review")
    parser.add_argument("--support-dir",type=Path,default=Path(__file__).resolve().parents[2]/"player_hands_realism_20260911/tools")
    parser.add_argument("--generic-validator",type=Path,default=Path(__file__).resolve().parents[2]/"player_hands_proportions_20260911/tools/verify_proportions.py")
    args=parser.parse_args(sys.argv[sys.argv.index("--")+1:])
    assert bpy.app.background
    legacy=module(args.support_dir/"verify_hands_realistic.py","finger_detail_legacy")
    generic=module(args.generic_validator,"finger_detail_generic")
    core=legacy.core
    generic.legacy=legacy
    generic.core=core
    source,output=args.source_dir.resolve(),args.output_dir.resolve()
    source_blend=source/"bilateral_hands_proportions.blend"
    final_blend=output/args.blend_name
    glbs={s:output/f"{s}_hand_finger_detail.glb" for s in ("left","right")}
    inputs=[source_blend,final_blend,*glbs.values(),Path(__file__),args.generic_validator,
        args.support_dir/"verify_hands_realistic.py",args.support_dir/"joint_verification_core.py"]
    inputs += [source/f"{s}_hand_proportions.glb" for s in glbs]
    inputs += [output/("realistic_hands_"+semantic+".png") for semantic in ("basecolor","normal","roughness")]
    hashes={str(p.resolve()):sha(p) for p in inputs}
    report={"status":"running","verified_sha256":hashes,"checks":{},"errors":[],"limitations":[
        "Actual appearance and ten individual digit-face comparisons require separate direct visual review.",
        "Neutral overlap checks cover changed physical skin triangles and distinguish inherited intersections; they are not a global cloth collision simulation.",
        "New skin/nail PBR pixels are allowed; original texture-byte equality is not a detail acceptance rule.",
        "Nail seating checks sample every vertex and four actual top-face interior points against distal nail-bed skin in eight evaluated poses; folded proximal webbing is excluded. They do not analytically prove every continuous point or whole-fist self-collision."]}
    try:
        bpy.ops.wm.open_mainfile(filepath=str(source_blend))
        scene,rigs=activate(args.scene)
        original={s:capture(scene,r) for s,r in rigs.items()}
        original_texture_samples=texture_surface_samples(scene)
        old_nails={s:nail_measurements(scene,r) for s,r in rigs.items()}
        for side in glbs:
            bpy.ops.wm.read_factory_settings(use_empty=True)
            bpy.ops.import_scene.gltf(filepath=str(source/f"{side}_hand_proportions.glb"),bone_heuristic="TEMPERANCE")
            rig=next(o for o in bpy.context.scene.objects if o.type=="ARMATURE")
            legacy.attach_prior_export_weights(original[side],legacy.snapshot(bpy.context.scene,rig))
        bpy.ops.wm.open_mainfile(filepath=str(final_blend))
        scene,rigs=activate(args.scene)
        current={s:capture(scene,r) for s,r in rigs.items()}
        report["checks"]["materials"]=legacy.inspect_materials(scene.objects)
        report["checks"]["texture_surface_changes"]=compare_texture_surfaces(texture_surface_samples(scene),original_texture_samples)
        atlases, packed_evidence=packed_atlases(scene,output)
        report["checks"]["actual_packed_png_equivalence"]=packed_evidence
        changes=report["checks"]["texture_surface_changes"]
        for role in ("Detailed_Skin","Detailed_Nail"):
            for semantic in ("normal","roughness"):
                assert changes[semantic][role]["changed_samples"]>=10, "New detail maps were not applied to actual skin/nail UVs: "+role+"/"+semantic
        for side,rig in rigs.items():
            row = {}
            report["checks"]["editable_"+side] = row
            row["source_preservation"] = inspect_changes(original[side],current[side])
            row["corrective_locality"] = inspect_key_locality(current[side])
            row["actual_articulation"] = generic.inspect_pose(scene,rig)
            row["actual_nail_seating"] = compare_nails(nail_measurements(scene,rig),old_nails[side])
            for label,part in current[side]["parts"].items():
                part["prior_export_weights"]=original[side]["parts"][label]["prior_export_weights"]
        for side,path in glbs.items():
            row={"container":legacy.inspect_glb_container(path),
                "actual_embedded_pixels":embedded_pixels(path,source/f"{side}_hand_proportions.glb",atlases)}
            bpy.ops.wm.read_factory_settings(use_empty=True)
            bpy.ops.import_scene.gltf(filepath=str(path),bone_heuristic="TEMPERANCE")
            scene=bpy.context.scene
            rig=next(o for o in scene.objects if o.type=="ARMATURE")
            actual=capture(scene,rig)
            row["roundtrip"]=generic.roundtrip(actual,current[side])
            assert actual["parts"]["WristCuff"]["flex"]==current[side]["parts"]["WristCuff"]["flex"]
            row["actual_articulation"]=generic.inspect_pose(scene,rig)
            row["corrective_locality"]=inspect_key_locality(actual)
            report["checks"][side+"_glb"]=row
    except Exception as error:
        report["errors"].append({"error":str(error),"traceback":traceback.format_exc()})
    assert all(sha(path)==value for path,value in hashes.items()),"A read-only input changed during verification"
    report["status"]="failed" if report["errors"] else "passed"
    (output/"verification_report.json").write_text(json.dumps(report,indent=2)+"\n")
    print("FINGER_DETAIL_VERIFICATION",report["status"],json.dumps(report["errors"]),flush=True)
    if report["errors"]:raise SystemExit(1)


if __name__=="__main__":
    main()
