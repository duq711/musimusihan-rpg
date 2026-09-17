"""A physically assembled seven-board shield matched to shield_views_v1.png."""
import math, random
import bpy, bmesh
from mathutils import Vector


def build_shield_v2(api):
    empty,mesh_obj,sphere,curve,box,export=[api[n] for n in ['empty','mesh_obj','sphere','curve','box','export']]
    material=api['material'];root=empty('SwordsmanRoundShield')
    oak=material('FP_ShieldOak',(.26,.17,.10),.89)
    iron=material('FP_ShieldIron',(.27,.28,.27),.42,.86)
    bevel=material('FP_ShieldEdge',(.49,.52,.53),.28,.88)
    leather=material('FP_ShieldEnarmes',(.12,.072,.035),.69)
    edge=material('FP_ShieldLeatherEdge',(.17,.10,.051),.73)
    stitch=material('FP_ShieldStitch',(.30,.22,.14),.88)
    rng=random.Random(7719);radius=.415
    def finish(obj):
        if obj.type=='MESH':
            bm=bmesh.new();bm.from_mesh(obj.data);bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces));bm.to_mesh(obj.data);bm.free()
        return obj
    def dish(x,z):return .025*max(0,1-(x*x+z*z)/radius**2)
    # Joined, beveled real boards. Both surfaces and the narrow edge wall exist;
    # no overlapping planes or painted gaps substitute for solid geometry.
    widths=[-.415,-.299,-.180,-.061,.059,.180,.300,.415]
    for board in range(7):
        x0,x1=widths[board]+.0010,widths[board+1]-.0010
        verts=[];uv=[];faces=[];cols=12;rows=56
        def idx(side,i,j):return side*(cols+1)*(rows+1)+i*(rows+1)+j
        for side in range(2):
            for i in range(cols+1):
                u=i/cols;x=x0+(x1-x0)*u;half=math.sqrt(max(0,radius*radius-x*x))
                for j in range(rows+1):
                    v=j/rows;z=(v*2-1)*half
                    gapwarp=.00038*math.sin(z*31+board*2)+.00020*math.sin(z*97-board)
                    xx=x+gapwarp
                    depression=.00035*math.sin(xx*130+z*2)+.00020*math.sin(xx*350-z*3)
                    y=(-.018 if side==0 else .002)-dish(xx,z)+depression
                    # A narrow planed bevel around each plank catches light.
                    border=min(i,cols-i,j,rows-j)
                    if border==0:y+=.0012 if side==0 else -.0012
                    verts.append((xx,y,z));uv.append((.08+board*.112+u*.14,.03+.94*(z/(2*radius)+.5)))
        for side in range(2):
            for i in range(cols):
                for j in range(rows):
                    f=(idx(side,i,j),idx(side,i+1,j),idx(side,i+1,j+1),idx(side,i,j+1))
                    faces.append(f if side else tuple(reversed(f)))
        for i in range(cols):
            for j in [0,rows]:faces.append((idx(0,i,j),idx(1,i,j),idx(1,i+1,j),idx(0,i+1,j)))
        for j in range(rows):
            for i in [0,cols]:faces.append((idx(0,i,j),idx(0,i,j+1),idx(1,i,j+1),idx(1,i,j)))
        finish(mesh_obj('OakBoard%02d'%board,verts,faces,oak,root,uv,True))
    # Rolled rim has a slender U cross-section and physically rounded lips.
    profile=[(.390,-.023),(.391,-.025),(.422,-.025),(.426,-.022),(.427,-.017),(.427,.002),(.425,.008),(.421,.011),(.392,.011),(.390,.008)]
    segments=192;verts=[];uv=[];faces=[]
    # Split the profile strips: circumferentially smooth with crisp bevels.
    for band in range(len(profile)-1):
        start=len(verts)
        for j in range(segments+1):
            a=math.tau*j/segments
            wear=.00035*math.sin(a*13)+.00022*math.sin(a*47)
            for k in [band,band+1]:
                r,y=profile[k];verts.append((math.cos(a)*(r+wear),y,math.sin(a)*(r+wear)))
                # Broad front/back faces use isotropic planar iron grain.
                # Rolled edge strips retain two-dimensional unwrapped UVs;
                # using `band` for both sides collapsed a whole face to one
                # texture row, producing the visible radial barcode artifact.
                uv.append((.5+math.cos(a)*r/.93,.5+math.sin(a)*r/.93) if band in [1,7] else (.04+.92*j/segments,.07+k*.085))
        for j in range(segments):faces.append((start+j*2,start+j*2+1,start+j*2+3,start+j*2+2))
    rim=finish(mesh_obj('RolledIronRim',verts,faces,iron,root,uv,True));rim.data.materials.append(bevel)
    for face in rim.data.polygons:
        if face.index//segments in [0,2,3,5,6,8]:face.material_index=1
    # Small forged rivets; washer seats, domed head and irregular orientation.
    for i in range(32):
        a=math.tau*(i+.1)/32;r=.407
        for depth in [-.027,.013]:
            sphere('RimRivetSeat',(math.cos(a)*r,depth,math.sin(a)*r),(.0064,.0010,.0064),iron,root,16,8)
            sphere('RimDomedRivet',(math.cos(a)*r,depth+(-.0018 if depth<0 else .0018),math.sin(a)*r),(.0045,.0024,.0045),bevel,root,16,8)
    # Low, hammered front boss with flange. It is not visible from the rear.
    verts=[];uv=[];faces=[];rings=[(.086,-.046),(.087,-.049),(.070,-.051),(.066,-.057),(.055,-.067),(.033,-.079),(.008,-.083),(0,-.084)]
    for j,(r,y) in enumerate(rings):
        for i in range(65):
            a=math.tau*i/64;hammer=.0006*math.sin(a*11+j*1.2)*min(1,r/.06)**2
            verts.append((math.cos(a)*r,y+hammer,math.sin(a)*r));uv.append((.5+math.cos(a)*r*4.7,.5+math.sin(a)*r*4.7))
    for j in range(len(rings)-1):
        for i in range(64):k=j*65+i;faces.append((k,k+1,k+66,k+65))
    finish(mesh_obj('HammeredBoss',verts,faces,iron,root,uv,True))
    for i in range(6):
        a=math.tau*i/6;sphere('BossRivet',(math.cos(a)*.078,-.052,math.sin(a)*.078),(.0048,.0025,.0048),bevel,root,16,8)

    # True fixed-end leather loops. Root coordinate +Y is owner side; after
    # the player's Y=PI orientation, the narrower grip is on the viewer's right.
    for name,cx,cz,width,span,height,angle in [('RearGrip',-.18,.015,.044,.235,.145,-4),('RearArmStrap',.13,-.005,.070,.365,.130,24)]:
        theta=math.radians(angle)
        def point(u,v,d):return Vector((cx+u*math.cos(theta)+v*math.sin(theta),d,cz-u*math.sin(theta)+v*math.cos(theta)))
        def base(v):
            p=point(0,v,0);return .004-dish(p.x,p.z)
        def rise(t):
            # Broad flattened crown, eased into fixed tabs instead of a tent.
            return height*math.sin(math.pi*t)**.62
        contact=empty(name,root);contact.location=point(0,0,base(0)+height)
        if name=='RearGrip':
            for label,t in [('Top',.75),('Bottom',.25)]:
                marker=empty(name+label,root);v=(t-.5)*span;marker.location=point(0,v,base(v)+rise(t))
        for sign in [-1,1]:
            # Mount tabs sit flush on the wood with visible stitched margins.
            v=sign*(span/2+.018);p=point(0,v,0);p.y=base(v)+.002
            tab=box(name+'MountingTab',p,(width+.020,.006,.060),leather,root,.006);tab.rotation_euler.y=-theta
            for u in [-width*.31,width*.31]:
                v=sign*(span/2+.025);p=point(u,v,base(v)+.007)
                sphere('EnarmesRivet',p,(.006,.003,.006),bevel,root,16,8)
        verts=[];uv=[];faces=[];rows=64;cols=8
        for j in range(rows+1):
            t=j/rows;v=(t-.5)*span;d=base(v)+rise(t)
            for i in range(cols+1):
                u=(i/cols-.5)*width;verts.append(point(u,v,d+.0005*math.cos(i/cols*math.tau)));uv.append((.04+.92*i/cols,.03+.94*t))
        for j in range(rows):
            for i in range(cols):k=j*(cols+1)+i;faces.append((k,k+1,k+cols+2,k+cols+1))
        strap=mesh_obj(name+'LeatherLoop',verts,faces,leather,root,uv,True);strap.data.materials.append(edge)
        solid=strap.modifiers.new('Leather thickness 4 mm','SOLIDIFY');solid.thickness=.004;solid.offset=0;solid.material_offset_rim=1
        bpy.context.view_layer.objects.active=strap;bpy.ops.object.modifier_apply(modifier=solid.name)
        # Sewn edges follow the actual strap's surface, never floating over it.
        for sign in [-1,1]:
            for j in range(30):
                points=[]
                for t in [.03+j*.031,.03+j*.031+.009]:
                    v=(t-.5)*span;points.append(point(sign*(width/2-.004),v,base(v)+rise(t)+.0025))
                curve('EnarmesStitch',points,.00045,stitch,root)
        if name=='RearArmStrap':
            # Tang buckle, retained tail, and real shallow punched hole seats.
            v=-.058;t=v/span+.5;d=base(v)+rise(t)+.005
            corners=[point(u,v+dv,d) for u,dv in [(-width*.58,-.013),(width*.58,-.013),(width*.58,.013),(-width*.58,.013),(-width*.58,-.013)]]
            curve('ForearmBuckle',corners,.0032,iron,root)
            curve('BuckleTongue',[point(0,v-.015,d+.001),point(0,v+.012,d+.002)],.0015,bevel,root)
            for v in [.014,.035,.056,.077,.098]:
                t=v/span+.5;d=base(v)+rise(t)+.0022
                sphere('BeltPunchedRecess',point(0,v,d),(.0018,.00045,.0023),edge,root,12,6)
    root['reference']='shield_views_v1.png';root['construction']='seven solid oak boards, rolled iron U rim, fixed leather enarmes'
    return export(root,'round_shield.glb')
