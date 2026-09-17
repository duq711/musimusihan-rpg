"""Export the ImageGen-guided production sword/shield with baked vertex AO.

Atlas pixels are the original ImageGen output. This builder maps its four
material fields onto actual surfaces; it never projects concept silhouettes.
"""
from pathlib import Path
import sys, math, json
import bpy, bmesh
from mathutils import Vector
from mathutils.bvhtree import BVHTree

HERE=Path(__file__).resolve().parent
ROOT=HERE.parents[1]
sys.path.insert(0,str(HERE))
from sword_geometry import build_sword_v2
from shield_geometry import build_shield_v2

legacy=ROOT/'asset-staging/sword_shield_first_person/build_assets.py'
api={'__file__':str(legacy),'__name__':'multiview_asset_helpers'}
helper_source=legacy.read_text().split('reports=[build_hand')[0]
helper_source=helper_source.replace("export_image_format='NONE')", "export_image_format='NONE',export_vertex_color='NAME',export_vertex_color_name='AmbientOcclusion',export_all_vertex_colors=False)")
exec(compile(helper_source,str(legacy),'exec'),api)
original_export=api['export']
reports=[]

def bake_and_export(root,filename):
    # Convert actual stitches/edges before UV mapping and AO. Preserve parent
    # contact markers, blade ownership, and discrete smithing surfaces.
    for obj in list(root.children_recursive):
        if obj.type=='CURVE':
            bpy.ops.object.select_all(action='DESELECT');obj.select_set(True);bpy.context.view_layer.objects.active=obj;bpy.ops.object.convert(target='MESH')
    bpy.context.view_layer.update()
    objects=[o for o in root.children_recursive if o.type=='MESH']
    # Triangulate the separately retained blade and grip as well as furniture.
    # Explicit material use makes glTF export the AO attribute as COLOR_0.
    for obj in objects:
        bm=bmesh.new();bm.from_mesh(obj.data)
        bmesh.ops.triangulate(bm,faces=list(bm.faces))
        bm.to_mesh(obj.data);bm.free();obj.data.update()
        for mat in obj.data.materials:
            if not mat.use_nodes: mat.use_nodes=True
            node=mat.node_tree.nodes.get('BakedContactAO')
            if node is None:
                node=mat.node_tree.nodes.new('ShaderNodeVertexColor')
                node.name='BakedContactAO';node.layer_name='AmbientOcclusion'
            mat.node_tree.links.new(node.outputs['Color'],mat.node_tree.nodes.get('Principled BSDF').inputs['Base Color'])
    vertices=[];polygons=[]
    for obj in objects:
        start=len(vertices);vertices.extend(obj.matrix_world@v.co for v in obj.data.vertices)
        polygons.extend(tuple(start+i for i in p.vertices) for p in obj.data.polygons)
    bvh=BVHTree.FromPolygons(vertices,polygons,all_triangles=False)
    samples=128;golden=math.pi*(3-math.sqrt(5));total=0
    for obj in objects:
        data=obj.data
        if not data.uv_layers: data.uv_layers.new(name='UVMap')
        uv=data.uv_layers.active
        # Curves without UVs use stable local surface coordinates. All genuine
        # wrapped mesh UVs are retained and mapped to the selected quadrant.
        us=[p.uv.x for p in uv.data];vs=[p.uv.y for p in uv.data]
        u0,u1=min(us,default=0),max(us,default=1);v0,v1=min(vs,default=0),max(vs,default=1)
        ao=[]
        normal_matrix=obj.matrix_world.to_3x3().inverted().transposed()
        for vertex in data.vertices:
            normal=(normal_matrix@vertex.normal).normalized()
            tangent=normal.cross(Vector((0,0,1)) if abs(normal.z)<.9 else Vector((0,1,0))).normalized()
            bitangent=normal.cross(tangent)
            origin=obj.matrix_world@vertex.co+normal*.00045;occlusion=0.
            for index in range(samples):
                z=math.sqrt((index+.5)/samples);r=math.sqrt(1-z*z);a=golden*index
                direction=tangent*(r*math.cos(a))+bitangent*(r*math.sin(a))+normal*z
                hit,_,_,distance=bvh.ray_cast(origin,direction,.13)
                if hit is not None:occlusion+=(1-distance/.13)**1.5
            ao.append(max(.22,1-.82*occlusion/samples))
        colors=data.color_attributes.new(name='AmbientOcclusion',type='FLOAT_COLOR',domain='CORNER')
        data.color_attributes.active_color=colors
        for face in data.polygons:
            name=data.materials[face.material_index].name
            if 'Oak' in name: quadrant=(0,0)
            elif any(n in name for n in ['Leather','Enarmes','Stitch']):quadrant=(.5,0)
            elif 'Iron' in name:quadrant=(.5,.5)
            else:quadrant=(0,.5)
            for li in face.loop_indices:
                # Blender UV origin is lower left, matching atlas banks here.
                p=uv.data[li].uv
                # Authored board strips share one coherent grain scale. Only
                # normalize genuinely repeating curve UVs, never each board.
                u=p.x if u0>=0 and u1<=1 else (p.x-u0)/max(.0001,u1-u0)
                v=p.y if v0>=0 and v1<=1 else (p.y-v0)/max(.0001,v1-v0)
                p.x=quadrant[0]+.015+min(1,max(0,u))*.47;p.y=quadrant[1]+.015+min(1,max(0,v))*.47
                a=ao[data.loops[li].vertex_index];colors.data[li].color=(a,a,a,1)
        total+=len(data.vertices)
    result=original_export(root,filename)
    result.update(reference='sword_views_v2.png' if 'longsword' in filename else 'shield_views_v1.png',ambient_occlusion=f'{samples} cosine-weighted hemisphere rays per real vertex, 13 cm range',ao_vertices=total,atlas='weapon_material_atlas_v2.png')
    return result

api['export']=bake_and_export
reports=[build_sword_v2(api),build_shield_v2(api)]
bpy.ops.wm.save_as_mainfile(filepath=str(HERE/'sword_shield_multiview.blend'))
(HERE/'build_report.json').write_text(json.dumps(reports,indent=2))
print('MULTIVIEW ASSET BUILD PASS',json.dumps(reports))
