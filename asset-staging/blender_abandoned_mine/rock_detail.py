"""Linked photogrammetry outcrops for the actual Blender mine source.

polish_scene(layout) is the idempotent post-build entry point. No window,
render, file save or export is performed here. Existing scan UVs/materials
and mesh datablocks are preserved; only instances and transforms are added.
"""
import math
import random
from collections import Counter
from pathlib import Path

import bpy
import numpy as np
from mathutils import Vector
from mathutils.bvhtree import BVHTree

ROOT=Path(__file__).resolve().parent
TAG="mine_geologic_polish"


def _inside(p,polygon):
    result=False
    for a,b in zip(polygon,polygon[1:]+polygon[:1]):
        if (a[1]>p[1])!=(b[1]>p[1]):
            if p[0]<(b[0]-a[0])*(p[1]-a[1])/(b[1]-a[1])+a[0]:
                result=not result
    return result


def _prop_boxes():
    """Actual visible assembly bounds, including relocated light fixtures."""
    boxes=[]
    bpy.context.view_layer.update()
    for obj in bpy.data.objects:
        if obj.type!="EMPTY" or not obj.get("mine_prop_kind"):
            continue
        points=[]
        for child in obj.children_recursive:
            if child.type=="MESH" and not child.hide_render:
                points.extend(child.matrix_world@Vector(v) for v in child.bound_box)
        if not points:
            continue
        low=np.min(np.array(points),axis=0)
        high=np.max(np.array(points),axis=0)
        boxes.append((low,high))
    return boxes


def _terrain_surface():
    vertices,faces=[],[]
    for obj in bpy.data.objects:
        if obj.type!="MESH" or not obj.name.startswith("Terrain_"):
            continue
        offset=len(vertices)
        vertices.extend(obj.matrix_world@v.co for v in obj.data.vertices)
        faces.extend(tuple(offset+i for i in face.vertices) for face in obj.data.polygons)
    return BVHTree.FromPolygons(vertices,faces,all_triangles=False) if vertices else None


def add_geologic_outcrops(layout,collection,clearance_fn,
                          ground_height_fn=None,ceiling_height_fn=None,
                          max_fragments=88,seed=4813139):
    """Add irregular clusters of scan fragments without covering walk lanes.

    clearance_fn(x,godot_z,radius) returns True for a safe floor anchor and
    a protected route envelope. At pedestrian height the complete horizontal
    instance bounding circle is checked. Elevated fragments start at >=3m;
    their anchors remain outside lanes and their volume is checked against
    props and the cave ceiling. The back half deliberately intersects walls.
    """
    for obj in list(bpy.data.objects):
        if obj.get(TAG):
            bpy.data.objects.remove(obj,do_unlink=True)
    templates=[]
    for source in ("rock_face_01","rock_face_02"):
        candidates=[m for m in bpy.data.meshes if m.name.startswith("ScanTemplate_"+source) and len(m.vertices)]
        if candidates:
            mesh=next((m for m in candidates if m.users),candidates[0])
            coords=np.array([v.co for v in mesh.vertices])
            low,high=coords.min(axis=0),coords.max(axis=0)
            templates.append((mesh,low,high))
    if not templates:
        raise RuntimeError("Geologic polish requires imported ScanTemplate_rock_face meshes")
    ground_height_fn=ground_height_fn or (lambda x,z:0)
    ceiling_height_fn=ceiling_height_fn or (lambda x,z:12)
    rng=random.Random(seed)
    prop_boxes=_prop_boxes()
    terrain_surface=_terrain_surface()
    occupied=[]
    assets=[]
    counts=Counter()
    rejected=Counter()
    rooms={r["id"]:r for r in layout["rooms"]}
    # Mineral provinces receive unequal clustered detail. The central mass is
    # first so its silhouette cannot be crowded out by the outer-wall budget.
    areas=[]
    for island in layout.get("islands",[]):
        if island["id"]=="grand_quarry_rock_island":
            areas.append((island["id"],island["room_id"],island["polygon"],True,17))
    targets={"grand_quarry":16,"rubble_passage":7,"western_altar":5,
             "north_workings":6,"foreman_workroom":4,"north_vents":5,
             "pillar_shrine":5,"east_store":4,"hoistroom":5,"entrance":5,
             "workshops":3,"southwest_adit":3,"bone_cavern":3}
    for room in sorted(layout["rooms"],key=lambda r:targets.get(r["id"],2),reverse=True):
        areas.append((room["id"],room["id"],room["polygon"],False,targets.get(room["id"],2)))
    for area_id,room_id,polygon,island,target in areas:
        if len(assets)>=max_fragments:
            break
        edges=[]
        for a,b in zip(polygon,polygon[1:]+polygon[:1]):
            a,b=np.array(a,dtype=float),np.array(b,dtype=float)
            length=float(np.linalg.norm(b-a))
            if length>.15:
                edges.append((a,b,length))
        accepted=0
        for attempt in range(target*55):
            if accepted>=target or len(assets)>=max_fragments:
                break
            # Several strata can share a fracture location; jitter along a
            # selected edge avoids an evenly spaced ring of duplicate rocks.
            a,b,length=rng.choices(edges,weights=[e[2] for e in edges],k=1)[0]
            t=rng.uniform(.08,.92)
            boundary=a+(b-a)*t
            normal=np.array([-(b-a)[1],(b-a)[0]])/length
            inside=_inside((boundary+normal*.3).tolist(),polygon)
            if inside==island:
                normal=-normal
            elevated=rng.random()<(.60 if island else .38)
            width=rng.uniform(1.9,3.25) if island else rng.uniform(2.15,4.65)
            depth=rng.uniform(.72,1.32) if island else rng.uniform(.84,1.75)
            height=rng.uniform(1.45,3.30) if elevated else rng.uniform(2.45,4.90)
            inset=depth*.40+rng.uniform(.18,.42)
            pos=boundary+normal*inset
            floor=ground_height_fn(*pos)
            bottom=floor+rng.uniform(3.00,4.50) if elevated else floor-.20
            ceiling=ceiling_height_fn(*pos)
            if bottom+height>ceiling-.30:
                height=ceiling-.30-bottom
            if height<1.1:
                rejected["ceiling"]+=1
                continue
            radius=math.hypot(width*.5,depth*.5)+.08
            # A high shelf cannot block a 1.8m player; its lower surface is
            # guaranteed above3m. Low crags reserve their entire XY envelope.
            reserve=.16 if elevated else radius
            if not clearance_fn(float(pos[0]),float(pos[1]),reserve):
                rejected["route_or_wall"]+=1
                continue
            clearance_anchor=pos.copy()
            if elevated:
                if terrain_surface is None:
                    rejected["missing_attachment_surface"]+=1
                    continue
                # The finite central boulder narrows towards its crown. Cast
                # against actual terrain at shelf height, not the floor map.
                # Bury the scan's open back in the hit face by ~30% of depth.
                ray_start=Vector((float(pos[0]+normal[0]*4),float(-pos[1]-normal[1]*4),bottom+height*.46))
                ray_dir=Vector((-float(normal[0]),float(normal[1]),0))
                hit,_,_,_=terrain_surface.ray_cast(ray_start,ray_dir,8.0)
                if hit is None:
                    rejected["no_wall_attachment"]+=1
                    continue
                attached=np.array([hit.x,-hit.y])+normal*depth*.18
                if np.linalg.norm(attached-pos)>3.5:
                    rejected["attachment_too_distant"]+=1
                    continue
                pos=attached
            if abs(pos[0])+radius>layout["width"]*.5-.15 or abs(pos[1])+radius>layout["depth"]*.5-.15:
                rejected["bounds"]+=1
                continue
            if any(math.dist(pos,p)<(r+radius)*.43 and abs(bottom-y)<min(height,h)*.65 for p,r,y,h in occupied):
                rejected["duplicate_cluster"]+=1
                continue
            # Axis-aligned conservative footprint avoids hiding any props.
            xyz=np.array([pos[0],-pos[1],bottom])
            low=xyz+np.array([-radius,-radius,0])
            high=xyz+np.array([radius,radius,height])
            if any(np.all(high>=plow-.18) and np.all(low<=phigh+.18) for plow,phigh in prop_boxes):
                rejected["prop_volume"]+=1
                continue
            mesh,mesh_low,mesh_high=templates[rng.randrange(len(templates))]
            size=mesh_high-mesh_low
            obj=bpy.data.objects.new(f"RockScan_Detail_{len(assets):03d}_{area_id}",mesh)
            collection.objects.link(obj)
            obj[TAG]=True
            obj["geology_area"]=area_id
            # Scan front is -Y. Face into chambers, and away from islands.
            angle=math.atan2(-normal[1],normal[0])+math.pi/2+rng.uniform(-.18,.18)
            obj.rotation_euler.z=angle
            obj.scale=(width/size[0],depth/size[1],height/size[2])
            obj.location=(float(pos[0]),float(-pos[1]),bottom-float(mesh_low[2])*obj.scale.z)
            occupied.append((pos.copy(),radius,bottom,height))
            item={"name":obj.name,"area":area_id,"room_id":room_id,
                  "template":mesh.name,"position_godot":[float(pos[0]),float(bottom),float(pos[1])],
                  "dimensions_m":[width,height,depth],"rotation_y":angle,
                  "elevated":elevated,"clearance_radius_m":reserve,
                  "clearance_anchor_xz":clearance_anchor.tolist(),
                  "attachment":"terrain_surface_raycast" if elevated else "sunken_ground_contact"}
            assets.append(item)
            counts[area_id]+=1
            accepted+=1
    bpy.context.view_layer.update()
    return {"added_fragments":len(assets),"existing_scan_instances":sum(o.type=="MESH" and o.name.startswith("RockScan_") and not o.get(TAG) for o in bpy.data.objects),
            "linked_template_meshes":len(templates),"counts":dict(counts),"assets":assets,
            "rejected_candidates":dict(rejected),"seed":seed,"max_fragments":max_fragments,
            "notes":["Existing scan topology, physical UVs and photographic materials are reused unchanged.",
                     "Low fragments clear a protected 1.35m route plus their full horizontal bounding radius.",
                     "High wall shelves start at least3m above local floor, outside prop volumes.",
                     "Post-build helper is idempotent and only replaces its own marked scan instances."]}


def polish_scene(layout):
    """Post-build wrapper for the saved full mine scene and terrain field."""
    data=np.load(ROOT/"terrain_mesh.npz")
    xs,zs=data["xs"],data["zs"]
    def sample(grid,x,z):
        ix=int(np.clip(round((x-xs[0])/(xs[1]-xs[0])),0,len(xs)-1))
        iz=int(np.clip(round((z-zs[0])/(zs[1]-zs[0])),0,len(zs)-1))
        return float(grid[iz,ix])
    segments=[(np.array(a),np.array(b)) for c in layout["corridors"] for a,b in zip(c["points"],c["points"][1:])]
    reserved=[(np.array(v["position"])[[0,2]],2.0) for group in layout["gameplay"].values() for v in group]
    reserved.extend([(np.array(layout["spawn"])[[0,2]],2.0),(np.array(layout["extraction"])[[0,2]],3.0)])
    def clear(x,z,radius):
        if sample(data["signed_distance"],x,z)<max(.1,radius*.3):
            return False
        p=np.array([x,z])
        for a,b in segments:
            axis=b-a
            t=np.clip(np.dot(p-a,axis)/max(.001,np.dot(axis,axis)),0,1)
            if np.linalg.norm(p-a-t*axis)<radius+1.35:
                return False
        return not any(np.linalg.norm(p-point)<r+radius for point,r in reserved)
    coll=bpy.data.collections.get("02_NaturalFormations")
    if coll is None:
        coll=bpy.data.collections.new("02_NaturalFormations")
        bpy.context.scene.collection.children.link(coll)
    return add_geologic_outcrops(layout,coll,clear,
        ground_height_fn=lambda x,z:sample(data["floor"],x,z),
        ceiling_height_fn=lambda x,z:sample(data["ceiling"],x,z),max_fragments=88)
