"""Restore original head materials/UVs on the existing projected head.

Source geometry is never linked or substituted. Exact triangle-position matching
keeps every vertex/face unchanged, including UV seams. Default mode restores
scalp only; full_head=True restores all original facial, skin and hair surfaces.
"""
from pathlib import Path
import bpy,json,hashlib,collections
from mathutils import Vector
from mathutils.kdtree import KDTree
W=Path(__file__).resolve().parent;ROOT=W.parents[1]
SOURCE=ROOT/'asset-staging/blender_mercenary_crossbowman_game_ready/mercenary_crossbowman_game_ready_v16.blend'
HAIR_NAMES={'MAT_ScalpHair_DarkBrown_PBR_2K_v11','MAT_Hair_ScalpNeutralBrown_2K_v16j','MAT_Hair_BackShellMatched_2K_v16j'}

def _geometry_signature(mesh):
    return hashlib.sha256(json.dumps({'vertices':[list(v.co) for v in mesh.vertices],'faces':[list(p.vertices) for p in mesh.polygons]},sort_keys=True).encode()).hexdigest()

def restore_scalp(full_head=False):
    head=bpy.data.objects['Gravebound_AnatomicalHead'];mesh=head.data
    before_geometry=_geometry_signature(mesh);before_uv=[tuple(v.uv) for v in mesh.uv_layers.active.data]
    before_materials=[p.material_index for p in mesh.polygons]
    with bpy.data.libraries.load(str(SOURCE),link=False) as (available,loaded):
        loaded.objects=['Mercenary_Male_HeadNeck_LOD0']
    original=loaded.objects[0];src=original.data
    assert not original.users_collection,'Source object must remain unlinked'
    positions=[]
    for vertex in src.vertices:
        co=vertex.co.copy();co.y-=.026;co.z-=.055;positions.append(co)
    kd=KDTree(len(positions))
    for index,co in enumerate(positions):kd.insert(co,index)
    kd.balance()
    canonical=[tuple(round(c,6) for c in co) for co in positions]
    by_face=collections.defaultdict(list)
    for polygon in src.polygons:by_face[tuple(sorted(canonical[i] for i in polygon.vertices))].append(polygon)
    target_keys=[];distances=[]
    for vertex in mesh.vertices:
        co,index,distance=kd.find(vertex.co);target_keys.append(canonical[index]);distances.append(distance)
    assert max(distances)<.000002,('Source head geometry does not match',max(distances))
    restored=[];unmatched=[];ambiguous=[];materials={};textures=[]
    hair_source_count=sum(src.materials[p.material_index].name in HAIR_NAMES for p in src.polygons)
    expected_count=len(src.polygons) if full_head else hair_source_count
    for polygon in mesh.polygons:
        candidates=by_face.get(tuple(sorted(target_keys[i] for i in polygon.vertices)),[])
        if not candidates:unmatched.append(polygon.index);continue
        selected=candidates if full_head else [p for p in candidates if src.materials[p.material_index].name in HAIR_NAMES]
        if not selected:continue
        if len(candidates)!=1:ambiguous.append(polygon.index);continue
        source_poly=selected[0];source_mat=src.materials[source_poly.material_index]
        if source_mat.name not in materials:
            material=source_mat.copy();material.name='Gravebound_Unhooded_'+source_mat.name.removeprefix('MAT_')
            # Give restored textures deterministic, packed data for GLB export.
            for node in material.node_tree.nodes:
                if node.type!='TEX_IMAGE' or not node.image:continue
                image=node.image.copy()
                filepath=Path(bpy.path.abspath(node.image.filepath,start=str(SOURCE.parent)))
                if not filepath.exists():filepath=SOURCE.parent/'textures'/Path(node.image.filepath).name
                assert filepath.exists(),str(filepath)
                image.filepath=str(filepath);image.reload()
                source_size=list(image.size)
                if max(source_size)>2048:
                    ratio=2048/max(source_size)
                    image.scale(round(source_size[0]*ratio),round(source_size[1]*ratio))
                image.pack();node.image=image
                textures.append({'material':material.name,'image':image.name,'source_file':str(filepath.relative_to(ROOT)),'source_sha256':hashlib.sha256(filepath.read_bytes()).hexdigest(),'source_size':source_size,'export_size':list(image.size),'packed':bool(image.packed_file)})
            # Original front/back projection shaders are unlit. Keep their
            # authored color but let the exposed head respond to game lights.
            if source_mat.name.startswith('MAT_ReferenceProjection_'):
                tree=material.node_tree
                color=next(n for n in tree.nodes if n.type=='TEX_IMAGE')
                output=next(n for n in tree.nodes if n.type=='OUTPUT_MATERIAL')
                surface=tree.nodes.new('ShaderNodeBsdfPrincipled')
                surface.inputs['Roughness'].default_value=.88
                tree.links.new(color.outputs['Color'],surface.inputs['Base Color'])
                tree.links.new(surface.outputs['BSDF'],output.inputs['Surface'])
            mesh.materials.append(material);materials[source_mat.name]=len(mesh.materials)-1
        polygon.material_index=materials[source_mat.name]
        # Per-loop transfer matters: neighboring triangles can share a vertex
        # while using different UV coordinates at an authored scalp seam.
        for loop_index in polygon.loop_indices:
            target_vertex=mesh.loops[loop_index].vertex_index;co=mesh.vertices[target_vertex].co
            source_loop=min(source_poly.loop_indices,key=lambda li:(positions[src.loops[li].vertex_index]-co).length_squared)
            assert (positions[src.loops[source_loop].vertex_index]-co).length<.000002
            mesh.uv_layers.active.data[loop_index].uv=src.uv_layers.active.data[source_loop].uv
        restored.append(polygon.index)
    assert not unmatched and not ambiguous,('Triangle mapping not exact',unmatched[:8],ambiguous[:8])
    assert len(restored)==expected_count,(len(restored),expected_count)
    restore_set=set(restored);untouched=[p for p in mesh.polygons if p.index not in restore_set]
    assert all(p.material_index==before_materials[p.index] and all(tuple(mesh.uv_layers.active.data[i].uv)==before_uv[i] for i in p.loop_indices) for p in untouched)
    assert _geometry_signature(mesh)==before_geometry
    if full_head:
        used=sorted(set(p.material_index for p in mesh.polygons))
        indices=[used.index(p.material_index) for p in mesh.polygons]
        kept=[mesh.materials[i] for i in used]
        mesh.materials.clear()
        for material in kept:mesh.materials.append(material)
        for polygon,index in zip(mesh.polygons,indices):polygon.material_index=index
    report={'source_blend_sha256':hashlib.sha256(SOURCE.read_bytes()).hexdigest(),'helper_sha256':hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),'head_vertices':len(mesh.vertices),'head_faces':len(mesh.polygons),'source_faces':len(src.polygons),'maximum_vertex_match_error_m':max(distances),'unmatched_faces':unmatched,'ambiguous_faces':ambiguous,'restoration_mode':'full_head' if full_head else 'scalp_only','restored_head_faces':len(restored),'restored_scalp_faces':hair_source_count,'source_scalp_faces':hair_source_count,'untouched_face_and_neck_faces':len(untouched),'non_scalp_uv_and_materials_unchanged':not full_head,'unrestored_faces_unchanged':True,'geometry_unchanged':True,'materials':list(materials),'textures':textures,'pass':True}
    bpy.data.objects.remove(original,do_unlink=True)
    (W/'restoration_report.json').write_text(json.dumps(report,indent=2))
    print('SCALP RESTORE PASS',json.dumps(report));return report
