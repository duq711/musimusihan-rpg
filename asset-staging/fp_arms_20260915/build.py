import bpy,struct,json,math,hashlib
from pathlib import Path
from mathutils import Matrix,Vector
ROOT=Path('/Users/duq711gmail.com/Documents/ChatGPT/무시무시한 rpg')
OUT=ROOT/'godot-game/assets/3d/player/fp_arms';OUT.mkdir(exist_ok=True)
f=open(ROOT/'asset-staging/fp_arms_20260915/fp_arms_original.glb','rb');f.read(12);n,t=struct.unpack('<II',f.read(8));d=json.loads(f.read(n));n,t=struct.unpack('<II',f.read(8));buf=f.read(n)
def acc(i):
 a=d['accessors'][i];v=d['bufferViews'][a['bufferView']];sz={'VEC2':2,'VEC3':3,'VEC4':4,'SCALAR':1,'MAT4':16}[a['type']];fmt={5126:'f',5123:'H',5125:'I'}[a['componentType']];stride=v.get('byteStride',struct.calcsize('<'+fmt*sz));off=v.get('byteOffset',0)+a.get('byteOffset',0)
 return [struct.unpack_from('<'+fmt*sz,buf,off+j*stride) for j in range(a['count'])]
pos=acc(0);norm=acc(1);uv=acc(3);indices=[x[0] for x in acc(4)];joints=acc(6);weights=acc(7);ids=d['skins'][0]['joints'];names=[d['nodes'][i]['name'] for i in ids]
bind=[Matrix([a[k:k+4] for k in range(0,16,4)]).transposed().inverted() for a in acc(5)]
parent={c:i for i,node in enumerate(d['nodes']) for c in node.get('children',[])}
bpy.ops.object.select_all(action='SELECT');bpy.ops.object.delete(use_global=False)
# Preserve source texture appearance, reducing only export resolution to 2K.
mat=bpy.data.materials.new('FP_Arms_Supplied');mat.use_nodes=True;bs=mat.node_tree.nodes.get('Principled BSDF')
for channel,imgi in [('albedo',0),('orm',1),('normal',2)]:
 image=d['images'][d['textures'][imgi]['source']];v=d['bufferViews'][image['bufferView']];path=OUT/(channel+'_source.png');path.write_bytes(buf[v.get('byteOffset',0):v.get('byteOffset',0)+v['byteLength']]);im=bpy.data.images.load(str(path));im.colorspace_settings.name='sRGB' if channel=='albedo' else 'Non-Color'
 if max(im.size)>2048:im.scale(2048,2048)
 im.filepath_raw=str(OUT/(channel+'.png'));im.file_format='PNG';im.save();path.unlink()
 node=mat.node_tree.nodes.new('ShaderNodeTexImage');node.image=im
 if channel=='albedo':mat.node_tree.links.new(node.outputs['Color'],bs.inputs['Base Color'])
 elif channel=='normal':
  normal=mat.node_tree.nodes.new('ShaderNodeNormalMap');mat.node_tree.links.new(node.outputs['Color'],normal.inputs['Color']);mat.node_tree.links.new(normal.outputs['Normal'],bs.inputs['Normal'])
 else:
  split=mat.node_tree.nodes.new('ShaderNodeSeparateColor');mat.node_tree.links.new(node.outputs['Color'],split.inputs[0]);mat.node_tree.links.new(split.outputs['Green'],bs.inputs['Roughness']);bs.inputs['Metallic'].default_value=0.0
G=Matrix(((1,0,0,0),(0,0,-1,0),(0,1,0,0),(0,0,0,1)))
meta={'source_sha256':hashlib.sha256((ROOT/'asset-staging/fp_arms_20260915/fp_arms_original.glb').read_bytes()).hexdigest(),'attribution':d['asset']['extras'],'sides':{}}
for side,sign in [('L',-1),('R',1)]:
 def idx(prefix):return next(i for i,n in enumerate(names) if n.startswith(prefix+'.'+side+'_'))
 wrist=bind[idx('hand')].translation;middle=bind[idx('middle1')].translation;index=bind[idx('point1')].translation;little=bind[idx('pink1')].translation
 z=-(middle-wrist).normalized();x=(index-little).normalized()*(-sign);y=z.cross(x).normalized();x=y.cross(z).normalized();basis=Matrix((x,y,z)).transposed();C=basis.transposed().to_4x4();C.translation=-(basis.transposed()@wrist);C=Matrix.Diagonal((.82,.82,.82,1))@C
 selected=[i for i,n in enumerate(names) if '.'+side+'_' in n and '_end_' not in n and not n.startswith(('armpole','handcontrol'))]
 rename={idx('hand'):'wrist',idx('arm'):'upper',idx('elbow'):'elbow',idx('forearm'):'forearm',idx('palm'):'palm'}
 for old,new in [('pink','little'),('ring','ring'),('middle','middle'),('point','index'),('thumb','thumb')]:
  for j in range(3):rename[idx(old+str(j+1))]=new+str(j)
 rig=bpy.data.objects.new('FP_'+side+'_Rig',bpy.data.armatures.new('FP_'+side+'_Skeleton'));bpy.context.collection.objects.link(rig);bpy.context.view_layer.objects.active=rig;rig.select_set(True);bpy.ops.object.mode_set(mode='EDIT')
 for i in selected:
  b=rig.data.edit_bones.new(rename[i]);M=G@C@bind[i];M.normalize();b.matrix=M;b.length=.02
 for i in selected:
  if rename[i] in ['wrist','upper','elbow','forearm']:continue
  pi=parent.get(ids[i]);pj=ids.index(pi) if pi in ids else -1
  if pj in selected:rig.data.edit_bones[rename[i]].parent=rig.data.edit_bones[rename[pj]]
 bpy.ops.object.mode_set(mode='OBJECT')
 # Keep original UVs, split the two actual hands (never mirror one hand).
 faces=[indices[i:i+3] for i in range(0,len(indices),3) if sum(pos[v][0] for v in indices[i:i+3])*(-sign)>0]
 sideparts=[]
 for label,arm in [('Hand',False),('Arm',True)]:
  fs=[face for face in faces if (sum((C@Vector(pos[v])).z for v in face)/3>.012)==arm];used=sorted(set(v for face in fs for v in face));remap={v:i for i,v in enumerate(used)}
  mesh=bpy.data.meshes.new('FP_'+side+'_'+label);mesh.from_pydata([G@C@Vector(pos[v]) for v in used],[],[[remap[v] for v in face] for face in fs]);mesh.update();obj=bpy.data.objects.new(mesh.name,mesh);bpy.context.collection.objects.link(obj);sideparts.append(obj);mesh.materials.append(mat)
  layer=mesh.uv_layers.new(name='UVMap')
  for loop in mesh.loops: u,v=uv[used[loop.vertex_index]];layer.data[loop.index].uv=(u,1-v)
  for p in mesh.polygons:p.use_smooth=True
  nb=(G@C).to_3x3().inverted().transposed();mesh.normals_split_custom_set_from_vertices([(nb@Vector(norm[v])).normalized() for v in used])
  for i in selected:obj.vertex_groups.new(name=rename[i])
  for ni,oi in enumerate(used):
   for j,w in zip(joints[oi],weights[oi]):
    if w>0 and j in rename:obj.vertex_groups[rename[j]].add([ni],w,'REPLACE')
  mod=obj.modifiers.new('Supplied skin weights','ARMATURE');mod.object=rig;obj.parent=rig
 data={'hand_scale':.82,'points':{},'hinges':{},'source_bones':rename}
 for key,pre in [('wrist','hand'),('elbow','elbow'),('forearm','forearm'),('shoulder','arm')]:data['points'][key]=list(C@bind[idx(pre)].translation)
 for i,new in rename.items():
  if new[-1:] in ['0','1','2']:
   axis=(C.to_3x3()@bind[i].to_3x3().col[2]).normalized()*(-sign)
   data['hinges'][new]=list(axis)
 meta['sides'][side]=data
 bpy.ops.object.select_all(action='DESELECT');rig.select_set(True)
 for o in sideparts:o.select_set(True)
 bpy.context.view_layer.objects.active=rig
 bpy.ops.export_scene.gltf(filepath=str(OUT/('left.glb' if side=='L' else 'right.glb')),use_selection=True,export_format='GLB',export_animations=False,export_skins=True,export_yup=True,export_extras=True)
 bpy.ops.object.select_all(action='DESELECT')
(OUT/'rig.json').write_text(json.dumps(meta,indent=2))
bpy.ops.wm.save_as_mainfile(filepath=str(ROOT/'asset-staging/fp_arms_20260915/Game_Arms.blend'))
print('FP ARMS BUILD PASS',meta['sides']['L']['points'])
