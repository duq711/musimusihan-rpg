"""Build the photograph-matched sword/shield and continuous anatomical hands."""
import bpy, math, json, random
from pathlib import Path
from mathutils import Vector, Matrix

STAGE=Path(__file__).resolve().parent
ROOT=STAGE.parents[1]
OUT=ROOT/'godot-game/assets/3d/player/sword_shield'
TEX=ROOT/'asset-staging/blender_mercenary_crossbowman_photoreal/textures'
OUT.mkdir(parents=True,exist_ok=True)
RNG=random.Random(91831)
bpy.ops.wm.open_mainfile(filepath=str(STAGE/'canonical_hand.blend'))
source=bpy.data.objects['AnatomicalHand']
SOURCE_VERTS=[v.co.copy() for v in source.data.vertices]
SOURCE_FACES=[tuple(f.vertices) for f in source.data.polygons]
bpy.ops.wm.read_factory_settings(use_empty=True)

def material(name,color,rough=.6,metal=0,texture=None,normal=None,tiling=1):
    m=bpy.data.materials.new(name);m.use_nodes=True
    p=m.node_tree.nodes.get('Principled BSDF')
    p.inputs['Base Color'].default_value=(*color,1)
    p.inputs['Roughness'].default_value=rough;p.inputs['Metallic'].default_value=metal
    if texture:
        image=bpy.data.images.load(str(TEX/texture),check_existing=True)
        node=m.node_tree.nodes.new('ShaderNodeTexImage');node.image=image
        mix=m.node_tree.nodes.new('ShaderNodeMixRGB');mix.blend_type='MULTIPLY';mix.inputs[0].default_value=1;mix.inputs[2].default_value=(*color,1)
        # Keep the tint as the glTF factor; the texture connects directly.
        m.node_tree.links.new(node.outputs['Color'],p.inputs['Base Color'])
        m['runtime_tint']=list(color)
    if normal:
        node=m.node_tree.nodes.new('ShaderNodeTexImage');node.image=bpy.data.images.load(str(TEX/normal),check_existing=True);node.image.colorspace_settings.name='Non-Color'
        n=m.node_tree.nodes.new('ShaderNodeNormalMap');n.inputs['Strength'].default_value=.38
        m.node_tree.links.new(node.outputs['Color'],n.inputs['Color']);m.node_tree.links.new(n.outputs['Normal'],p.inputs['Normal'])
    m.diffuse_color=(*color,1)
    return m

SKIN=material('FP_Skin',(.48,.295,.195),.60)
LEATHER=material('FP_WornLeather',(.14,.11,.085),.58,texture='brown_leather_albedo_2k.jpg',normal='brown_leather_nor_gl_2k.jpg')
BRACER=material('FP_LayeredVambrace',(.18,.13,.09),.55)
ENARMES=material('FP_EnarmesLeather',(.14,.09,.05),.68)
EDGE=material('FP_LeatherEdge',(.095,.064,.041),.65)
LINEN=material('FP_QuiltedLinen',(.11,.10,.081),.94,texture='rough_linen_diff_2k.jpg',normal='rough_linen_nor_gl_2k.jpg')
THREAD=material('FP_WaxedThread',(.13,.103,.067),.85)
STEEL=material('FP_BrushedSteel',(.48,.51,.52),.27,.87)
DARK_STEEL=material('FP_AgedSteel',(.22,.235,.24),.38,.8)
RIM_STEEL=material('FP_RolledRimSteel',(.25,.24,.22),.30,.72)
BRASS=material('FP_WornRivets',(.29,.22,.13),.42,.73)
OAK=material('FP_WornOak',(.37,.28,.17),.88,texture='wood_table_worn_diff_2k.jpg',normal='wood_table_worn_nor_gl_2k.jpg')

def empty(name,parent=None):
    obj=bpy.data.objects.new(name,None);bpy.context.scene.collection.objects.link(obj)
    if parent:obj.parent=parent
    return obj

def mesh_obj(name,verts,faces,mat,parent=None,uvs=None,smooth=True):
    data=bpy.data.meshes.new(name+'Mesh');data.from_pydata(verts,[],faces);data.update()
    obj=bpy.data.objects.new(name,data);bpy.context.scene.collection.objects.link(obj)
    if parent:obj.parent=parent
    if mat:data.materials.append(mat)
    for face in data.polygons:face.use_smooth=smooth
    layer=data.uv_layers.new(name='UVMap')
    for face in data.polygons:
        for li in face.loop_indices:
            vi=data.loops[li].vertex_index;v=data.vertices[vi].co
            layer.data[li].uv=uvs[vi] if uvs else (v.x*5,v.y*5)
    return obj

def tube(name,centers,radii,mat,parent,segments=32,ellipses=None,uvscale=1,cap=True):
    verts=[];uvs=[];faces=[]
    for j,center in enumerate(centers):
        c=Vector(center)
        direction=Vector(centers[min(j+1,len(centers)-1)])-Vector(centers[max(j-1,0)])
        direction.normalize()
        guide=Vector((0,0,1)) if abs(direction.z)<.90 else Vector((0,1,0))
        a=direction.cross(guide).normalized();b=a.cross(direction).normalized()
        for i in range(segments+1):
            t=math.tau*i/segments
            ry=radii[j];rx=ry if not ellipses else ellipses[j]
            verts.append(c+a*(math.cos(t)*rx)+b*(math.sin(t)*ry));uvs.append((i/segments*uvscale,j/(len(centers)-1)*uvscale))
    for j in range(len(centers)-1):
        for i in range(segments):
            k=j*(segments+1)+i
            faces.append((k,k+segments+1,k+segments+2,k+1))
    if cap:
        faces.append(tuple(reversed(range(segments))))
        last=(len(centers)-1)*(segments+1);faces.append(tuple(last+i for i in range(segments)))
    return mesh_obj(name,verts,faces,mat,parent,uvs)

def sphere(name,loc,scale,mat,parent,segments=16,rings=8):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=segments,ring_count=rings,location=loc)
    obj=bpy.context.object;obj.name=name;obj.scale=scale
    bpy.ops.object.transform_apply(location=False,rotation=False,scale=True)
    obj.data.materials.append(mat);obj.parent=parent
    for f in obj.data.polygons:f.use_smooth=True
    return obj

def curve(name,points,radius,mat,parent):
    data=bpy.data.curves.new(name,'CURVE');data.dimensions='3D';data.resolution_u=1
    data.bevel_depth=radius;data.bevel_resolution=2
    spline=data.splines.new('POLY');spline.points.add(len(points)-1)
    for dst,src in zip(spline.points,points):dst.co=(*src,1)
    obj=bpy.data.objects.new(name,data);bpy.context.scene.collection.objects.link(obj);obj.parent=parent;data.materials.append(mat)
    return obj

def box(name,location,size,mat,parent,bevel=.001):
    bpy.ops.mesh.primitive_cube_add(size=1,location=location)
    obj=bpy.context.object;obj.name=name;obj.dimensions=size
    bpy.ops.object.transform_apply(location=False,rotation=False,scale=True)
    obj.data.materials.append(mat);obj.parent=parent
    if bevel:
        mod=obj.modifiers.new('Worn rounded edges','BEVEL');mod.width=bevel;mod.segments=3
        bpy.context.view_layer.objects.active=obj;bpy.ops.object.modifier_apply(modifier=mod.name)
    for f in obj.data.polygons:f.use_smooth=True
    return obj

def export(root,filename):
    # Batch static details by their actual joint parent. Anatomical skin keeps
    # its own deforming draw; sleeve/bracer still have independent elbow fit.
    for holder in [o for o in [root]+list(root.children_recursive) if o.type in {'EMPTY','ARMATURE'}]:
        parts=[c for c in holder.children if c.type in {'MESH','CURVE'} and not any(m.type=='ARMATURE' for m in c.modifiers) and c.name not in {'PittedBlade','GripLeather','GripBinding','FullerPolishedChannel'}]
        if not parts:continue
        bpy.ops.object.select_all(action='DESELECT')
        for c in parts:c.select_set(True)
        bpy.context.view_layer.objects.active=parts[0]
        bpy.ops.object.convert(target='MESH')
        bpy.ops.object.join()
        merged=bpy.context.object;merged.name=holder.name+'_Surface'
        bpy.ops.object.transform_apply(location=True,rotation=True,scale=True)
        mod=merged.modifiers.new('Stable triangulation','TRIANGULATE');bpy.ops.object.modifier_apply(modifier=mod.name)
    bpy.ops.object.select_all(action='DESELECT')
    objects=[root]+list(root.children_recursive)
    for obj in objects:obj.select_set(True)
    bpy.context.view_layer.objects.active=root
    bpy.ops.export_scene.gltf(filepath=str(OUT/filename),export_format='GLB',use_selection=True,export_apply=True,export_extras=True,export_animations=False,export_yup=True,export_skins=True,export_normals=True,export_tangents=True,export_image_format='NONE')
    return {'file':filename,'objects':len(objects),'triangles':sum(sum(len(f.vertices)-2 for f in o.data.polygons) for o in objects if o.type=='MESH')}

def cloth_segment(parent,name,start,end,wide,narrow,padded=False):
    holder=empty(name,parent);verts=[];uvs=[];faces=[];rows=65;cols=64
    for j in range(rows):
        t=j/(rows-1);y=start+(end-start)*t
        base=wide*(1-t)+narrow*t
        for i in range(cols+1):
            angle=math.tau*i/cols
            if padded:
                fold=.003*math.sin(t*math.pi*8+math.sin(angle*3))+.002*math.sin(t*math.pi*19+angle*2)
                quilting=.0018*(1-math.cos(angle*12+t*math.pi*8))*(1-math.cos(angle*12-t*math.pi*8))/4
            else:
                fold=.001*math.sin(t*41+angle*5)+.001*math.sin(t*67-angle*7)+.0022*math.cos(t*math.tau*8);quilting=0
            r=base+fold+quilting
            verts.append((math.cos(angle)*r,y,math.sin(angle)*r*.84));uvs.append((i/cols*2,t*2))
    for j in range(rows-1):
        for i in range(cols):
            a=j*(cols+1)+i;faces.append((a,a+cols+1,a+cols+2,a+1))
    mesh_obj(name+'Surface',verts,faces,LINEN if padded else BRACER,holder,uvs)
    if padded:
        for sign in [-1,1]:
            for lane in range(12):
                points=[]
                for j in range(49):
                    t=j/48;y=start+(end-start)*t;angle=lane*math.tau/12+sign*t*math.pi*2/3
                    base=wide*(1-t)+narrow*t+.001
                    fold=.003*math.sin(t*math.pi*8+math.sin(angle*3))+.002*math.sin(t*math.pi*19+angle*2)
                    r=base+fold
                    points.append((math.cos(angle)*r,y,math.sin(angle)*r*.84))
                curve('QuiltSeam',points,.00048,THREAD,holder)
    else:
        # The overlapping leather lames have real, narrow folded edges.
        # They remain distinct from the wider fastening straps and buckles.
        for panel in range(1,8):
            t=panel/8;y=start+(end-start)*t;r=wide*(1-t)+narrow*t+.0028
            points=[(math.cos(a)*r,y,math.sin(a)*r*.84) for a in [math.tau*i/96 for i in range(97)]]
            curve('LameFold',points,.0010,EDGE,holder)
        for y in [start+.030, start+.081, start+.132, start+.183, end-.025]:
            t=(y-start)/(end-start);r=wide*(1-t)+narrow*t+.0038
            for shift in [-.006,.006]:
                points=[(math.cos(a)*r,y+shift,math.sin(a)*r*.84) for a in [math.tau*i/96 for i in range(97)]]
                curve('BracerBoundEdge',points,.0012,EDGE,holder)
            tube('BracerStrap',[(0,y-.007,0),(0,y+.007,0)],[(r+.001)*.84,(r+.001)*.84],LEATHER,holder,48,[r+.001,r+.001])
            box('BracerBuckle',(r*.60,y,r*.84*.83),(.013,.015,.003),DARK_STEEL,holder,.001)
            for xsign in [-1,1]:
                sphere('BracerRivet',(xsign*r*.72,y,r*.84*.71),(.0028,.0028,.0013),BRASS,holder)
        # Long stitched borders on the visible back of the leather vambrace.
        for angle in [.95,2.19]:
            for j in range(31):
                t=.04+.92*j/31;y=start+(end-start)*t;r=wide*(1-t)+narrow*t+.0015
                points=[(math.cos(angle)*r,y+dy,math.sin(angle)*r*.84) for dy in [-.0015,.0015]]
                curve('BracerStitch',points,.00045,THREAD,holder)
    return holder

JOINTS={
 'little':[(-.043,.060),(-.059,.093),(-.067,.113),(-.074,.129)],
 'ring':[(-.023,.075),(-.026,.120),(-.027,.146),(-.028,.167)],
 'middle':[(.004,.081),(.005,.128),(.004,.156),(.005,.178)],
 'index':[(.030,.072),(.033,.115),(.035,.143),(.038,.163)],
 'thumb':[(.030,.005),(.060,.035),(.072,.063),(.081,.087)]}

def build_hand(side):
    # Canonical source has the dorsal right-hand thumb on +X. Reflect the left and
    # bind it independently so normals/bones never depend on negative scaling.
    reflection=1 if side=='right' else -1
    root=empty('SwordShieldArm_'+side)
    vertices=[Vector((v.x*reflection,v.y,v.z))*1.25 for v in SOURCE_VERTS]
    faces=SOURCE_FACES if reflection>0 else [tuple(reversed(f)) for f in SOURCE_FACES]
    skin=mesh_obj('ContinuousAnatomicalHand',vertices,faces,SKIN,root)
    armdata=bpy.data.armatures.new('HandSkeleton');rig=bpy.data.objects.new('HandRig',armdata);bpy.context.scene.collection.objects.link(rig);rig.parent=root
    bpy.context.view_layer.objects.active=rig;rig.select_set(True);bpy.ops.object.mode_set(mode='EDIT')
    wrist=armdata.edit_bones.new('wrist');wrist.head=(0,-.05625,0);wrist.tail=(0,.075,0);wrist.align_roll(Vector((0,0,1)))
    joints={}
    for finger,path in JOINTS.items():
        points=[]
        for x,y in path:
            near=[v.z for v in SOURCE_VERTS if (v.x-x)**2+(v.y-y)**2<.008**2]
            z=(min(near)+max(near))/2 if near else 0
            points.append(Vector((x*reflection,y,z))*1.25)
        joints[finger]=[list(p) for p in points]
        parent=wrist
        for i in range(3):
            bone=armdata.edit_bones.new(finger+str(i));bone.head=points[i];bone.tail=points[i+1];bone.parent=parent;bone.use_connect=i>0;bone.align_roll(Vector((0,0,1)));parent=bone
    bpy.ops.object.mode_set(mode='OBJECT')
    bpy.ops.object.select_all(action='DESELECT');skin.select_set(True);rig.select_set(True);bpy.context.view_layer.objects.active=rig
    bpy.ops.object.parent_set(type='ARMATURE_AUTO')
    unweighted=sum(not v.groups for v in skin.data.vertices)
    if unweighted:raise RuntimeError('Hand has unweighted vertices: '+str(unweighted))
    # Glove shell follows exactly the same skin weights, including the soft
    # webbing; distal fingers and nails remain exposed.
    selected_faces=[];used=set()
    bone_names={g.index:g.name for g in skin.vertex_groups}
    def covered(v):
        if v.co.y<.065:return True
        weights={bone_names[g.group]:g.weight for g in v.groups}
        finger=max(JOINTS,key=lambda n:sum(weights.get(n+str(j),0) for j in range(3)))
        start,end=joints[finger][0],joints[finger][1]
        cutoff=start[1]+(end[1]-start[1])*.43
        return v.co.y<cutoff
    for f in skin.data.polygons:
        if all(covered(skin.data.vertices[i]) for i in f.vertices):selected_faces.append(tuple(f.vertices));used.update(f.vertices)
    remap={old:new for new,old in enumerate(sorted(used))}
    glove=mesh_obj('FingerlessLeatherGlove',[skin.data.vertices[i].co+skin.data.vertices[i].normal*(.0012+.0005*math.sin(skin.data.vertices[i].co.y*220+skin.data.vertices[i].co.x*80)) for i in sorted(used)],[[remap[i] for i in f] for f in selected_faces],LEATHER,rig)
    for group in skin.vertex_groups:
        new=glove.vertex_groups.new(name=group.name)
        for old,newidx in remap.items():
            try:weight=group.weight(old)
            except RuntimeError:continue
            if weight>0:new.add([newidx],weight,'REPLACE')
    glove.data.materials.append(EDGE)
    solid=glove.modifiers.new('Bound finger openings','SOLIDIFY');solid.thickness=.0015;solid.offset=0;solid.material_offset_rim=1
    bpy.context.view_layer.objects.active=glove;bpy.ops.object.modifier_apply(modifier=solid.name)
    mod=glove.modifiers.new('Anatomical glove deformation','ARMATURE');mod.object=rig
    # The palm is under the leather shell, so the original continuous skin
    # remains available around every finger opening.
    bracer=cloth_segment(root,'Forearm',-.27,.008,.065 if side=='left' else .080,.044,False)
    sleeve=cloth_segment(root,'UpperArm',-.60,-.215,.082 if side=='left' else .094,.055 if side=='left' else .070,True)
    cuff=empty('WristCuff',root)
    tube('ClosedLeatherCuff',[(0,-.058,0),(0,-.015,0),(0,.012,0)],[.0375,.03625,.0325],LEATHER,cuff,48,[.050,.04875,.045],cap=False)
    for y,r in [(-.05,.049),(.007,.045)]:
        curve('CuffBoundEdge',[(math.cos(a)*r,y,math.sin(a)*r*.75) for a in [math.tau*i/96 for i in range(97)]],.0008,EDGE,cuff)
    root['profile']='sword_shield';root['anatomy_license']='Blender Human Base Meshes CC0 1.0';root['side']=side
    report=export(root,side+'_arm.glb')
    report.update(unweighted_vertices=unweighted,joints=joints)
    return report

def build_sword():
    root=empty('SwordsmanLongsword')
    # Blender Z becomes Godot Y; the guard origin and actual blade bounds are
    # the player's real strike geometry, not a second invisible hit shape.
    rows=[(-.010,.031,.0045),(.10,.030,.0043),(.47,.025,.0036),(.82,.017,.0028),(.965,.009,.0019),(1.035,.0002,.0003)]
    verts=[];faces=[];uvs=[]
    for z,w,t in rows:
        ring=[(-w,0),(-w*.74,-t),(-w*.28,-t*.60),(0,-t*.53),(w*.28,-t*.60),(w*.74,-t),(w,0),(w*.74,t),(w*.28,t*.60),(0,t*.53),(-w*.28,t*.60),(-w*.74,t)]
        for x,y in ring:verts.append((x,y,z));uvs.append((x/.062+.5,z))
    for j in range(len(rows)-1):
        for i in range(12):faces.append((j*12+i,j*12+(i+1)%12,(j+1)*12+(i+1)%12,(j+1)*12+i))
    faces.append(tuple(reversed(range(12))));faces.append(tuple((len(rows)-1)*12+i for i in range(12)))
    blade=mesh_obj('PittedBlade',verts,faces,STEEL,root,uvs,False)
    # This narrow polished channel remains a real material-bearing surface
    # so existing silver/steel reinforcement remains visible on crafted swords.
    channel_verts=[];channel_faces=[]
    for side in [-1,1]:
        base=len(channel_verts)
        for z,w,t in rows:
            for x in [-w*.26,w*.26]:channel_verts.append((x,side*(t*.56+.00015),z))
        for j in range(len(rows)-1):
            f=(base+j*2,base+j*2+1,base+j*2+3,base+j*2+2)
            channel_faces.append(f if side<0 else tuple(reversed(f)))
    mesh_obj('FullerPolishedChannel',channel_verts,channel_faces,STEEL,root,smooth=False)
    # Curved, rounded quillons taper toward their ends.
    centers=[];radii=[]
    for i in range(33):
        x=-.123+i*.246/32;a=abs(x)/.123
        centers.append((x,0,-.006+.021*a*a+x*.22));radii.append(.0085-.003*a)
    tube('SweptCrossguard',centers,radii,DARK_STEEL,root,12)
    sphere('GuardCollar',(0,0,-.005),(.036,.015,.013),DARK_STEEL,root,32,12)
    tube('GripLeather',[(0,0,-.015),(0,0,-.274)],[.018,.015],LEATHER,root,32,uvscale=2)
    points=[]
    for i in range(321):
        t=i/320;a=t*math.tau*18;r=.019-.003*t
        points.append((math.cos(a)*r,math.sin(a)*r,-.026-.245*t))
    curve('GripBinding',points,.0008,EDGE,root)
    # Compact wheel pommel, with a real chamfer and central peen.
    tube('FlaredPommel',[(0,0,-.270),(0,0,-.292),(0,0,-.326),(0,0,-.340)],[.015,.028,.034,.025],STEEL,root,48)
    sphere('PommelPeen',(0,0,-.343),(.007,.007,.003),DARK_STEEL,root)
    grip=empty('HandGrip',root);grip.location=(0,-.002,-.108)
    tip=empty('BladeTip',root);tip.location=(0,0,1.035)
    return export(root,'longsword.glb')

def build_shield():
    root=empty('SwordsmanRoundShield')
    radius=.415;count=9
    # Independent boards with subtle convex dish. The owner sees the back,
    # with their grip on the right and forearm strap on the left.
    for plank in range(count):
        x0=-radius+2*radius*plank/count+.0007;x1=-radius+2*radius*(plank+1)/count-.0007
        outline=[]
        for x in [x0+(x1-x0)*i/12 for i in range(13)]:outline.append((x,math.sqrt(max(0,radius*radius-x*x))))
        for x in [x1-(x1-x0)*i/12 for i in range(13)]:outline.append((x,-math.sqrt(max(0,radius*radius-x*x))))
        verts=[];uv=[]
        for depth in [-.037,.010]:
            for x,z in outline:
                dish=.016*(1-(x*x+z*z)/radius**2)
                verts.append((x,depth-dish,z));uv.append(((x-x0)*3+plank*.19,z*1.4+.5))
        n=len(outline);faces=[tuple(reversed(range(n))),tuple(n+i for i in range(n))]
        for i in range(n):faces.append((i,(i+1)%n,(i+1)%n+n,i+n))
        mesh_obj('OakBoard%02d'%plank,verts,faces,OAK,root,uv,False)
    # Thin U-shaped steel edge around the wooden rim.
    verts=[];faces=[];uv=[]
    profile=[(.397,-.043),(.423,-.043),(.427,-.037),(.427,.011),(.423,.017),(.397,.017)]
    for j in range(193):
        a=math.tau*j/192
        for profile_index,(r,y) in enumerate(profile):
            rr=r+.0006*math.sin(a*19)+.0003*math.sin(a*41)
            verts.append((math.cos(a)*rr,y,math.sin(a)*rr));uv.append((j/192*8,profile_index*.08))
    for j in range(192):
        for i in range(len(profile)-1):
            k=j*len(profile)+i;faces.append((k,k+len(profile),k+len(profile)+1,k+1))
    rim=mesh_obj('ThinRolledIronRim',verts,[tuple(reversed(f)) for f in faces],RIM_STEEL,root,uv)
    rim.data.materials.append(RIM_STEEL)
    for face in rim.data.polygons:
        if face.index%(len(profile)-1) in [1,3]:face.material_index=1
    for edge in rim.data.edges:
        if edge.vertices[0]%len(profile)==edge.vertices[1]%len(profile):edge.use_edge_sharp=True
    for index in range(36):
        a=math.tau*index/36
        for y in [-.046,.020]:
            sphere('RimRivet',(math.cos(a)*.407,y,math.sin(a)*.407),(.0048,.0020,.0048),STEEL,root,12,6)
    # Metal boss on the opponent's face only.
    sphere('FrontBoss',(0,-.070,0),(.095,.05,.095),DARK_STEEL,root,48,20)
    for name,x,center_z,width,depth,angle in [('RearGrip',.073,.032,.029,.115,28),('RearArmStrap',.228,-.0075,.050,.120,45)]:
        # Rotate the enarmes across the board grain: the grip remains upright
        # and the cuff crosses the actual forearm from shoulder to fist.
        def strap_point(u,v,d):
            t=math.radians(angle)
            arch=max(0,math.sin(math.pi*(v+.12)/.24))
            sweep_x,sweep_z=(.24,-.055) if name=='RearGrip' else (.085,.005)
            return (x+u*math.cos(t)+v*math.sin(t)-sweep_x*(1-arch),d,center_z-u*math.sin(t)+v*math.cos(t)+sweep_z*(1-arch))
        holder=empty(name,root);holder.location=strap_point(0,0,.020+depth)
        if name=='RearGrip':
            for label,v in [('Top',.08),('Bottom',-.08)]:
                anchor=empty(name+label,root);anchor.location=strap_point(0,v,.020+depth*math.sin(math.pi*(v+.12)/.24))
        verts=[];faces=[];uv=[];strap_columns=8
        for j in range(33):
            t=j/32;v=-.12+.24*t;d=.020+depth*math.sin(math.pi*t)
            rounding=min(1,.35+min(t,1-t)*14)
            for column in range(strap_columns+1):
                across=column/strap_columns
                verts.append(strap_point((across-.5)*width*rounding,v,d));uv.append((across,t*2))
        for j in range(32):
            for column in range(strap_columns):
                k=j*(strap_columns+1)+column
                faces.append((k,k+1,k+strap_columns+2,k+strap_columns+1))
        strap=mesh_obj(name+'Leather',verts,faces,ENARMES,root,uv)
        strap.data.materials.append(EDGE)
        solid=strap.modifiers.new('Actual leather thickness','SOLIDIFY');solid.thickness=.003
        solid.material_offset_rim=1
        bpy.context.view_layer.objects.active=strap;bpy.ops.object.modifier_apply(modifier=solid.name)
        for edge in [-1,1]:
            curve(name+'BoundEdge',[strap_point(edge*(width/2-.002)*min(1,.35+min(j/48,1-j/48)*14),-.12+.24*j/48,.022+depth*math.sin(math.pi*j/48)) for j in range(49)],.00065,THREAD,root)
        for v in [-.110,.110]:
            rivet_depth=.024+depth*math.sin(math.pi*(v+.12)/.24)
            sphere('StrapRivet',strap_point(0,v,rivet_depth),(.009,.0024,.009),BRASS,root)
    return export(root,'round_shield.glb')

reports=[build_hand('left'),build_hand('right'),build_sword(),build_shield()]
bpy.ops.wm.save_as_mainfile(filepath=str(STAGE/'sword_shield_first_person.blend'))
(STAGE/'build_report.json').write_text(json.dumps(reports,indent=2))
print('SWORD SHIELD ASSET BUILD PASS',json.dumps(reports))
