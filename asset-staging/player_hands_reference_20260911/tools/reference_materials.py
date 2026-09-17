"""Reference-photo skin fields and a portable PBR bake shader.

Call prepare_fields after anatomical sculpting, then procedural_materials.
No geometry, weights, pose, shape keys, or UVs are changed here. The returned
material tuples match realism_bake.procedural_materials. Remove ATTRIBUTE_NAMES
after baking; the final glTF must not multiply these pigment fields by its atlas.
Native coordinates are holder-local metres: +Y fingers, +Z dorsum, -Y forearm.
"""
import math

import bpy
from mathutils import Vector
from reference_photo_projection import prepare_photo_uv, photo_pigment, ATTRIBUTE_NAMES as PHOTO_ATTRIBUTES

DIGITS = ("thumb", "index", "middle", "ring", "little")
ROLES = ("Detailed_Skin", "Detailed_Glove", "Detailed_Sleeve", "Detailed_Nail", "Detailed_Trim")
PROCEDURAL_ATTRIBUTES = ("ReferencePigment", "ReferenceNative", "ReferencePalm", "ReferenceFacing",
                   "ReferenceJoint0", "ReferenceJoint1", "ReferenceJoint2", "ReferenceNail")
ATTRIBUTE_NAMES = PROCEDURAL_ATTRIBUTES + PHOTO_ATTRIBUTES
SKIN_SRGB = (.760, .535, .400)
PALM_SRGB = (.850, .655, .505)
NAIL_SRGB = (.795, .560, .505)


def color(values):
    """An artist-facing sRGB triple to scene-linear RGBA."""
    return tuple(v / 12.92 if v <= .04045 else ((v + .055) / 1.055) ** 2.4 for v in values) + (1.0,)


def _mix(a, b, amount):
    return tuple(x * (1.0 - amount) + y * amount for x, y in zip(a, b))


def _smooth(a, b, value):
    t = min(1.0, max(0.0, (value - a) / (b - a)))
    return t * t * (3.0 - 2.0 * t)


def _field(obj, name, color_field=False):
    old = obj.data.attributes.get(name)
    if old:
        obj.data.attributes.remove(old)
    return obj.data.attributes.new(name=name, type="FLOAT_COLOR" if color_field else "FLOAT_VECTOR", domain="POINT")


def _native_matrix(obj, holder):
    return holder.matrix_world.inverted() @ obj.matrix_world if holder else obj.matrix_world.copy()


def _frames(skin, rig, holder, points, owners):
    """Centre landmarks on the sculpted skin section, not the bone head."""
    result = {}
    transform = _native_matrix(rig, holder)
    for digit in DIGITS:
        candidates = [i for i, owner in enumerate(owners) if owner == digit]
        assert len(candidates) >= 24, "Cannot measure the actual " + digit + " skin section"
        for joint in range(3):
            matrix = transform @ rig.data.bones[digit + str(joint)].matrix_local
            center = matrix.translation.copy()
            along = matrix.to_3x3().col[1].normalized()
            dorsal = matrix.to_3x3().col[2].normalized()
            across = along.cross(dorsal).normalized()
            nearest = sorted(candidates, key=lambda i: abs((points[i] - center).dot(along)))[:64]
            radius = .010
            for direction in (across, dorsal):
                offsets = sorted((points[i] - center).dot(direction) for i in nearest)
                lo, hi = offsets[2], offsets[-3]
                center += direction * ((lo + hi) * .5)
                if direction == across:
                    radius = max(.004, (hi - lo) * .5)
            result[digit, joint] = (center, along, dorsal, across, radius)
    return result


def prepare_fields(skin, rig, holder, nails):
    """Populate bake-only attributes on an already sculpted bare hand and nails."""
    matrix = _native_matrix(skin, holder)
    normal_matrix = matrix.to_3x3().inverted().transposed()
    points = [matrix @ vertex.co for vertex in skin.data.vertices]
    normals = [(normal_matrix @ vertex.normal).normalized() for vertex in skin.data.vertices]
    group_names = {group.index: group.name for group in skin.vertex_groups}
    owners = []
    for vertex in skin.data.vertices:
        name = group_names[max(vertex.groups, key=lambda g: g.weight).group] if vertex.groups else "wrist"
        owners.append(next((digit for digit in DIGITS if name.startswith(digit)), "wrist"))
    frames = _frames(skin, rig, holder, points, owners)
    tip_extents = {digit: max((p-frames[digit,2][0]).dot(frames[digit,2][1]) for p,owner in zip(points,owners) if owner==digit) for digit in DIGITS}
    thumb_sign = 1.0 if frames["thumb", 0][0].x > frames["middle", 0][0].x else -1.0
    palm_start = .010  # The preserved wrist / soft transition boundary.
    palm_end = sum(frames[digit, 0][0].y for digit in ("index", "middle", "ring")) / 3.0
    palm_points = [p for p, owner in zip(points, owners) if owner == "wrist" and .035 < p.y < .075]
    assert len(palm_points) > 20 and palm_end > .065
    lateral = sorted(p.x for p in palm_points)
    palm_center_x = (lateral[2] + lateral[-3]) * .5
    palm_half_width = (lateral[-3] - lateral[2]) * .5
    assert palm_half_width > .025
    fields = {name: _field(skin, name, name == "ReferencePigment") for name in PROCEDURAL_ATTRIBUTES if name != "ReferenceNail"}
    for vertex, point, normal, owner in zip(skin.data.vertices, points, normals, owners):
        index = vertex.index
        finger = owner != "wrist"
        dorsal = frames[owner, 1][2] if finger else Vector((0, 0, 1))
        facing = normal.dot(dorsal)
        palm, back = max(0.0, -facing) ** 1.5, max(0.0, facing) ** 1.5
        redness = 0.0
        for joint in range(3):
            field = fields["ReferenceJoint" + str(joint)]
            if finger:
                center, along, unused, across, radius = frames[owner, joint]
                offset = point - center
                field.data[index].vector = (offset.dot(across) / radius, offset.dot(along), DIGITS.index(owner) + 1.0)
                redness = max(redness, math.exp(-((offset.dot(along) / .006) ** 2)))
            else:
                field.data[index].vector = (4.0, .15, 0.0)
        # Broad, subtle circulation variation; the crease shader adds no black ink.
        # Keep the shared hand/cuff wrist region neutral on both surfaces;
        # palmar pigmentation appears gradually above their overlap.
        pigment = _mix(SKIN_SRGB, PALM_SRGB, palm * .70 * _smooth(.025, .045, point.y))
        tip_blood = _smooth(.48,.91,(point-frames[owner,2][0]).dot(frames[owner,2][1])/max(tip_extents[owner],.005)) if finger else 0.0
        pigment = _mix(pigment, (.855, .430, .330), max(redness*.19,tip_blood*.22))
        fields["ReferencePigment"].data[index].color = color(pigment)
        fields["ReferenceNative"].data[index].vector = point
        fields["ReferencePalm"].data[index].vector = (thumb_sign * (point.x - palm_center_x) / palm_half_width,
            (point.y - palm_start) / (palm_end - palm_start), 0.0)
        fields["ReferenceFacing"].data[index].vector = (palm, back, 1.0 if finger else 0.0)
    photo_report = prepare_photo_uv(skin, rig, holder, points, owners, frames)
    nail_rows = [prepare_part(nail, rig, holder) for nail in nails if nail.type == "MESH"]
    return {"photo_projection": photo_report, "attributes": list(fields) + list(PHOTO_ATTRIBUTES), "geometry_changed": False, "thumb_side_native_x_sign": thumb_sign,
            "palm_start_y": palm_start, "palm_end_y": palm_end, "palm_center_x": palm_center_x,
            "palm_half_width": palm_half_width, "skin_srgb": SKIN_SRGB, "palm_srgb": PALM_SRGB,
            "joint_section_centers_native": {digit + str(joint): list(value[0]) for (digit, joint), value in frames.items()},
            "palm_main_flows": 3, "palm_total_segments_including_branches": 12, "nails": nail_rows}


def prepare_part(obj, rig=None, holder=None):
    """Fields for rigid nails or existing sleeve/trim meshes; no surface edits."""
    matrix = _native_matrix(obj, holder)
    points = [matrix @ vertex.co for vertex in obj.data.vertices]
    native = _field(obj, "ReferenceNative")
    pigment = _field(obj, "ReferencePigment", True)
    is_nail = "Nail_" in obj.name
    is_skin = any(slot.material and slot.material.name.split(".")[0] == "Detailed_Skin" for slot in obj.material_slots)
    normal_matrix = matrix.to_3x3().inverted().transposed()
    facing = _field(obj, "ReferenceFacing") if is_skin else None
    palm_coords = _field(obj, "ReferencePalm") if is_skin else None
    nail_coords = _field(obj, "ReferenceNail") if is_nail else None
    if is_nail:
        assert rig is not None
        digit = next(digit for digit in DIGITS if "Nail_" + digit in obj.name)
        frame = _native_matrix(rig, holder) @ rig.data.bones[digit + "2"].matrix_local
        axis = frame.to_3x3().col[1].normalized()
        across = axis.cross(frame.to_3x3().col[2].normalized()).normalized()
        along = [point.dot(axis) for point in points]
        lateral = [point.dot(across) for point in points]
        lo, hi = min(along), max(along)
        left, right = min(lateral), max(lateral)
        assert hi - lo > .003 and right - left > .003
    for index, point in enumerate(points):
        native.data[index].vector = point
        base = NAIL_SRGB if is_nail else (.14, .115, .090)
        if is_skin:
            normal = (normal_matrix @ obj.data.vertices[index].normal).normalized()
            palm, back = max(0.0, -normal.z) ** 1.5, max(0.0, normal.z) ** 1.5
            base = _mix(SKIN_SRGB, PALM_SRGB, palm * .70 * _smooth(.025, .045, point.y))
            facing.data[index].vector = (palm, back, 0.0)
            # A sleeve transition has no palm or finger creases of its own.
            palm_coords.data[index].vector = (4.0, 4.0, 0.0)
        pigment.data[index].color = color(base)
        if is_nail:
            nail_coords.data[index].vector = ((along[index] - lo) / (hi - lo),
                (lateral[index] - (left + right) * .5) / ((right - left) * .5), hi - lo)
    return {"object": obj.name, "is_nail": is_nail, "is_skin_material": is_skin, "geometry_changed": False}


class _Nodes:
    def __init__(self, material):
        material.use_nodes = True
        self.nodes, self.links = material.node_tree.nodes, material.node_tree.links
        self.nodes.clear()

    def new(self, kind, name=None):
        result = self.nodes.new(kind)
        if name:
            result.name = name
        return result

    def assign(self, value, socket):
        if isinstance(value, (int, float, tuple, list, Vector)):
            socket.default_value = value
        else:
            self.links.new(value, socket)

    def math(self, operation, *values):
        result = self.new("ShaderNodeMath")
        result.operation = operation
        for value, socket in zip(values, result.inputs):
            self.assign(value, socket)
        return result.outputs[0]

    def vector(self, operation, first, second=None):
        result = self.new("ShaderNodeVectorMath")
        result.operation = operation
        self.assign(first, result.inputs[0])
        if second is not None:
            self.assign(second, result.inputs[3] if operation == "SCALE" else result.inputs[1])
        return result.outputs["Value" if operation in ("DOT_PRODUCT", "LENGTH", "DISTANCE") else "Vector"]

    def attribute(self, name, separate=False):
        attribute = self.new("ShaderNodeAttribute", name)
        attribute.attribute_name = name
        if not separate:
            return attribute
        xyz = self.new("ShaderNodeSeparateXYZ")
        self.links.new(attribute.outputs["Vector"], xyz.inputs[0])
        return tuple(xyz.outputs)

    def mix(self, factor, first, second, operation="MIX"):
        result = self.new("ShaderNodeMixRGB")
        result.blend_type = operation
        for value, socket in zip((factor, first, second), result.inputs):
            self.assign(value, socket)
        return result.outputs[0]

    def noise(self, position, scale, detail=2.0):
        result = self.new("ShaderNodeTexNoise")
        self.links.new(position, result.inputs["Vector"])
        result.inputs["Scale"].default_value = scale
        result.inputs["Detail"].default_value = detail
        result.inputs["Roughness"].default_value = .55
        return result.outputs["Fac"]

    def gaussian(self, value, width):
        return self.math("EXPONENT", self.math("MULTIPLY", self.math("POWER", self.math("DIVIDE", value, width), 2.0), -1.0))

    def line(self, position, points, width):
        if len(points)>2:
            controls=[Vector(p) for p in points];curved=[]
            for index in range(len(controls)-1):
                p0=controls[max(0,index-1)];p1=controls[index];p2=controls[index+1];p3=controls[min(len(controls)-1,index+2)]
                for step in range(4):
                    t=step/4.;curved.append(.5*((2*p1)+(-p0+p2)*t+(2*p0-5*p1+4*p2-p3)*t*t+(-p0+3*p1-3*p2+p3)*t*t*t))
            curved.append(controls[-1]);points=curved
        points = [Vector((x * .050, y * .085, 0.0)) for x, y in points]
        distances = []
        for first, second in zip(points, points[1:]):
            direction = (second - first).normalized()
            relative = self.vector("SUBTRACT", position, first)
            length = self.math("MINIMUM", self.math("MAXIMUM", self.vector("DOT_PRODUCT", relative, direction), 0.0), (second - first).length)
            distances.append(self.vector("LENGTH", self.vector("SUBTRACT", relative, self.vector("SCALE", direction, length))))
        distance = distances[0]
        for following in distances[1:]:
            distance = self.math("MINIMUM", distance, following)
        endpoint = self.math("MINIMUM", self.vector("DISTANCE", position, points[0]), self.vector("DISTANCE", position, points[-1]))
        fade = self.math("MINIMUM", self.math("DIVIDE", endpoint, .0035), 1.0)
        return self.math("MULTIPLY", self.gaussian(distance, width), fade)


def _skin_height(n, native, grain):
    palm, dorsal, finger = n.attribute("ReferenceFacing", True)
    palm_coords = n.vector("MULTIPLY", n.attribute("ReferencePalm").outputs["Vector"], (.050, .085, 0.0))
    height = n.math("MULTIPLY", n.math("SUBTRACT", grain, .5), .000013)
    palm_darkness = 0.0
    # Three major irregular flows (nine segments), three much finer branches.
    flows = (
        (((.45, .90), (.06, .65), (.00, .32), (.26, .08)), .00055, .000210),
        (((-.82, .84), (-.35, .80), (.08, .77), (.50, .83)), .00046, .000170),
        (((.44, .80), (.12, .60), (-.35, .45), (-.75, .37)), .00050, .000200),
        (((.02, .36), (-.16, .24)), .00019, .000026),
        (((-.35, .80), (-.29, .94)), .00017, .000020),
        (((-.32, .46), (-.37, .29)), .00018, .000024),
    )
    for points, width, depth in flows:
        crease = n.math("MULTIPLY", n.line(palm_coords, points, width), palm)
        height = n.math("ADD", height, n.math("MULTIPLY", crease, -depth))
        palm_darkness = n.math("MAXIMUM", palm_darkness, crease)
    xyz=n.new("ShaderNodeSeparateXYZ");n.links.new(native,xyz.inputs[0]);x,y=xyz.outputs['X'],xyz.outputs['Y']
    wrist_gate=n.math('EXPONENT',n.math('MULTIPLY',n.math('POWER',n.math('DIVIDE',n.math('ABSOLUTE',x),.029),6.),-1.))
    wrist_curve=n.math('MULTIPLY',n.math('POWER',n.math('DIVIDE',x,.030),2.),.0017)
    for offset,width,depth in ((.006,.00042,.000085),(-.002,.00034,.000060),(-.008,.00024,.000025)):
        crease=n.math('MULTIPLY',n.math('MULTIPLY',n.gaussian(n.math('SUBTRACT',n.math('ADD',y,wrist_curve),offset),width),wrist_gate),palm)
        height=n.math('ADD',height,n.math('MULTIPLY',crease,-depth));palm_darkness=n.math('MAXIMUM',palm_darkness,crease)
    jitter = n.math("MULTIPLY", n.math("SUBTRACT", n.noise(native, 430.0, 1.0), .5), .00010)
    for joint in range(3):
        u, v, digit = n.attribute("ReferenceJoint" + str(joint), True)
        phase = n.math("ADD", n.math("MULTIPLY", digit, 1.73), joint * 2.1)
        variation = n.math("SINE", phase)
        curve = n.math("MULTIPLY", n.math("POWER", u, 2.0), .0011 if joint else .0018)
        tilt = n.math("MULTIPLY", n.math("MULTIPLY", u, variation), .00045)
        arc = n.math("ADD", n.math("ADD", n.math("ADD", v, curve), tilt), jitter)
        width = n.math("ADD", .00025, n.math("MULTIPLY", variation, .000035))
        gate = n.math("EXPONENT", n.math("MULTIPLY", n.math("POWER", n.math("ABSOLUTE", u), 6.0), -1.5))
        facing = n.math("MULTIPLY", finger, n.math("ADD", palm, n.math("MULTIPLY", dorsal, .45 if joint else .18)))
        primary = n.math("MULTIPLY", n.math("MULTIPLY", n.gaussian(arc, width), gate), facing)
        height = n.math("ADD", height, n.math("MULTIPLY", primary, -.000130 if joint else -.000070))
        # One offset, shorter auxiliary fold; never the old identical three stripes.
        secondary_offset = n.math("ADD", .00155, n.math("MULTIPLY", variation, .00045))
        short_gate = n.gaussian(n.math("ADD", u, n.math("MULTIPLY", variation, .22)), .58)
        secondary = n.math("MULTIPLY", n.math("MULTIPLY", n.gaussian(n.math("SUBTRACT", arc, secondary_offset), .00016), short_gate), facing)
        height = n.math("ADD", height, n.math("MULTIPLY", secondary, -.000024))
    return height, palm_darkness


def procedural_materials(scene):
    """Return the seven-field tuples consumed by the existing bake pipeline."""
    result = {}
    palette = {"Detailed_Glove": (.092, .068, .050), "Detailed_Sleeve": (.143, .126, .105), "Detailed_Trim": (.205, .163, .106)}
    for name in ROLES:
        material = bpy.data.materials.get(name)
        if material is None:
            continue
        n = _Nodes(material)
        output = n.new("ShaderNodeOutputMaterial")
        bsdf = n.new("ShaderNodeBsdfPrincipled")
        n.links.new(bsdf.outputs["BSDF"], output.inputs["Surface"])
        bsdf.inputs["Metallic"].default_value = 0.0
        bsdf.inputs["IOR"].default_value = 1.45
        bsdf.inputs["Specular IOR Level"].default_value = .32
        native = n.attribute("ReferenceNative").outputs["Vector"]
        broad = n.noise(native, 105.0)
        grain = n.noise(native, 1900.0)
        pigment = n.attribute("ReferencePigment").outputs["Color"] if name in ("Detailed_Skin", "Detailed_Nail") else color(palette[name])
        variation = n.math("ADD", .970, n.math("MULTIPLY", broad, .060))
        base = n.mix(1.0, pigment, variation, "MULTIPLY")
        ranges = {"Detailed_Skin": (.48, .61), "Detailed_Nail": (.30, .38), "Detailed_Glove": (.60, .77), "Detailed_Sleeve": (.64, .85), "Detailed_Trim": (.61, .77)}
        low, high = ranges[name]
        rough = n.math("ADD", low, n.math("MULTIPLY", broad, high - low))
        height = n.math("MULTIPLY", n.math("SUBTRACT", grain, .5), .000040)
        if name == "Detailed_Skin":
            height, crease = _skin_height(n, native, grain)
            base = n.mix(n.math("MULTIPLY", crease, .18), base, color((.42, .27, .21)))
            base = photo_pigment(n, base)
        elif name == "Detailed_Nail":
            t, across, unused = n.attribute("ReferenceNail", True)
            # A faint basal crescent, and only the outermost ~0.3 mm free edge.
            crescent = n.gaussian(n.math("SUBTRACT", t, n.math("ADD", .10, n.math("MULTIPLY", n.math("POWER", across, 2.0), .055))), .045)
            base = n.mix(n.math("MULTIPLY", crescent, .075), base, color((.845, .755, .700)))
            tip = n.math("MINIMUM", n.math("MAXIMUM", n.math("DIVIDE", n.math("SUBTRACT", t, .974), .022), 0.0), 1.0)
            base = n.mix(n.math("MULTIPLY", tip, .38), base, color((.88, .83, .75)))
            height = n.math("MULTIPLY", n.math("SUBTRACT", grain, .5), .000003)
        bump = n.new("ShaderNodeBump")
        bump.inputs["Strength"].default_value = .80 if name == "Detailed_Skin" else .45
        bump.inputs["Distance"].default_value = 1.0
        n.links.new(height, bump.inputs["Height"])
        n.links.new(bump.outputs["Normal"], bsdf.inputs["Normal"])
        n.links.new(base, bsdf.inputs["Base Color"])
        n.links.new(rough, bsdf.inputs["Roughness"])
        emission = n.new("ShaderNodeEmission", "BakeEmission")
        target = n.new("ShaderNodeTexImage", "BakeTarget")
        material.diffuse_color = color(SKIN_SRGB if name == "Detailed_Skin" else NAIL_SRGB if name == "Detailed_Nail" else palette[name])
        result[name] = (material, bsdf, output, emission, target, base, rough)
    return result
