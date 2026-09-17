import bpy, math, random, platform
from pathlib import Path
ROOT=Path(__file__).resolve().parents[3]
OUT=ROOT/'asset-staging/splint_wrap_20260915/output'
GAME=ROOT/'godot-game/assets/3d/items/splint'
print('BUILD_HOST',platform.node(),platform.system(),bpy.app.version_string)
bpy.ops.object.select_all(action='SELECT'); bpy.ops.object.delete(use_global=False)
random.seed(31037)
mat=bpy.data.materials.new('Dry split ash wood'); mat.use_nodes=True
bs=mat.node_tree.nodes.get('Principled BSDF'); bs.inputs['Roughness'].default_value=.92
n=512; pixels=[]
for y in range(n):
    for x in range(n):
        grain=math.sin(x*.34+math.sin(y*.025)*1.8)*.05+math.sin(x*1.31+y*.006)*.023
        tone=.57+grain+random.uniform(-.017,.017)
        pixels.extend((tone,tone*.77,tone*.49,1))
im=bpy.data.images.new('Longitudinal wood grain',width=n,height=n); im.pixels.foreach_set(pixels); im.pack()
tex=mat.node_tree.nodes.new('ShaderNodeTexImage'); tex.image=im; mat.node_tree.links.new(tex.outputs['Color'],bs.inputs['Base Color'])
# 32 cm long, 4.4 cm wide, 1.2 cm thick: one simple flattened wooden stick.
bpy.ops.mesh.primitive_cube_add(size=1)
stick=bpy.context.object; stick.name='WoodSupport'
stick.dimensions=(.044,.32,.012); bpy.ops.object.transform_apply(location=False,rotation=False,scale=True)
bevel=stick.modifiers.new('Soft chipped edges','BEVEL'); bevel.width=.0025; bevel.segments=3
bpy.ops.object.modifier_apply(modifier=bevel.name)
for v in stick.data.vertices:
    v.co.x+=random.uniform(-.0005,.0005); v.co.z+=random.uniform(-.00025,.00025)
stick.data.materials.append(mat)
uv=stick.data.uv_layers.active
for poly in stick.data.polygons:
    for li in poly.loop_indices:
        co=stick.data.vertices[stick.data.loops[li].vertex_index].co
        uv.data[li].uv=(co.x/.044+.5,-co.y/.32+.5)
bpy.ops.wm.save_as_mainfile(filepath=str(OUT/'wood_support.blend'))
bpy.ops.export_scene.gltf(filepath=str(GAME/'wood_support.glb'),export_format='GLB',export_animations=False)
print('WOOD_SUPPORT_PASS',len(stick.data.vertices),len(stick.data.polygons))
