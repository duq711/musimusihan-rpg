"""Author full leather gloves from the approved rig; bake and export in background."""
import argparse, hashlib, json, math, sys
from pathlib import Path
import bpy
from mathutils import Vector
from mathutils.kdtree import KDTree
sys.path.insert(0, str(Path(__file__).resolve().parent))
from reference_export import descendants, bone_signature, export_native

DIGITS = ('thumb','index','middle','ring','little')
MAPS = ('basecolor','roughness','normal')

def sha(p): return hashlib.sha256(Path(p).read_bytes()).hexdigest()

def collect(scene):
    result={}
    for side in ('left','right'):
        holder=scene.objects[side.upper()+'_PreviewTranslationOnly']; objects=descendants(holder)
        result[side]={'holder':holder,'objects':objects,
          'rig':next(o for o in objects if o.type=='ARMATURE'),
          'skin':next(o for o in objects if o.type=='MESH' and 'Anatomical' in o.name)}
    return result

def invariant(h):
    ob=h['skin'];m=ob.data
    data={'bones':bone_signature(h['rig']), 'polys':[list(p.vertices) for p in m.polygons],
      'uv':[[list(x.uv) for x in layer.data] for layer in m.uv_layers],
      'weights':[[(g.group,g.weight) for g in v.groups] for v in m.vertices],
      'groups':[g.name for g in ob.vertex_groups], 'keys':[k.name for k in m.shape_keys.key_blocks],
      'transforms':{o.name:[list(r) for r in o.matrix_basis] for o in h['objects'] if 'Nail_' not in o.name}}
    return hashlib.sha256(json.dumps(data,sort_keys=True).encode()).hexdigest()

def cover_hand(h):
    ob=h['skin'];m=ob.data;rig=h['rig']; before=[v.co.copy() for v in m.vertices]
    groups={g.index:g.name for g in ob.vertex_groups}
    owners=[]
    for v in m.vertices:
        w={d:sum(g.weight for g in v.groups if groups[g.group].startswith(d)) for d in DIGITS}
        d=max(w,key=w.get);owners.append((d,w[d]))
    eligible=set(); protected=set()
    for p in m.polygons:
        (eligible if m.materials[p.material_index].name=='Detailed_Skin' else protected).update(p.vertices)
    eligible-=protected
    # The source stores coincident UV/material seam vertices separately. Keep
    # their new positions identical, or smoothing opens a slit at the thumb.
    tree=KDTree(12036)
    for i,p in enumerate(before[:12036]):tree.insert(p,i)
    tree.balance();seam_groups=[];seen=set()
    for i in range(12036):
        if i in seen:continue
        group={j for _,j,_ in tree.find_range(before[i],.000001)}
        seen.update(group)
        if len(group)>1:
            seam_groups.append(group)
            if any(j not in eligible for j in group):eligible.difference_update(group)
    neighbors=[set() for v in before]
    for e in m.edges:
        a,b=e.vertices;neighbors[a].add(b);neighbors[b].add(a)
    points=[p.copy() for p in before]
    # A supple 0.45 mm shell softens the existing naked-finger creases.
    for unused in range(3):
        new=[p.copy() for p in points]
        for i in eligible:
            if i>=12036 or not neighbors[i]:continue
            avg=sum((points[j] for j in neighbors[i]),Vector())/len(neighbors[i])
            new[i]=points[i].lerp(avg,.22)
        for group in seam_groups:
            if group.issubset(eligible):
                avg=sum((new[j] for j in group),Vector())/len(group)
                for j in group:new[j]=avg.copy()
        points=new
    normals=[Vector() for v in before]
    for p in m.polygons:
        if max(p.vertices)>=12036:continue
        a=points[p.vertices[0]]
        for j in range(1,len(p.vertices)-1):
            n=(points[p.vertices[j]]-a).cross(points[p.vertices[j+1]]-a)
            for i in (p.vertices[0],p.vertices[j],p.vertices[j+1]):normals[i]+=n
    for group in seam_groups:
        normal=sum((normals[j] for j in group),Vector()).normalized()
        for j in group:normals[j]=normal.copy()
    for i in eligible:
        if i<12036:points[i]+=normals[i].normalized()*.00045
    delta=[a-b for a,b in zip(points,before)]
    for key in m.shape_keys.key_blocks:
        for i in eligible:key.data[i].co+=delta[i]
    for i in eligible:m.vertices[i].co=points[i]
    # Regenerate corner normals on the authored glove, retaining topology and UVs.
    if m.has_custom_normals:m.normals_split_custom_set([(0,0,0)]*len(m.loops))
    m.update()
    inv=ob.matrix_world.inverted();frames={}
    for d in DIGITS:
        bm=inv@rig.matrix_world@rig.data.bones[d+'1'].matrix_local
        axis=bm.to_3x3().col[1].normalized();dorsal=bm.to_3x3().col[2].normalized()
        nail=next(o for o in h['objects'] if o.type=='MESH' and 'Nail_'+d in o.name)
        # Thumb's approved axial orientation is read from the actual nail surface.
        if d=='thumb':
            normal=Vector()
            for p in nail.data.polygons:
                if p.center.z>0:normal+=(inv.to_3x3()@nail.matrix_world.to_3x3()@p.normal)*p.area
            if normal.length>1e-6:dorsal=normal.normalized()
        dorsal=(dorsal-axis*dorsal.dot(axis)).normalized();cross=axis.cross(dorsal).normalized()
        subset=[points[i] for i,(digit,w) in enumerate(owners[:12036]) if digit==d and w>.8]
        origin=bm.translation.copy()
        for v in (cross,dorsal):
            values=sorted((p-origin).dot(v) for p in subset)
            origin+=v*(values[3]+values[-4])*.5
        frames[d]=(origin,axis,dorsal,cross)
    attr=m.attributes.get('GlovePanel') or m.attributes.new('GlovePanel','FLOAT_VECTOR','POINT')
    for i,p in enumerate(points):
        d,w=owners[i];o,axis,dorsal,cross=frames[d];q=p-o
        attr.data[i].vector=(q.dot(axis),q.dot(dorsal),w)
    removed=[]
    for nail in list(h['objects']):
        if nail.type=='MESH' and 'Nail_' in nail.name:
            removed.append(nail.name);bpy.data.objects.remove(nail,do_unlink=True)
    h['objects']=descendants(h['holder'])
    return {'removed_nails':removed,'finger_padding_m':.00045,'modified_vertices':len(eligible),
      'maximum_vertex_displacement_m':max(d.length for d in delta),
      'vertices':len(m.vertices),'corrective_keys':len(m.shape_keys.key_blocks)-1}

class Graph:
    def __init__(self,mat):
        self.mat=mat;self.nodes=mat.node_tree.nodes;self.links=mat.node_tree.links;self.nodes.clear()
    def n(self,kind):return self.nodes.new(kind)
    def link(self,v,s):
        if isinstance(v,bpy.types.NodeSocket):self.links.new(v,s)
        else:s.default_value=v
    def math(self,op,a,b=0):
        n=self.n('ShaderNodeMath');n.operation=op;self.link(a,n.inputs[0]);self.link(b,n.inputs[1]);return n.outputs[0]
    def mix(self,f,a,b):
        n=self.n('ShaderNodeMixRGB');self.link(f,n.inputs[0]);self.link(a,n.inputs[1]);self.link(b,n.inputs[2]);return n.outputs[0]
    def noise(self,coord,scale,detail=2):
        n=self.n('ShaderNodeTexNoise');self.link(coord,n.inputs['Vector']);n.inputs['Scale'].default_value=scale;n.inputs['Detail'].default_value=detail;return n.outputs['Fac']

def procedural(role):
    mat=bpy.data.materials.new('Bake_'+role);mat.use_nodes=True;g=Graph(mat)
    tex=g.n('ShaderNodeTexCoord');coord=tex.outputs['Object']
    coarse=g.noise(coord,35,3);grain=g.noise(coord,2400,2);fine=g.noise(coord,6500,1)
    is_sleeve=role=='Detailed_Sleeve';is_trim=role=='Detailed_Trim'
    if is_sleeve:a,b=(.021,.020,.018,1),(.035,.033,.029,1)
    elif is_trim:a,b=(.095,.051,.020,1),(.16,.094,.041,1)
    elif role=='Detailed_Glove_Fingers':a,b=(.023,.011,.005,1),(.058,.026,.010,1)
    else:a,b=(.022,.010,.004,1),(.052,.023,.009,1)
    base=g.mix(coarse,a,b)
    rough=g.math('ADD',.69 if not is_sleeve else .82,g.math('MULTIPLY',grain,.18 if not is_sleeve else .10))
    height=g.math('ADD',g.math('MULTIPLY',grain,.68),g.math('MULTIPLY',fine,.32))
    bump=g.n('ShaderNodeBump');g.link(height,bump.inputs['Height']);bump.inputs['Strength'].default_value=.40;bump.inputs['Distance'].default_value=.00012 if not is_sleeve else .000065
    bsdf=g.n('ShaderNodeBsdfPrincipled');g.link(base,bsdf.inputs['Base Color']);g.link(rough,bsdf.inputs['Roughness']);g.link(bump.outputs['Normal'],bsdf.inputs['Normal']);bsdf.inputs['Specular IOR Level'].default_value=.27
    out=g.n('ShaderNodeOutputMaterial');g.link(bsdf.outputs[0],out.inputs[0]);emission=g.n('ShaderNodeEmission');target=g.n('ShaderNodeTexImage')
    return {'material':mat,'basecolor':base,'roughness':rough,'bsdf':bsdf,'output':out,'emission':emission,'target':target}

def bake_surface(scene,hands,records):
    verts=[];faces=[];uv=[];normals=[];roles=[];fields=[]
    pairs=[(h,obj) for h in hands.values() for obj in h['objects']]
    for hand,obj in pairs:
        if obj.type!='MESH':continue
        mesh=obj.data;start=len(verts);matrix=hand['holder'].matrix_world.inverted()@obj.matrix_world
        verts.extend(matrix@v.co for v in mesh.vertices)
        attr=mesh.attributes.get('GlovePanel');fields.extend([tuple(a.vector) for a in attr.data] if attr else [(0,1,0)]*len(mesh.vertices))
        nm=matrix.to_3x3().inverted().transposed()
        for p in mesh.polygons:
            role=mesh.materials[p.material_index].name
            faces.append([start+i for i in p.vertices]);roles.append(role)
            uv.extend(tuple(mesh.uv_layers.active.data[i].uv) for i in p.loop_indices)
            normals.extend((nm@mesh.corner_normals[i].vector).normalized() for i in p.loop_indices)
    mesh=bpy.data.meshes.new('Glove_Bake_Mesh');mesh.from_pydata(verts,[],faces);mesh.update()
    layer=mesh.uv_layers.new(name='RealismUV')
    for a,v in zip(layer.data,uv):a.uv=v
    at=mesh.attributes.new('GlovePanel','FLOAT_VECTOR','POINT')
    for a,v in zip(at.data,fields):a.vector=v
    names=list(records)
    for role in names:mesh.materials.append(records[role]['material'])
    for p,role in zip(mesh.polygons,roles):p.material_index=names.index(role);p.use_smooth=True
    mesh.normals_split_custom_set(normals)
    obj=bpy.data.objects.new('Glove_Bake_Surface',mesh);scene.collection.objects.link(obj)
    bpy.ops.object.select_all(action='DESELECT');obj.select_set(True);bpy.context.view_layer.objects.active=obj
    return obj

def bake(scene,hands,out,resolution,samples):
    roles=('Detailed_Glove_Fingers','Detailed_Glove','Detailed_Trim','Detailed_Sleeve')
    originals={r:bpy.data.materials[r] for r in roles}
    images={m:originals[roles[0]].node_tree.nodes['Baked_'+m].image for m in MAPS}
    records={r:procedural(r) for r in roles};surface=bake_surface(scene,hands,records)
    scene.render.engine='CYCLES';scene.cycles.device='CPU';scene.cycles.samples=samples
    scene.render.bake.use_selected_to_active=False;scene.render.bake.normal_space='TANGENT';scene.render.bake.margin=8
    result={};packed={}
    for mode in MAPS:
        target=images[mode].copy();target.name='MercenaryGlove_'+mode
        target.colorspace_settings.name='sRGB' if mode=='basecolor' else 'Non-Color'
        for r in records.values():
            nodes=r['material'].node_tree.nodes;links=r['material'].node_tree.links
            r['target'].image=target;nodes.active=r['target']
            for n in nodes:n.select=n==r['target']
            if mode=='normal':links.new(r['bsdf'].outputs[0],r['output'].inputs[0])
            else:
                links.new(r[mode],r['emission'].inputs['Color']);links.new(r['emission'].outputs[0],r['output'].inputs[0])
        print('GLOVE_BAKE_START',mode,flush=True)
        bpy.ops.object.bake(type='NORMAL' if mode=='normal' else 'EMIT',use_clear=False,margin=8)
        path=out/('realistic_hands_'+mode+'.png');target.filepath_raw=str(path);target.file_format='PNG';target.save()
        fresh=bpy.data.images.load(str(path),check_existing=False);fresh.name='MercenaryGlove_Packed_'+mode
        fresh.colorspace_settings.name=target.colorspace_settings.name;fresh.pack()
        assert hashlib.sha256(fresh.packed_file.data).hexdigest()==sha(path)
        packed[mode]=fresh;result[mode]={'file':path.name,'sha256':sha(path),'size':list(fresh.size),'packed_bytes_verified':True}
        for r in records.values():r['target'].image=None
        bpy.data.images.remove(target)
        print('GLOVE_BAKE_COMPLETE',mode,flush=True)
    for role,mat in originals.items():
        g=Graph(mat);bsdf=g.n('ShaderNodeBsdfPrincipled');bsdf.inputs['Specular IOR Level'].default_value=.27
        outnode=g.n('ShaderNodeOutputMaterial');g.link(bsdf.outputs[0],outnode.inputs[0])
        for mode,im in packed.items():
            node=g.n('ShaderNodeTexImage');node.name='Baked_'+mode;node.image=im
            if mode=='normal':
                nm=g.n('ShaderNodeNormalMap');g.link(node.outputs['Color'],nm.inputs['Color']);g.link(nm.outputs[0],bsdf.inputs['Normal'])
            else:g.link(node.outputs['Color'],bsdf.inputs['Base Color' if mode=='basecolor' else 'Roughness'])
    mesh=surface.data;bpy.data.objects.remove(surface,do_unlink=True);bpy.data.meshes.remove(mesh)
    for r in records.values():bpy.data.materials.remove(r['material'],do_unlink=True)
    return result

def main():
    p=argparse.ArgumentParser();p.add_argument('--source',type=Path,required=True);p.add_argument('--output-dir',type=Path,required=True)
    p.add_argument('--bake-samples',type=int,default=2);a=p.parse_args(sys.argv[sys.argv.index('--')+1:])
    assert bpy.app.background;source=a.source.resolve();out=a.output_dir.resolve();out.mkdir(parents=True,exist_ok=False)
    source_sha=sha(source);bpy.ops.wm.open_mainfile(filepath=str(source));scene=bpy.data.scenes['Bilateral_Realistic_Review'];bpy.context.window.scene=scene
    hands=collect(scene);before={s:invariant(h) for s,h in hands.items()}
    report={'source':str(source),'source_sha256':source_sha,'style':'Plain full-finger dark brown mercenary leather gloves; matte grain, reinforced palm/back, modest stitching.','hands':{s:cover_hand(h) for s,h in hands.items()}}
    bpy.data.materials['Detailed_Skin'].name='Detailed_Glove_Fingers'
    after={s:invariant(h) for s,h in hands.items()};assert before==after,'Rig, UV, topology, weights or transforms changed'
    report['protected_payload_sha256']=after
    report['maps']=bake(scene,hands,out,4096,a.bake_samples)
    for side,h in hands.items():report['hands'][side]['export']=export_native(scene,h['objects'],h['holder'],out/(side+'_mercenary_glove.glb'))
    # Keep the saved source clean and the former nail material out of production.
    mat=bpy.data.materials.get('Detailed_Nail')
    if mat and mat.users==0:bpy.data.materials.remove(mat)
    for o in scene.objects:o.select_set(False)
    bpy.context.preferences.filepaths.save_version=0
    blend=out/'bilateral_mercenary_gloves.blend';bpy.ops.wm.save_as_mainfile(filepath=str(blend),check_existing=False,relative_remap=False)
    assert sha(source)==source_sha;report['blend_sha256']=sha(blend)
    (out/'build_report.json').write_text(json.dumps(report,indent=2));print('MERCENARY_GLOVES_BUILD_COMPLETE',out,flush=True)

if __name__=='__main__':main()
