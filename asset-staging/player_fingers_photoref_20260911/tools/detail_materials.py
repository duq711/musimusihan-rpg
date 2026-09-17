"""Native Cycles finger microdetail baked over the existing 4K hand atlas.

API: bake_finger_detail(scene, hands, output_dir, resolution=4096,
                       samples=8, strength=1.0) -> serializable report.
``hands`` maps left/right to dictionaries containing holder, rig, skin, objects.
Run after geometry sculpt, with neutral bones/shape keys, before export/save.
Only temporary physical skin/nail geometry is baked. Original meshes, UVs,
weights, material roles and non-skin shader topology are never rewritten.
This module does not ingest, paint, project or edit the generated references.
"""
from pathlib import Path
from array import array
import hashlib
import math
import bpy
import numpy as np
from mathutils import Vector

DIGITS = ('thumb', 'index', 'middle', 'ring', 'little')
MAPS = ('basecolor', 'roughness', 'normal')
ATTRS = ('FDJoint1', 'FDJoint2', 'FDPad', 'FDDorsal', 'FDMask', 'FDNail', 'FDLocal')


def _smooth(a, b, x):
    t = max(0.0, min(1.0, (x-a)/(b-a)))
    return t*t*(3-2*t)


def _source_pixels(image):
    values = array('f', [0.0]) * len(image.pixels)
    image.pixels.foreach_get(values)
    return values


def _shader_signature(material):
    # Image identity is deliberately excluded; atlas content is verified below.
    return {
        'nodes': [(n.name, n.bl_idname) for n in material.node_tree.nodes],
        'links': [(l.from_node.name, l.from_socket.name, l.to_node.name,
                   l.to_socket.name) for l in material.node_tree.links],
        'values': [(n.name, x.name, tuple(x.default_value) if hasattr(x.default_value, '__len__')
                    else x.default_value) for n in material.node_tree.nodes for x in n.inputs
                   if hasattr(x, 'default_value') and x.type in ('VALUE','RGBA','VECTOR')]
    }


def _owners(skin):
    names = {g.index: g.name for g in skin.vertex_groups}
    result = []
    for vertex in skin.data.vertices:
        weights = {d: sum(g.weight for g in vertex.groups if names[g.group].startswith(d))
                   for d in DIGITS}
        digit = max(weights, key=weights.get)
        result.append((digit, weights[digit]))
    return result


def _frames(hand):
    skin, rig = hand['skin'], hand['rig']
    points = [skin.matrix_world @ v.co for v in skin.data.vertices]
    owners = _owners(skin)
    frames, nails = {}, {}
    for obj in hand['objects']:
        if obj.type == 'MESH' and any(m and m.name == 'Detailed_Nail' for m in obj.data.materials):
            digit = next(d for d in DIGITS if d in obj.name)
            nails[digit] = obj
    assert set(nails) == set(DIGITS), 'Expected five named nail meshes'
    for digit in DIGITS:
        physical = [i for i, (d,w) in enumerate(owners[:12036]) if d == digit and w > .45]
        assert physical, digit
        # A bone's local Z is the old unrolled rest frame. The thumb has since
        # been rolled with its skin bed, so derive anatomical dorsal from the
        # actual nail cap instead. The cap is the first half of this preserved
        # 322-vertex shell; area weighting is stable after a local nail refit.
        nail=nails[digit]
        nail_points=[nail.matrix_world @ v.co for v in nail.data.vertices]
        cap_count=len(nail_points)//2
        assert len(nail_points)==322, 'Preserve the existing nail shell contract'
        cap_normal=Vector((0.,0.,0.))
        for polygon in nail.data.polygons:
            if max(polygon.vertices)>=cap_count: continue
            a=nail_points[polygon.vertices[0]]
            for j in range(1,len(polygon.vertices)-1):
                b=nail_points[polygon.vertices[j]];c=nail_points[polygon.vertices[j+1]]
                cap_normal+=(b-a).cross(c-a)
        assert cap_normal.length>1e-8, 'Cannot determine actual nail cap direction'
        cap_normal.normalize()
        for joint in (0,1,2):
            matrix = rig.matrix_world @ rig.data.bones[digit+str(joint)].matrix_local
            anchor,axis=matrix.translation,matrix.to_3x3().col[1].normalized()
            dorsal=(cap_normal-axis*cap_normal.dot(axis)).normalized()
            cross = axis.cross(dorsal).normalized()
            near = sorted(physical, key=lambda i: abs((points[i]-anchor).dot(axis)))[:60]
            center = anchor.copy()
            for direction in (cross,dorsal):
                values = sorted((points[i]-anchor).dot(direction) for i in near)
                center += direction * ((values[3]+values[-4])*.5)
            width = sorted((points[i]-center).dot(cross) for i in near)
            frames[digit,joint] = (center,axis,dorsal,cross,max(.004,(width[-4]-width[3])*.5))
        center,axis,dorsal,cross,radius = frames[digit,2]
        axial = [(points[i]-center).dot(axis) for i in physical]
        tip = max(axial)
        nail = nails[digit]
        nail_points = [nail.matrix_world @ v.co for v in nail.data.vertices]
        along = [(p-center).dot(axis) for p in nail_points]
        lateral = [(p-center).dot(cross) for p in nail_points]
        frames[digit,'tip'] = tip
        frames[digit,'nail'] = (min(along),max(along),(min(lateral)+max(lateral))*.5,max(.003,(max(lateral)-min(lateral))*.5))
    return frames, owners, nails


def _point_fields(point, digit, enable, frames, nail=False):
    values = {}
    for joint in (1,2):
        center,axis,dorsal,cross,radius = frames[digit,joint]
        q = point-center
        values['FDJoint'+str(joint)] = (q.dot(cross),q.dot(axis),radius)
    center,axis,dorsal,cross,radius = frames[digit,2]
    q = point-center
    t,u = q.dot(axis),q.dot(cross)
    tip = frames[digit,'tip']
    nmin,nmax,ncenter,nradius = frames[digit,'nail']
    values['FDPad'] = (u, t-tip*.60, tip)
    values['FDDorsal'] = tuple(dorsal)
    values['FDLocal'] = (u,t,q.dot(dorsal))
    # Fade the effect at the base of the finger; physical palm and wrist unchanged.
    root,root_axis,*unused = frames[digit,0]
    gate = enable * _smooth(.003,.017,(point-root).dot(root_axis))
    if digit == 'thumb':
        root,root_axis,*unused = frames[digit,1]
        gate = enable * _smooth(-.008,.011,(point-root).dot(root_axis))
    values['FDMask'] = (gate, float(DIGITS.index(digit)), 0.0 if digit == 'thumb' else 1.0)
    values['FDNail'] = ((u-ncenter)/nradius,(t-nmin)/max(.001,nmax-nmin),float(DIGITS.index(digit)))
    return values


def _surface(scene, hand, materials):
    frames,owners,nails = _frames(hand)
    vertices, faces, uv, normals, assignments = [], [], [], [], []
    fields = {name:[] for name in ATTRS}
    source_names = []
    for obj in [hand['skin']] + [nails[d] for d in DIGITS]:
        mesh = obj.data
        assert mesh.uv_layers.active and mesh.uv_layers.active.name == 'RealismUV'
        if mesh.shape_keys:
            assert all(abs(k.value)<1e-8 for k in mesh.shape_keys.key_blocks), 'Bake neutral corrective values only'
        point_map = {}
        mat_name = 'Detailed_Nail' if obj != hand['skin'] else 'Detailed_Skin'
        normal_matrix = obj.matrix_world.to_3x3().inverted().transposed()
        for polygon in mesh.polygons:
            original_material = mesh.materials[polygon.material_index]
            if not original_material or original_material.name != mat_name:
                continue
            face=[]
            for loop_index in polygon.loop_indices:
                vi=mesh.loops[loop_index].vertex_index
                if vi not in point_map:
                    p=obj.matrix_world @ mesh.vertices[vi].co
                    point_map[vi]=len(vertices); vertices.append(p)
                    if mat_name=='Detailed_Nail':
                        digit=next(d for d in DIGITS if d in obj.name); enable=1.0
                    else:
                        assert vi < 12036, 'Skin bake must exclude glove decoration vertices'
                        digit,enable=owners[vi]
                        enable=_smooth(.25,.70,enable)
                    attrs=_point_fields(p,digit,enable,frames,mat_name=='Detailed_Nail')
                    for name in ATTRS: fields[name].append(attrs[name])
                face.append(point_map[vi])
                uv.append(tuple(mesh.uv_layers.active.data[loop_index].uv))
                normals.append((normal_matrix @ mesh.corner_normals[loop_index].vector).normalized())
            faces.append(face); assignments.append(1 if mat_name=='Detailed_Nail' else 0)
        source_names.append(obj.name)
    mesh=bpy.data.meshes.new('FingerDetail_Bake_Surface_Mesh')
    mesh.from_pydata(vertices,[],faces); mesh.update()
    for name in ('Detailed_Skin','Detailed_Nail'): mesh.materials.append(materials[name]['material'])
    layer=mesh.uv_layers.new(name='RealismUV')
    for index,value in enumerate(uv): layer.data[index].uv=value
    for polygon,index in zip(mesh.polygons,assignments):
        polygon.material_index=index; polygon.use_smooth=True
    mesh.normals_split_custom_set(normals)
    for name in ATTRS:
        attr=mesh.attributes.new(name=name,type='FLOAT_VECTOR',domain='POINT')
        for datum,value in zip(attr.data,fields[name]): datum.vector=value
    surface=bpy.data.objects.new('FingerDetail_Bake_Surface',mesh)
    scene.collection.objects.link(surface)
    bpy.ops.object.select_all(action='DESELECT');surface.select_set(True);bpy.context.view_layer.objects.active=surface
    return surface, {'bake_source_objects':source_names,'bake_vertices':len(vertices),'bake_faces':len(faces),
                     'original_geometry_changed':False,'temporary_point_attributes':list(ATTRS)}


class _Nodes:
    def __init__(self,material):
        self.material=material; self.nodes=material.node_tree.nodes; self.links=material.node_tree.links
    def node(self,kind,name=None):
        result=self.nodes.new(kind)
        if name: result.name=name
        return result
    def link(self,value,socket):
        if isinstance(value,(int,float)): socket.default_value=value
        elif isinstance(value,(tuple,list)): socket.default_value=value
        else: self.links.new(value,socket)
    def op(self,kind,*args):
        result=self.node('ShaderNodeMath'); result.operation=kind
        for value,socket in zip(args,result.inputs): self.link(value,socket)
        return result.outputs[0]
    def attr(self,name):
        attr=self.node('ShaderNodeAttribute'); attr.attribute_name=name
        xyz=self.node('ShaderNodeSeparateXYZ'); self.links.new(attr.outputs['Vector'],xyz.inputs[0])
        return xyz.outputs
    def noise(self,vector,scale,detail=2.0):
        result=self.node('ShaderNodeTexNoise'); result.inputs['Scale'].default_value=scale
        result.inputs['Detail'].default_value=detail; result.inputs['Roughness'].default_value=.65
        self.link(vector,result.inputs['Vector']); return result.outputs['Fac']
    def gauss(self,value,width,power=2):
        return self.op('EXPONENT',self.op('MULTIPLY',self.op('POWER',self.op('DIVIDE',self.op('ABSOLUTE',value),width),power),-1.0))
    def mix(self,a,b,factor,mode='MIX'):
        result=self.node('ShaderNodeMixRGB');result.blend_type=mode
        self.link(factor,result.inputs[0]);self.link(a,result.inputs[1]);self.link(b,result.inputs[2])
        return result.outputs[0]
    def vector(self,x,y,z):
        result=self.node('ShaderNodeCombineXYZ')
        for value,socket in zip((x,y,z),result.inputs): self.link(value,socket)
        return result.outputs[0]
    def edge(self,vector,scale):
        result=self.node('ShaderNodeTexVoronoi')
        result.voronoi_dimensions='3D';result.feature='DISTANCE_TO_EDGE'
        self.link(vector,result.inputs['Vector']);result.inputs['Scale'].default_value=scale
        result.inputs['Randomness'].default_value=1.0
        return result.outputs['Distance']


def _procedural(original,strength):
    material=original.copy();material.name='FingerDetail_Bake_'+original.name
    n=_Nodes(material);o=n.op
    bsdf=next(x for x in n.nodes if x.type=='BSDF_PRINCIPLED')
    output=next(x for x in n.nodes if x.type=='OUTPUT_MATERIAL')
    base=n.nodes['Baked_basecolor'].outputs['Color']
    rough=n.nodes['Baked_roughness'].outputs['Color']
    oldnormal=next(x for x in n.nodes if x.type=='NORMAL_MAP').outputs['Normal']
    geometry=n.node('ShaderNodeNewGeometry')
    position=geometry.outputs['Position']
    variation=n.noise(position,185.0,2.1)
    gentle=n.noise(position,67.0,1.0)
    gate,seed,has_pip=n.attr('FDMask')
    def smooth(a,b,value):
        t=o('MINIMUM',1.0,o('MAXIMUM',0.0,o('DIVIDE',o('SUBTRACT',value,a),b-a)))
        return o('MULTIPLY',o('MULTIPLY',t,t),o('SUBTRACT',3.0,o('MULTIPLY',2.0,t)))
    def mul(*values):
        value=values[0]
        for other in values[1:]: value=o('MULTIPLY',value,other)
        return value
    def add(*values):
        value=values[0]
        for other in values[1:]: value=o('ADD',value,other)
        return value
    if original.name=='Detailed_Skin':
        dorsal=n.node('ShaderNodeAttribute');dorsal.attribute_name='FDDorsal'
        dot=n.node('ShaderNodeVectorMath');dot.operation='DOT_PRODUCT'
        n.link(dorsal.outputs['Vector'],dot.inputs[0]);n.link(geometry.outputs['Normal'],dot.inputs[1])
        # Creases continue around the nail-side shoulder, avoiding a stamped
        # oval patch confined to the exact front-facing center of each joint.
        front=smooth(-.28,.72,dot.outputs['Value'])
        back=smooth(-.16,.70,o('MULTIPLY',dot.outputs['Value'],-1.0))
        u0,v0,r0=n.attr('FDJoint2')
        xx,vv,zz=n.attr('FDLocal')
        local=n.vector(xx,vv,zz)
        grain=n.noise(local,420.0,2.0)
        drift=n.noise(local,620.0,1.8)
        # Thin connected furrows follow irregular three-dimensional cell
        # boundaries. Distance-to-edge is used only as an incision, never as
        # raised cellular/cobblestone displacement. Unequal domain warps and a
        # second sparse scale create short branches without a regular lattice.
        warp=mul(o('SUBTRACT',grain,.5),.00072)
        warp2=mul(o('SUBTRACT',drift,.5),.00043)
        domain=n.vector(add(xx,warp),add(mul(vv,1.35),warp2),add(zz,mul(warp,-.61)))
        edge=n.edge(domain,1060.0)
        fine=n.gauss(edge,.078,2)
        domain2=n.vector(add(mul(xx,.86),mul(warp2,1.1)),add(mul(vv,1.72),mul(warp,-.5)),add(zz,warp2))
        edge2=n.edge(domain2,1530.0)
        fine2=mul(n.gauss(edge2,.059,2),smooth(.37,.68,drift))
        micro=add(mul(fine,-.000014),mul(fine2,-.000007))
        # A shallow, broken directional component adds stretch lines between
        # joints. Warped spacing varies continuously; no global parallel bands.
        phase=mul(add(mul(xx,.68),mul(vv,.73),mul(o('SUBTRACT',grain,.5),.0012)),2*math.pi/.00115)
        striae=mul(o('POWER',mul(add(o('COSINE',phase),1.0),.5),8.0),smooth(.40,.67,drift))
        micro=add(micro,mul(striae,-.000009))
        height=0.0;crease=0.0;redness=0.0;fold_lips=0.0
        for joint in (1,2):
            u,v,r=n.attr('FDJoint'+str(joint))
            jgate=has_pip if joint==1 else 1.0
            # Four main overlapping transverse folds, each with a soft tissue
            # lip and a narrower crease. The radius is anatomical, not a mask
            # radius: unequal lateral extents/slants keep folds visibly open.
            primary=(
                (-.0043,.0012,-.055,-.10,.89,.00019,.000078,.000044),
                (-.00155,.0017,.038,.13,1.03,.00022,.000108,.000057),
                (.0012,.00075,-.032,-.07,.91,.00020,.000091,.000050),
                (.00375,.0014,.051,.18,.78,.00017,.000067,.000037),
            )
            joint_scale=.78 if joint==2 else 1.0
            jitter=mul(o('SUBTRACT',grain,.5),.00016)
            for offset,curve,slant,shift,extent,width,depth,lip_depth in primary:
                shifted=o('SUBTRACT',u,mul(r,shift))
                bend=mul(o('POWER',o('DIVIDE',shifted,r),2.0),curve*joint_scale)
                arc=add(o('SUBTRACT',v,offset*joint_scale),bend,mul(u,slant),jitter)
                lateral=n.gauss(shifted,mul(r,extent),6)
                facing=mul(lateral,front,jgate)
                incision=mul(n.gauss(arc,width),facing)
                # The broad low ridge is offset from the cut; it does not form
                # a complete raised ring around the joint.
                lip=mul(n.gauss(o('SUBTRACT',arc,.00042),.00049),facing)
                height=add(height,mul(incision,-depth),mul(lip,lip_depth))
                crease=o('MAXIMUM',crease,incision)
                fold_lips=o('MAXIMUM',fold_lips,lip)
            secondary=(
                (-.0061,-.0005,-.065,-.41,.59,.000090,.000021),
                (-.0035,.0011,.140,.31,.47,.000100,.000033),
                (-.0027,.0002,-.190,-.52,.50,.000090,.000026),
                (-.0002,-.0003,.110,.35,.48,.000095,.000029),
                (.00225,.0006,-.160,-.43,.59,.000100,.000030),
                (.0051,-.0007,.077,.31,.54,.000085,.000022),
                (.0067,.0009,-.025,-.10,.66,.000080,.000018),
            )
            for offset,curve,slant,shift,extent,width,depth in secondary:
                shifted=o('SUBTRACT',u,mul(r,shift))
                bend=mul(o('POWER',o('DIVIDE',shifted,r),2.0),curve*joint_scale)
                arc=add(o('SUBTRACT',v,offset*joint_scale),bend,mul(u,slant),jitter)
                line=mul(n.gauss(arc,width),n.gauss(shifted,mul(r,extent),6),front,jgate)
                height=add(height,mul(line,-depth))
                crease=o('MAXIMUM',crease,mul(line,.58))
            # The palmar hinge uses one main groove and two unequal branches,
            # rather than reusing the dorsal pattern on both sides of a digit.
            for offset,curve,slant,shift,extent,width,depth in (
                    (-.0018,.00072,-.043,-.07,1.10,.00022,.000094),
                    (.00040,.0011,.038,.08,1.05,.00029,.000138),
                    (.0021,.00060,-.034,-.15,.87,.00018,.000072)):
                shifted=o('SUBTRACT',u,mul(r,shift))
                arc=add(o('SUBTRACT',v,offset),mul(o('POWER',o('DIVIDE',shifted,r),2.0),curve),jitter,mul(u,slant))
                facing=mul(n.gauss(shifted,mul(r,extent),6),back,jgate)
                line=mul(n.gauss(arc,width),facing)
                lip=mul(n.gauss(o('SUBTRACT',arc,.00046),.00056),facing)
                height=add(height,mul(line,-depth),mul(lip,.000035))
                crease=o('MAXIMUM',crease,line)
            redness=o('MAXIMUM',redness,mul(n.gauss(v,.0063),jgate))
        # Fingertip ridges have an offset elongated core and an open returning
        # tail. Individual seeds vary lean, core position and pitch modestly.
        u,v,pad_length=n.attr('FDPad')
        lower=o('MINIMUM',v,0.0)
        tilt=add(.21,mul(seed,.023))
        x=o('SUBTRACT',o('SUBTRACT',u,mul(r0,add(-.055,mul(seed,.035)))),mul(lower,tilt))
        y=mul(o('MAXIMUM',v,0.0),add(.73,mul(seed,.016)))
        loop=o('SQRT',add(o('POWER',x,2.0),o('POWER',y,2.0),.0000000012))
        loop=add(loop,mul(lower,-.092))
        pitch=add(.000415,mul(seed,.000006))
        phase=add(mul(o('DIVIDE',loop,pitch),2*math.pi),mul(gentle,.18),mul(seed,.35))
        ridges=o('POWER',mul(add(o('COSINE',phase),1.0),.5),1.8)
        pad=mul(n.gauss(u,mul(r0,.98),6),n.gauss(v,mul(pad_length,.76),6),back,smooth(.001,.004,v0))
        height=add(height,mul(micro,o('SUBTRACT',1.0,mul(pad,.93))),mul(ridges,pad,.000025))
        height=mul(height,gate,strength)
        # Local vascular tint is deliberately visible in the fingertip pads and
        # folds. It does not replace the user's warm overall skin palette.
        pigment=mul(o('SUBTRACT',variation,.5),.075)
        base=n.mix(base,add(1.0,mul(pigment,gate)),1.0,'MULTIPLY')
        pink=n.mix(base,(1.035,.64,.60,1.0),1.0,'MULTIPLY')
        rosy=mul(gate,strength,o('MINIMUM',.66,add(mul(pad,.56),mul(redness,.17))))
        base=n.mix(base,pink,rosy)
        crease_dark=mul(crease,gate,.29*strength)
        base=n.mix(base,(.88,.78,.74,1.0),crease_dark,'MULTIPLY')
        # Fine surface lines scatter a little more light than the hydrated skin
        # in between. Their color change remains much weaker than their relief.
        dry=mul(o('MAXIMUM',fine,fine2),gate,o('SUBTRACT',1.0,mul(pad,.94)),.045)
        base=n.mix(base,(1.055,1.055,1.045,1.0),dry,'MULTIPLY')
        base=n.mix(base,(1.02,1.012,1.005,1.0),mul(fold_lips,gate,.20),'MULTIPLY')
        target_rough=add(.51,mul(o('SUBTRACT',gentle,.5),.045),mul(fine,.025),mul(crease,.018),mul(pad,-.035))
        rough=n.mix(rough,target_rough,gate)
        # Do not accumulate the previous stylized normal map on each revision.
        # The gated palm/wrist transition still keeps its preserved old normal.
        normal=n.mix(oldnormal,geometry.outputs['Normal'],gate)
    else:
        u,t,seed=n.attr('FDNail')
        # A shallow naturally striated nail plate, with pigment much more varied
        # than height. Micron-scale longitudinal grain cannot create corrugation.
        phase=add(mul(u,2*math.pi*12.5),mul(seed,.43))
        strand=add(mul(o('SINE',phase),.65),mul(o('SINE',add(mul(u,2*math.pi*21.3),1.2)),.35))
        ridge=mul(strand,.00000115)
        fine_noise=n.noise(position,1550.0,1.1)
        height=mul(add(ridge,mul(o('SUBTRACT',fine_noise,.5),.0000008)),strength)
        # The distal pale edge is only 4-6 percent of the plate. Its border
        # curves with the fingertip instead of a thick white horizontal bar.
        white_start=add(.954,mul(o('POWER',u,2.0),-.030),mul(o('SUBTRACT',gentle,.5),.008))
        free_edge=smooth(-.009,.009,o('SUBTRACT',t,white_start))
        # Lunula: a very subdued proximal crescent. Its central highest point
        # recedes toward the sidewalls, not a white oval floating in the plate.
        lunula_border=add(.137,mul(o('POWER',u,2.0),-.118))
        lunula=mul(o('SUBTRACT',1.0,smooth(-.017,.020,o('SUBTRACT',t,lunula_border))),smooth(-.04,.025,t))
        sidewall=smooth(.75,1.0,o('ABSOLUTE',u))
        proximal=n.gauss(o('SUBTRACT',t,.028),.028)
        pinkbed=(.445,.194,.176,1.0)
        nailcolor=n.mix(pinkbed,(1.028,.86,.84,1.0),mul(sidewall,.24), 'MULTIPLY')
        nailcolor=n.mix(nailcolor,(.51,.285,.258,1.0),mul(lunula,.43))
        nailcolor=n.mix(nailcolor,(.78,.70,.575,1.0),mul(free_edge,.86))
        nailcolor=n.mix(nailcolor,add(1.0,mul(strand,.025),mul(o('SUBTRACT',variation,.5),.048)),1.0,'MULTIPLY')
        # A thin translucent-looking cuticle tint sits at the proximal margin;
        # root models the supporting cuticle and nail sidewall geometry.
        nailcolor=n.mix(nailcolor,(.59,.358,.272,1.0),mul(proximal,.20))
        base=nailcolor
        rough=add(.31,mul(o('SUBTRACT',gentle,.5),.025),mul(free_edge,.055),mul(proximal,.045))
        normal=geometry.outputs['Normal']
    bump=n.node('ShaderNodeBump','FingerDetail_Microrelief')
    bump.inputs['Strength'].default_value=1.0;bump.inputs['Distance'].default_value=1.0
    n.link(height,bump.inputs['Height']);n.link(normal,bump.inputs['Normal'])
    n.link(bump.outputs['Normal'],bsdf.inputs['Normal'])
    n.link(base,bsdf.inputs['Base Color']);n.link(rough,bsdf.inputs['Roughness'])
    target=n.node('ShaderNodeTexImage','FingerDetail_BakeTarget')
    emission=n.node('ShaderNodeEmission','FingerDetail_BakeEmission')
    return {'material':material,'bsdf':bsdf,'output':output,'target':target,'emission':emission,'basecolor':base,'roughness':rough}


def _protected_non_skin_texels(hand, resolution):
    """Interior samples at least three texels from glove/cloth UV boundaries."""
    result=set()
    for obj in hand['objects']:
        if obj.type!='MESH' or not obj.data.uv_layers.active: continue
        mesh=obj.data; mesh.calc_loop_triangles(); uv=mesh.uv_layers.active.data
        for triangle in mesh.loop_triangles:
            material=mesh.materials[mesh.polygons[triangle.polygon_index].material_index]
            if not material or material.name not in ('Detailed_Glove','Detailed_Sleeve','Detailed_Trim'): continue
            points=[Vector(uv[i].uv)*resolution for i in triangle.loops]
            center=sum(points,Vector((0.,0.)))/3
            distance=[]
            for a,b in zip(points,points[1:]+points[:1]):
                edge=b-a
                if edge.length<1e-8: distance.append(0.0)
                else: distance.append(abs(edge.x*(center.y-a.y)-edge.y*(center.x-a.x))/edge.length)
            if min(distance)>3.0:
                x,y=int(center.x),int(center.y)
                if 0<=x<resolution and 0<=y<resolution: result.add(y*resolution+x)
    assert len(result)>100, 'Expected many protected non-skin atlas samples'
    return sorted(result)


def _load_fresh_packed(path, colorspace, name):
    """Persist new bake bytes, never re-pack a copy of an already packed image.

    Blender Image.copy() retains the source packed-file payload. Saving changed
    pixels updates the external PNG but pack() on that copied image can leave
    the old payload attached, so both .blend reopen and glTF export see old data.
    A fresh file image has no stale packed payload; its packed bytes must exactly
    match the just-saved PNG before it is attached to the production materials.
    """
    path=Path(path).resolve()
    image=bpy.data.images.load(str(path),check_existing=False)
    image.name=name;image.colorspace_settings.name=colorspace
    image.pack()
    expected=hashlib.sha256(path.read_bytes()).hexdigest()
    assert image.packed_file is not None
    assert hashlib.sha256(image.packed_file.data).hexdigest()==expected, ('Fresh packed image bytes differ',str(path))
    return image


def bake_finger_detail(scene, hands, output_dir, resolution=4096, samples=8, strength=1.0):
    """Bake local finger details; return logs/statistics suitable for build JSON.

    No heavy work happens on import. A single hand supplies the shared atlas;
    both hands keep their own geometry/rig and use the resulting packed maps.
    Original five role node trees stay intact except their Baked_* image links.
    """
    assert bpy.app.background, 'Use the authorized background Blender session'
    assert 'left' in hands and 0.0 < strength <= 1.6
    output_dir=Path(output_dir);output_dir.mkdir(parents=True,exist_ok=True)
    originals={name:bpy.data.materials[name] for name in ('Detailed_Skin','Detailed_Nail','Detailed_Glove','Detailed_Sleeve','Detailed_Trim')}
    signatures={name:_shader_signature(mat) for name,mat in originals.items()}
    source_images={mode:originals['Detailed_Skin'].node_tree.nodes['Baked_'+mode].image for mode in MAPS}
    assert all(tuple(im.size)==(resolution,resolution) for im in source_images.values()), 'Preserve source 4K atlas size'
    for hand in hands.values():
        assert all(p.matrix_basis.is_identity for p in hand['rig'].pose.bones), 'Bake neutral rest pose only'
    temporary={name:_procedural(originals[name],strength) for name in ('Detailed_Skin','Detailed_Nail')}
    surface,report=_surface(scene,hands['left'],temporary)
    report.update({'resolution':[resolution,resolution],'samples':samples,'strength':strength,
                   'bake_engine':'CYCLES','bake_device':'CPU','shared_atlas_side':'left',
                   'atlas_uv_preserved':True,'only_physical_skin_and_nail_faces_baked':True,
                   'bake_margin_pixels':0,'existing_atlas_gutters_retained':True,
                   'non_skin_shader_topology_and_defaults_preserved':True,
                   'features':['digit-specific open fingertip ridge flow and visible rosy pad tint','four soft overlapping PIP and DIP folds with irregular short branches','fine connected and intersecting skin furrows with nonuniform domain warp','separate palmar flexion creases','pink nail bed, restrained proximal lunula and thin curved free edge','micron-scale longitudinal keratin grain'],
                   'appearance_revision':'photographic_reference_01','prior_finger_normal_replaced_inside_gate':True,
                   'intrinsic_dorsal_from_actual_nail_top_area':True,'concentric_knuckle_rings_removed':True,
                   'microdetail_nominal_height_m':{'fine_network':.000014,'secondary_network':.000007,'fingerprint_ridges':.000025,'main_dorsal_crease':.000108,'main_palmar_crease':.000138,'nail_keratin':.00000115},
                   'maps':{}})
    scene.render.engine='CYCLES';scene.cycles.device='CPU';scene.cycles.samples=samples
    scene.render.bake.use_selected_to_active=False;scene.render.bake.normal_space='TANGENT'
    scene.render.bake.use_clear=False;scene.render.bake.margin=0
    images={}
    protected=_protected_non_skin_texels(hands['left'],resolution)
    original_pixel_hashes={mode:hashlib.sha256(_source_pixels(im)).hexdigest() for mode,im in source_images.items()}
    report['protected_non_skin_interior_texels']=len(protected)
    try:
        for mode in MAPS:
            source=source_images[mode]
            target=source.copy();target.name='FingerDetail_'+mode
            target.colorspace_settings.name='sRGB' if mode=='basecolor' else 'Non-Color'
            # Image.copy keeps every original atlas texel. Only selected skin/nail
            # UV footprints are written by Cycles. Skin/glove material boundaries
            # share UV edges within the same island, so margin must remain zero.
            # Existing atlas gutters retain the original pixels without repaint.
            for record in temporary.values():
                material=record['material'];nodes=material.node_tree.nodes;links=material.node_tree.links
                record['target'].image=target;nodes.active=record['target']
                for n in nodes:n.select=n==record['target']
                if mode=='normal':links.new(record['bsdf'].outputs['BSDF'],record['output'].inputs['Surface'])
                else:
                    links.new(record[mode],record['emission'].inputs['Color'])
                    links.new(record['emission'].outputs[0],record['output'].inputs['Surface'])
            bpy.ops.object.bake(type='NORMAL' if mode=='normal' else 'EMIT',use_clear=False,margin=0)
            path=output_dir/('realistic_hands_'+mode+'.png')
            target.filepath_raw=str(path.resolve());target.file_format='PNG';target.save()
            persisted=_load_fresh_packed(path,target.colorspace_settings.name,'FingerDetail_Packed_'+mode)
            images[mode]=persisted
            # Verify actual serialized PNG pixels, not the higher-precision
            # pre-save bake buffer or an inherited packed source payload.
            values=_source_pixels(persisted);before=_source_pixels(source)
            assert hashlib.sha256(before).hexdigest()==original_pixel_hashes[mode], ('Source image buffer mutated',mode)
            after_np=np.frombuffer(values,dtype=np.float32).reshape(-1,4)
            before_np=np.frombuffer(before,dtype=np.float32).reshape(-1,4)
            max_protected_delta=float(np.max(np.abs(after_np[protected,:3]-before_np[protected,:3])))
            assert max_protected_delta<1e-6, ('Non-skin texture changed',mode,max_protected_delta)
            changed=0
            for start in range(0,len(after_np),262144):
                changed+=int(np.count_nonzero(np.any(np.abs(after_np[start:start+262144,:3]-before_np[start:start+262144,:3])>1e-6,axis=1)))
            assert changed>100, ('Expected baked detail variation',mode,changed)
            samples_rgb=[tuple(values[i:i+3]) for i in range(0,len(values),4*997)]
            report['maps'][mode]={'file':path.name,'sha256':hashlib.sha256(path.read_bytes()).hexdigest(),
                                 'packed':persisted.packed_file is not None,'changed_texels':changed,
                                 'packed_bytes_equal_saved_png':True,
                                 'packed_sha256':hashlib.sha256(persisted.packed_file.data).hexdigest(),
                                 'pixel_statistics_source':'freshly_reloaded_saved_png',
                                 'untouched_texels':resolution*resolution-changed,
                                 'original_source_pixel_sha256':original_pixel_hashes[mode],
                                 'non_skin_interior_maximum_delta':max_protected_delta,
                                 'min_rgb':[min(p[k] for p in samples_rgb) for k in range(3)],
                                 'max_rgb':[max(p[k] for p in samples_rgb) for k in range(3)]}
            del after_np,before_np,values,before
            for record in temporary.values():record['target'].image=None
            bpy.data.images.remove(target)
            print('FINGER_DETAIL_ATLAS_BAKED',mode,changed,flush=True)
        for material in originals.values():
            for mode,image in images.items():material.node_tree.nodes['Baked_'+mode].image=image
        for name,material in originals.items():
            assert _shader_signature(material)==signatures[name], ('Original shader changed',name)
    finally:
        mesh=surface.data;bpy.data.objects.remove(surface,do_unlink=True);bpy.data.meshes.remove(mesh)
        for record in temporary.values():bpy.data.materials.remove(record['material'],do_unlink=True)
    return report
