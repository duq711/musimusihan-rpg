import bpy,json
from mathutils import Vector
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.fbx(filepath='/Users/duq711gmail.com/Downloads/animation fbx/ork@idle1.fbx')
r={'objects':[],'actions':[]}
for o in bpy.data.objects:
 d={'name':o.name,'type':o.type,'location':list(o.location),'scale':list(o.scale),'dimensions':list(o.dimensions),'parent':o.parent.name if o.parent else None,'parent_bone':o.parent_bone}
 if o.type=='MESH':d.update(verts=len(o.data.vertices),materials=[m.name if m else None for m in o.data.materials],groups=[g.name for g in o.vertex_groups],modifiers=[(m.type,m.object.name if m.type=='ARMATURE' and m.object else None) for m in o.modifiers])
 if o.type=='ARMATURE':d['bones']=[{'name':b.name,'head':list(b.head_local),'tail':list(b.tail_local),'parent':b.parent.name if b.parent else None} for b in o.data.bones]
 r['objects'].append(d)
for a in bpy.data.actions:r['actions'].append({'name':a.name,'range':list(a.frame_range),'slots':[s.identifier for s in a.slots]})
r['fps']=bpy.context.scene.render.fps
open('asset-staging/orc_20260917/inspect.json','w').write(json.dumps(r,indent=2))
bpy.ops.wm.save_as_mainfile(filepath=bpy.path.abspath('//asset-staging/orc_20260917/inspect.blend'))
