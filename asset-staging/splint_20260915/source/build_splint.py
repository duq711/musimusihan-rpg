import bpy, math, random
from pathlib import Path
from mathutils import Vector
random.seed(15)
ROOT = Path(__file__).resolve().parents[3]
OUT = ROOT / 'asset-staging/splint_20260915/output'
GAME = ROOT / 'godot-game/assets/3d/items/splint'
bpy.ops.object.select_all(action='SELECT'); bpy.ops.object.delete(use_global=False)
def pos(p): return (p[0], -p[2], p[1])
def mat(name, color, roughness, metal=0):
    m=bpy.data.materials.new(name); m.diffuse_color=(*color,1); m.use_nodes=True
    bs=m.node_tree.nodes.get('Principled BSDF'); bs.inputs['Base Color'].default_value=(*color,1); bs.inputs['Roughness'].default_value=roughness; bs.inputs['Metallic'].default_value=metal
    if not metal:
        # Packed procedural albedo is exported to GLB, including linen weave.
        n=256; pixels=[]; rng=random.Random(name)
        for y in range(n):
            for x in range(n):
                if 'linen' in name.lower() or 'stitches' in name.lower():
                    v=.78+.13*math.sin(x*math.pi/2)*math.sin(y*math.pi/2)+rng.random()*.15
                elif 'oak' in name.lower():
                    v=.75+.14*math.sin(x*.4+math.sin(y*.03)*1.8)+rng.random()*.12
                else: v=.78+rng.random()*.25
                pixels.extend([min(1,c*v) for c in color]+[1])
        im=bpy.data.images.new(name+' grain',width=n,height=n); im.pixels.foreach_set(pixels); im.pack()
        tex=m.node_tree.nodes.new('ShaderNodeTexImage'); tex.image=im; m.node_tree.links.new(tex.outputs['Color'],bs.inputs['Base Color'])
    return m
wood=mat('Aged oak',(.23,.135,.055),.88)
grain=mat('Split wood grain',(.085,.045,.016),.95)
linen=mat('Unbleached linen',(.54,.48,.36),1)
seam=mat('Linen stitches',(.72,.65,.49),1)
leather=mat('Worn brown leather',(.115,.047,.021),.82)
iron=mat('Forged iron',(.095,.088,.075),.43,.78)
def cube(name,p,s,m,parent=None,bevel=.001):
    bpy.ops.mesh.primitive_cube_add(size=1,location=pos(p)); o=bpy.context.object; o.name=name; o.dimensions=(s[0],s[2],s[1]); bpy.ops.object.transform_apply(location=False,rotation=False,scale=True); o.data.materials.append(m)
    if bevel:
        mod=o.modifiers.new('Soft worn edges','BEVEL'); mod.width=bevel; mod.segments=2
        bpy.context.view_layer.objects.active=o; bpy.ops.object.modifier_apply(modifier=mod.name)
    if parent: o.parent=parent
    return o
def band(name,z,width,radius,start,end,m,parent=None):
    vs=[]; fs=[]; n=64
    for i in range(n+1):
        a=start+(end-start)*i/n
        for r,d in [(radius,-width/2),(radius,width/2),(radius+.0025,-width/2),(radius+.0025,width/2)]:
            vs.append(pos((math.sin(a)*r,math.cos(a)*r,z+d)))
    for i in range(n):
        k=i*4
        for a,b,c,d in [(0,4,5,1),(2,3,7,6),(0,2,6,4),(1,5,7,3)]: fs.append((k+a,k+b,k+c,k+d))
    fs.extend([(0,1,3,2),(n*4,n*4+2,n*4+3,n*4+1)])
    mesh=bpy.data.meshes.new(name); mesh.from_pydata(vs,[],fs); mesh.materials.append(m)
    uv=mesh.uv_layers.new(name='Weave UV')
    for polygon in mesh.polygons:
        for li in polygon.loop_indices:
            vi=mesh.loops[li].vertex_index; uv.data[li].uv=(float(vi//4)/n, (vi%4)%2)
    o=bpy.data.objects.new(name,mesh); bpy.context.collection.objects.link(o)
    for poly in mesh.polygons: poly.use_smooth=True
    if parent:o.parent=parent
    return o
root=bpy.data.objects.new('Splint',None); bpy.context.collection.objects.link(root)
for x in [-.080,.080]:
    for offset in [-.012,.012]:
        cube('Oak support rail',(x+offset,-.027,.182),(.021,.015,.274),wood,root,.002)
        for i in range(12):
            cube('Longitudinal grain',(x+offset+random.uniform(-.009,.009),-.0189,random.uniform(.08,.28)),(.0005,.0004,random.uniform(.015,.06)),grain,root,.0001)
band('Padded linen cradle',.182,.257,.081,.14,math.tau-.14,linen,root)
for z in [.061,.304]:band('Hem seam',z,.002,.084,.14,math.tau-.14,seam,root)
for i,z in enumerate([.275,.18,.085]):
    group=bpy.data.objects.new('Strap_%d'%i,None); bpy.context.collection.objects.link(group); group.parent=root
    band('Leather belt %d'%i,z,.026,.089,0,math.tau,leather,group)
    for x in [-.016,.016]:cube('Buckle side',(x,.094,z),(.004,.005,.037),iron,group)
    for dz in [-.018,.018]:cube('Buckle bar',(0,.094,z+dz),(.035,.005,.004),iron,group)
    cube('Buckle tongue',(0,.098,z),(.003,.003,.030),iron,group)
    cube('Pull tab',(.039,.092,z),(.062,.004,.022),leather,group)
    for x in [.026,.039,.052,.065]:cube('Punched hole',(x,.095,z),(.002,.001,.004),grain,group,.0005)
    for x in [-.071,.071]:cube('Rail rivet',(x,-.014,z),(.006,.004,.006),iron,group,.002)
    # glTF contains reusable tightening actions as well as the editable source.
    for f,s in [(1,1.45),(round((2.8+i*1.1)*30),1.45),(round((3.6+i*1.1)*30),1),(240,1)]:
        group.scale=(s,1,s); group.keyframe_insert(data_path='scale',frame=f)
    group.animation_data.action.name='Tighten_%d'%i
bpy.context.scene.frame_end=240; bpy.context.scene.render.fps=30; bpy.context.scene.frame_set(240)
bpy.ops.wm.save_as_mainfile(filepath=str(OUT/'wood_linen_splint.blend'))
bpy.ops.export_scene.gltf(filepath=str(GAME/'wood_linen_splint.glb'),export_format='GLB',export_animations=True)
print('SPLINT_ASSET_PASS',len(bpy.data.objects),'objects',sum(len(o.data.polygons) for o in bpy.data.objects if o.type=='MESH'),'polygons')
