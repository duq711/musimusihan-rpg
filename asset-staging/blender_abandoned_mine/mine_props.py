"""Authored abandoned-mine prop assemblies for Blender and glTF.

build_props(layout, materials, collection, clearance_fn=None,
            ground_height_fn=None) returns JSON-serializable placement/collision
metadata. clearance_fn(x, godot_z, radius) must return True when placement is
allowed. UVs are physical metres; the supplied materials control scan scale.
All coordinates inside an assembly use X=width, Y=length, Z=up. World layout
(Godot x,z) is converted to Blender (x,-z,z_up). No application/UI operations.
"""

from __future__ import annotations

import math
import random
from collections import defaultdict

import bpy
import bmesh
from mathutils import Matrix, Vector

TAU = math.tau


def _point_inside(p, polygon):
    x, y = p
    result = False
    for a, b in zip(polygon, polygon[1:] + polygon[:1]):
        if (a[1] > y) != (b[1] > y):
            hit = (b[0] - a[0]) * (y - a[1]) / (b[1] - a[1]) + a[0]
            if x < hit:
                result = not result
    return result


def _segment_distance(point, a, b):
    p, a, b = Vector(point), Vector(a), Vector(b)
    axis = b - a
    t = max(0.0, min(1.0, (p - a).dot(axis) / max(axis.length_squared, 1e-8)))
    return (p - a - axis * t).length


def _plain_material(name, color, roughness=0.85, metallic=0.0):
    mat = bpy.data.materials.new(name)
    mat.diffuse_color = (*color, 1)
    mat.use_nodes = True
    shader = mat.node_tree.nodes.get("Principled BSDF")
    shader.inputs["Base Color"].default_value = (*color, 1)
    shader.inputs["Roughness"].default_value = roughness
    shader.inputs["Metallic"].default_value = metallic
    return mat


class Props:
    def __init__(self, layout, materials, collection, clearance_fn, ground_height_fn):
        self.layout = layout
        self.materials = dict(materials)
        self.collection = collection
        self.clearance_fn = clearance_fn
        self.ground_height_fn = ground_height_fn or (lambda x, z: 0.0)
        self.rng = random.Random(int(layout.get("seed", 139131)) + 4177)
        self.rooms = {room["id"]: room for room in layout["rooms"]}
        self.assets = []
        self.collisions = []
        self.skipped = []
        self.occupied = []
        self.used_landmarks = set()
        self.counts = defaultdict(int)
        self.group = None
        self.pieces = []
        self.materials.setdefault("rope", _plain_material("AgedHempRope", (0.18, 0.105, 0.043), 0.96))
        self.materials.setdefault("cloth", _plain_material("DustyCanvas", (0.13, 0.095, 0.047), 0.98))
        self.materials.setdefault("glass", _plain_material("LanternSmokeGlass", (0.06, 0.039, 0.015), 0.35))
        self.materials.setdefault("wick", _plain_material("LanternWick", (0.035, 0.018, 0.007), 1.0))
        if "flame" not in self.materials:
            flame = _plain_material("MineLanternLivingFlame", (1.0,.22,.025), .4)
            shader = flame.node_tree.nodes.get("Principled BSDF")
            shader.inputs["Emission Color"].default_value = (1.0,.20,.018,1)
            shader.inputs["Emission Strength"].default_value = 5.0
            self.materials["flame"] = flame
        self.collision_collection = bpy.data.collections.new("MinePropCollisionProxies")
        collection.children.link(self.collision_collection)

    def mesh(self, name, vertices, faces, material, uv_faces=None, smooth=False):
        data = bpy.data.meshes.new(name)
        data.from_pydata(vertices, [], faces)
        data.update()
        uv = data.uv_layers.new(name="UVMap")
        if uv_faces is not None:
            for poly, coords in zip(data.polygons, uv_faces):
                for loop_index, coordinate in zip(poly.loop_indices, coords):
                    uv.data[loop_index].uv = coordinate
        else:
            offset = (self.rng.random() * 9, self.rng.random() * 9)
            for poly in data.polygons:
                normal = poly.normal
                dominant = max(range(3), key=lambda axis: abs(normal[axis]))
                axes = ((1, 2), (0, 2), (0, 1))[dominant]
                for loop_index in poly.loop_indices:
                    co = data.vertices[data.loops[loop_index].vertex_index].co
                    uv.data[loop_index].uv = (co[axes[0]] + offset[0], co[axes[1]] + offset[1])
        for polygon in data.polygons:
            polygon.use_smooth = smooth
        obj = bpy.data.objects.new(name, data)
        self.collection.objects.link(obj)
        obj.parent = self.group
        if isinstance(material, str):
            material = self.materials[material]
        data.materials.append(material)
        self.pieces.append(obj)
        return obj

    def beam(self, name, a, b, width, depth=None, material="wood", wear=0.015):
        """Eight-sided chamfer profile, bowed centreline, nonuniform taper.

        Side UV V follows the grain down the timber. End caps have separate
        metre UVs. Chamfers are actual topology, retained by the game export.
        """
        a, b = Vector(a), Vector(b)
        depth = width if depth is None else depth
        length = (b - a).length
        chamfer = min(width, depth) * (0.11 if material == "wood" else 0.07)
        x, y = width / 2, depth / 2
        profile = [(-x + chamfer, -y), (x - chamfer, -y), (x, -y + chamfer),
                   (x, y - chamfer), (x - chamfer, y), (-x + chamfer, y),
                   (-x, y - chamfer), (-x, -y + chamfer)]
        segments = max(2, min(7, math.ceil(length / 0.65)))
        phase = self.rng.uniform(0, TAU)
        vertices, faces, uvs = [], [], []
        perimeter = [0.0]
        for j in range(8):
            perimeter.append(perimeter[-1] + (Vector(profile[(j + 1) % 8]) - Vector(profile[j])).length)
        uv_shift = self.rng.uniform(0, 8)
        for ring in range(segments + 1):
            t = ring / segments
            taper = 1 - t * self.rng.uniform(0.012, 0.045) if material == "wood" else 1.0
            bow = math.sin(t * math.pi) * wear
            for j, (px, py) in enumerate(profile):
                dent = self.rng.uniform(-wear, wear) * 0.20
                vertices.append(((px + dent) * taper + bow * math.cos(phase),
                                 (py + dent) * taper + bow * math.sin(phase), length * t))
        for ring in range(segments):
            for j in range(8):
                faces.append((ring * 8 + j, ring * 8 + (j + 1) % 8,
                              (ring + 1) * 8 + (j + 1) % 8, (ring + 1) * 8 + j))
                u0, u1 = perimeter[j], perimeter[j + 1]
                v0, v1 = length * ring / segments + uv_shift, length * (ring + 1) / segments + uv_shift
                uvs.append([(u0, v0), (u1, v0), (u1, v1), (u0, v1)])
        faces.extend([tuple(reversed(range(8))), tuple(segments * 8 + j for j in range(8))])
        uvs.extend([list(reversed(profile)), list(profile)])
        obj = self.mesh(name, vertices, faces, material, uvs)
        obj.location = a
        obj.rotation_mode = "QUATERNION"
        axis = (b - a).normalized()
        lateral = axis.cross(Vector((0, 0, 1)))
        if lateral.length < .001:
            lateral = Vector((1, 0, 0))
        lateral.normalize()
        vertical = axis.cross(lateral).normalized()
        obj.rotation_quaternion = Matrix((lateral, vertical, axis)).transposed().to_quaternion()
        return obj

    def tube(self, name, points, radius, material="metal", sides=10, capped=True):
        points = [Vector(p) for p in points]
        vertices, faces, uvs = [], [], []
        distances = [0.0]
        for a, b in zip(points, points[1:]):
            distances.append(distances[-1] + (b - a).length)
        for i, point in enumerate(points):
            tangent = points[min(i + 1, len(points) - 1)] - points[max(0, i - 1)]
            tangent.normalize()
            axis = tangent.cross(Vector((0, 0, 1)))
            if axis.length < 0.01:
                axis = tangent.cross(Vector((0, 1, 0)))
            axis.normalize()
            other = tangent.cross(axis).normalized()
            r = radius[i] if isinstance(radius, list) else radius
            for j in range(sides):
                angle = TAU * j / sides
                vertices.append(point + (axis * math.cos(angle) + other * math.sin(angle)) * r)
        for i in range(len(points) - 1):
            for j in range(sides):
                faces.append((i * sides + j, i * sides + (j + 1) % sides,
                              (i + 1) * sides + (j + 1) % sides, (i + 1) * sides + j))
                uvs.append([(j / sides, distances[i]), ((j + 1) / sides, distances[i]),
                            ((j + 1) / sides, distances[i + 1]), (j / sides, distances[i + 1])])
        if capped:
            faces.extend([tuple(reversed(range(sides))), tuple((len(points) - 1) * sides + j for j in range(sides))])
            uvs.extend([[(0.5 + 0.5 * math.cos(TAU * j / sides), 0.5 + 0.5 * math.sin(TAU * j / sides)) for j in reversed(range(sides))],
                        [(0.5 + 0.5 * math.cos(TAU * j / sides), 0.5 + 0.5 * math.sin(TAU * j / sides)) for j in range(sides)]])
        return self.mesh(name, vertices, faces, material, uvs, smooth=sides > 10)

    def disc(self, name, center, radius, depth, axis=(0, 0, 1), material="metal", sides=24):
        axis, center = Vector(axis).normalized(), Vector(center)
        return self.tube(name, [center - axis * depth / 2, center + axis * depth / 2], radius, material, sides)

    def hoop(self, name, center, radius, thickness=0.025, axis="Z", material="metal", steps=40):
        c = Vector(center)
        points = []
        for i in range(steps + 1):
            a = TAU * i / steps
            delta = Vector((radius * math.cos(a), radius * math.sin(a), 0))
            if axis == "X":
                delta = Vector((0, delta.x, delta.y))
            elif axis == "Y":
                delta = Vector((delta.x, 0, delta.y))
            points.append(c + delta)
        return self.tube(name, points, thickness, material, 8, capped=False)

    def bolt(self, position, axis=(0, 1, 0), radius=0.023):
        self.disc("ForgedBoltWasher", position, radius * 1.5, 0.009, axis, sides=12)
        p = Vector(position) + Vector(axis).normalized() * 0.012
        self.disc("HandForgedHexBolt", p, radius, 0.023, axis, sides=6)

    def band(self, center, width, depth, height=0.095):
        x, y, z = center
        for sy in (-1, 1):
            self.beam("IronTimberBand", (x - width / 2 - 0.008, y + sy * depth / 2, z),
                      (x + width / 2 + 0.008, y + sy * depth / 2, z), 0.026, height, "metal", 0)
            self.bolt((x, y + sy * (depth / 2 + 0.018), z), (0, sy, 0))
        for sx in (-1, 1):
            self.beam("IronTimberBandReturn", (x + sx * width / 2, y - depth / 2, z),
                      (x + sx * width / 2, y + depth / 2, z), 0.025, height, "metal", 0)

    def proxy(self, name, center, size):
        center, size = Vector(center), Vector(size)
        verts = [(sx * size.x / 2, sy * size.y / 2, sz * size.z / 2)
                 for sx, sy, sz in [(-1,-1,-1),(1,-1,-1),(1,1,-1),(-1,1,-1),(-1,-1,1),(1,-1,1),(1,1,1),(-1,1,1)]]
        data = bpy.data.meshes.new("collision_" + name)
        data.from_pydata(verts, [], [(0,3,2,1),(4,5,6,7),(0,1,5,4),(1,2,6,5),(2,3,7,6),(3,0,4,7)])
        obj = bpy.data.objects.new("collision_" + name, data)
        self.collision_collection.objects.link(obj)
        obj.parent = self.group
        obj.location = center
        obj.hide_render = True
        obj.display_type = "WIRE"
        obj["collision_only"] = True
        bpy.context.view_layer.update()
        world = obj.matrix_world.translation
        self.collisions.append({"name": obj.name, "asset": self.group.name, "shape": "box",
                                "center_godot": [world.x, world.z, -world.y],
                                "size_godot": [size.x, size.z, size.y],
                                "rotation_y": self.group.rotation_euler.z})

    def begin(self, kind, zone, position, rotation=0.0):
        self.counts[kind] += 1
        name = f"Mine_{zone}_{kind}_{self.counts[kind]:02d}"
        group = bpy.data.objects.new(name, None)
        self.collection.objects.link(group)
        group.location = (position[0], -position[1], self.ground_height_fn(*position) - 0.025)
        group.rotation_euler.z = rotation
        group["mine_prop_kind"] = kind
        group["zone_id"] = zone
        self.group, self.pieces = group, []
        self.assets.append({"name": name, "kind": kind, "zone": zone, "position_godot": [position[0], group.location.z, position[1]], "rotation_y": rotation})

    def finish(self):
        # Keep distinct material surfaces while consolidating bolts/planks into
        # a few draw calls. Joining affects only this new background scene.
        by_material = defaultdict(list)
        for obj in self.pieces:
            by_material[obj.data.materials[0].name].append(obj)
        for material_name, objects in by_material.items():
            bpy.ops.object.select_all(action="DESELECT")
            for obj in objects:
                obj.select_set(True)
            bpy.context.view_layer.objects.active = objects[0]
            if len(objects) > 1:
                bpy.ops.object.join()
            objects[0].name = self.group.name + "_" + material_name
            objects[0]["mine_prop_kind"] = self.group["mine_prop_kind"]
        self.group = None
        self.pieces = []

    def support(self, width=4.0, height=3.8):
        for side in (-1, 1):
            x = side * width / 2
            lean = side * self.rng.uniform(0.035, 0.085)
            self.beam("SunkHewnUpright", (x, 0, -0.16), (x + lean, 0.02, height), 0.32, 0.38)
            self.band((x, 0, 0.42), 0.35, 0.41)
            self.band((x + lean, 0.01, height - 0.38), 0.35, 0.41)
            self.beam("LoadBearingDiagonalBrace", (x - side * 1.10, 0.005, height - 0.10),
                      (x + lean * 0.6, 0, height - 1.13), 0.19, 0.23, wear=0.008)
            self.bolt((x - side * 0.91, -0.135, height - 0.25), (0, -1, 0), 0.026)
            self.bolt((x - side * 0.10, -0.14, height - 0.98), (0, -1, 0), 0.026)
            self.proxy("support_foot", (x, 0, height / 2), (0.44, 0.45, height))
        self.beam("SaggingCapTimber", (-width / 2 - 0.27, 0, height), (width / 2 + 0.30, 0, height - 0.035), 0.40, 0.43, wear=0.045)
        for side in (-1, 1):
            self.beam("PackingWedge", (side * width / 2 - 0.25, 0, height + 0.22),
                      (side * width / 2 + 0.20, 0, height + 0.27), 0.19, 0.14, wear=0.025)

    def rails(self, length=10.0, gauge=0.94):
        # Extruded historic rail profile: broad foot, narrow web, rounded head.
        profile = [(-.060,0),(.060,0),(.060,.020),(.014,.020),(.014,.095),(.039,.102),(.039,.127),(-.039,.127),(-.039,.102),(-.014,.095),(-.014,.020),(-.060,.020)]
        for side in (-1, 1):
            vertices = [(x + side * gauge / 2, y, z + 0.035) for y in (-length / 2, length / 2) for x, z in profile]
            n = len(profile)
            faces = [tuple(reversed(range(n))), tuple(n + i for i in range(n))]
            faces += [(i, (i+1)%n, (i+1)%n+n, i+n) for i in range(n)]
            self.mesh("CorrodedRailProfile", vertices, faces, "metal")
            for end in (-1, 1):
                self.beam("RailFishplate", (side * gauge / 2, end * (length / 2 - .55), .080),
                          (side * gauge / 2, end * (length / 2 - .07), .080), .052, .035, "metal", 0)
        sleepers = max(2, int(length / 0.78))
        for i in range(sleepers):
            y = -length / 2 + .2 + i * (length - .4) / (sleepers - 1)
            yaw = self.rng.uniform(-.065, .065)
            self.beam("BuriedRailSleeper", (-.82, y - yaw, -.0125), (.82, y + yaw, -.0125), .22, .135, wear=.032)
            for side in (-1, 1):
                for edge in (-1, 1):
                    self.bolt((side * gauge / 2 + edge * .076, y, .083), (0, 0, 1), .014)

    def crate(self, offset=(0,0,0), size=(1.05,.78,.82), open_top=False):
        x,y,z = offset
        w,d,h = size
        for sx in (-1,1):
            for sy in (-1,1):
                self.beam("CrateCornerPost", (x+sx*(w/2-.045),y+sy*(d/2-.045),z),
                          (x+sx*(w/2-.045),y+sy*(d/2-.045),z+h), .082,.082,wear=.007)
        for row in range(4):
            rz = z + .105 + row * (h-.13)/4
            for sy in (-1,1):
                self.beam("SplitCrateLongSlat", (x-w/2,y+sy*d/2,rz), (x+w/2,y+sy*d/2,rz+self.rng.uniform(-.013,.013)), .043,h/4-.018,wear=.012)
                for sx in (-1,1):
                    self.bolt((x+sx*(w/2-.10),y+sy*(d/2+.030),rz),(0,sy,0),.009)
            for sx in (-1,1):
                self.beam("CrateEndSlat", (x+sx*w/2,y-d/2,rz), (x+sx*w/2,y+d/2,rz), .043,h/4-.018,wear=.009)
        for i in range(5):
            yy = y - d/2 + .075 + i*(d-.15)/4
            self.beam("CrateBottomBoard", (x-w/2,yy,z+.055),(x+w/2,yy,z+.055),d/5-.006,.047,wear=.008)
            if not open_top and i != 1:
                self.beam("CrackedCrateLid", (x-w/2,yy,z+h),(x+w/2,yy,z+h+self.rng.uniform(-.015,.015)),d/5-.011,.052,wear=.022)
        self.beam("CrateDiagonalShippingBrace", (x-w/2+.05,y-d/2-.032,z+.08),(x+w/2-.05,y-d/2-.032,z+h-.09),.028,.081,wear=.006)
        self.proxy("crate", (x,y,z+h/2),(w,d,h))

    def barrel(self, offset=(0,0,0), scale=1.0):
        x,y,z = offset
        h, radius = 1.08*scale,.365*scale
        n = 18
        for stave in range(n):
            vertices=[]
            for ring in range(7):
                t=ring/6
                r=radius*(.86+.14*math.sin(math.pi*t))
                for inner in (False,True):
                    for edge in (-1,1):
                        a=TAU*(stave+0.5)/n+edge*(math.pi/n-.007)
                        rr=r-(.025*scale if inner else 0)
                        vertices.append((x+rr*math.cos(a),y+rr*math.sin(a),z+t*h))
            faces=[]
            for ring in range(6):
                for a,b in [(0,1),(1,3),(3,2),(2,0)]:
                    faces.append((ring*4+a,ring*4+b,(ring+1)*4+b,(ring+1)*4+a))
            faces += [(0,2,3,1),(24,25,27,26)]
            self.mesh("CurvedOakBarrelStave",vertices,faces,"wood")
        for t in (.12,.47,.88):
            r=radius*(.86+.14*math.sin(math.pi*t))+.012
            for dz in (-.030,.030):
                self.hoop("RivetedBarrelHoop",(x,y,z+t*h+dz),r,.018*scale)
            for a in (0,math.pi):
                self.bolt((x+r*math.cos(a),y+r*math.sin(a),z+t*h),(math.cos(a),math.sin(a),0),.014)
        cap_radius=radius*.84
        for strip in range(5):
            yy=-cap_radius+(strip+.5)*(2*cap_radius/5)
            span=math.sqrt(max(.01,cap_radius**2-yy**2))
            self.beam("BarrelHeadPlank",(x-span,y+yy,z+h-.02),(x+span,y+yy,z+h-.02),2*cap_radius/5-.008,.036,wear=.004)
        self.proxy("barrel",(x,y,z+h/2),(radius*1.9,radius*1.9,h))

    def wheel(self, center, radius=.29):
        self.hoop("IronMineWheelRim",center,radius,.044,"X",steps=32)
        self.disc("MineWheelHub",center,.082,.14,(1,0,0),sides=16)
        x,y,z=center
        for i in range(8):
            a=TAU*i/8
            self.beam("WheelRadialSpoke",(x,y+.063*math.cos(a),z+.063*math.sin(a)),
                      (x,y+(radius-.022)*math.cos(a),z+(radius-.022)*math.sin(a)),.036,.042,"metal",0)

    def cart(self, tipped=True):
        # Complete running gear remains visible below the flared ore hopper.
        for yy in (-.69,.69):
            self.disc("ForgedCartAxle",(0,yy,.29),.049,1.55,(1,0,0),sides=16)
            for xx in (-.66,.66):
                self.wheel((xx,yy,.29))
        for xx in (-.46,.46):
            self.beam("CartUndercarriage",(xx,-1.05,.42),(xx,1.05,.42),.15,.16,"metal",0.002)
        for i in range(7):
            yy=-.93+i*.31
            self.beam("OreCartFloorBoard",(-.48,yy,.50),(.48,yy,.50),.30,.078,wear=.014)
        for row in range(4):
            zz=.64+row*.235
            halfw=.50+row*.074
            for side in (-1,1):
                self.beam("FlaredCartSidePlank",(side*halfw,-1.03,zz),(side*halfw,1.03,zz+.015),.076,.216,wear=.025)
                for yy in (-.9,.9):
                    self.bolt((side*(halfw+.046),yy,zz),(side,0,0),.018)
            for sy in (-1,1):
                self.beam("CartEndPlank",(-halfw,sy*1.04,zz),(halfw,sy*1.04,zz),.075,.216,wear=.018)
        for side in (-1,1):
            for yy in (-.77,.77):
                self.beam("HopperIronCornerStrap",(side*.51,yy,.50),(side*.775,yy,1.47),.095,.024,"metal",0)
        self.hoop("TowRing",(0,-1.26,.43),.14,.023,"Y",steps=24)
        for i in range(12):
            self.ore((self.rng.uniform(-.48,.48),self.rng.uniform(-.75,.75),self.rng.uniform(.57,.82)),self.rng.uniform(.12,.26))
        if tipped:
            # Tip the entire coherent vehicle around one wheel contact line.
            bpy.context.view_layer.update()
            angle=.36
            for obj in list(self.pieces):
                from mathutils import Matrix
                transform=Matrix.Translation((.57,0,.04)) @ Matrix.Rotation(angle,4,"Y") @ Matrix.Translation((-.57,0,-.04))
                obj.matrix_local=transform @ obj.matrix_local
            for i in range(20):
                self.ore((self.rng.uniform(.75,1.9),self.rng.uniform(-.8,.9),.055),self.rng.uniform(.07,.20))
        self.proxy("ore_cart",(.10,0,.70),(1.65,2.25,1.42))

    def ore(self, center, radius):
        bm=bmesh.new()
        bmesh.ops.create_icosphere(bm,subdivisions=1,radius=radius)
        for vert in bm.verts:
            vert.co *= self.rng.uniform(.75,1.2)
            vert.co.z *= self.rng.uniform(.6,1.0)
        bm.verts.ensure_lookup_table()
        bm.verts.index_update()
        verts=[tuple(v.co+Vector(center)) for v in bm.verts]
        faces=[tuple(v.index for v in face.verts) for face in bm.faces]
        bm.free()
        self.mesh("SpilledAngularOre",verts,faces,"rock_dark")

    def rope_coil(self, center=(0,0,.05), radius=.26, turns=4):
        cx,cy,cz=center
        points=[]
        for i in range(turns*40+1):
            t=i/40
            a=TAU*t
            r=radius+.016*t
            points.append((cx+r*math.cos(a),cy+r*math.sin(a),cz+.019*t))
        self.tube("CoiledHempRope",points,.022,"rope",sides=8)
        self.tube("FrayedCoilTail",[(cx+radius+.016*turns,cy,cz+.019*turns),(cx+radius+.32,cy-.15,cz+.022),(cx+radius+.58,cy-.21,cz+.01)],.018,"rope",8)

    def winch(self):
        for xx in (-1.20,1.20):
            for yy in (-.77,.77):
                self.beam("HoistScaffoldUpright",(xx,yy,-.10),(xx+.035,yy,3.85),.27,.31,wear=.026)
                self.band((xx,yy,.28),.30,.34)
                self.proxy("winch_post",(xx,yy,1.85),(.40,.43,3.85))
            self.beam("HoistCrossTie",(xx,-.95,3.79),(xx,.95,3.79),.34,.31,wear=.023)
            self.beam("ScaffoldDiagonal",(xx,-.75,.52),(xx,.75,3.65),.15,.18,wear=.012)
        self.beam("MainPulleyBeam",(-1.44,0,3.90),(1.44,0,3.90),.40,.36,wear=.032)
        for xx in (-1.20,1.20):
            self.beam("DrumBearingSupport",(xx,-.78,1.55),(xx,.78,1.55),.23,.26,wear=.012)
        self.disc("WindingDrumOakCore",(0,0,1.78),.265,1.70,(1,0,0),"wood",32)
        self.proxy("winch_drum",(0,0,1.78),(1.92,.76,.76))
        self.disc("WinchThroughAxle",(0,0,1.78),.06,3.15,(1,0,0),"metal",20)
        for xx in (-.88,.88):
            self.disc("WindingDrumFlange",(xx,0,1.78),.37,.07,(1,0,0),sides=40)
        rope=[]
        for i in range(520):
            t=i/519
            a=t*TAU*22
            rope.append((-0.79+1.58*t,.292*math.cos(a),1.78+.292*math.sin(a)))
        self.tube("DrumWoundHemp",rope,.028,"rope",6)
        self.hoop("HandCrankWheel",(1.52,0,1.78),.49,.037,"X",steps=40)
        for i in range(6):
            a=TAU*i/6
            self.beam("CrankWheelSpoke",(1.52,0,1.78),(1.52,.47*math.cos(a),1.78+.47*math.sin(a)),.036,.048,"metal",0)
        self.disc("HandWornCrankGrip",(1.68,.40,2.04),.042,.28,(1,0,0),"wood",14)
        self.hoop("UpperGroovedPulley",(0,0,3.51),.235,.048,"X",steps=40)
        self.disc("PulleySpindle",(0,0,3.51),.035,.25,(1,0,0),sides=14)
        for xx in (-.15,.15):
            self.beam("PulleyHanger",(xx,0,3.90),(xx,0,3.49),.060,.025,"metal",0)
        self.tube("WorkingHoistRope",[(.30,.22,1.93),(.03,.24,3.44),(0,.19,3.68),(0,-.16,3.70),(0,-.24,3.49),(0,-.24,.47)],.024,"rope",10)
        self.hoop("HoistLoadHook",(0,-.24,.33),.11,.026,"Y",steps=24)
        self.rope_coil((-.55,-1.10,.04),.27)

    def bridge(self, length, width):
        for xx in (-width*.36,width*.36):
            self.beam("BridgeLongitudinalStringer",(xx,-length/2,-.18),(xx,length/2,-.12),.28,.31,wear=.050)
        count=max(6,int(length/.31))
        for i in range(count):
            yy=-length/2+(i+.5)*length/count
            shorten=.40 if i in (3,count-5) else self.rng.uniform(0,.10)
            ends=(-width/2+shorten,width/2-self.rng.uniform(0,.08))
            zz=self.rng.uniform(-.018,.018)
            self.beam("UnevenBridgeDeckBoard",(ends[0],yy,zz),(ends[1],yy+self.rng.uniform(-.03,.03),zz),length/count-.018,.12,wear=.030)
            self.proxy("bridge_deck_board",((ends[0]+ends[1])/2,yy,zz-.012),(ends[1]-ends[0],length/count-.018,.10))
            for xx in (-width*.36,width*.36):
                self.bolt((xx,yy,zz+.065),(0,0,1),.012)
        for side in (-1,1):
            xx=side*(width/2-.07)
            posts=[]
            for i in range(5):
                yy=-length/2+i*length/4
                broken=side==1 and i==2
                h=.40 if broken else 1.00+self.rng.uniform(-.05,.05)
                self.beam("BrokenBridgeRailPost" if broken else "BridgeRailPost",(xx,yy,-.18),(xx+side*.035,yy,h),.12,.14,wear=.025)
                posts.append((xx+side*.035,yy,h))
            for i in range(4):
                if side==1 and i in (1,2):
                    continue
                self.beam("WornBridgeHandrail",posts[i],posts[i+1],.09,.10,wear=.035)

    def pickaxe(self, offset=(0,0,0)):
        x,y,z=offset
        self.tube("PickaxeAshHandle",[(x,y,z+.03),(x+.018,y+.018,z+.56),(x+.025,y,z+1.11)],[.027,.029,.024],"wood",12)
        self.tube("CurvedForgedPickHead",[(x-.53,y,z+.97),(x-.36,y,z+1.11),(x-.12,y,z+1.17),(x+.12,y,z+1.17),(x+.34,y,z+1.08),(x+.46,y,z+.93)], [.007,.031,.055,.052,.028,.007],"metal",8)
        self.disc("PickHeadEye",(x+.018,y,z+1.15),.065,.11,(0,0,1),"metal",12)

    def shovel(self, offset=(0,0,0)):
        x,y,z=offset
        self.tube("ShovelWoodShaft",[(x,y,z+.27),(x,y-.015,z+1.18)],[.025,.022],"wood",12)
        vertices=[]
        for row in range(7):
            t=row/6
            half=.115*math.sin(math.pi*(.10+.85*t))+.035
            for col in range(7):
                s=col/3-1
                vertices.append((x+s*half,y+.052*(1-s*s)*math.sin(t*math.pi),z+.34-t*.32))
        faces=[(r*7+c,r*7+c+1,(r+1)*7+c+1,(r+1)*7+c) for r in range(6) for c in range(6)]
        self.mesh("DishedWornShovelBlade",vertices,faces,"metal",smooth=True)
        self.hoop("ShovelDGrip",(x,y-.015,z+1.27),.088,.018,"Y","wood",24)

    def lantern(self, offset=(0,0,0), lit=False):
        x,y,z=offset
        self.disc("LanternOilReservoir",(x,y,z+.06),.115,.11,(0,0,1),"metal",20)
        self.disc("LanternSmokeCap",(x,y,z+.39),.12,.035,(0,0,1),"metal",20)
        for i in range(4):
            a=TAU*(i+.5)/4
            xx,yy=x+.092*math.cos(a),y+.092*math.sin(a)
            self.tube("LanternProtectiveCage",[(xx,yy,z+.09),(xx,yy,z+.36)],.008,"metal",6)
        if not lit:
            self.disc("SmokedLanternGlass",(x,y,z+.235),.071,.255,(0,0,1),"glass",16)
        else:
            # Broken/open panes leave the actual point light unobstructed.
            # The surviving cage and rain cap still identify an oil lantern.
            self.hoop("LanternMidCageRing",(x,y,z+.26),.092,.006,"Z","metal",20)
            self.tube("BentOilFlame",[(x,y,z+.132),(x+.004,y,z+.164),(x-.002,y+.002,z+.205),(x+.007,y,z+.234)],
                      [.005,.018,.010,.0008],"flame",10)
        self.disc("UnlitOilWick",(x,y,z+.13),.012,.04,(0,0,1),"wick",10)
        self.hoop("LanternCarryHandle",(x,y,z+.47),.088,.009,"Y","metal",24)

    def workbench(self):
        for xx in (-.95,.95):
            for yy in (-.34,.34):
                self.beam("WorkbenchLeg",(xx,yy,-.03),(xx*.97,yy,.84),.12,.15,wear=.012)
        for i in range(5):
            yy=-.37+i*.185
            self.beam("WorkbenchScarredTop",(-1.13,yy,.86),(1.13,yy,.86),.174,.085,wear=.018)
        for xx in (-.95,.95):
            self.beam("BenchLegTie",(xx,-.36,.24),(xx,.36,.24),.09,.11,wear=.006)
        self.beam("BenchLongStretcher",(-.96,0,.22),(.96,0,.22),.10,.13,wear=.010)
        self.proxy("workbench",(0,0,.45),(2.23,.89,.92))
        # Small dismantled vice, an identifiable screw and sliding jaw.
        self.beam("ForgedBenchViceBody",(-.82,-.26,.965),(-.32,-.26,.965),.18,.14,"metal",0)
        for xx in (-.74,-.36):
            self.beam("ViceJaw",(xx,-.36,1.03),(xx,-.14,1.03),.058,.11,"metal",0)
        self.disc("ViceScrew",(-.93,-.26,.965),.022,.54,(1,0,0),"metal",12)
        self.disc("ViceCrossHandle",(-1.16,-.26,.965),.012,.28,(0,0,1),"metal",10)
        self.lantern((.72,.19,.91))
        self.rope_coil((.38,-.10,.92),.14,3)

    def cloth(self, offset=(0,0,0), width=1.45, height=1.40):
        x,y,z=offset
        cols,rows=16,18
        verts=[]
        for r in range(rows+1):
            t=r/rows
            for c in range(cols+1):
                s=c/cols
                zz=z-t*height
                if r==rows:
                    zz+=.12+.085*math.sin(c*1.83)+self.rng.uniform(-.06,.04)
                verts.append((x+(s-.5)*width,y+.035*math.sin(s*TAU*4+t*2)+.075*t*t,zz))
        faces=[]
        for r in range(rows):
            for c in range(cols):
                if (r>14 and c in (2,3,11)) or (r in (10,11) and c==13):
                    continue
                a=r*(cols+1)+c
                faces.append((a,a+1,a+cols+2,a+cols+1))
        self.mesh("TornFoldedWorkCanvas",verts,faces,"cloth",smooth=True)

    def can_place(self, point, radius):
        if self.clearance_fn is not None and not self.clearance_fn(point[0],point[1],radius):
            return False
        if any((Vector(point)-Vector(other)).length < radius+other_radius+.25 for other,other_radius in self.occupied):
            return False
        if self.clearance_fn is None:
            for sample in [(point[0]+math.cos(TAU*i/8)*radius,point[1]+math.sin(TAU*i/8)*radius) for i in range(8)]:
                if not any(_point_inside(sample,room["polygon"]) for room in self.rooms.values()):
                    return False
            for corridor in self.layout.get("corridors",[]):
                if any(_segment_distance(point,a,b)<radius+corridor["width"]*.37 for a,b in zip(corridor["points"],corridor["points"][1:])):
                    return False
            for island in self.layout.get("islands",[])+self.layout.get("pools",[]):
                if _point_inside(point,island["polygon"]):
                    return False
            for room in self.rooms.values():
                if (Vector(point)-Vector(room["center"])).length<radius+2.2:
                    return False
        return True

    def place(self, room_id, kind, radius, callback, preferred_angle=0.0, landmark_type=None):
        room=self.rooms.get(room_id)
        if room is None:
            return
        center=room["center"]
        polygon=room["polygon"]
        xs,zs=[p[0] for p in polygon],[p[1] for p in polygon]
        rx,rz=(max(xs)-min(xs))*.5,(max(zs)-min(zs))*.5
        landmark=None
        if landmark_type:
            landmark=next((item for item in self.layout.get("landmarks",[]) if item["room_id"]==room_id and item["type"]==landmark_type and item["id"] not in self.used_landmarks),None)
        if landmark:
            pos=landmark["position"]
            point=(pos[0],pos[2])
            if self.can_place(point,radius):
                self.occupied.append((point,radius))
                self.begin(kind,room_id,point,float(landmark.get("rotation_y",0)))
                self.assets[-1]["landmark_id"]=landmark["id"]
                self.used_landmarks.add(landmark["id"])
                callback()
                self.finish()
                return
        for i in range(36):
            angle=preferred_angle+i*2.399963
            factor=.57+(i%3)*.09
            point=(center[0]+math.cos(angle)*max(radius,rx*factor),center[1]+math.sin(angle)*max(radius,rz*factor))
            if not self.can_place(point,radius):
                continue
            self.occupied.append((point,radius))
            self.begin(kind,room_id,point,math.atan2(center[0]-point[0],-(center[1]-point[1])))
            if landmark:
                self.assets[-1]["landmark_id"]=landmark["id"]
                self.assets[-1]["placement_adjustment"]="Shifted to a clear edge of the same authored work area"
                self.used_landmarks.add(landmark["id"])
            callback()
            self.finish()
            return
        self.skipped.append({"kind":kind,"zone":room_id,"reason":"No collision-free edge placement remained"})


def build_props(layout: dict, materials: dict, collection, clearance_fn=None, ground_height_fn=None) -> dict:
    required={"rock","rock_dark","ground","wood","metal"}
    missing=required-set(materials)
    if missing:
        raise ValueError("Missing scan materials: "+", ".join(sorted(missing)))
    props=Props(layout,materials,collection,clearance_fn,ground_height_fn)
    # Distinct working areas tell the history of the mine without filling every
    # chamber with identical decoration or occupying the combat floor.
    props.place("hoistroom","manual_hoist",2.2,props.winch,.1,"mine_hoist")
    props.place("grand_quarry","overturned_ore_cart",2.0,lambda:props.cart(True),2.9)
    props.place("north_workings","ore_cart",1.65,lambda:props.cart(False),.4)
    props.place("workshops","workbench",1.6,props.workbench,1.5,"workshop")
    props.place("workshops","workbench",1.6,props.workbench,4.5,"workshop")
    props.place("foreman_workroom","foreman_bench",1.6,props.workbench,3.2,"workshop")
    for room_id,angle in [("entrance",2.6),("east_store",.2),("east_store",2.5),("foreman_workroom",.6),("north_workings",4.1)]:
        def crates():
            props.crate((-.52,0,0),(.95,.77,.77))
            props.crate((.48,.19,0),(.85,.70,.64),True)
            if props.rng.random()>.45:
                props.crate((-.52,0,.79),(.78,.65,.60))
            props.lantern((.41,-.25,.67))
        props.place(room_id,"abandoned_crate_stack",1.30,crates,angle,"ore_store" if room_id=="east_store" else None)
    for room_id,angle in [("east_store",4.3),("foreman_workroom",2.0),("workshops",3.8),("southwest_adit",.4)]:
        def barrels():
            props.barrel((-.38,0,0),1.0)
            props.barrel((.40,.17,0),.87)
            props.rope_coil((.27,-.71,.02),.20)
        props.place(room_id,"barrels_and_rope",1.2,barrels,angle)
    for room_id,angle in [("north_workings",1.4),("workshops",.7),("entrance",5.2),("rubble_passage",2.6)]:
        def tools():
            props.pickaxe((-.28,0,0))
            props.shovel((.35,.04,0))
            props.lantern((.02,-.25,0))
            props.rope_coil((-.15,.40,.03),.18,3)
        props.place(room_id,"abandoned_hand_tools",.82,tools,angle)
    def hanging_canvas():
        props.beam("CanvasRackUpright",(-.78,0,-.08),(-.76,0,1.92),.10,.13,wear=.015)
        props.beam("CanvasRackUpright",(.78,0,-.08),(.79,0,1.94),.10,.13,wear=.015)
        props.beam("CanvasDryingRail",(-.89,0,1.90),(.91,0,1.93),.11,.10,wear=.020)
        props.cloth((0,-.035,1.87))
    props.place("east_store","torn_canvas_rack",1.1,hanging_canvas,5.6)

    # A limited set of genuinely mined connections receives frames. Their feet
    # sit beside the path, never a blocking beam at walking height.
    mine_zones={"entrance","north_workings","foreman_workroom","workshops","east_store","hoistroom","grand_quarry"}
    support_count=0
    for corridor in layout.get("corridors",[]):
        if not ({corridor["from"],corridor["to"]}&mine_zones):
            continue
        points=corridor["points"]
        a,b=Vector(points[0]),Vector(points[1])
        if (b-a).length<3.0 or support_count>=15:
            continue
        p=a.lerp(b,.58)
        direction=(b-a).normalized()
        side=Vector((-direction.y,direction.x))
        width=max(2.5,min(4.6,corridor["width"]-.45))
        feet=[p+side*width*.5,p-side*width*.5]
        if clearance_fn and not all(clearance_fn(foot.x,foot.y,.24) for foot in feet):
            continue
        props.begin("timber_support",corridor["from"],(p.x,p.y),math.atan2(-side.y,side.x))
        props.support(width,min(3.9,props.rooms[corridor["from"]]["height"]-.55))
        props.finish()
        support_count+=1

    used_rail_segments=set()
    for room_id in ("north_workings","grand_quarry","workshops"):
        for corridor in layout.get("corridors",[]):
            if room_id not in (corridor["from"],corridor["to"]):
                continue
            eligible=[]
            for index,(a,b) in enumerate(zip(corridor["points"],corridor["points"][1:])):
                length=(Vector(b)-Vector(a)).length
                key=(corridor["id"],index)
                if length>=6 and key not in used_rail_segments:
                    eligible.append((length,index,a,b,key))
            if not eligible:
                continue
            length,index,a,b,key=max(eligible,key=lambda part:part[0])
            direction=(Vector(b)-Vector(a)).normalized()
            p=Vector(a).lerp(Vector(b),.5)
            props.begin("short_disused_rail",room_id,(p.x,p.y),math.atan2(-direction.y,direction.x)-math.pi/2)
            props.rails(min(9.0,length-.7))
            props.finish()
            used_rail_segments.add(key)
            break
    for bridge in layout.get("bridges",[]):
        pos=bridge["position"]
        props.begin("weathered_footbridge",bridge["room_id"],(pos[0],pos[2]),bridge.get("rotation_y",0))
        # Authored bridge height is deck top, not plank centre. Keep the top
        # (including uneven-board variation) within a 5.5 cm dry-bank step.
        props.group.location.z=min(float(pos[1]),.055)-.078
        props.bridge(bridge["length"],bridge["width"])
        props.finish()
    bpy.ops.object.select_all(action="DESELECT")
    return {"schema_version":1,"coordinate_system":"Godot x,y,z metres; Blender x,-z,y",
            "assets":props.assets,"collision_proxies":props.collisions,"counts":dict(props.counts),
            "skipped":props.skipped,"uv_metres_per_unit":1.0,
            "notes":["Scan materials supplied by the parent shell builder.",
                     "collision_* meshes are hidden from renders and exported separately as box metadata.",
                     "Low rails are nonblocking dressing. Timber support feet stay outside the walk route."]}


def add_light_fixtures(layout: dict, materials: dict, collection, light_markers: list, ground_height_fn=None) -> dict:
    """Attach visibly supported expedition oil lamps to authoritative lights.

    Each marker's position[x,y,z] is its wick/flame centre. No lights are added
    here: the parent owns their energies, colors, and runtime state. Open cage
    lamps avoid enclosing the light inside opaque exported glass.
    """
    props=Props(layout,materials,collection,None,ground_height_fn)
    for index,marker in enumerate(light_markers):
        pos=marker["position"]
        zone=str(marker.get("room_id",marker.get("zone","gallery")))
        props.begin("supported_oil_lantern",zone,(pos[0],pos[2]),float(marker.get("rotation_y",index*2.399963)))
        # begin() sinks standing props 2.5 cm; account for that when matching an
        # exact light coordinate supplied by the gameplay/export manifest.
        wick_height=float(pos[1])-props.group.location.z
        base=wick_height-.176
        props.lantern((0,0,base),lit=True)
        top=base+.57
        props.beam("HandHewnLampStake",(.27,.13,-.13),(.26,.12,top+.10),.105,.135,wear=.018)
        props.beam("LanternBracketCap",(.26,.12,top+.07),(-.025,-.01,top+.055),.10,.085,wear=.006)
        props.tube("ForgedLanternHangingHook",[(.09,.045,top+.055),(.018,.008,top+.022),(0,0,base+.53),(-.023,0,base+.54)],.009,"metal",8)
        props.band((.26,.12,max(.30,top-.34)),.12,.15,.058)
        props.disc("StakeGroundFerrule",(.27,.13,.012),.105,.085,(0,0,1),"metal",10)
        props.proxy("lantern_stake",(.27,.13,top*.5),(.15,.17,top+.12))
        props.assets[-1]["light_marker_id"]=str(marker.get("id",index))
        props.assets[-1]["wick_godot"]=[float(pos[0]),float(pos[1]),float(pos[2])]
        props.finish()
    bpy.ops.object.select_all(action="DESELECT")
    return {"assets":props.assets,"collision_proxies":props.collisions,"counts":dict(props.counts),
            "notes":["Open-sided cages prevent the authored light from being occluded by opaque panes.",
                     "Each lamp wick is aligned to its supplied gameplay light marker."]}


def _masonry_block(props, name, center, size, material="rock", erosion=.025):
    """Worn ashlar: separate chamfer topology and chipped, uneven corners."""
    bm=bmesh.new()
    bmesh.ops.create_cube(bm,size=1)
    for vertex in bm.verts:
        vertex.co=Vector(tuple(vertex.co[i]*size[i] for i in range(3)))
        vertex.co += Vector(tuple(props.rng.uniform(-erosion,erosion) for _ in range(3)))
    bmesh.ops.bevel(bm,geom=list(bm.edges),offset=min(size)*.055,
                    segments=2,affect="EDGES")
    bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces))
    bm.verts.ensure_lookup_table()
    bm.verts.index_update()
    vertices=[tuple(v.co+Vector(center)) for v in bm.verts]
    faces=[tuple(v.index for v in face.verts) for face in bm.faces]
    bm.free()
    return props.mesh(name,vertices,faces,material)


def _carved_drape(props):
    # A continuous fluted cloak, shoulders and deep open cowl form a worn
    # miner effigy. The cowl really has an opening, not a dark painted sphere.
    vertices,faces=[],[]
    profile=[(.73,.52,.38),(.92,.48,.36),(1.18,.43,.32),
             (1.48,.39,.30),(1.76,.49,.32),(1.95,.34,.26),(2.05,.22,.22)]
    sides=32
    for ring,(z,rx,ry) in enumerate(profile):
        for j in range(sides):
            a=TAU*j/sides
            folds=1+.055*math.cos(a*9+ring*.14)+.027*math.sin(a*5-ring*.35)
            vertices.append((rx*math.cos(a)*folds,ry*math.sin(a)*folds,z))
    for i in range(len(profile)-1):
        for j in range(sides):
            faces.append((i*sides+j,i*sides+(j+1)%sides,(i+1)*sides+(j+1)%sides,(i+1)*sides+j))
    faces.extend([tuple(reversed(range(sides))),tuple((len(profile)-1)*sides+j for j in range(sides))])
    props.mesh("WeatheredMinerCloak",vertices,faces,"rock",smooth=True)
    # Hood: front lip and domed rear, elliptical rings left open at the face.
    verts,faces=[],[]
    hood=[(-.265,.255,.335),(-.12,.30,.365),(.07,.285,.34),(.22,.14,.24),(.26,.025,.10)]
    for y,rx,rz in hood:
        for j in range(32):
            a=TAU*j/32
            verts.append((rx*math.cos(a),y,2.16+rz*math.sin(a)))
    for i in range(len(hood)-1):
        for j in range(32):
            faces.append((i*32+j,i*32+(j+1)%32,(i+1)*32+(j+1)%32,(i+1)*32+j))
    # Inward lip has an inset, recessed facial plane.
    for j in range(32):
        a=TAU*j/32
        verts.append((.193*math.cos(a),-.195,2.16+.275*math.sin(a)))
    inner=(len(hood))*32
    for j in range(32):
        faces.append((j,inner+j,inner+(j+1)%32,(j+1)%32))
    faces.append(tuple(reversed([inner+j for j in range(32)])))
    props.mesh("ErodedOpenHood",verts,faces,"rock",smooth=True)
    props.tube("CarvedLeftSleeve",[(-.38,-.06,1.79),(-.39,-.30,1.57),(-.18,-.46,1.52)], [.15,.135,.095],"rock",16)
    props.tube("CarvedRightSleeve",[(.38,-.06,1.79),(.39,-.30,1.57),(.18,-.46,1.52)], [.15,.135,.095],"rock",16)
    # The old shrine lamp has a reservoir, vented roof and bowed handle.
    props.lantern((0,-.47,1.32),lit=False)


def add_stone_architecture(layout: dict, materials: dict, collection,
                           clearance_fn=None, ground_height_fn=None) -> dict:
    """Place the map's masonry pillars, west altar and north miners' shrine.

    Structural landmarks retain their coordinates wherever clearance allows;
    any small adjustment or impossible placement is explicitly reported.
    Collision boxes match the load-bearing cores and low foundations.
    """
    props=Props(layout,materials,collection,clearance_fn,ground_height_fn)
    relevant={"stone_pillar","ruined_altar","ruined_shrine"}
    for marker in layout.get("landmarks",[]):
        kind=marker.get("type")
        if kind not in relevant:
            continue
        pos=marker["position"]
        point=(float(pos[0]),float(pos[2]))
        radius=.68 if kind=="stone_pillar" else 1.05
        chosen=None
        candidates=[point]
        for distance in (.50,1.0,1.5):
            candidates.extend((point[0]+distance*math.cos(a*TAU/12),point[1]+distance*math.sin(a*TAU/12)) for a in range(12))
        for candidate in candidates:
            if clearance_fn is None or clearance_fn(*candidate,radius):
                chosen=candidate
                break
        if chosen is None:
            props.skipped.append({"landmark_id":marker["id"],"type":kind,"reason":"No clear structural footprint within 1.5m of the authored landmark."})
            continue
        props.begin(kind,marker["room_id"],chosen,float(marker.get("rotation_y",0)))
        props.group["landmark_id"]=marker["id"]
        props.assets[-1]["landmark_id"]=marker["id"]
        if chosen!=point:
            props.assets[-1]["placement_adjustment"]={"authored_godot":[point[0],0,point[1]],"offset_metres":math.dist(chosen,point)}
        if kind=="stone_pillar":
            height=float(marker.get("height",6.4))
            shrine=marker["room_id"]=="pillar_shrine"
            _masonry_block(props,"SunkenPierFoundation",(0,0,.13),(1.34,1.34,.36),erosion=.04)
            _masonry_block(props,"WeatheredPierPlinth",(0,0,.38),(1.15,1.15,.20))
            if shrine:
                # Stone drums retain broad eroded flutes and real joints.
                number=11
                step=(height-.98)/number
                for course in range(number):
                    z=.49+course*step
                    verts,faces=[],[]
                    for ring in range(3):
                        for j in range(32):
                            a=TAU*j/32
                            r=.435+.013*math.cos(8*a+course*.11)-.008*ring
                            if ring==1:r+=.006
                            verts.append((r*math.cos(a),r*math.sin(a),z+ring*(step-.017)/2))
                    for ring in range(2):
                        for j in range(32):
                            faces.append((ring*32+j,ring*32+(j+1)%32,(ring+1)*32+(j+1)%32,(ring+1)*32+j))
                    faces.extend([tuple(reversed(range(32))),tuple(64+j for j in range(32))])
                    props.mesh("CarvedLimestoneColumnDrum",verts,faces,"rock")
                    props.disc("DarkColumnJoint",(0,0,z-.007),.408,.022,material="rock_dark",sides=24)
                props.disc("ErodedCapitalNeck",(0,0,height-.39),.52,.22,material="rock",sides=16)
            else:
                number=11
                step=(height-.93)/number
                # Alternating bond courses around a solid rubble/mortar core.
                _masonry_block(props,"RubblePierCore",(0,0,height/2),(.81,.81,height-.16),"rock_dark",.01)
                for course in range(number):
                    z=.49+course*step+step/2
                    for half in (-1,1):
                        center=(half*.235,0,z) if course%2==0 else (0,half*.235,z)
                        size=(.455,.95,step-.018) if course%2==0 else (.95,.455,step-.018)
                        _masonry_block(props,"AlternatingAshlarCourse",center,size,erosion=.012)
            _masonry_block(props,"ChamferedStoneCapital",(0,0,height-.13),(1.22,1.22,.30),erosion=.045)
            props.proxy("stone_pillar_core",(0,0,height/2),(.97,.97,height))
            props.proxy("stone_pillar_foundation",(0,0,.22),(1.32,1.32,.48))
        elif kind=="ruined_altar":
            _masonry_block(props,"AbandonedAltarFoundation",(0,0,.12),(2.0,1.32,.30),erosion=.055)
            for x in (-.65,.65):
                _masonry_block(props,"AltarPier",(x,0,.57),(.46,.92,.63),erosion=.035)
            _masonry_block(props,"ChippedOfferingSlab",(0,0,.95),(2.13,1.33,.23),erosion=.06)
            props.disc("TarnishedOfferingDish",(-.24,-.07,1.10),.22,.028,material="metal",sides=32)
            props.hoop("OfferingDishRolledRim",(-.24,-.07,1.116),.225,.017,steps=32)
            props.lantern((.68,.13,1.076),lit=False)
            props.proxy("abandoned_stone_altar",(0,0,.54),(2.10,1.32,1.07))
        else:
            _masonry_block(props,"ShrineBuriedFoundation",(0,0,.11),(1.76,1.36,.30),erosion=.045)
            _masonry_block(props,"MinersEffigyPedestal",(0,0,.41),(1.33,1.03,.40),erosion=.032)
            _masonry_block(props,"EffigyPedestalCornice",(0,0,.67),(1.52,1.20,.15),erosion=.04)
            _carved_drape(props)
            props.proxy("shrine_pedestal",(0,0,.36),(1.76,1.36,.74))
            props.proxy("shrine_effigy",(0,0,1.62),(1.03,.97,1.85))
        props.finish()
    bpy.ops.object.select_all(action="DESELECT")
    return {"assets":props.assets,"collision_proxies":props.collisions,
            "counts":dict(props.counts),"skipped":props.skipped,
            "notes":["Masonry uses the same metre-mapped scanned stone as the cave.",
                     "Authored structural positions are preserved unless a reported local clearance adjustment is necessary."]}
