"""Create shoulder bridge surfaces from the loaded character, without edits to sources.

Coordinates in the extraction report are Blender world coordinates: +Y is front.
The caller owns materials, cloth thickness, baking and export.
"""
from pathlib import Path
import bpy,bmesh,math,json
from mathutils import Vector
from mathutils.bvhtree import BVHTree
W=Path(__file__).resolve().parent

def _world_data(obj):
    mesh=obj.data;mesh.calc_loop_triangles()
    vertices=[obj.matrix_world@v.co for v in mesh.vertices]
    triangles=[tuple(t.vertices) for t in mesh.loop_triangles]
    edges=[tuple(e.vertices) for e in mesh.edges]
    return vertices,edges,BVHTree.FromPolygons(vertices,triangles,all_triangles=True)

def _slice(vertices,edges,x):
    points=[]
    for ai,bi in edges:
        a,b=vertices[ai],vertices[bi]
        if abs(a.x-b.x)<1e-9 or (a.x-x)*(b.x-x)>0:continue
        t=(x-a.x)/(b.x-a.x)
        if 0<=t<=1:points.append(a+t*(b-a))
    return points

def _height(tree,x,y,fallback):
    p=tree.ray_cast(Vector((x,y,2.)),Vector((0,0,-1)),1.)[0]
    return p.z if p is not None else fallback

def create_bridges():
    """Return two new unthickened world-space shoulder meshes; source meshes unchanged."""
    back=bpy.data.objects['Gravebound_MantleBack'];back_data=_world_data(back)
    result=[];report={'world_front_axis':'+Y','x_segments':56,'depth_segments':20,'underlap_m':.008,'central_arch_m':.006,'source_parts':{},'sides':[]}
    for sign,front_name,label in ((1,'Gravebound_Mantle_L','R'),(-1,'Gravebound_Mantle_R','L')):
        front=bpy.data.objects[front_name];fv,fe,ft=_world_data(front);bv,be,bt=back_data
        front_extent=max(sign*v.x for v in fv);back_extent=max(sign*v.x for v in bv)
        xmax=min(front_extent,back_extent)-.0005;xmin=.074
        verts=[];faces=[];rows=[]
        for j in range(57):
            r=j/56;xp=xmin+(xmax-xmin)*r
            fx=sign*min(xp,front_extent-.0005);bx=sign*min(xp,back_extent-.0005)
            fs=_slice(fv,fe,fx);bs=_slice(bv,be,bx)
            assert fs and bs,(front_name,j,fx,bx)
            f=max(fs,key=lambda p:p.z)
            ymax=max(p.y for p in bs)
            b=max((p for p in bs if p.y>=ymax-.004),key=lambda p:p.z)
            # Inside the neckline the back drape has no shoulder edge; follow the
            # same upper collar height while extending beneath the hood/cowl.
            inner=max(0.,min(1.,(.110-xp)/.036));inner=inner*inner*(3-2*inner)
            b.z=max(b.z,1.508*inner+b.z*(1-inner))
            f.z=max(f.z,1.506*inner+f.z*(1-inner))
            dy=max(.006,f.y-b.y);under=.008
            for k in range(21):
                s=k/20;y=(b.y-under)+(dy+2*under)*s
                u=(y-b.y)/dy;uc=max(0.,min(1.,u))
                x=b.x+(f.x-b.x)*uc
                z=b.z+(f.z-b.z)*uc+.006*math.sin(math.pi*uc)
                # The core rides immediately beneath the old panel edge; the
                # overlap follows the actual panel surface, not a floating flap.
                z-=.0015
                if u<0:
                    z=_height(bt,x,y,b.z)-.0025
                elif u>1:
                    z=_height(ft,x,y,f.z)-.0025
                # Raised inner edge is tucked inside the existing neck cowl.
                if inner>0:
                    z=max(z,1.493*inner+z*(1-inner))
                verts.append((x,y,z))
            rows.append({'abs_x':xp,'back_edge':list(b),'front_edge':list(f),'gap_depth_m':f.y-b.y})
        for j in range(56):
            for k in range(20):
                a=j*21+k;faces.append((a,a+21,a+22,a+1))
        mesh=bpy.data.meshes.new('Gravebound_ShoulderBridge_'+label);mesh.from_pydata(verts,[],faces);mesh.update()
        bm=bmesh.new();bm.from_mesh(mesh);bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces))
        # Single sheet normals face upward before the caller's solidify.
        if sum(f.normal.z*f.calc_area() for f in bm.faces)<0:bmesh.ops.reverse_faces(bm,faces=list(bm.faces))
        bm.to_mesh(mesh);bm.free()
        for p in mesh.polygons:p.use_smooth=True
        obj=bpy.data.objects.new('Gravebound_ShoulderBridge_'+label,mesh);bpy.context.scene.collection.objects.link(obj)
        obj['purpose']='Continuous cloth connecting front and rear mantle over shoulder'
        result.append(obj)
        report['sides'].append({'object':obj.name,'front_source':front_name,'x_extent':[xmin,xmax],'rows':rows})
    (W/'geometry_extraction_report.json').write_text(json.dumps(report,indent=2))
    return result
