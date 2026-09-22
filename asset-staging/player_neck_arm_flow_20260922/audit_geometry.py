"""Independent comparison of the localized neck/arm revision with the sturdy source.

Run with Blender -b --python audit_geometry.py. The builder is not imported.
Only geometry_audit.json is written; this does not replace visual review.
"""
from pathlib import Path
import bpy, hashlib, json, math, struct
from statistics import mean
from mathutils import Vector
from mathutils.bvhtree import BVHTree

HERE = Path(__file__).resolve().parent
SOURCE = HERE.parent/'player_sturdy_neck_shoulders_20260922/Gravebound_Sturdy_Neck_Shoulders.blend'
RESULT = HERE/'Gravebound_Neck_Arm_Flow.blend'
SOURCE_GLB = SOURCE.with_name('gravebound_player_sturdy_neck_shoulders.glb')
RESULT_GLB = HERE/'gravebound_player_neck_arm_flow.glb'
HEAD = 'Gravebound_AnatomicalHead'
TORSO = 'Gravebound_QuiltedTorso'
ARMS = ['Gravebound_FP_'+side+'_Arm' for side in ['L','R']]
GARMENT = [TORSO]+ARMS
TARGETS = [HEAD]+GARMENT
failures = []
def check(value, message):
    if not value: failures.append(message)
def sha(path): return hashlib.sha256(path.read_bytes()).hexdigest()
def digest(value): return hashlib.sha256(json.dumps(value,sort_keys=True).encode()).hexdigest()
def snapshot(path):
    bpy.ops.wm.open_mainfile(filepath=str(path))
    rows = {}
    for obj in bpy.context.scene.objects:
        if obj.type != 'MESH': continue
        mesh = obj.data; mesh.calc_loop_triangles()
        local = {
            'vertices':[list(v.co) for v in mesh.vertices],
            'faces':[list(f.vertices) for f in mesh.polygons],
            'face_materials':[f.material_index for f in mesh.polygons],
            'smooth':[f.use_smooth for f in mesh.polygons],
            'uv':[[list(u.uv) for u in layer.data] for layer in mesh.uv_layers],
            'uv_names':[layer.name for layer in mesh.uv_layers],
            'uv_render':[layer.active_render for layer in mesh.uv_layers],
            'materials':[m.name if m else None for m in mesh.materials],
            'normals':[list(n.vector) for n in mesh.corner_normals],
        }
        normal_matrix = obj.matrix_world.to_3x3().inverted().transposed()
        normals = {}
        for loop, n in zip(mesh.loops, local['normals']):
            normals.setdefault(loop.vertex_index, list((normal_matrix@Vector(n)).normalized()))
        rows[obj.name] = {
            'local':local, 'local_hash':digest(local),
            'world_matrix':[list(row) for row in obj.matrix_world],
            'vertices':[list(obj.matrix_world@v.co) for v in mesh.vertices],
            'triangles':[list(t.vertices) for t in mesh.loop_triangles],
            'loop_vertices':[loop.vertex_index for loop in mesh.loops],
            'face_loops':[list(face.loop_indices) for face in mesh.polygons],
            'normals':normals,
        }
    return rows

def glb_data(path):
    data = path.read_bytes(); length = struct.unpack_from('<I',data,12)[0]
    doc=json.loads(data[20:20+length]); blob=data[28+length:]
    def accessor(index):
        a=doc['accessors'][index]; view=doc['bufferViews'][a['bufferView']]
        n={'SCALAR':1,'VEC2':2,'VEC3':3,'VEC4':4}[a['type']]
        size=n*{5120:1,5121:1,5122:2,5123:2,5125:4,5126:4}[a['componentType']]
        start=view.get('byteOffset',0)+a.get('byteOffset',0); stride=view.get('byteStride',size)
        packed=b''.join(blob[start+i*stride:start+i*stride+size] for i in range(a['count']))
        return [a['count'],a['type'],a['componentType'],hashlib.sha256(packed).hexdigest()]
    def values(index):
        a=doc['accessors'][index]; view=doc['bufferViews'][a['bufferView']]
        n={'SCALAR':1,'VEC2':2,'VEC3':3,'VEC4':4}[a['type']]
        fmt={5123:'H',5125:'I',5126:'f'}[a['componentType']]
        size=n*struct.calcsize(fmt); start=view.get('byteOffset',0)+a.get('byteOffset',0)
        stride=view.get('byteStride',size)
        return [struct.unpack_from('<'+fmt*n,blob,start+i*stride) for i in range(a['count'])]
    meshes={}; non_tangent_meshes={}; tangents={}; normal_tangent_alignment={}

    for node in doc['nodes']:
        if 'mesh' not in node: continue
        parts=[]
        for p in doc['meshes'][node['mesh']]['primitives']:
            parts.append({'attributes':{k:accessor(i) for k,i in p['attributes'].items()},'indices':accessor(p['indices']),'material':doc['materials'][p['material']].get('name')})
        meshes[node['name']]=digest(parts)
        non_tangent_meshes[node['name']]=digest([{**p,'attributes':{k:v for k,v in p['attributes'].items() if k!='TANGENT'}} for p in parts])
        vectors=[]
        for p in doc['meshes'][node['mesh']]['primitives']:
            if 'TANGENT' not in p['attributes']: continue
            a=doc['accessors'][p['attributes']['TANGENT']]; view=doc['bufferViews'][a['bufferView']]
            start=view.get('byteOffset',0)+a.get('byteOffset',0); stride=view.get('byteStride',16)
            vectors.extend(struct.unpack_from('<4f',blob,start+i*stride) for i in range(a['count']))
        tangents[node['name']]=vectors
        for primitive in doc['meshes'][node['mesh']]['primitives']:
            material=doc['materials'][primitive['material']]
            if not material.get('name','').startswith('Gravebound_Sleeve_Flow_'): continue
            attrs=primitive['attributes']
            uv_name='TEXCOORD_'+str(material.get('normalTexture',{}).get('texCoord',0))
            if uv_name not in attrs or 'TANGENT' not in attrs: continue
            positions=values(attrs['POSITION']); normals=values(attrs['NORMAL'])
            uv=values(attrs[uv_name]); tangent=values(attrs['TANGENT'])
            indices=[v[0] for v in values(primitive['indices'])]; dots=[]
            for k in range(0,len(indices),3):
                a,b,c=indices[k:k+3]
                ab=Vector(positions[b])-Vector(positions[a]); ac=Vector(positions[c])-Vector(positions[a])
                u=Vector(uv[b])-Vector(uv[a]); v=Vector(uv[c])-Vector(uv[a])
                det=u.x*v.y-u.y*v.x
                if abs(det)<1e-12: continue
                deriv=(v.y*ab-u.y*ac)/det; normal=Vector(normals[a])
                deriv=deriv-normal*deriv.dot(normal)
                if deriv.length<1e-12: continue
                dots.append(deriv.normalized().dot(Vector(tangent[a][:3])))
            normal_tangent_alignment[material['name']]={'normal_uv_attribute':uv_name,'sampled_triangles':len(dots),'mean_direction_dot':mean(dots) if dots else None,'fraction_direction_dot_above_0_95':sum(d>.95 for d in dots)/len(dots) if dots else None}
    images=[]

    for im in doc.get('images',[]):
        if 'bufferView' not in im: continue
        view=doc['bufferViews'][im['bufferView']]; start=view.get('byteOffset',0)
        images.append(hashlib.sha256(blob[start:start+view['byteLength']]).hexdigest())
    def texture(index):
        t=doc['textures'][index]
        image_hash=images[t['source']]
        sampler=doc.get('samplers',[])[t['sampler']] if 'sampler' in t else {}
        return {'image_sha256':image_hash,'sampler':sampler}
    def canonical(value,parent_key=''):
        if isinstance(value,dict):
            row={k:canonical(v,k) for k,v in value.items()}
            if parent_key.endswith('Texture') and 'index' in value:
                row['index']=texture(value['index'])
            return row
        if isinstance(value,list): return [canonical(v,parent_key) for v in value]
        return value
    materials={m['name']:canonical(m) for m in doc.get('materials',[])}
    return {'meshes':meshes,'non_tangent_meshes':non_tangent_meshes,'tangents':tangents,'normal_tangent_alignment':normal_tangent_alignment,'image_hashes':sorted(images),'materials':materials}


def tree_for(snapshot,names):
    vertices=[]; faces=[]
    for name in names:
        row=snapshot[name]; off=len(vertices)
        vertices.extend(Vector(v) for v in row['vertices'])
        faces.extend([off+i for i in f] for f in row['triangles'])
    return BVHTree.FromPolygons(vertices,faces,all_triangles=True)

def max_displacement(a,b,indices):
    return max(((Vector(b[i])-Vector(a[i])).length for i in indices),default=0.)

source=snapshot(SOURCE); result=snapshot(RESULT)
check(set(source)==set(result) and len(result)==20,'Mesh inventory changed')
preserved=sorted(set(source)-set(TARGETS)); check(len(preserved)==16,'Expected sixteen preserved meshes')
for name in preserved:
    check(source[name]['local_hash']==result[name]['local_hash'],name+': mesh data changed')
    check(source[name]['world_matrix']==result[name]['world_matrix'],name+': transform changed')
for name in TARGETS:
    a,b=source[name],result[name]
    check(a['world_matrix']==b['world_matrix'],name+': transform changed')
    check(len(a['vertices'])==len(b['vertices']),name+': vertex count changed')
    for key in ['faces','smooth']:
        check(a['local'][key]==b['local'][key],name+': '+key+' changed')
    if name not in ARMS:
        for key in ['face_materials','materials','uv','uv_names','uv_render']:
            check(a['local'][key]==b['local'][key],name+': '+key+' changed')


head_regions={}
for label,predicate in [('face_and_scalp_at_or_above_1_51m',lambda p:p[2]>=1.51),('neck_base_at_or_below_1_445m',lambda p:p[2]<=1.445)]:
    indices=[i for i,p in enumerate(source[HEAD]['vertices']) if predicate(p)]
    error=max_displacement(source[HEAD]['vertices'],result[HEAD]['vertices'],indices)
    check(bool(indices) and error<1e-7,label+': geometry changed')
    head_regions[label]={'vertex_count':len(indices),'maximum_displacement_m':error}
head_moved=[(Vector(q)-Vector(p)).length for p,q in zip(source[HEAD]['vertices'],result[HEAD]['vertices'])]
check(.001<max(head_moved)<.004,'Neck adjustment outside subtle 1-4mm envelope')

garment_regions={}
for name in GARMENT:
    a,b=source[name],result[name]
    indices=[i for i,p in enumerate(a['vertices']) if p[2]<=1.275]
    error=max_displacement(a['vertices'],b['vertices'],indices)
    check(error<1e-7,name+': lower garment/arm shape changed')
    normal_error=max(((Vector(a['normals'][i])-Vector(b['normals'][i])).length for i in indices),default=0.)
    garment_regions[name]={'protected_vertex_count':len(indices),'maximum_displacement_below_1_275m':error,'maximum_normal_difference_below_1_275m':normal_error,'maximum_total_displacement_m':max_displacement(a['vertices'],b['vertices'],range(len(a['vertices'])))}
    check(garment_regions[name]['maximum_total_displacement_m']<.009,name+': adjustment exceeds 9mm localized envelope')

uv_preservation={}
baked_sleeves={}
for name in ARMS:
    a,b=source[name],result[name]
    old_layers=len(a['local']['uv'])
    check(b['local']['uv_names']==a['local']['uv_names']+['SleeveBlendBake'],name+': unexpected UV layers')
    check(b['local']['uv'][:old_layers]==a['local']['uv'],name+': original UV layers changed')
    check(b['local']['uv_render']==[False]*old_layers+[True],name+': baked UV is not active for tangent export')
    side='L' if '_L_' in name else 'R'
    new_material='Gravebound_Sleeve_Flow_'+side
    check(b['local']['materials']==a['local']['materials']+[new_material],name+': material slots changed outside bake addition')
    source_slot=a['local']['materials'].index('Gravebound_Matched_Sleeve_Cloth')
    new_slot=len(a['local']['materials'])
    selected=[]; unselected=[]
    for fi,(face,source_material,result_material) in enumerate(zip(a['local']['faces'],a['local']['face_materials'],b['local']['face_materials'])):
        allowed=source_material==source_slot and max(a['vertices'][i][2] for i in face)>1.18
        check(result_material==(new_slot if allowed else source_material),name+': material reassignment outside authorized upper cloth faces '+str(fi))
        (selected if allowed else unselected).append(fi)
    check(bool(selected) and bool(unselected),name+': missing selected or preserved sleeve faces')
    original_layer=a['local']['uv_names'].index('UVMap')
    new_layer=b['local']['uv_names'].index('SleeveBlendBake')
    corners=[li for fi in unselected for li in a['face_loops'][fi]]
    error=max(((Vector(a['local']['uv'][original_layer][li])-Vector(b['local']['uv'][new_layer][li])).length for li in corners),default=0.)
    check(error<1e-8,name+': bake UV changed on unselected sleeve/skin faces')
    uv_preservation[name]={'original_layers_all_corners_exact':b['local']['uv'][:old_layers]==a['local']['uv'],'unselected_face_count':len(unselected),'unselected_corner_count':len(corners),'unselected_new_uv_maximum_error':error,'baked_uv_active_for_tangent_export':b['local']['uv_render']==[False]*old_layers+[True]}
    baked_sleeves[name]={'new_material':new_material,'new_uv':'SleeveBlendBake','new_material_face_count':len(selected),'lowest_selected_vertex_z_m':min(a['vertices'][vi][2] for fi in selected for vi in a['local']['faces'][fi]),'selection_rule':'Source matched-cloth faces with at least one vertex above 1.18m; crossing boundary faces are included.'}

seams={}
for name in ARMS:
    a=source[TORSO]; arm=source[name]
    lookup={tuple(round(v,6) for v in p):i for i,p in enumerate(a['vertices']) if p[2]>1.30}
    pairs=[(lookup[key],i) for i,p in enumerate(arm['vertices']) if p[2]>1.30 and (key:=tuple(round(v,6) for v in p)) in lookup]
    check(len(pairs)>=150,name+': original seam not located')
    gaps=[(Vector(result[TORSO]['vertices'][i])-Vector(result[name]['vertices'][j])).length for i,j in pairs]
    dots=[Vector(result[TORSO]['normals'][i]).dot(Vector(result[name]['normals'][j])) for i,j in pairs]
    seams[name]={'shared_pairs':len(pairs),'maximum_gap_m':max(gaps),'minimum_normal_dot':min(dots)}
    check(max(gaps)<1e-6,name+': shoulder join separates')
    check(min(dots)>.995,name+': shoulder join has a shading break')

trees={label:tree_for(data,GARMENT) for label,data in [('source',source),('result',result)]}
profile=[]
for z in [1.30,1.33,1.36,1.39]:
    for side in [-1,1]:
        for direction in [-1,1]:
            values={}
            for label,tree in trees.items():
                points=[]
                for x in [.18,.185,.19,.193,.195,.20,.21,.22,.23,.24,.25,.26,.27]:
                    hit,*_=tree.ray_cast(Vector((side*x,direction,z)),Vector((0,-direction,0)),2.)
                    if hit: points.append((x,direction*(hit.y-.002)))
                root=min(v for x,v in points if .18<=x<=.20)
                cap=max(v for x,v in points if .21<=x<=.27)
                values[label]={'root_depth_m':root,'cap_depth_m':cap,'cap_minus_root_m':cap-root}
            decrease=values['source']['cap_minus_root_m']-values['result']['cap_minus_root_m']
            check(decrease>0.,'Shoulder valley did not become shallower at '+str((z,side,direction)))
            profile.append({'height_m':z,'body_side':side,'front_back_ray':direction,**values,'valley_reduction_m':decrease})

armpits=[]
for side in [-1,1]:
    for z in [1.24,1.25,1.26,1.27]:
        for x in [.19,.195,.20]:
            hits={label:tree.ray_cast(Vector((side*x,-1,z)),Vector((0,1,0)),2.)[0] for label,tree in trees.items()}
            if hits['source'] is None:
                check(hits['result'] is None,'Existing armpit opening filled at '+str((side*x,z)))
                armpits.append({'x_m':side*x,'z_m':z,'source_open':True,'result_open':hits['result'] is None})
check(len(armpits)>=12,'Insufficient armpit clearance samples')

torso=tree_for(result,[TORSO]);neck_probes=[]
for x,y in [(0,.007)]+[(math.cos(i*math.tau/8)*r,.007+math.sin(i*math.tau/8)*r) for r in [.035,.050] for i in range(8)]:
    hit,*_=torso.ray_cast(Vector((x,y,1.55)),Vector((0,0,-1)),.3)
    check(hit is not None and hit.z<1.445,'Torso intrudes into neck interior')
    neck_probes.append({'x_m':x,'y_m':y,'floor_z_m':hit.z if hit else None})

glb_source=glb_data(SOURCE_GLB);glb_result=glb_data(RESULT_GLB)
exported_tangents={}
for name in preserved:
    check(glb_source['non_tangent_meshes'][name]==glb_result['non_tangent_meshes'][name],name+': exported position/normal/UV/index/material data changed')
    a,b=glb_source['tangents'][name],glb_result['tangents'][name]
    check(len(a)==len(b),name+': exported tangent count changed')
    difference=max((max(abs(x-y) for x,y in zip(p,q)) for p,q in zip(a,b)),default=0.)
    check(difference<.00011,name+': exported tangent change exceeds exporter rounding tolerance')
    exported_tangents[name]={'vector_count':len(a),'different_vectors':sum(p!=q for p,q in zip(a,b)),'maximum_component_error':difference}

source_images_retained=set(glb_source['image_hashes']).issubset(glb_result['image_hashes'])
check(source_images_retained,'An original embedded texture was removed or changed')
original_materials_retained=all(glb_result['materials'].get(name)==value for name,value in glb_source['materials'].items())
check(original_materials_retained,'An original GLB material or its image content changed')
new_material_names={'Gravebound_Sleeve_Flow_L','Gravebound_Sleeve_Flow_R'}
check(set(glb_result['materials'])-set(glb_source['materials'])==new_material_names,'Unexpected added GLB materials')
for name in new_material_names:
    material=glb_result['materials'].get(name,{})
    pbr=material.get('pbrMetallicRoughness',{})
    check(abs(pbr.get('roughnessFactor',1)-.9)<1e-6 and pbr.get('metallicFactor',1)==0,name+': baked cloth roughness/metallic changed')
    check('baseColorTexture' in pbr,name+': baked albedo is not connected')
    check('normalTexture' in material,name+': rebaked cloth normal is not connected')
    alignment=glb_result['normal_tangent_alignment'].get(name,{})
    check(alignment.get('sampled_triangles',0)>20000 and (alignment.get('mean_direction_dot') or 0)>.97 and (alignment.get('fraction_direction_dot_above_0_95') or 0)>.92,name+': exported TANGENT does not match the UV used by the rebaked normal')
    for channel,entry in [('albedo',pbr.get('baseColorTexture',{})),('normal',material.get('normalTexture',{}))]:
        check(entry.get('texCoord',0)==1,name+': '+channel+' does not address SleeveBlendBake UV channel')
        check(entry.get('index',{}).get('image_sha256') not in set(glb_source['image_hashes']),name+': '+channel+' was not rebaked')

report={'source_blend_sha256':sha(SOURCE),'result_blend_sha256':sha(RESULT),'source_glb_sha256':sha(SOURCE_GLB),'result_glb_sha256':sha(RESULT_GLB),'mesh_count':len(result),'entirely_preserved_meshes':preserved,'all_topology_preserved':True,'original_material_assignments_preserved_except_authorized_upper_sleeves':True,'baked_upper_sleeves':baked_sleeves,'head_protected_regions':head_regions,'maximum_neck_displacement_m':max(head_moved),'garment_protected_regions':garment_regions,'lower_sleeve_uv_preservation':uv_preservation,'shoulder_joins':seams,'shoulder_valley_profiles':profile,'preserved_armpit_openings':armpits,'neck_interior_probes':neck_probes,'exported_preserved_position_normal_uv_indices_match':all(glb_source['non_tangent_meshes'][n]==glb_result['non_tangent_meshes'][n] for n in preserved),'exported_recomputed_tangents':exported_tangents,'all_original_embedded_texture_bytes_retained':source_images_retained,'new_embedded_image_count':len(set(glb_result['image_hashes'])-set(glb_source['image_hashes'])),'original_material_settings_unchanged':original_materials_retained,'new_baked_material_names':sorted(new_material_names),'rebaked_normal_tangent_alignment':glb_result['normal_tangent_alignment'],'scope_note_ko':'접합부 변위는 9mm 이내이며 낮은 팔과 겨드랑이 빈 공간을 보존했습니다. 이 기하 검사는 자연스러운 외관 판정을 대신하지 않습니다.','scope_note_en':'Join changes stay below 9mm; the lower arms and armpit clearances are preserved. This geometry audit does not replace visual acceptance.','failures':failures,'pass':not failures}
(HERE/'geometry_audit.json').write_text(json.dumps(report,indent=2)+'\n')
print('INDEPENDENT NECK ARM FLOW AUDIT','PASS' if not failures else 'FAIL',json.dumps(failures),flush=True)
if failures: raise SystemExit(1)
