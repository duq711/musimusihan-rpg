"""Organic, authored partial giant-beast remains; Blender background only.

Public API: build_monster_remains(layout, materials, collection,
                                 clearance_fn=None, ground_height_fn=None) -> JSON metadata.
One unit is a metre. Landmark positions are Godot X/Y/Z; assembly geometry is
Blender X/length-Y/up-Z. There are no UI, network or external asset operations.
"""
from __future__ import annotations

import math
import random
from pathlib import Path

import bpy
import bmesh
from mathutils import Vector


class BoneMesh:
    """Watertight tapered tubes and organically perturbed ellipsoidal masses."""
    def __init__(self):
        self.vertices = []
        self.faces = []
        self.part_counts = {}

    def add(self, vertices, faces, kind):
        offset = len(self.vertices)
        self.vertices.extend(vertices)
        self.faces.extend(tuple(offset + i for i in face) for face in faces)
        self.part_counts[kind] = self.part_counts.get(kind, 0) + 1

    def ellipsoid(self, center, size, kind="vertebral_body", rings=10, sides=16, phase=0):
        center = Vector(center)
        vertices, faces = [], []
        for i in range(rings + 1):
            phi = math.pi * i / rings
            # Tiny polar rings avoid degenerate poles and give worn rounded ends.
            sp = max(.018, math.sin(phi))
            for j in range(sides):
                a = math.tau * j / sides
                irregular = 1 + .035 * math.sin(a * 3 + phi * 4 + phase)
                v = Vector((size[0] * sp * math.cos(a) * irregular,
                            size[1] * sp * math.sin(a) * irregular,
                            size[2] * math.cos(phi)))
                vertices.append(center + v)
        for i in range(rings):
            for j in range(sides):
                faces.append((i*sides+j,i*sides+(j+1)%sides,
                              (i+1)*sides+(j+1)%sides,(i+1)*sides+j))
        faces.extend([tuple(reversed(range(sides))),tuple(rings*sides+j for j in range(sides))])
        self.add(vertices, faces, kind)

    def tube(self, points, radii, kind, sides=12, flatness=1.0, broken=False):
        points = [Vector(p) for p in points]
        vertices, faces = [], []
        previous_axis = None
        for i, p in enumerate(points):
            tangent = points[min(i+1,len(points)-1)] - points[max(i-1,0)]
            tangent.normalize()
            axis = tangent.cross(Vector((0,1,0)))
            if axis.length < .03:
                axis = tangent.cross(Vector((1,0,0)))
            axis.normalize()
            if previous_axis is not None and axis.dot(previous_axis) < 0:
                axis.negate()
            previous_axis = axis
            other = tangent.cross(axis).normalized()
            radius = radii[i] if isinstance(radii,list) else radii
            for j in range(sides):
                a = math.tau * j / sides
                worn = 1 + .035*math.sin(3*a+i*.8)
                end_offset = 0
                if broken and i == len(points)-1:
                    end_offset = radius*(.22*math.sin(a*3)+.14*math.cos(a*5))
                vertices.append(p+(axis*math.cos(a)+other*math.sin(a)*flatness)*radius*worn+tangent*end_offset)
        for i in range(len(points)-1):
            for j in range(sides):
                faces.append((i*sides+j,i*sides+(j+1)%sides,
                              (i+1)*sides+(j+1)%sides,(i+1)*sides+j))
        faces.extend([tuple(reversed(range(sides))),tuple((len(points)-1)*sides+j for j in range(sides))])
        self.add(vertices,faces,kind)

    def object(self, name, material, collection):
        mesh = bpy.data.meshes.new(name)
        mesh.from_pydata(self.vertices,[],self.faces)
        mesh.update()
        # Recalculate outward normals including fractured rib end caps.
        bm=bmesh.new()
        bm.from_mesh(mesh)
        bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces))
        bm.to_mesh(mesh)
        bm.free()
        mesh.materials.append(material)
        assign_uv(mesh)
        for polygon in mesh.polygons:
            polygon.use_smooth=True
        obj=bpy.data.objects.new(name,mesh)
        collection.objects.link(obj)
        return obj


def assign_uv(mesh):
    uv=mesh.uv_layers.get("UVMap") or mesh.uv_layers.new(name="UVMap")
    for poly in mesh.polygons:
        dominant=max(range(3),key=lambda k:abs(poly.normal[k]))
        axes=((1,2),(0,2),(0,1))[dominant]
        for index in poly.loop_indices:
            co=mesh.vertices[mesh.loops[index].vertex_index].co
            uv.data[index].uv=(co[axes[0]],co[axes[1]])


def ensure_portable_bone_textures(output_dir=None):
    """Write deterministic seamless 512 px PNG tiles, requiring only Blender NumPy.

    A metre-scale isotropic mineral stain and shallow cortical pores avoid wood
    grain. Images are shared by background previews and exported glTF materials.
    """
    import numpy as np
    folder=Path(output_dir) if output_dir else Path(__file__).resolve().parent/"bone_textures"
    folder.mkdir(parents=True,exist_ok=True)
    paths={key:folder/("aged_bone_"+key+"_512.png") for key in ("albedo","roughness","normal_gl")}
    if all(p.is_file() for p in paths.values()):
        return {key:str(path) for key,path in paths.items()}
    size=512
    yy,xx=np.mgrid[0:size,0:size].astype(np.float32)/size
    rng=np.random.default_rng(417978)
    def seamless_field(low,high,count):
        result=np.zeros((size,size),dtype=np.float32)
        for _ in range(count):
            kx=int(rng.integers(low,high+1))*(1 if rng.random()>.5 else -1)
            ky=int(rng.integers(low,high+1))*(1 if rng.random()>.5 else -1)
            result+=np.sin(math.tau*(kx*xx+ky*yy)+rng.random()*math.tau)
        return result/np.sqrt(count*.5)
    broad=seamless_field(1,5,24)
    mid=seamless_field(5,16,32)
    fine=seamless_field(22,90,36)
    stain=np.clip(.53+.14*broad+.06*mid,0,1)
    pores=np.clip(-fine-.7,0,2)/2
    # Linear shader values translated to standard sRGB texture encoding.
    low=np.array((.255,.193,.112),dtype=np.float32)
    high=np.array((.62,.53,.385),dtype=np.float32)
    linear=(low[None,None,:]*(1-stain[:,:,None])+high[None,None,:]*stain[:,:,None])
    linear*=1-.11*pores[:,:,None]
    srgb=np.where(linear<=.0031308,linear*12.92,1.055*np.power(linear,1/2.4)-.055)
    rough=np.clip(.82+.025*mid+.065*pores,.68,.95)
    height=.00025*mid-.0007*pores+.00012*fine
    dx=(np.roll(height,-1,axis=1)-np.roll(height,1,axis=1))*size*.5
    dy=(np.roll(height,-1,axis=0)-np.roll(height,1,axis=0))*size*.5
    normal=np.stack((-dx,-dy,np.ones_like(dx)),axis=-1)
    normal/=np.linalg.norm(normal,axis=-1)[:,:,None]
    normal=normal*.5+.5
    arrays={"albedo":srgb,"roughness":np.repeat(rough[:,:,None],3,axis=-1),"normal_gl":normal}
    for key,rgb in arrays.items():
        rgba=np.concatenate((rgb,np.ones((size,size,1),dtype=np.float32)),axis=-1).astype(np.float32)
        image=bpy.data.images.new("TEMP_BoneTile_"+key,width=size,height=size,alpha=True)
        # Write the already encoded numbers without display/color conversion.
        image.colorspace_settings.name="Non-Color"
        image.pixels.foreach_set(rgba.ravel())
        image.filepath_raw=str(paths[key])
        image.file_format="PNG"
        image.save()
        bpy.data.images.remove(image)
    return {key:str(path) for key,path in paths.items()}


def aged_bone_material():
    """glTF-portable shader: UV image albedo, roughness and OpenGL normal."""
    paths=ensure_portable_bone_textures()
    mat=bpy.data.materials.get("Mine_AgedIvoryBone") or bpy.data.materials.new("Mine_AgedIvoryBone")
    mat.diffuse_color=(.51,.425,.295,1)
    mat.use_nodes=True
    nodes=mat.node_tree.nodes
    links=mat.node_tree.links
    nodes.clear()
    output=nodes.new("ShaderNodeOutputMaterial")
    shader=nodes.new("ShaderNodeBsdfPrincipled")
    links.new(shader.outputs["BSDF"],output.inputs["Surface"])
    shader.inputs["Base Color"].default_value=mat.diffuse_color
    shader.inputs["Roughness"].default_value=.81
    uv=nodes.new("ShaderNodeTexCoord")
    for key in ("albedo","roughness","normal_gl"):
        image=bpy.data.images.load(paths[key],check_existing=True)
        image.colorspace_settings.name="sRGB" if key=="albedo" else "Non-Color"
        tex=nodes.new("ShaderNodeTexImage")
        tex.name="Bone_"+key
        tex.image=image
        tex.extension="REPEAT"
        links.new(uv.outputs["UV"],tex.inputs["Vector"])
        if key=="normal_gl":
            normal=nodes.new("ShaderNodeNormalMap")
            normal.inputs["Strength"].default_value=.65
            links.new(tex.outputs["Color"],normal.inputs["Color"])
            links.new(normal.outputs["Normal"],shader.inputs["Normal"])
        else:
            links.new(tex.outputs["Color"],shader.inputs["Base Color" if key=="albedo" else "Roughness"])
    mat["bone_texture_version"]=1
    mat["texture_tile_m"]=1.0
    mat["portable_material"]=True
    return mat


def apply_portable_bone_material(collection=None):
    """Retrofit already-built scenes before re-saving/re-exporting the GLB.

    Finds GiantBeast meshes or objects tagged monster_skeleton; only their aged
    bone slots are updated. Existing geometry, transforms and scene stay intact.
    """
    mat=aged_bone_material()
    objects=collection.all_objects if collection else bpy.data.objects
    changed=[]
    for obj in objects:
        if obj.type!="MESH":
            continue
        if not (obj.name.startswith("GiantBeast_") or obj.get("mine_prop_kind")=="monster_skeleton"):
            continue
        if not obj.data.materials:
            obj.data.materials.append(mat)
        else:
            for index,old in enumerate(obj.data.materials):
                if old is None or "Bone" in old.name or "bone" in old.name:
                    obj.data.materials[index]=mat
        changed.append(obj.name)
    return {"material":mat.name,"mesh_objects":changed,"textures":ensure_portable_bone_textures(),"portable_material":True}


def skull_mass(material,collection):
    # Anatomical silhouette: narrow nasal bridge, flared cheek/maxilla, rounded
    # cranial vault and a pinched occipital joint. No cuboid head geometry.
    profiles=[(-6.15,.20,.40,.15),(-5.95,.38,.49,.20),
              (-5.60,.45,.59,.26),(-5.12,.46,.74,.33),
              (-4.72,.65,.92,.52),(-4.37,.87,1.00,.66),
              (-4.00,.79,1.04,.62),(-3.65,.54,1.08,.43),
              (-3.44,.20,1.10,.20)]
    vertices,faces=[],[]
    sides=48
    for i in range(41):
        t=i/40*(len(profiles)-1)
        k=min(len(profiles)-2,int(t))
        f=t-k
        f=f*f*(3-2*f)
        y,w,z,h=[profiles[k][j]*(1-f)+profiles[k+1][j]*f for j in range(4)]
        for j in range(sides):
            a=math.tau*j/sides
            irregular=1+.025*math.sin(3*a+y*4)+.014*math.cos(7*a-y)
            # Midline sagittal crest broadens into the back of the skull.
            crest=.12*max(0,math.sin(a))**10*max(0,1-abs(y+4.0)/.7)
            vertices.append((math.cos(a)*w*irregular,y,z+math.sin(a)*h*irregular+crest))
    for i in range(40):
        for j in range(sides):
            faces.append((i*sides+j,i*sides+(j+1)%sides,(i+1)*sides+(j+1)%sides,(i+1)*sides+j))
    faces.extend([tuple(reversed(range(sides))),tuple(40*sides+j for j in range(sides))])
    geo=BoneMesh()
    geo.add(vertices,faces,"skull_cranium")
    obj=geo.object("GiantBeast_HollowSkull",material,collection)
    # Actual holes reveal thickness and internal darkness from every viewpoint.
    cutters=[("cranial_cavity",(0,-4.10,1.03),(.55,.57,.45)),
             ("left_orbit",(-.67,-4.40,1.15),(.47,.39,.40)),
             ("right_orbit",(.67,-4.40,1.15),(.47,.39,.40)),
             ("left_nasal_fenestra",(-.37,-5.38,.57),(.30,.36,.22)),
             ("right_nasal_fenestra",(.37,-5.38,.57),(.30,.36,.22)),
             ("nasal_opening",(0,-6.15,.44),(.20,.30,.14))]
    for name,center,size in cutters:
        geo=BoneMesh()
        geo.ellipsoid(center,size,name,20,28)
        cutter=geo.object("TEMP_"+name,material,collection)
        mod=obj.modifiers.new(name,"BOOLEAN")
        mod.operation="DIFFERENCE"
        mod.solver="EXACT"
        mod.object=cutter
        bpy.context.view_layer.objects.active=obj
        bpy.ops.object.modifier_apply(modifier=mod.name)
        bpy.data.objects.remove(cutter,do_unlink=True)
    bevel=obj.modifiers.new("WornSocketRims","BEVEL")
    bevel.width=.035
    bevel.segments=2
    bpy.context.view_layer.objects.active=obj
    bpy.ops.object.modifier_apply(modifier=bevel.name)
    assign_uv(obj.data)
    for poly in obj.data.polygons:
        poly.use_smooth=True
    obj["anatomical_detail"]="hollow cranial vault, bilateral eye sockets, nasal fenestrae"
    return obj


def _footprint_allowed(x,z,angle,clearance_fn,room_polygon):
    def inside(px,pz):
        result=False
        for a,b in zip(room_polygon,room_polygon[1:]+room_polygon[:1]):
            if (a[1]>pz)!=(b[1]>pz) and px < (b[0]-a[0])*(pz-a[1])/(b[1]-a[1])+a[0]:
                result=not result
        return result
    # Sample the complete occupied body envelope, never just the origin.
    for yy,width in [(-6.2,.55),(-5.5,.75),(-4.4,1.0),(-3.4,1.2),
                     (-2.5,2.0),(-1.5,2.15),(-.5,2.2),(.5,2.2),
                     (1.5,2.1),(2.5,1.85),(3.5,1.65),(4.5,.8),(5.8,.8)]:
        for xx in (-width,0,width):
            wx=x+xx*math.cos(angle)-yy*math.sin(angle)
            wz=z-xx*math.sin(angle)-yy*math.cos(angle)
            if not inside(wx,wz) or (clearance_fn and not clearance_fn(wx,wz,.28)):
                return False
    return True


def build_monster_remains(layout, materials, collection, clearance_fn=None, ground_height_fn=None):
    landmark=next((v for v in layout.get("landmarks",[]) if v.get("type")=="monster_skeleton"),None)
    if not landmark:
        return {"assets":[],"collisions":[],"skipped":["No monster_skeleton landmark"],"counts":{}}
    room=next(v for v in layout["rooms"] if v["id"]==landmark["room_id"])
    origin=landmark["position"]
    angle=landmark.get("rotation_y",0)
    placement=None
    # Retain the authored point whenever possible, then offset in quarter metre
    # precision along the surrounding broad chamber to retain the protected lane.
    candidates=[(0.0,0.0)]
    for radius in (.75,1.5,2.25,3.0,4.0,5.0,6.0,7.0,8.0):
        candidates.extend((radius*math.cos(a*math.tau/20),radius*math.sin(a*math.tau/20)) for a in range(20))
    for dx,dz in candidates:
        if _footprint_allowed(origin[0]+dx,origin[2]+dz,angle,clearance_fn,room["polygon"]):
            placement=(origin[0]+dx,origin[2]+dz)
            break
    if placement is None:
        return {"assets":[],"collisions":[],"skipped":[{"id":landmark["id"],"reason":"No lane-safe skeleton footprint within 8 m of landmark"}],"counts":{}}
    material=materials.get("bone") or aged_bone_material()
    geo=BoneMesh()
    rng=random.Random(layout.get("seed",139131)+978)
    # Curved spine gradually sinks into the sediment toward the partial tail.
    def spine(y):
        return Vector((.15*math.sin(y*.66),y,1.62-.075*y-.045*y*y))
    for index in range(19):
        y=-3.25+index*.39
        c=spine(y)
        scale=1.0-.045*max(0,y-1.6)
        geo.ellipsoid(c,(.285*scale,.177,.215*scale),phase=index*.31)
        # Smooth swept neural arch and swept spinous process attached to centrum.
        geo.tube([c+Vector((-.16,0,.08)),c+Vector((-.21,.01,.28)),
                  c+Vector((0,.025,.40)),c+Vector((.21,.01,.28)),c+Vector((.16,0,.08))],
                 [.085,.09,.105,.09,.085],"neural_arch")
        geo.tube([c+Vector((0,.02,.32)),c+Vector((-.02,.10,.54)),
                  c+Vector((.015,.18,.77)),c+Vector((.03,.26,.84))],
                 [.14,.11,.07,.025],"spinous_process",flatness=.66)
        for side in (-1,1):
            geo.tube([c+Vector((side*.14,-.025,.07)),c+Vector((side*.30,.015,.14)),
                      c+Vector((side*.46,.10,.18))],[.10,.11,.065],"transverse_process")
    # Twelve rib pairs spanning 6.9 m: irregular flattened bone ribbons curve
    # from vertebral articulations down around the chest, with several real breaks.
    for i in range(12):
        y=-2.80+i*.59
        c=spine(y)
        breadth=(1.2+.65*math.sin(math.pi*(i+1)/13))*(1-.055*max(0,i-8))
        for side in (-1,1):
            broken=(i,side) in {(1,-1),(4,1),(7,-1),(10,1),(11,-1)}
            stop=rng.uniform(.43,.76) if broken else rng.uniform(.94,1.0)
            points=[]
            radii=[]
            for j in range(31):
                t=j/30*stop
                a=t*math.pi*.86
                x=side*(.28+breadth*math.sin(a))
                # Natural proximal rib neck, outward upper bend, inward lower end.
                z=c.z + .18*math.sin(a) - (c.z-.14)*(1-math.cos(a))*.53
                yy=y+.12+.40*t+.12*math.sin(a)*math.sin(i*.83)
                points.append((c.x+x,yy,z))
                radii.append((.105*(1-.48*t)+.032*math.exp(-t*18))*(1+rng.uniform(-.04,.04)))
            geo.tube(points,radii,"broken_rib" if broken else "intact_rib",sides=14,flatness=.60,broken=broken)
            geo.ellipsoid(points[0],(.15,.13,.125),"rib_articulation",8,12)
    # Last lumbar vertebrae become progressively smaller, curl sideways and lie
    # half buried. They are jointed bones, not a single rope-like tail.
    for i in range(7):
        t=i/6
        c=Vector((.12+.56*t*t,4.05+i*.28,.49-.31*t))
        scale=1-.68*t
        geo.ellipsoid(c,(.22*scale,.13*scale,.16*scale),"caudal_vertebra",8,12)
        for side in (-1,1):
            geo.tube([c,c+Vector((side*.22*scale,.055,.045))],[.065*scale,.023*scale],"caudal_process",8)
    # Detached but nearby upper cervical vertebra creates a believable broken neck.
    geo.ellipsoid((.02,-3.52,1.21),(.30,.19,.23),"atlas_joint")
    # Mandibular dentary and ascending ramus, linked across the narrow chin.
    for side in (-1,1):
        jaw=[(side*.65,-3.92,1.06),(side*.76,-4.05,.71),(side*.68,-4.25,.36),
             (side*.57,-4.70,.23),(side*.45,-5.18,.20),(side*.33,-5.69,.20),(side*.12,-6.05,.27)]
        geo.tube(jaw,[.14,.20,.16,.13,.11,.10,.08],"mandible",16,flatness=.77)
        geo.ellipsoid(jaw[0],(.16,.18,.13),"jaw_condyle",8,12)
        # Swept zygomatic arch behind each true eye socket.
        geo.tube([(side*.47,-3.72,1.02),(side*.96,-3.94,.82),
                  (side*1.02,-4.29,.66),(side*.77,-4.69,.66),(side*.50,-4.97,.67)],
                 [.10,.10,.085,.085,.11],"zygomatic_arch",14)
        for i in range(7):
            y=-5.84+i*.175
            x=side*(.26+.032*i)
            h=.14 if i<2 else .18
            # Gaps in the worn teeth prevent an artificial identical comb.
            if (side==1 and i==3) or (side==-1 and i==5):
                continue
            geo.tube([(x,y,.27),(x*.97,y-.016,.27+h*.65),(x*.94,y-.05,.27+h)],
                     [.052,.037,.010],"lower_tooth",10)
        geo.tube([(side*.43,-5.29,.70),(side*.45,-5.32,.49),(side*.42,-5.43,.27)],
                 [.095,.069,.008],"upper_canine",14)
        for i in range(4):
            y=-4.96+i*.18
            geo.tube([(side*(.45+.04*i),y,.60),(side*(.43+.04*i),y-.02,.42)],
                     [.063,.019],"upper_molar",10)
    # Two individually curved detached rib fragments lie in sediment at the flank.
    for i in range(2):
        points=[(1.65+.23*i+.38*math.sin(t*math.pi),1.1+i*.78+t*.62,.06+.10*math.sin(t*math.pi)) for t in [j/16 for j in range(17)]]
        geo.tube(points,[.066-.026*j/16 for j in range(17)],"detached_rib_fragment",12,.65,True)
    group=bpy.data.objects.new("Mine_bone_cavern_monster_skeleton",None)
    collection.objects.link(group)
    ground_y=ground_height_fn(*placement) if ground_height_fn else room.get("floor_y",0)
    group.location=(placement[0],-placement[1],ground_y-.055)
    group.rotation_euler.z=angle
    group["mine_prop_kind"]="monster_skeleton"
    group["zone_id"]=room["id"]
    group["source_landmark"]=landmark["id"]
    body=geo.object("GiantBeast_OrganicArticulatedRemains",material,collection)
    skull=skull_mass(material,collection)
    for obj in (body,skull):
        obj.parent=group
        obj["mine_prop_kind"]="monster_skeleton"
        obj["zone_id"]=room["id"]
    bpy.context.view_layer.update()
    vertices=[obj.matrix_world@v.co for obj in (body,skull) for v in obj.data.vertices]
    low=[min(v[k] for v in vertices) for k in range(3)]
    high=[max(v[k] for v in vertices) for k in range(3)]
    faces=sum(len(o.data.polygons) for o in (body,skull))
    asset={"name":group.name,"kind":"monster_skeleton","zone":room["id"],
           "position_godot":[placement[0],group.location.z,placement[1]],"rotation_y":angle,
           "source_landmark":landmark["id"],"landmark_offset_m":round(math.hypot(placement[0]-origin[0],placement[1]-origin[2]),4),
           "anatomical_parts":geo.part_counts,"skull_eye_sockets":2,
           "length_m":12.3,"ribcage_length_m":6.9,"mesh_objects":2,
           "vertices":len(vertices),"faces":faces,"bounds_blender":{"min":low,"max":high}}
    return {"assets":[asset],"collisions":[],"counts":{"monster_skeleton":1},"skipped":[],
            "placement_checks":"full footprint passed room polygon; lane clearance enforced when callback supplied", "total_vertices":len(vertices),"total_faces":faces}
