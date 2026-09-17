import bpy,json,sys
from pathlib import Path
base=Path(__file__).resolve().parents[1]
records=[]
for asset in ['wooden_barrels_01','treasure_chest','wooden_crate_02','wooden_crate_01']:
 path=base/'sources'/asset/(asset+'_4k.blend')
 bpy.ops.wm.open_mainfile(filepath=str(path),load_ui=False,use_scripts=False)
 rec={'asset':asset,'unit_scale':bpy.context.scene.unit_settings.scale_length,'objects':[],'materials':[],'images':[]}
 for o in bpy.data.objects:
  rec['objects'].append({'name':o.name,'type':o.type,'location':list(o.location),'dimensions':list(o.dimensions),'rotation':list(o.rotation_euler),'parent':o.parent.name if o.parent else None,'vertices':len(o.data.vertices) if o.type=='MESH' else None,'polygons':len(o.data.polygons) if o.type=='MESH' else None,'modifiers':[(m.type,m.name) for m in o.modifiers],'materials':[s.material.name if s.material else None for s in o.material_slots]})
 for m in bpy.data.materials:
  rec['materials'].append({'name':m.name,'nodes':[{'name':n.name,'type':n.type,'image':n.image.name if n.type=='TEX_IMAGE' and n.image else None} for n in m.node_tree.nodes] if m.use_nodes else []})
 rec['images']=[{'name':i.name,'path':i.filepath,'size':list(i.size),'colorspace':i.colorspace_settings.name} for i in bpy.data.images]
 records.append(rec)
(base/'source_inspection.json').write_text(json.dumps(records,indent=2))
print(json.dumps(records,indent=2))
