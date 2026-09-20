"""Restore naturally colored eyes inside the existing Gravebound_Eyes node.

The original eye centers and ellipsoid bounds are retained. Face and every other
mesh are untouched. The caller owns saving the final Blender/GLB artifacts.
"""
from pathlib import Path
import bpy,bmesh,json,math,hashlib
from mathutils import Vector
from mathutils.bvhtree import BVHTree
W=Path(__file__).resolve().parent

def _signature(o):
    return hashlib.sha256(json.dumps({'vertices':[list(v.co) for v in o.data.vertices],'faces':[list(p.vertices) for p in o.data.polygons],'uv':[[list(p.uv) for p in l.data] for l in o.data.uv_layers],'world':[list(r) for r in o.matrix_world]},sort_keys=True).encode()).hexdigest()

def _material(name,color,roughness):
    m=bpy.data.materials.new(name);m.use_nodes=True;p=m.node_tree.nodes.get('Principled BSDF')
    p.inputs['Base Color'].default_value=(*color,1);p.inputs['Roughness'].default_value=roughness;p.inputs['Specular IOR Level'].default_value=.42
    m.diffuse_color=(*color,1);return m

def _iris_texture():
    n=256;im=bpy.data.images.new('Gravebound_Natural_Brown_Iris',width=n,height=n,alpha=False);im.colorspace_settings.name='sRGB'
    pixels=[]
    for y in range(n):
        for x in range(n):
            dx=(x+.5-n/2)/(n/2);dy=(y+.5-n/2)/(n/2);r=math.hypot(dx,dy);a=math.atan2(dy,dx)
            # Layered radial fibers and a restrained dark outer limbal ring.
            fiber=.5+.22*math.sin(89*a+8*r)+.15*math.sin(151*a-12*r)+.1*math.sin(223*a+19*r)
            fiber=max(0.,min(1.,fiber));warm=1+.10*math.sin(17*a+11*r)
            base=(.25+.15*fiber)*warm
            limbal=max(.16,min(1.,(1.01-r)/.12))
            pupil=0.035 if r<.405 else 1.
            pixels.extend((base*limbal*pupil,base*.69*limbal*pupil,base*.36*limbal*pupil,1))
    im.pixels.foreach_set(pixels);im.update();im.pack();return im

def _sclera_texture():
    """Compact polar UV albedo: lid shading and a trace of inner-corner warmth."""
    size=256;im=bpy.data.images.new('Gravebound_Sclera_Soft_Lid_Shade',width=size,height=size,alpha=False);im.colorspace_settings.name='sRGB'
    pixels=[]
    def srgb(value):return 12.92*value if value<=.0031308 else 1.055*value**(1/2.4)-.055
    for y in range(size):
        theta=math.pi*(y+.5)/size
        for x in range(size):
            angle=math.tau*(x+.5)/size
            nasal=math.sin(theta)*math.cos(angle);vertical=math.sin(theta)*math.sin(angle);forward=max(0.,math.cos(theta))
            # The opening extends from normalized vertical -.455 to +.09.
            # Shade grows softly near the upper lid; no painted catchlights.
            upper=math.exp(-((vertical-.09)/.20)**2)*forward
            lower=math.exp(-((vertical+.455)/.105)**2)*forward
            peripheral=(1-forward)*.10
            shade=max(.38,1-.52*upper-.12*lower-peripheral)
            warmth=.07*math.exp(-((nasal-.76)/.22)**2)*forward
            variation=1+.006*math.sin(31*angle+7*theta)*math.sin(19*theta)
            base=(.22,.20,.17);warm=(.25,.155,.145)
            rgb=[(base[i]*(1-warmth)+warm[i]*warmth)*shade*variation for i in range(3)]
            pixels.extend((*[srgb(v) for v in rgb],1))
    im.pixels.foreach_set(pixels);im.update();im.pack();return im

def repair_eyes():
    eye=bpy.data.objects['Gravebound_Eyes'];original_world=eye.matrix_world.copy();inverse=original_world.inverted()
    others={o.name:_signature(o) for o in bpy.data.objects if o.type=='MESH' and o!=eye}
    # Source already has two overlapping sclera shells per eye. Use the outer
    # bounds once, removing the redundant inner shell from this object only.
    source_points=[original_world@v.co for v in eye.data.vertices]
    eyes=[]
    for sign in (-1,1):
        points=[p for p in source_points if sign*p.x>0]
        lo=Vector(tuple(min(p[i] for p in points) for i in range(3)));hi=Vector(tuple(max(p[i] for p in points) for i in range(3)))
        eyes.append(((lo+hi)*.5,(hi-lo)*.5))
    sclera=_material('Gravebound_Eye_Warm_Sclera',(.22,.20,.17),.32)
    sclera_tex=_sclera_texture();sclera_node=sclera.node_tree.nodes.new('ShaderNodeTexImage');sclera_node.image=sclera_tex;sclera.node_tree.links.new(sclera_node.outputs['Color'],sclera.node_tree.nodes.get('Principled BSDF').inputs['Base Color'])
    iris=_material('Gravebound_Eye_Brown_Iris',(.07,.035,.014),.25)
    pupil=_material('Gravebound_Eye_Pupil',(.0018,.0015,.0013),.22)
    tex=_iris_texture();node=iris.node_tree.nodes.new('ShaderNodeTexImage');node.image=tex;iris.node_tree.links.new(node.outputs['Color'],iris.node_tree.nodes.get('Principled BSDF').inputs['Base Color'])
    verts=[];faces=[];face_mats=[];face_uv=[]
    def vertex(world):verts.append(tuple(inverse@Vector(world)));return len(verts)-1
    def face(indices,mi,uvs=None):faces.append(tuple(indices));face_mats.append(mi);face_uv.append(uvs or [(0,0)]*len(indices))
    n=64;lat=32;ir=.0056;pr=.00225;gaze_z=-.0025
    for center,radius in eyes:
        c=center;r=radius
        # Parametrize around world +Y, the character's front/gaze axis.
        front=vertex((c.x,c.y+r.y,c.z));rings=[]
        def eye_uv(k,v):
            u=k/n
            # Mirror horizontally so the small warm region always faces the nose.
            return (u if c.x<0 else .5-u,v)
        for j in range(1,lat):
            theta=math.pi*j/lat;ring=[]
            for k in range(n):
                a=math.tau*k/n;ring.append(vertex((c.x+r.x*math.sin(theta)*math.cos(a),c.y+r.y*math.cos(theta),c.z+r.z*math.sin(theta)*math.sin(a))))
            rings.append(ring)
        back=vertex((c.x,c.y-r.y,c.z))
        for k in range(n):face((front,rings[0][k],rings[0][(k+1)%n]),0,[eye_uv(k+.5,0),eye_uv(k,1/lat),eye_uv(k+1,1/lat)])
        for j,(a,b) in enumerate(zip(rings,rings[1:])):
            for k in range(n):face((a[k],b[k],b[(k+1)%n],a[(k+1)%n]),0,[eye_uv(k,(j+1)/lat),eye_uv(k,(j+2)/lat),eye_uv(k+1,(j+2)/lat),eye_uv(k+1,(j+1)/lat)])
        for k in range(n):face((back,rings[-1][(k+1)%n],rings[-1][k]),0,[eye_uv(k+.5,1),eye_uv(k+1,(lat-1)/lat),eye_uv(k,(lat-1)/lat)])
        # Iris and pupil follow the sclera curvature with 0.16 mm separation.
        # Center the iris inside the measured opening (its midpoint is 2.825 mm
        # below the eyeball center). Keep the pupil 0.325 mm above that midpoint;
        # the entire globe stays fixed and the gaze follows its curvature.
        iris_rings=[];iris_radii=[0,pr]+[pr+(ir-pr)*j/12 for j in range(1,13)]
        iris_center=vertex((c.x,c.y+r.y*math.sqrt(1-(gaze_z/r.z)**2)+.00016,c.z+gaze_z))
        for radial in iris_radii[1:]:
            ring=[]
            for k in range(n):
                a=math.tau*k/n;dx=radial*math.cos(a);dz=gaze_z+radial*math.sin(a)
                y=c.y+r.y*math.sqrt(max(0.,1-(dx/r.x)**2-(dz/r.z)**2))+.00016
                ring.append(vertex((c.x+dx,y,c.z+dz)))
            iris_rings.append(ring)
        def uv(radial,k):
            a=math.tau*k/n;return (.5+.5*radial/ir*math.cos(a),.5+.5*radial/ir*math.sin(a))
        for k in range(n):face((iris_center,iris_rings[0][k],iris_rings[0][(k+1)%n]),2)
        for j,(a,b) in enumerate(zip(iris_rings,iris_rings[1:])):
            ra=iris_radii[j+1];rb=iris_radii[j+2]
            for k in range(n):face((a[k],b[k],b[(k+1)%n],a[(k+1)%n]),1,[uv(ra,k),uv(rb,k),uv(rb,k+1),uv(ra,k+1)])
    mesh=bpy.data.meshes.new('Gravebound_Natural_Eyes');mesh.from_pydata(verts,[],faces);mesh.update()
    for mat in (sclera,iris,pupil):mesh.materials.append(mat)
    layer=mesh.uv_layers.new(name='UVMap')
    for p,mi,uvs in zip(mesh.polygons,face_mats,face_uv):
        p.material_index=mi;p.use_smooth=True
        for loop,uv in zip(p.loop_indices,uvs):layer.data[loop].uv=uv
    bm=bmesh.new();bm.from_mesh(mesh);bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces));bm.to_mesh(mesh);bm.free()
    # Orient the open iris/pupil caps toward the camera; their normals are not
    # determined by a closed volume during bmesh normal recalculation.
    for p in mesh.polygons:
        world_normal=original_world.to_3x3()@p.normal
        if p.material_index in (1,2) and world_normal.y<0:p.flip()
    mesh.update();eye.data=mesh
    head=bpy.data.objects['Gravebound_AnatomicalHead'];head.data.calc_loop_triangles()
    headtree=BVHTree.FromPolygons([head.matrix_world@v.co for v in head.data.vertices],[tuple(t.vertices) for t in head.data.loop_triangles],all_triangles=True)
    mesh.calc_loop_triangles();tree=BVHTree.FromPolygons([original_world@v.co for v in mesh.vertices],[tuple(t.vertices) for t in mesh.loop_triangles],all_triangles=True)
    probes=[]
    for center,radius in eyes:
        for label,dx in [('pupil',0),('iris',.0038),('sclera',.009)]:
            x=center.x+dx*(-1 if center.x<0 else 1);z=center.z+gaze_z;origin=Vector((x,.3,z));direction=Vector((0,-1,0))
            hit,normal,idx,dist=tree.ray_cast(origin,direction,.5);headhit=headtree.ray_cast(origin,direction,.5)[0]
            mi=mesh.polygons[mesh.loop_triangles[idx].polygon_index].material_index if idx is not None else None
            probes.append({'side':'left' if center.x<0 else 'right','part':label,'hit':list(hit) if hit else None,'material':mi,'front_normal_y':normal.y if normal else None,'visible_through_socket':hit is not None and (headhit is None or hit.y>headhit.y)})
    assert all(p['visible_through_socket'] for p in probes),probes
    assert all(p['material']=={'pupil':2,'iris':1,'sclera':0}[p['part']] for p in probes),probes
    assert others=={name:_signature(bpy.data.objects[name]) for name in others}
    assert eye.matrix_world==original_world
    report={'eye_centers_world':[list(c) for c,r in eyes],'eye_radii_m':[list(r) for c,r in eyes],'iris_radius_m':ir,'pupil_radius_m':pr,'iris_forward_separation_m':.00016,'iris_center_z_offset_m':gaze_z,'iris_centers_world':[[c.x,c.y+r.y*math.sqrt(1-(gaze_z/r.z)**2)+.00016,c.z+gaze_z] for c,r in eyes],'sclera_linear_color':[.22,.20,.17],'source_overlapping_shells':4,'rebuilt_sclera_shells':2,'other_meshes_unchanged':len(others),'eye_transform_unchanged':True,'mesh_node_count':sum(o.type=='MESH' for o in bpy.data.objects),'vertices':len(mesh.vertices),'faces':len(mesh.polygons),'materials':[m.name for m in mesh.materials],'iris_texture_size':list(tex.size),'iris_texture_packed':bool(tex.packed_file),'sclera_texture_size':list(sclera_tex.size),'sclera_texture_packed':bool(sclera_tex.packed_file),'sclera_shading':'soft upper-lid proximity shadow; subtle lower-lid shade; faint nasal warmth; no painted highlights','sclera_roughness':.32,'socket_probes':probes,'helper_sha256':hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),'pass':True}
    (W/'eyes_repair_report.json').write_text(json.dumps(report,indent=2));print('EYES REPAIR PASS',json.dumps(report));return report
