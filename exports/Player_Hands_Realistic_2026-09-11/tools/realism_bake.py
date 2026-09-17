"""Non-overlapping priority UV atlas and single-surface Cycles PBR baking."""
import math
from array import array
from pathlib import Path
import bpy
from mathutils import Vector
from realism_surface import color

def node(nodes,kind,name=None):
 n=nodes.new(kind)
 if name:n.name=name
 return n

def procedural_materials(scene):
 result={}
 for material in bpy.data.materials:
  if material.name not in ('Detailed_Skin','Detailed_Glove','Detailed_Sleeve','Detailed_Nail','Detailed_Trim'):continue
  material.use_nodes=True;nodes=material.node_tree.nodes;nodes.clear();links=material.node_tree.links
  output=node(nodes,'ShaderNodeOutputMaterial');bsdf=node(nodes,'ShaderNodeBsdfPrincipled');links.new(bsdf.outputs['BSDF'],output.inputs['Surface'])
  bsdf.inputs['Metallic'].default_value=0;bsdf.inputs['IOR'].default_value=1.45;bsdf.inputs['Specular IOR Level'].default_value=.32
  coord=node(nodes,'ShaderNodeNewGeometry');pigment=node(nodes,'ShaderNodeAttribute');pigment.attribute_name='RealismPigment';mask=node(nodes,'ShaderNodeAttribute');mask.attribute_name='RealismMasks';sep=node(nodes,'ShaderNodeSeparateColor');links.new(mask.outputs['Color'],sep.inputs['Color'])
  noise=node(nodes,'ShaderNodeTexNoise');noise.inputs['Scale'].default_value=115;noise.inputs['Detail'].default_value=2.4;noise.inputs['Roughness'].default_value=.62;links.new(coord.outputs['Position'],noise.inputs['Vector'])
  grain=node(nodes,'ShaderNodeTexNoise');grain.inputs['Scale'].default_value=2200;grain.inputs['Detail'].default_value=2;grain.inputs['Roughness'].default_value=.55;links.new(coord.outputs['Position'],grain.inputs['Vector'])
  tint=node(nodes,'ShaderNodeMixRGB');tint.blend_type='MULTIPLY';tint.inputs[0].default_value=1
  variation=node(nodes,'ShaderNodeMapRange');variation.inputs['From Min'].default_value=0;variation.inputs['From Max'].default_value=1;variation.inputs['To Min'].default_value=.91;variation.inputs['To Max'].default_value=1.08;links.new(noise.outputs['Fac'],variation.inputs['Value']);links.new(variation.outputs['Result'],tint.inputs[2])
  if material.name in ('Detailed_Skin','Detailed_Nail'):links.new(pigment.outputs['Color'],tint.inputs[1])
  else:
   palette={'Detailed_Glove':(.092,.068,.050),'Detailed_Sleeve':(.143,.126,.105),'Detailed_Trim':(.205,.163,.106)}
   tint.inputs[1].default_value=color(palette[material.name])
   if material.name=='Detailed_Sleeve':
    sleeve=node(nodes,'ShaderNodeMixRGB');sleeve.inputs[1].default_value=color((.143,.126,.105));sleeve.inputs[2].default_value=color((.088,.066,.049));links.new(sep.outputs['Blue'],sleeve.inputs[0]);links.new(sleeve.outputs[0],tint.inputs[1])
  links.new(tint.outputs[0],bsdf.inputs['Base Color'])
  rough=node(nodes,'ShaderNodeMapRange');ranges={'Detailed_Skin':(.49,.64),'Detailed_Nail':(.29,.40),'Detailed_Glove':(.60,.77),'Detailed_Sleeve':(.64,.86),'Detailed_Trim':(.61,.77)};lo,hi=ranges[material.name];rough.inputs['To Min'].default_value=lo;rough.inputs['To Max'].default_value=hi;links.new(noise.outputs['Fac'],rough.inputs['Value']);links.new(rough.outputs['Result'],bsdf.inputs['Roughness'])
  height=node(nodes,'ShaderNodeMath');height.operation='MULTIPLY';height.inputs[1].default_value=.13 if material.name=='Detailed_Skin'else .24;links.new(grain.outputs['Fac'],height.inputs[0])
  bump=node(nodes,'ShaderNodeBump');bump.inputs['Strength'].default_value=.55;bump.inputs['Distance'].default_value=.00024 if material.name=='Detailed_Skin'else .00030
  if material.name=='Detailed_Skin':
   def operation(kind,*args):
    n=node(nodes,'ShaderNodeMath');n.operation=kind
    for index,value in enumerate(args):
     if isinstance(value,(float,int)):n.inputs[index].default_value=value
     else:links.new(value,n.inputs[index])
    return n.outputs[0]
   dorsal=node(nodes,'ShaderNodeAttribute');dorsal.attribute_name='RealismDorsal';dot=node(nodes,'ShaderNodeVectorMath');dot.operation='DOT_PRODUCT';links.new(dorsal.outputs['Vector'],dot.inputs[0]);links.new(coord.outputs['Normal'],dot.inputs[1])
   outer=operation('MAXIMUM',dot.outputs['Value'],0.);inner=operation('MAXIMUM',operation('MULTIPLY',dot.outputs['Value'],-1.),0.)
   facing=operation('ADD',operation('MULTIPLY',outer,.80),operation('MULTIPLY',inner,1.05))
   full=operation('MULTIPLY',grain.outputs['Fac'],.000023)
   jitter=node(nodes,'ShaderNodeTexNoise');jitter.inputs['Scale'].default_value=560.;jitter.inputs['Detail'].default_value=1.;links.new(coord.outputs['Position'],jitter.inputs['Vector']);jittervalue=operation('MULTIPLY',operation('SUBTRACT',jitter.outputs['Fac'],.5),.00019)
   for number in (1,2):
    attribute=node(nodes,'ShaderNodeAttribute');attribute.attribute_name='RealismJoint'+str(number);xyz=node(nodes,'ShaderNodeSeparateXYZ');links.new(attribute.outputs['Vector'],xyz.inputs[0]);u=xyz.outputs['X'];v=xyz.outputs['Y']
    curve=operation('MULTIPLY',operation('POWER',operation('DIVIDE',u,.011),2.),.0013)
    arc=operation('ADD',operation('ADD',v,curve),jittervalue)
    gate=operation('EXPONENT',operation('MULTIPLY',operation('POWER',operation('DIVIDE',operation('ABSOLUTE',u),.0105),6.),-1.))
    for offset,width,depth in ((-.0022,.00030,.000075),(0.,.00038,.00012),(.0021,.00025,.000060)):
     normalized=operation('DIVIDE',operation('SUBTRACT',arc,offset),width)
     line=operation('EXPONENT',operation('MULTIPLY',operation('POWER',normalized,2.),-1.))
     term=operation('MULTIPLY',operation('MULTIPLY',operation('MULTIPLY',line,gate),facing),-depth)
     full=operation('ADD',full,term)
   links.new(full,bump.inputs['Height']);bump.inputs['Distance'].default_value=1.;bump.inputs['Strength'].default_value=.85

  else:links.new(height.outputs[0],bump.inputs['Height'])
  if material.name=='Detailed_Nail':bump.inputs['Distance'].default_value=.000035;bump.inputs['Strength'].default_value=.30
  links.new(bump.outputs['Normal'],bsdf.inputs['Normal'])
  emission=node(nodes,'ShaderNodeEmission','BakeEmission');image=node(nodes,'ShaderNodeTexImage','BakeTarget');result[material.name]=(material,bsdf,output,emission,image,tint.outputs[0],rough.outputs['Result'])
 return result

def unwrap(objects):
 stats={}
 for obj in objects:
  bpy.ops.object.select_all(action='DESELECT');obj.select_set(True);bpy.context.view_layer.objects.active=obj
  # The original UV layers overlap, include negative values and have missing
  # nail/detail coordinates. Replace only UV data; no geometric operations.
  for layer in list(obj.data.uv_layers):obj.data.uv_layers.remove(layer)
  obj.data.uv_layers.new(name='RealismUV');bpy.ops.object.mode_set(mode='EDIT');bpy.ops.mesh.select_all(action='SELECT')
  bpy.ops.uv.smart_project(angle_limit=math.radians(65),island_margin=.015,area_weight=.10,correct_aspect=True,scale_to_bounds=True)
  bpy.ops.object.mode_set(mode='OBJECT')
  priority=10.0 if 'Anatomical' in obj.name else (.15 if 'Nail_'in obj.name else(.8 if'WristCuff'in obj.name else(.45 if'UpperArm'in obj.name else 1.0)))
  uv=obj.data.uv_layers.active.data;current_area=0.
  for polygon in obj.data.polygons:
   coords=[uv[i].uv for i in polygon.loop_indices];current_area+=abs(sum(coords[i].x*coords[(i+1)%len(coords)].y-coords[(i+1)%len(coords)].x*coords[i].y for i in range(len(coords)))*.5)
  multiplier=math.sqrt(priority/max(current_area,1e-12))
  for loop in uv:loop.uv*=multiplier
  stats[obj.name]={'uv_name':'RealismUV','priority_scale':priority,'loop_count':len(obj.data.loops)}
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
 scene.render.engine='CYCLES';scene.cycles.device='CPU';scene.cycles.samples=4;scene.render.bake.margin=2;scene.render.bake.use_clear=True;scene.render.bake.use_selected_to_active=False;scene.render.bake.normal_space='TANGENT'
 for mode,filename in [('basecolor','realistic_hands_basecolor.png'),('roughness','realistic_hands_roughness.png'),('normal','realistic_hands_normal.png')]:
  image=bpy.data.images.new(filename.removesuffix('.png'),width=4096,height=4096,alpha=False,float_buffer=False)
  image.colorspace_settings.name='sRGB'if mode=='basecolor'else'Non-Color';image.generated_color=(.5,.5,1,1)if mode=='normal'else(0,0,0,1)
  for material,bsdf,out,emission,target,base,rough in materials.values():
   target.image=image;material.node_tree.nodes.active=target
   for n in material.node_tree.nodes:n.select=n==target
   if mode=='normal':material.node_tree.links.new(bsdf.outputs['BSDF'],out.inputs['Surface'])
   else:
    material.node_tree.links.new(base if mode=='basecolor'else rough,emission.inputs['Color']);material.node_tree.links.new(emission.outputs[0],out.inputs['Surface'])
  bpy.ops.object.bake(type='NORMAL'if mode=='normal'else'EMIT',use_clear=True,margin=2)
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
    normal=node(nodes,'ShaderNodeNormalMap');normal.inputs['Strength'].default_value=1.;normal.uv_map='RealismUV';links.new(tex.outputs['Color'],normal.inputs['Color']);links.new(normal.outputs['Normal'],p.inputs['Normal'])
   else:links.new(tex.outputs['Color'],p.inputs['Base Color'if key=='basecolor'else'Roughness'])
  material.diffuse_color=color((.565,.392,.291))if material.name=='Detailed_Skin'else color((.1,.075,.055))
 # Pixel maps now contain these fields; remove exportable vertex tint to avoid
 # the engine multiplying pigment into the baked albedo a second time.
 for obj in objects:
  for name in ('RealismPigment','RealismMasks','RealismJoint1','RealismJoint2','RealismDorsal'):
   layer=obj.data.attributes.get(name)
   if layer:obj.data.attributes.remove(layer)
 return stats
