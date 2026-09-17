"""Proportion scaling only: no sculpting, remeshing, painting or smoothing."""
from mathutils import Vector, Matrix

DIGITS=('thumb','index','middle','ring','little')
RADIAL=dict(zip(DIGITS,(.78,.72,.73,.72,.68)))
LENGTH=dict(zip(DIGITS,(1.02,.98,1.,1.,.90)))

def smooth(a,b,x):
    t=max(0.,min(1.,(x-a)/(b-a)))
    return t*t*(3.-2.*t)

def body(p):
    x,y,z=p
    if y<=-.075:return p.copy()
    wrist=smooth(-.075,-.025,y)
    palm=smooth(-.015,.055,y)
    sx=1.-.25*wrist+.07*palm
    sz=1.-.15*wrist
    center=-.019*smooth(.015,.055,y)
    return Vector((x*sx,y,center+(z-center)*sz))

def section_center(points,faces,origin,axis):
    hits=[]
    for face in faces:
        for a,b in zip(face,face[1:]+face[:1]):
            pa,pb=points[a],points[b]
            da,db=(pa-origin).dot(axis),(pb-origin).dot(axis)
            if (da<0)!=(db<0):hits.append(pa+(pb-pa)*(da/(da-db)))
    assert hits,'No physical digit section'
    dorsal=Vector((0,0,1));cross=axis.cross(dorsal).normalized()
    u=[(p-origin).dot(cross) for p in hits];v=[(p-origin).dot(dorsal) for p in hits]
    center=origin+cross*(min(u)+max(u))*.5+dorsal*(min(v)+max(v))*.5
    return center,(max(u)-min(u),max(v)-min(v))

class ProportionMap:
    def __init__(self,holder,rig,skin):
        native=holder.matrix_world.inverted()@skin.matrix_world
        points=[native@v.co for v in skin.data.vertices[:12036]]
        names={g.index:g.name for g in skin.vertex_groups}
        weights=[{d:sum(g.weight for g in v.groups if names[g.group].startswith(d)) for d in DIGITS} for v in skin.data.vertices[:12036]]
        faces=[list(p.vertices) for p in skin.data.polygons if max(p.vertices)<12036]
        matrix=holder.matrix_world.inverted()@rig.matrix_world
        self.frames={};self.dimensions={}
        for digit in DIGITS:
            start=1 if digit=='thumb' else 0
            m=matrix@rig.data.bones[digit+str(start)].matrix_local
            origin=m.translation;axis=m.to_3x3().col[1].normalized()
            section_origin=(matrix@rig.data.bones[digit+('2' if digit=='thumb' else '1')].matrix_local).translation
            subset=[f for f in faces if sum(weights[i][digit] for i in f)/len(f)>.6]
            center,size=section_center(points,subset,section_origin,axis)
            # The original bone lies off the surface-section centre. Scale about
            # the measured skin axis, and map the bones through the same field.
            base=center-axis*(center-origin).dot(axis)
            self.frames[digit]=(base,axis)
            self.dimensions[digit]={'source_section_width_m':size[0], 'source_section_depth_m':size[1],
                'radial_scale':RADIAL[digit], 'length_scale':LENGTH[digit], 'centerline_base':list(base), 'axis':list(axis)}

    def digit(self,p,d):
        base,axis=self.frames[d];q=p-base;t=q.dot(axis)
        return body(base)+axis*(t*LENGTH[d])+(q-axis*t)*RADIAL[d]

    def warp(self,p,weights):
        result=body(p)
        for d,w in weights.items():
            if w<=0:continue
            base,axis=self.frames[d];t=(p-base).dot(axis)
            gate=smooth(-.015,.012,t) if d!='thumb' else smooth(-.008,.012,t)
            result+=(self.digit(p,d)-body(p))*(w*gate)
        return result

    def jacobian(self,p,weights):
        e=.000002;columns=[]
        for k in range(3):
            shift=Vector();shift[k]=e
            columns.append((self.warp(p+shift,weights)-self.warp(p-shift,weights))/(2*e))
        return Matrix(columns).transposed()

def digit_weights(obj,vertex):
    names={g.index:g.name for g in obj.vertex_groups}
    result={}
    for group in vertex.groups:
        name=names[group.group]
        for d in DIGITS:
            if name.startswith(d):result[d]=result.get(d,0.)+group.weight
    return result
