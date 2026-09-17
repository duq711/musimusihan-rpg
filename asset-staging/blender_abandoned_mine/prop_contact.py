"""Fit authored mining equipment to the final cave surface.

Called after geological geometry has been finalized, before saving/exporting.
No scene is loaded, saved or exported here. The pass can be repeated: authored
positions are retained in custom properties and old replacement parts removed.
Every contact is measured against the actual terrain triangles, not the coarse
floor-height raster. Returned coordinates are Godot x,y,z in metres.
"""
from __future__ import annotations
import math
import json
from pathlib import Path
import bpy
import numpy as np
from mathutils import Matrix, Vector
from mathutils.bvhtree import BVHTree
import mine_props

TAG = 'mine_physical_contact_v1'
UP = Vector((0,0,1))


def xyz(p):
    return [float(p.x), float(p.z), float(-p.y)]


class ContactScene:
    def __init__(self, layout, report):
        self.layout, self.report = layout, report
        verts, faces = [], []
        bpy.context.view_layer.update()
        for obj in bpy.data.objects:
            if obj.type == 'MESH' and obj.name.startswith('Terrain_'):
                offset = len(verts)
                verts.extend(obj.matrix_world @ v.co for v in obj.data.vertices)
                faces.extend(tuple(offset + v for v in p.vertices) for p in obj.data.polygons)
        self.terrain = BVHTree.FromPolygons(verts, faces, all_triangles=False)
        self.collection = bpy.data.collections['03_AbandonedMine']
        materials = {}
        for key, name in {'wood':'Mine_AgedOak','metal':'Mine_RustedIron','rock':'Mine_Limestone',
                          'rock_dark':'Mine_DarkGallery','rope':'AgedHempRope','cloth':'DustyCanvas',
                          'glass':'LanternSmokeGlass','wick':'LanternWick','flame':'MineLanternLivingFlame'}.items():
            materials[key] = bpy.data.materials.get(name)
            if materials[key] is None:
                materials[key] = next(m for m in bpy.data.materials if name in m.name)
        self.props = mine_props.Props(layout, materials, self.collection, None, lambda x,z:0)
        self.contacts = {'schema_version':1,'ground_contacts':[], 'timber_supports':[], 'wall_lanterns':[],
            'notes':['All contact positions use raycasts against exported Terrain_ triangles.',
                     'Wall oil lamps replace the freestanding path stakes; point lights follow the real wick.',
                     'Roof packing and separately grounded feet connect each timber frame to the cave.',
                     'Table and stacked equipment retain physical support; loose lanterns stand on the ground.']}
        self.segments = []
        for corridor in layout['corridors']:
            for a,b in zip(corridor['points'],corridor['points'][1:]):
                self.segments.append((Vector((a[0],-a[1])),Vector((b[0],-b[1])),corridor))

    def floor(self, x, y):
        hit, normal, _, _ = self.terrain.ray_cast(Vector((x,y,1.15)), -UP, 8)
        return hit if hit is not None and normal.z > .45 else None

    def roof(self, x, y):
        floor = self.floor(x,y)
        if floor is None:return None
        hit, normal, _, _ = self.terrain.ray_cast(floor+UP*1.2, UP, 30)
        return hit if hit is not None else None

    def route_distance(self, p):
        p = Vector((p.x,p.y))
        distances=[]
        for a,b,_ in self.segments:
            axis=b-a
            t=max(0,min(1,(p-a).dot(axis)/max(axis.length_squared,.0001)))
            distances.append((p-a-axis*t).length)
        return min(distances)

    def begin_existing(self, group):
        for child in list(group.children_recursive):
            bpy.data.objects.remove(child,do_unlink=True)
        self.props.group=group
        self.props.pieces=[]
        group[TAG]=True
        for section in ('props','fixtures','architecture'):
            if section in self.report:
                self.report[section]['collision_proxies']=[c for c in self.report[section].get('collision_proxies',[]) if c['asset'] != group.name]
        self.props.collisions=[]
        return self.props

    def finish_existing(self, group, section='props'):
        self.props.finish()
        self.report[section]['collision_proxies'].extend(self.props.collisions)
        p=xyz(group.location)
        for a in self.report[section]['assets']:
            if a['name']==group.name:
                a['position_godot']=p
                a['rotation_y']=float(group.rotation_euler.z)
        bpy.context.view_layer.update()

    def ground_parts(self, group, objects, label, local_transform=None):
        if not objects:return 0
        bpy.context.view_layer.update()
        if local_transform is not None:
            for obj in objects:obj.matrix_local=local_transform@obj.matrix_local
        bpy.context.view_layer.update()
        points=[obj.matrix_world@v.co for obj in objects if obj.type=='MESH' and not obj.hide_render for v in obj.data.vertices]
        if not points:return 0
        low=min(v.z for v in points)
        candidates=[v for v in points if v.z<low+.009]
        values=[]
        for p in candidates:
            floor=self.floor(p.x,p.y)
            if floor is not None:values.append((floor.z-p.z,p,floor))
        if not values:raise RuntimeError('No actual ground below '+group.name+' '+label+' points='+str([tuple(v) for v in candidates[:5]])+' group='+str(tuple(group.location)))
        # Sink all bottom corners by at least 8mm, avoiding one floating side
        # on the irregular gravel. Only the buried contact strip is affected.
        delta=min(v[0] for v in values)-.008
        for obj in objects:obj.location.z+=delta
        contact=max(values,key=lambda v:v[1].z+delta-v[2].z)
        point=contact[1]+UP*delta
        entry={'name':group.name,'part':label,'point_godot':xyz(point),
               'surface_godot':xyz(contact[2]),'gap_m':float(point.z-contact[2].z),
               'adjustment_m':float(delta),
               'surface_normal_godot':xyz(self.terrain.find_nearest(contact[2])[1])}
        self.contacts['ground_contacts'].append(entry)
        return delta

    def subset(self, callback, group, label, transform=None):
        start=len(self.props.pieces)
        children=set(group.children)
        callback()
        objects=list(self.props.pieces[start:])+[o for o in group.children if o not in children and o.hide_render]
        delta=self.ground_parts(group,objects,label,transform)
        return delta

    def rebuild_crates(self, group):
        original_tall=group.get('contact_crates_stacked')
        if original_tall is None:
            inverse=group.matrix_world.inverted()
            highest=max((inverse@child.matrix_world@v.co).z for child in group.children if child.type=='MESH' and not child.hide_render for v in child.data.vertices)
            original_tall=highest>1.26
            group['contact_crates_stacked']=original_tall
        p=self.begin_existing(group)
        left_shift=self.subset(lambda:p.crate((-.52,0,0),(.95,.77,.77)),group,'closed shipping crate')
        self.subset(lambda:p.crate((.48,.19,0),(.85,.70,.64),True),group,'open shipping crate')
        if original_tall:
            # Upper crate rests on the closed lower crate's real lid, not on
            # the neighboring open box or an independent floor offset.
            p.crate((-.52,0,.779+left_shift),(.78,.65,.60))
        self.subset(lambda:p.lantern((.45,-.59,0)),group,'loose oil lantern')
        self.finish_existing(group)

    def rebuild_tools(self, group):
        p=self.begin_existing(group)
        # Abandoned hand tools lie on the floor instead of balancing upright
        # without leaning against anything. Their parts move as rigid objects.
        pick=Matrix.Translation((-.10,.51,.03))@Matrix.Rotation(math.radians(81),4,'X')@Matrix.Rotation(.22,4,'Z')
        shovel=Matrix.Translation((.14,-.51,.02))@Matrix.Rotation(math.radians(-84),4,'X')@Matrix.Rotation(-.25,4,'Z')
        self.subset(lambda:p.pickaxe(),group,'fallen pickaxe',pick)
        self.subset(lambda:p.shovel(),group,'fallen shovel',shovel)
        self.subset(lambda:p.lantern((.03,-.05,0)),group,'loose oil lantern')
        self.subset(lambda:p.rope_coil((-.50,.41,.03),.18,3),group,'rope coil')
        self.finish_existing(group)

    def fit_rigid_ground(self,group):
        if group.get('contact_rigid_grounded'):
            self.contacts['ground_contacts'].append(json.loads(group['contact_ground_record']))
            return
        objects=[o for o in group.children if o.type=='MESH']
        self.ground_parts(group,objects,str(group.get('mine_prop_kind')))
        group['contact_rigid_grounded']=True
        group['contact_ground_record']=json.dumps(self.contacts['ground_contacts'][-1])

    def support_candidate(self, group):
        original=group.get('contact_authored_origin')
        if original is None:
            original=list(group.location)
            group['contact_authored_origin']=original
        original=Vector(original)
        closest=min(self.segments,key=lambda s:self.segment_distance(original,s[0],s[1]))
        corridor=closest[2]
        width=max(2.50,min(4.10,float(corridor['width'])-.70))
        options=[]
        for a,b,c in self.segments:
            if c['id']!=corridor['id']:continue
            direction=(b-a).normalized();side=Vector((-direction.y,direction.x))
            for t in np.linspace(.08,.92,max(6,int((b-a).length*1.5))):
                center=a.lerp(b,float(t))
                for w in (width,max(2.5,width-.5)):
                    samples=[]
                    for offset in np.linspace(-w/2-.15,w/2+.15,17):
                        xy=center+side*float(offset)
                        roof=self.roof(xy.x,xy.y)
                        floor=self.floor(xy.x,xy.y)
                        if roof is None or floor is None:break
                        samples.append((float(offset),roof.z,floor.z))
                    if len(samples)!=17:continue
                    heights=[z-f for x,z,f in samples]
                    if min(heights)<2.85 or max(heights)>7.7:continue
                    # A straight cap can use short packing blocks for rough
                    # strata; do not erect implausible16m poles in the quarry.
                    slope=(samples[-1][1]-samples[0][1])/(samples[-1][0]-samples[0][0])
                    intercept=min(z-slope*x for x,z,f in samples)-.24
                    gaps=[z-(intercept+slope*x+.22) for x,z,f in samples]
                    if max(gaps)>1.0:continue
                    displacement=(center-Vector((original.x,original.y))).length
                    cost=displacement+.5*max(heights)+.8*max(gaps)
                    options.append((cost,center,w,side,slope,intercept,samples))
        if not options:raise RuntimeError('No naturally supported frame site for '+group.name)
        return min(options,key=lambda c:c[0])

    @staticmethod
    def segment_distance(p,a,b):
        v=b-a;p=Vector((p.x,p.y));t=max(0,min(1,(p-a).dot(v)/max(v.length_squared,.0001)))
        return (p-a-v*t).length

    def rebuild_support(self,group):
        _,center,width,side,slope,intercept,samples=self.support_candidate(group)
        p=self.begin_existing(group)
        group.location=(center.x,center.y,0)
        group.rotation_euler.z=math.atan2(side.y,side.x)
        bpy.context.view_layer.update()
        inv=group.matrix_world.inverted()
        feet=[];roofs=[]
        for sign in (-1,1):
            x=sign*width*.5
            xy=group.matrix_world@Vector((x,0,0))
            floor=self.floor(xy.x,xy.y)
            cap=intercept+slope*x
            p.beam('TerrainSunkUpright',(x,0,floor.z-.10),(x,0,cap),.34,.39,wear=.018)
            p.band((x,0,floor.z+.26),.37,.42,.09)
            p.band((x,0,cap-.34),.37,.42,.09)
            p.beam('LoadBearingShoulderBrace',(x,0,cap-1.15),(x-sign*.93,0,intercept+slope*(x-sign*.93)-.03),.21,.24)
            p.proxy('support_foot',(x,0,(floor.z+cap)*.5),(.44,.45,cap-floor.z+.1))
            foot=Vector((xy.x,xy.y,floor.z-.10))
            feet.append({'point_godot':xyz(foot),'surface_godot':xyz(floor),'gap_m':-.10})
        a,b=-width*.5-.23,width*.5+.23
        p.beam('ContinuousRoofCap',(a,0,intercept+slope*a),(b,0,intercept+slope*b),.43,.44,wear=.025)
        # Closely spaced squat packing blocks distribute roof loads along
        # the cap. Upper ends penetrate the sampled rock by30mm.
        for x in np.linspace(a+.06,b-.06,7):
            xy=group.matrix_world@Vector((float(x),0,0))
            roof=self.roof(xy.x,xy.y)
            low=intercept+slope*float(x)+.17
            top=roof.z+.035
            p.beam('RoofContactPacking',(float(x),0,low),(float(x),0,top),.34,.31,wear=.015)
            touch=Vector((xy.x,xy.y,top))
            roofs.append({'point_godot':xyz(touch),'surface_godot':xyz(roof),'gap_m':float(roof.z-top)})
        group['attachment']='terrain_fitted_floor_to_ceiling'
        self.finish_existing(group)
        self.contacts['timber_supports'].append({'name':group.name,'position_godot':xyz(group.location),
            'width_m':width,'rotation_y':float(group.rotation_euler.z),'foot_contacts':feet,'roof_contacts':roofs,
            'maximum_roof_height_m':max(v['surface_godot'][1] for v in roofs)})

    def wall_candidate(self,old):
        choices=[]
        # Retain each lamp's neighborhood and brightness. Its new anchor is
        # a real wall triangle hit from inside the traversable cave volume.
        for dz in (0,.35,-.25,.65):
            origin=old+UP*dz
            for angle in np.linspace(0,math.tau,72,endpoint=False):
                direction=Vector((math.cos(angle),math.sin(angle),0))
                hit,normal,_,distance=self.terrain.ray_cast(origin,direction,18)
                if hit is None or abs(normal.z)>.72:continue
                n=Vector((normal.x,normal.y,0)).normalized()
                if abs(n.dot(direction))<.5:continue
                wick=hit+n*.38
                if self.route_distance(wick)<1.55:continue
                # Lamp lower rim must sit above the pedestrian's shoulders;
                # the small bracket never occupies the floor route.
                floor=self.floor(wick.x,wick.y)
                if floor is None or wick.z-floor.z<1.7:continue
                roof=self.roof(wick.x,wick.y)
                if roof is None or roof.z-wick.z<.63:continue
                # Check the open cage envelope stays in the room; concave
                # corners are rejected rather than letting glass enter rock.
                good=True
                tangent=Vector((-n.y,n.x,0))
                for delta in (-.14,.14):
                    h=self.terrain.ray_cast(wick+tangent*delta,-n,.38)[0]
                    if h is None or (wick+tangent*delta-h).length<.20:good=False;break
                if not good:continue
                score=float(distance)+abs(dz)*.5
                choices.append((score,hit,n,wick))
        if not choices:raise RuntimeError('No real wall attachment near '+str(list(old)))
        return min(choices,key=lambda c:c[0])

    def rebuild_wall_lights(self):
        fixtures=self.report['fixtures']['assets']
        for i,(entry,asset) in enumerate(zip(self.report['lights'],fixtures)):
            group=bpy.data.objects.get(asset['name'])
            if group is None:raise RuntimeError('Missing lamp '+asset['name'])
            original=group.get('contact_authored_wick')
            if original is None:
                pos=entry['position'];original=[pos[0],-pos[2],pos[1]]
                group['contact_authored_wick']=original
            _,hit,n,wick=self.wall_candidate(Vector(original))
            p=self.begin_existing(group)
            # Local -Y points from the wall into the gallery. The mount
            # center lies38cm behind the wick, and its bolts enter the rock.
            group.location=wick
            group.rotation_euler.z=math.atan2(n.y,n.x)+math.pi/2
            bpy.context.view_layer.update()
            inv=group.matrix_world.inverted()
            p.lantern((0,0,-.176),lit=True)
            top=.41
            backplate=p.beam('WallMountedOakBackplate',(0,.405,-.10),(0,.405,.47),.18,.095,wear=.014)
            bpy.context.view_layer.update()
            def wall_local(height, lateral=0):
                origin=group.matrix_world@Vector((lateral,-.12,height))
                surface=self.terrain.ray_cast(origin,-n,1.5)[0]
                if surface is None:raise RuntimeError('Missing backplate bearing '+group.name)
                return inv@surface
            # Shape the rear bearing strip to the rock instead of leaving a
            # planar wooden board suspended in front of a recessed wall.
            object_inverse=backplate.matrix_world.inverted()
            for vertex in backplate.data.vertices:
                local=inv@backplate.matrix_world@vertex.co
                local.y+=wall_local(local.z,local.x).y-.405
                vertex.co=object_inverse@group.matrix_world@local
            backplate.data.update()
            upper_mount=wall_local(top)
            lower_mount=wall_local(.02)
            p.beam('ForgedWallLampArm',tuple(upper_mount),(0,-.016,top),.050,.058,'metal',0)
            p.beam('WallArmTriangleBrace',tuple(lower_mount),(0,.045,top),.028,.035,'metal',0)
            p.tube('AttachedHangingHook',[(0,-.016,top),(0,-.016,.355),(0,.005,.344),(0,.018,.365)],.011,'metal',10)
            anchors=[]
            for height in (-.04,.37):
                origin=wick+UP*height
                anchor,normal,_,_=self.terrain.ray_cast(origin,-n,1.2)
                if anchor is None:raise RuntimeError('Missing wall bolt contact '+group.name)
                local=inv@anchor
                end=local+Vector((0,.085,0))
                p.tube('RockEmbeddedAnchorBolt',[(0,local.y-.025,height),tuple(end)],.018,'metal',10)
                p.bolt((0,local.y-.065,height),(0,-1,0),.027)
                anchors.append({'point_godot':xyz(group.matrix_world@end),'surface_godot':xyz(anchor),'penetration_m':.085})
            # A compact mount proxy attaches to the rock at upper-body height;
            # the old floor-to-ceiling freestanding stake is entirely removed.
            p.proxy('wall_lamp_mount',(0,.34,.16),(.24,.20,.65))
            group['attachment']='raycast_wall_bracket'
            self.finish_existing(group,'fixtures')
            entry['position']=xyz(wick)
            asset['wick_godot']=xyz(wick)
            asset['attachment']='raycast_wall_bracket'
            for name in ('MineLight_%03d'%i,'LightMarker_%03d'%i):
                obj=bpy.data.objects.get(name)
                if obj:obj.location=wick
            self.contacts['wall_lanterns'].append({'name':group.name,'light_index':i,'wick_godot':xyz(wick),
                'wall_anchor_godot':xyz(hit),'wall_normal_godot':xyz(n),
                'bracket_tip_godot':xyz(group.matrix_world@Vector((0,0,.40))),
                'anchor_contacts':anchors,'route_distance_m':self.route_distance(wick),
                'wall_offset_m':.38})

    def run(self):
        groups=[o for o in bpy.data.objects if o.type=='EMPTY' and o.get('mine_prop_kind')]
        for group in groups:
            kind=group.get('mine_prop_kind')
            if kind=='abandoned_crate_stack':self.rebuild_crates(group)
            elif kind=='abandoned_hand_tools':self.rebuild_tools(group)
            elif kind=='timber_support':self.rebuild_support(group)
            elif kind in ('workbench','foreman_bench','barrels_and_rope','manual_hoist','ore_cart','overturned_ore_cart','torn_canvas_rack'):
                self.fit_rigid_ground(group)
        self.rebuild_wall_lights()
        # Refresh collider coordinates after per-part grounding/transforming.
        bpy.context.view_layer.update()
        for section in ('props','fixtures','architecture'):
            for c in self.report.get(section,{}).get('collision_proxies',[]):
                obj=bpy.data.objects.get(c['name'])
                if obj:
                    c['center_godot']=xyz(obj.matrix_world.translation)
        for category in ('ground_contacts','timber_supports','wall_lanterns'):
            for item in self.contacts[category]:
                group=bpy.data.objects.get(item['name'])
                item['mesh_names']=[o.name for o in group.children if o.type=='MESH' and not o.hide_render]
        self.contacts['counts']={key:len(self.contacts[key]) for key in ('ground_contacts','timber_supports','wall_lanterns')}
        self.report['prop_contact']=self.contacts
        return self.contacts


def fix_scene(layout,report):
    """Mutate only prop assemblies/lights in the currently loaded scene.

    Returns the JSON-safe contact audit, also stored as report['prop_contact'].
    Caller owns saving the source, manifest and gameplay export.
    """
    return ContactScene(layout,report).run()
