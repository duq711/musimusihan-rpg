"""Priority UV and real PBR baking for the photo-reference hand revision."""
import math
from array import array
from pathlib import Path
import bpy
from mathutils import Vector
from reference_materials import color,procedural_materials,ATTRIBUTE_NAMES
def node(nodes,kind,name=None):
 n=nodes.new(kind)
 if name:n.name=name
 return n

def unwrap(objects):
 stats={}
 for obj in objects:
  bpy.ops.object.select_all(action='DESELECT');obj.select_set(True);bpy.context.view_layer.objects.active=obj
  # The original UV layers overlap, include negative values and have missing
  # nail/detail coordinates. Replace only UV data; no geometric operations.
  for layer in list(obj.data.uv_layers):obj.data.uv_layers.remove(layer)
  obj.data.uv_layers.new(name='ReferenceUV');bpy.ops.object.mode_set(mode='EDIT');bpy.ops.mesh.select_all(action='SELECT')
  bpy.ops.uv.smart_project(angle_limit=math.radians(65),island_margin=.015,area_weight=.10,correct_aspect=True,scale_to_bounds=True)
  bpy.ops.object.mode_set(mode='OBJECT')
  priority=10.0 if 'Anatomical' in obj.name else (.15 if 'Nail_'in obj.name else(.8 if'WristCuff'in obj.name else(.45 if'UpperArm'in obj.name else 1.0)))
  uv=obj.data.uv_layers.active.data;current_area=0.
  for polygon in obj.data.polygons:
   coords=[uv[i].uv for i in polygon.loop_indices];current_area+=abs(sum(coords[i].x*coords[(i+1)%len(coords)].y-coords[(i+1)%len(coords)].x*coords[i].y for i in range(len(coords)))*.5)
  multiplier=math.sqrt(priority/max(current_area,1e-12))
  for loop in uv:loop.uv*=multiplier
  stats[obj.name]={'uv_name':'ReferenceUV','priority_scale':priority,'loop_count':len(obj.data.loops)}
 bpy.ops.object.select_all(action='DESELECT')
 for obj in objects:obj.select_set(True)
 bpy.context.view_layer.objects.active=objects[0];bpy.ops.object.mode_set(mode='EDIT');bpy.ops.mesh.select_all(action='SELECT')
 bpy.ops.uv.select_all(action='SELECT');bpy.ops.uv.pack_islands(rotate=True,scale=True,margin=.0012,margin_method='FRACTION',shape_method='CONCAVE')
 bpy.ops.object.mode_set(mode='OBJECT')
 for obj in objects:
  uv=obj.data.uv_layers.active.data;area=0.;bad=0
  for poly in obj.data.polygons:
   coords=[uv[i].uv for i in poly.loop_indices];v=abs(sum(coords[i].x*coords[(i+1)%len(coords)].y-coords[(i+1)%len(coords)].x*coords[i].y for i in range(len(coords)))*.5);area+=v;bad+=v<1e-12
  stats[obj.name].update({'atlas_fraction_uv_area':area,'degenerate_polygons':bad})
 return stats

def combined_copy(scene,objects):
 copies=[];bpy.ops.object.select_all(action='DESELECT')
 for obj in objects:
  copy=obj.copy();copy.data=obj.data.copy();copy.name='BakeCopy_'+obj.name;scene.collection.objects.link(copy);matrix=obj.matrix_world.copy();copy.parent=None;copy.matrix_world=matrix
  for mod in list(copy.modifiers):copy.modifiers.remove(mod)
  if copy.data.shape_keys:copy.shape_key_clear()
  copy.select_set(True);copies.append(copy)
 bpy.context.view_layer.objects.active=copies[0];bpy.ops.object.join();result=bpy.context.object;result.name='Realism_Combined_Bake_Surface'
 return result

def bake(scene,objects,output):
 materials=procedural_materials(scene);surface=combined_copy(scene,objects);images={};stats={}
 scene.render.engine='CYCLES';scene.cycles.device='CPU';scene.cycles.samples=4;scene.render.bake.margin=16;scene.render.bake.use_clear=True;scene.render.bake.use_selected_to_active=False;scene.render.bake.normal_space='TANGENT'
 for mode,filename in [('basecolor','reference_hands_basecolor.png'),('roughness','reference_hands_roughness.png'),('normal','reference_hands_normal.png')]:
  image=bpy.data.images.new(filename.removesuffix('.png'),width=4096,height=4096,alpha=False,float_buffer=False)
  image.colorspace_settings.name='sRGB'if mode=='basecolor'else'Non-Color';image.generated_color=(.5,.5,1,1)if mode=='normal'else(0,0,0,1)
  for material,bsdf,out,emission,target,base,rough in materials.values():
   target.image=image;material.node_tree.nodes.active=target
   for n in material.node_tree.nodes:n.select=n==target
   if mode=='normal':material.node_tree.links.new(bsdf.outputs['BSDF'],out.inputs['Surface'])
   else:
    material.node_tree.links.new(base if mode=='basecolor'else rough,emission.inputs['Color']);material.node_tree.links.new(emission.outputs[0],out.inputs['Surface'])
  bpy.ops.object.bake(type='NORMAL'if mode=='normal'else'EMIT',use_clear=True,margin=16)
  image.filepath_raw=str(output/filename);image.file_format='PNG';image.save();image.pack();images[mode]=image
  print('PBR_ATLAS_BAKED',mode,flush=True)
  # Sparse actual pixel statistics include RGB variation and usable nonzero pixels.
  pixels=array('f',[0.0])*len(image.pixels);image.pixels.foreach_get(pixels);sample=[tuple(pixels[i:i+3])for i in range(0,len(pixels),4*997)]
  stats[mode]={'file':filename,'resolution':[4096,4096],'colorspace':image.colorspace_settings.name,'sample_min':[min(c[k]for c in sample)for k in range(3)],'sample_max':[max(c[k]for c in sample)for k in range(3)],'packed':image.packed_file is not None}
 bpy.data.objects.remove(surface,do_unlink=True)
 for material,unused,*remaining in materials.values():
  nodes=material.node_tree.nodes;nodes.clear();links=material.node_tree.links;out=node(nodes,'ShaderNodeOutputMaterial');p=node(nodes,'ShaderNodeBsdfPrincipled');links.new(p.outputs['BSDF'],out.inputs['Surface']);p.inputs['Metallic'].default_value=0;p.inputs['IOR'].default_value=1.45;p.inputs['Specular IOR Level'].default_value=.32
  for key,image in images.items():
   tex=node(nodes,'ShaderNodeTexImage','Baked_'+key);tex.image=image;tex.interpolation='Linear'
   if key=='normal':
    normal=node(nodes,'ShaderNodeNormalMap');normal.inputs['Strength'].default_value=1.;normal.uv_map='ReferenceUV';links.new(tex.outputs['Color'],normal.inputs['Color']);links.new(normal.outputs['Normal'],p.inputs['Normal'])
   else:links.new(tex.outputs['Color'],p.inputs['Base Color'if key=='basecolor'else'Roughness'])
  material.diffuse_color=color((.72,.53,.42))if material.name=='Detailed_Skin'else color((.1,.075,.055))
 # Pixel maps now contain these fields; remove exportable vertex tint to avoid
 # the engine multiplying pigment into the baked albedo a second time.
 for obj in objects:
  for name in ATTRIBUTE_NAMES:
   layer=obj.data.attributes.get(name)
   if layer:obj.data.attributes.remove(layer)
 return stats
