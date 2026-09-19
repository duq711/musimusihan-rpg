"""Mac Blender: partition the existing low shield, preserving its exterior.

No runtime animation or collision nodes are exported. Each centered mesh is one
reassemblable rigid-body candidate; Godot may derive a convex hull per mesh.
"""
import bpy, bmesh, math, json, hashlib
from pathlib import Path
from mathutils import Vector
from mathutils.bvhtree import BVHTree

ROOT = Path(__file__).resolve().parents[2]
STAGE = Path(__file__).resolve().parent
SOURCE = ROOT / 'godot-game/assets/3d/player/shield_damage/round_shield_low.glb'
OUT = SOURCE.parent / 'round_shield_fragments.glb'
BLEND = STAGE / 'shield_fragments.blend'
MATERIAL_CLASS = {
    'FP_ShieldOak': 'wood', 'FP_ShieldFractureOak': 'wood',
    'FP_ShieldEnarmes': 'leather', 'FP_ShieldLeatherEdge': 'leather',
    'FP_ShieldStitch': 'leather',
}

def sha(path): return hashlib.sha256(path.read_bytes()).hexdigest()
def godot(v): return [float(v.x), float(v.z), float(-v.y)]
def clean(bm):
    bmesh.ops.delete(bm, geom=[v for v in bm.verts if not v.link_faces], context='VERTS')
    bm.normal_update()

def subset(source, selected_faces, name):
    ob = source.copy(); ob.data = source.data.copy(); ob.name = name
    bpy.context.collection.objects.link(ob)
    bm = bmesh.new(); bm.from_mesh(ob.data); bm.faces.ensure_lookup_table()
    bmesh.ops.delete(bm, geom=[f for f in bm.faces if f.index not in selected_faces], context='FACES')
    clean(bm); bm.to_mesh(ob.data); bm.free()
    return ob

def mesh_bm(ob):
    bm = bmesh.new(); bm.from_mesh(ob.data)
    bmesh.ops.remove_doubles(bm, verts=list(bm.verts), dist=0.0000005)
    bm.normal_update()
    return bm

def close_original_sheet(ob):
    """Originally open thin rim/buckle/stitch surfaces gain inward backing."""
    bm = mesh_bm(ob); boundary = sum(e.is_boundary for e in bm.edges)
    bm.to_mesh(ob.data); bm.free()
    if not boundary: return False
    bpy.context.view_layer.objects.active = ob
    mod = ob.modifiers.new('Internal 0.8mm backing of original open sheet', 'SOLIDIFY')
    mod.thickness = 0.0008; mod.offset = -1.0; mod.use_rim = True
    mod.solidify_mode = 'NON_MANIFOLD'
    mod.use_even_offset = True; mod.use_quality_normals = True
    bpy.ops.object.modifier_apply(modifier=mod.name)
    bm = mesh_bm(ob)
    bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
    bm.to_mesh(ob.data); bm.free()
    return True

def join(parts, name):
    bpy.ops.object.select_all(action='DESELECT')
    for ob in parts: ob.select_set(True)
    bpy.context.view_layer.objects.active = parts[0]
    if len(parts)>1: bpy.ops.object.join()
    result=parts[0]; result.name=name
    return result

def clip(bm, point, normal, keep_positive, cap_material):
    """Plane partition: opposite halves share the same exact cut plane."""
    bmesh.ops.bisect_plane(bm, geom=list(bm.verts)+list(bm.edges)+list(bm.faces),
        dist=0.00000005, plane_co=point, plane_no=normal,
        clear_inner=keep_positive, clear_outer=not keep_positive)
    clean(bm)
    # Input components are closed. The only boundaries are the new plane cuts;
    # fill each separate loop so rivets do not bridge to the rim.
    edges={e for e in bm.edges if e.is_boundary and
        all(abs((v.co-point).dot(normal))<0.000003 for v in e.verts)}
    while edges:
        first=edges.pop(); group={first}; todo=[first]
        while todo:
            edge=todo.pop()
            for vertex in edge.verts:
                for candidate in vertex.link_edges:
                    if candidate in edges:
                        edges.remove(candidate); group.add(candidate); todo.append(candidate)
        faces=bmesh.ops.holes_fill(bm, edges=list(group), sides=0).get('faces', [])
        for f in faces: f.material_index=cap_material; f.smooth=False
    clean(bm)

def make_piece(source, planes, kind, pieces):
    # Each source component was welded before joining; avoid merging separate
    # rivet/buckle shells merely because they touch after inward backing.
    bm=bmesh.new(); bm.from_mesh(source.data); bm.normal_update()
    cap = next((i for i,m in enumerate(source.data.materials) if m and m.name == 'FP_ShieldFractureOak'), 0)
    if kind != 'wood':
        cap=next((i for i,m in enumerate(source.data.materials) if m and m.name == ('FP_ShieldIron' if kind=='metal' else 'FP_ShieldEnarmes')),0)
    for point,normal,positive in planes: clip(bm,Vector(point),Vector(normal).normalized(),positive,cap)
    if not bm.faces: bm.free(); return
    bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces))
    # Triangulate caps explicitly to make export and collision deterministic.
    bmesh.ops.triangulate(bm, faces=[f for f in bm.faces if len(f.verts)>4])
    center=(Vector(tuple(min(v.co[i] for v in bm.verts) for i in range(3)))+
            Vector(tuple(max(v.co[i] for v in bm.verts) for i in range(3))))*0.5
    for v in bm.verts: v.co-=center
    number=len(pieces)
    name=f'ShieldFragment_{number:03d}_{kind}'
    mesh=bpy.data.meshes.new(name); bm.to_mesh(mesh)
    for m in source.data.materials: mesh.materials.append(m)
    ob=bpy.data.objects.new(name,mesh); bpy.context.collection.objects.link(ob)
    ob.location=center
    ob['fragment_kind']=kind
    ob['wood_coordinate_offset']=godot(center)
    ob['source_stage']='low'
    ob['collision_hint']='single_convex_hull'
    boundary=sum(e.is_boundary for e in bm.edges)
    nonmanifold=sum(not e.is_manifold for e in bm.edges)
    volume=abs(bm.calc_volume(signed=True))
    hull=bmesh.new()
    for v in bm.verts: hull.verts.new(v.co)
    bmesh.ops.convex_hull(hull,input=list(hull.verts),use_existing_faces=False)
    hull_volume=abs(hull.calc_volume(signed=True)); hull.free()
    row={'name':name,'kind':kind,'origin_godot':godot(center),'origin_blender':list(center),
         'wood_coordinate_offset':godot(center),'vertex_count':len(bm.verts),
         'triangle_count':sum(len(f.verts)-2 for f in bm.faces),'boundary_edges':boundary,
         'nonmanifold_edges':nonmanifold,'mesh_volume_m3':volume,
         'convex_volume_m3':hull_volume,
         'bounds_local_godot':[[min(godot(v.co)[i] for v in bm.verts),max(godot(v.co)[i] for v in bm.verts)] for i in range(3)],
         'materials':sorted({mesh.materials[f.material_index].name for f in bm.faces})}
    bm.free(); pieces.append((ob,row))

def main():
    before={p:sha(p) for p in [SOURCE,SOURCE.parent/'round_shield_medium.glb',SOURCE.parent.parent/'sword_shield/round_shield.glb']}
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=str(SOURCE))
    source=bpy.data.objects['SwordsmanRoundShield_Surface']
    bm=mesh_bm(source); bm.to_mesh(source.data); bm.faces.ensure_lookup_table()
    original_vertices=[source.matrix_world@v.co for v in bm.verts]
    original_centers=[source.matrix_world@f.calc_center_median() for f in bm.faces]
    remaining=set(bm.faces); comps=[]
    while remaining:
        seed=remaining.pop(); faces={seed}; todo=[seed]
        while todo:
            f=todo.pop()
            for e in f.edges:
                for q in e.link_faces:
                    if q in remaining: remaining.remove(q); faces.add(q);todo.append(q)
        vertices={v for f in faces for v in f.verts}
        center=sum((v.co for v in vertices),Vector())/len(vertices)
        mats={source.data.materials[f.material_index].name for f in faces}
        radii=sorted(math.hypot(v.co.x,v.co.z) for v in vertices)
        comps.append({'faces':{f.index for f in faces},'center':center,'mats':mats,
                      'radius_median':radii[len(radii)//2], 'radius_max':radii[-1],
                      'boundary':any(e.is_boundary for f in faces for e in f.edges)})
    bm.free()
    woods=sorted([c for c in comps if any(MATERIAL_CLASS.get(m)=='wood' for m in c['mats'])],key=lambda c:c['center'].x)
    assert len(woods)==7
    other=[c for c in comps if c not in woods]
    groups={'rim':[],'boss':[],'left_grip':[],'right_strap':[]}
    wood_hardware={i:[] for i in range(len(woods))}
    for c in other:
        p=c['center']; radius=math.hypot(p.x,p.z)
        leather=any(MATERIAL_CLASS.get(m)=='leather' for m in c['mats'])
        if leather or (radius<0.29 and p.y>0.02): key='left_grip' if p.x<0 else 'right_strap'
        # A long rim arc's centroid can lie near the shield centre, but its
        # actual vertices remain on the outer ring. Centroid-only assignment
        # would wrongly join that arc to the central boss and create a huge
        # convex collision hull spanning empty space across the whole shield.
        elif c['radius_median']>0.29 or c['radius_max']>0.32: key='rim'
        elif c['radius_max']<0.105 and p.y<-.035: key='boss'
        else:
            # Rear strap mounting rivets sit on separate planks, not on the
            # central front boss. Keep each attached to its original board.
            board=min(range(len(woods)),key=lambda i:abs(woods[i]['center'].x-p.x))
            wood_hardware[board].append(c)
            continue
        groups[key].append(c)
    pieces=[]; originals_closed=0
    for i,c in enumerate(woods):
        attached_faces=set(c['faces'])
        for hardware in wood_hardware[i]: attached_faces.update(hardware['faces'])
        ob=subset(source,attached_faces,f'SourceBoard{i}')
        # Staggered slanted breaks across, rather than along, each narrow plank.
        offsets=[(-.14,.10),(-.12,.13),(-.17,.07),(-.10,.16),(-.15,.12),(-.11,.17),(-.13,.08)][i]
        slope=[.23,-.19,.31,-.27,.17,-.22,.28][i]
        planes=[((c['center'].x,0,z),(-slope,0,1)) for z in offsets]
        make_piece(ob,[(planes[0][0],planes[0][1],False)],'wood',pieces)
        make_piece(ob,[(planes[0][0],planes[0][1],True),(planes[1][0],planes[1][1],False)],'wood',pieces)
        make_piece(ob,[(planes[1][0],planes[1][1],True)],'wood',pieces)
        bpy.data.objects.remove(ob,do_unlink=True)
    for key,components in groups.items():
        parts=[]
        for index,c in enumerate(components):
            ob=subset(source,c['faces'],f'Source_{key}_{index}')
            if c['boundary']: originals_closed += close_original_sheet(ob)
            parts.append(ob)
        ob=join(parts,'Source_'+key)
        if key=='rim':
            for index in range(8):
                a=math.radians(-22.5+45*index); b=a+math.pi/4
                make_piece(ob,[((0,0,0),(-math.sin(a),0,math.cos(a)),True),
                               ((0,0,0),(math.sin(b),0,-math.cos(b)),True)],'metal',pieces)
        else: make_piece(ob,[],'metal' if key=='boss' else 'leather',pieces)
        bpy.data.objects.remove(ob,do_unlink=True)
    assert 20<=len(pieces)<=32, len(pieces)
    for ob in list(bpy.context.scene.objects):
        if ob not in [p[0] for p in pieces]: bpy.data.objects.remove(ob,do_unlink=True)
    root=bpy.data.objects.new('ShieldFragments',None);bpy.context.collection.objects.link(root)
    for ob,row in pieces: ob.parent=root
    bpy.context.view_layer.update()
    # Exterior coverage is measured against every original face center/vertex;
    # internal caps may add faces but cannot remove the source silhouette.
    vertices=[];faces=[]
    for ob,row in pieces:
        offset=len(vertices); vertices += [ob.matrix_world@v.co for v in ob.data.vertices]
        faces += [[offset+i for i in f.vertices] for f in ob.data.polygons]
    tree=BVHTree.FromPolygons(vertices,faces,all_triangles=False)
    deviation=max(tree.find_nearest(p)[3] for p in original_vertices+original_centers)
    failures=[]
    if deviation>0.0001: failures.append(f'Exterior coverage deviation {deviation}')
    for ob,row in pieces:
        if row['boundary_edges'] or row['nonmanifold_edges']: failures.append(f"{row['name']} is not closed")
        if row['kind']=='metal':
            spans=[bounds[1]-bounds[0] for bounds in row['bounds_local_godot']]
            if max(spans)>0.36 or row['convex_volume_m3']>0.0015:
                failures.append(f"{row['name']} contains oversized/disconnected metal geometry")
    boss=next(row for _,row in pieces if row['name']=='ShieldFragment_029_metal')
    boss_spans=[bounds[1]-bounds[0] for bounds in boss['bounds_local_godot']]
    if max(boss_spans)>0.20 or boss['convex_volume_m3']>0.001:
        failures.append('Central boss convex hull covers geometry outside its local 20cm envelope')
    (STAGE/'build_diagnostics.json').write_text(json.dumps({'failures':failures,'fragments':[r for _,r in pieces]},indent=2)+'\n')
    if failures: bpy.ops.wm.save_as_mainfile(filepath=str(STAGE/'diagnostic_fragments.blend'))
    assert not failures,failures
    root['source_sha256']=before[SOURCE]
    root['fragment_count']=len(pieces)
    bpy.context.scene['description']='Reassemblable low-shield fragments; source exterior preserved.'
    bpy.ops.wm.save_as_mainfile(filepath=str(BLEND))
    bpy.ops.export_scene.gltf(filepath=str(OUT),export_format='GLB',export_yup=True,
        export_animations=False,export_extras=True,export_materials='EXPORT')
    assert all(sha(path)==digest for path,digest in before.items())
    report={'host':'MacBook','blender_version':bpy.app.version_string,
        'source':str(SOURCE.relative_to(ROOT)),'source_sha256':before[SOURCE],
        'output':str(OUT.relative_to(ROOT)),'output_sha256':sha(OUT),'output_bytes':OUT.stat().st_size,
        'fragment_count':len(pieces),'count_by_kind':{k:sum(r['kind']==k for _,r in pieces) for k in ['wood','metal','leather']},
        'original_open_sheets_given_inward_0_8mm_backing':originals_closed,
        'original_exterior_max_distance_m':deviation,
        'original_high_medium_low_preserved':True,
        'rim_classification':'Actual vertex-radius distribution, not component centroid; centre boss remains within 20cm envelope.',
        'rear_mount_hardware_attached_to_original_planks':sum(len(v) for v in wood_hardware.values()),
        'metal_collision_bounds_verified':True,
        'coordinate_contract':'Each mesh is centered; identity rotation/scale; translation restores the source shield. Godot basis is (Blender X, Z, -Y).',
        'fracture_material':'FP_ShieldFractureOak',
        'shader_contract':'Pass the original shield-local mesh transform as wood_coordinates to preserve procedural grain.',
        'runtime_validation':'Pending parent integration and Godot renderer/physics checks.',
        'failures':failures,'fragments':[r for _,r in pieces]}
    (STAGE/'manifest.json').write_text(json.dumps(report,indent=2)+'\n')
    print('SHIELD FRAGMENTS BUILD PASS',json.dumps({k:v for k,v in report.items() if k!='fragments'}))

main()
