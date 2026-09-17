"""Attach every mineral component and remove unsupported rock-skin triangles.

This is a production scene pass, not a visibility override. It does not load,
save or export a file. The caller runs it after surface_contact and before
assigning final geology materials/UVs. Reports include actual triangle samples,
not just vertices (a vertex-only fit cannot detect a face bridging empty air).
"""
import json
import bpy
import bmesh
import numpy as np
from mathutils import Vector
import rock_detail

VERSION = 1
MAX_FACE_GAP = .105  # final exported centroid and edge-midpoint bound is .11m
ROOT_BURIAL = .035
UP = Vector((0,0,1))


def godot(p):
    return [float(p.x),float(p.z),float(-p.y)]


def components(mesh):
    parent=list(range(len(mesh.vertices)))
    def find(v):
        while parent[v]!=v:
            parent[v]=parent[parent[v]]
            v=parent[v]
        return v
    for edge in mesh.edges:
        a,b=edge.vertices
        ra,rb=find(a),find(b)
        if ra!=rb:parent[rb]=ra
    grouped={}
    for i in range(len(mesh.vertices)):
        grouped.setdefault(find(i),[]).append(i)
    return list(grouped.values())


def boundary_indices(mesh):
    counts={}
    for face in mesh.polygons:
        ids=list(face.vertices)
        for a,b in zip(ids,ids[1:]+ids[:1]):
            edge=(min(a,b),max(a,b))
            counts[edge]=counts.get(edge,0)+1
    return sorted({v for edge,count in counts.items() if count==1 for v in edge})


def remove_faces(mesh,indices):
    if not indices:return
    bm=bmesh.new();bm.from_mesh(mesh);bm.faces.ensure_lookup_table()
    bmesh.ops.delete(bm,geom=[bm.faces[i] for i in indices],context='FACES')
    loose=[v for v in bm.verts if not v.link_faces]
    if loose:bmesh.ops.delete(bm,geom=loose,context='VERTS')
    bm.to_mesh(mesh);bm.free();mesh.update()


def remove_components(mesh,sets):
    ids=set(v for indices in sets for v in indices)
    if not ids:return
    remove_faces(mesh,[f.index for f in mesh.polygons if any(v in ids for v in f.vertices)])


class FormationContact:
    def __init__(self,layout,report):
        self.layout,self.report=layout,report
        self.terrain=rock_detail._terrain_surface()
        if self.terrain is None:raise RuntimeError('Actual terrain is required for formation contact')
        self.audit={'version':VERSION,'assets':[],'removed_assets':[],
            'max_face_gap_m':MAX_FACE_GAP,'root_burial_m':ROOT_BURIAL,
            'method':'Connected mineral roots fitted to actual terrain; rock-skin face interiors and edge midpoints tested; unsupported bridging triangles permanently removed and new edges buried.'}

    def surface(self,x,y,hanging):
        point,normal,_,_=self.terrain.ray_cast(Vector((x,y,1.2)),UP if hanging else -UP,30)
        if point is None:return None
        if hanging and normal.z>-.05:return None
        if not hanging and normal.z<.4:return None
        return point,normal

    def fit_minerals(self,obj):
        if obj.get('formation_contact_version')==VERSION:
            self.audit['assets'].extend(json.loads(obj['formation_contact_report']))
            self.audit['removed_assets'].extend(json.loads(obj.get('formation_removed_components','[]')))
            return
        world=obj.matrix_world.copy();inverse=world.inverted()
        mesh=obj.data
        if mesh.users>1:obj.data=mesh.copy();mesh=obj.data
        coords=[world@v.co for v in mesh.vertices]
        entries=[];discard=[];removed_start=len(self.audit['removed_assets'])
        for index,ids in enumerate(components(mesh)):
            points=[coords[i] for i in ids]
            low=min(p.z for p in points);high=max(p.z for p in points)
            calcite=len(ids)>60 and high-low>.19
            hanging=calcite and not obj.name.startswith('RockFormation_')
            kind='ceiling_calcite' if hanging else ('floor_stalagmite' if calcite else 'floor_scree')
            anchor_height=high if hanging else low
            root_ids=[i for i in ids if abs(coords[i].z-anchor_height)<.012]
            center=sum((coords[i] for i in root_ids),Vector())/len(root_ids)
            old_gaps=[];hits={}
            for i in root_ids:
                hit=self.surface(coords[i].x,coords[i].y,hanging)
                if hit is not None:
                    hits[i]=hit
                    old_gaps.append((hit[0].z-coords[i].z) if hanging else (coords[i].z-hit[0].z))
            if len(hits)!=len(root_ids):
                # A decorative mineral is never allowed to hang over an
                # actual cave opening merely because the raster had a value.
                discard.append(ids)
                self.audit['removed_assets'].append({'name':obj.name,'component':index,'kind':kind,
                    'position_godot':godot(center),'reason':'A component root has no actual floor/ceiling bearing surface'})
                continue
            if calcite:
                roof_min=min(h[0].z for h in hits.values()) if hanging else None
                whole_shift=(roof_min-anchor_height+ROOT_BURIAL) if hanging else 0
                # Form an embedded, irregular root apron. Keep the taper and
                # tip shape, but join the broad base to the actual rock rather
                # than a horizontal nominal height or a single sampled point.
                for i in ids:
                    point=coords[i].copy()
                    t=(anchor_height-point.z)/(high-low) if hanging else (point.z-anchor_height)/(high-low)
                    influence=max(0,1-t/.34)**2
                    if not hanging:
                        widen=1+.18*max(0,1-t/.26)**2
                        point.x=center.x+(point.x-center.x)*widen
                        point.y=center.y+(point.y-center.y)*widen
                    surface=self.surface(point.x,point.y,hanging)
                    if surface is None:continue
                    if hanging:
                        point.z+=whole_shift
                        point.z+=(surface[0].z+ROOT_BURIAL-(anchor_height+whole_shift))*influence
                    else:
                        point.z+=(surface[0].z-ROOT_BURIAL-anchor_height)*influence
                    mesh.vertices[i].co=inverse@point
                    coords[i]=point
            else:
                # Scree stays partly buried. Correct a loose component only
                # if any bottom contact is floating; never lift buried gravel.
                shift=min(0,min(hits[i][0].z-coords[i].z for i in root_ids)-.018)
                for i in ids:
                    coords[i]+=UP*shift
                    mesh.vertices[i].co=inverse@coords[i]
            samples=[]
            for i in root_ids:
                point=coords[i];hit=self.surface(point.x,point.y,hanging)
                if hit is None:continue
                gap=hit[0].z-point.z if hanging else point.z-hit[0].z
                samples.append({'point_godot':godot(point),'surface_godot':godot(hit[0]),
                    'normal_godot':godot(hit[1]),'gap_m':float(gap)})
            assert samples and max(s['gap_m'] for s in samples)<.003,(obj.name,index,samples)
            entry={'name':obj.name,'component':index,'kind':kind,'position_godot':godot(center),
                'previous_max_root_gap_m':max(old_gaps),'max_root_gap_m':max(s['gap_m'] for s in samples),
                'contact_samples':samples,'changed':calcite or any(gap>-.018 for gap in old_gaps)}
            entries.append(entry)
        remove_components(mesh,discard)
        mesh.update()
        obj['formation_contact_version']=VERSION
        obj['formation_contact_report']=json.dumps(entries)
        obj['formation_removed_components']=json.dumps(self.audit['removed_assets'][removed_start:])
        self.audit['assets'].extend(entries)

    def test_faces(self,obj,keep_samples=True):
        co=[obj.matrix_world@v.co for v in obj.data.vertices]
        bad=[];worst=[];count=0;maximum=0.0
        for face in obj.data.polygons:
            ids=list(face.vertices)
            points=[co[i] for i in ids]
            samples=[('centroid',sum(points,Vector())/len(points))]
            samples.extend(('edge_midpoint',(a+b)*.5) for a,b in zip(points,points[1:]+points[:1]))
            invalid=False
            for kind,p in samples:
                hit,normal,_,gap=self.terrain.find_nearest(p)
                if hit is None:raise RuntimeError('Missing rock-skin terrain host '+obj.name)
                count+=1;maximum=max(maximum,float(gap))
                if gap>MAX_FACE_GAP:invalid=True
                if keep_samples:
                    worst.append((float(gap),face.index,kind,p.copy(),hit,normal))
            if invalid:bad.append(face.index)
        if keep_samples:worst=sorted(worst,key=lambda s:s[0],reverse=True)[:16]
        return bad,worst,maximum,count

    def bury_boundary(self,obj):
        world=obj.matrix_world.copy();inverse=world.inverted()
        for i in boundary_indices(obj.data):
            point=world@obj.data.vertices[i].co
            hit,normal,_,_=self.terrain.find_nearest(point)
            obj.data.vertices[i].co=inverse@(hit-normal*.027)
        obj.data.update()

    def remove_tiny_patches(self,obj):
        mesh=obj.data
        small=[]
        for ids in components(mesh):
            index_set=set(ids)
            faces=[f for f in mesh.polygons if f.vertices[0] in index_set]
            if len(faces)<16:small.append(ids)
        if small:remove_components(mesh,small)
        return len(small)

    def fit_skin(self,obj):
        if obj.get('formation_skin_contact_version')==VERSION:
            entry=json.loads(obj['formation_skin_contact_report'])
            self.audit['assets'].append(entry)
            self.refresh_scan_report(obj,entry)
            return
        mesh=obj.data
        if mesh.users>1:obj.data=mesh.copy();mesh=obj.data
        original_faces=len(mesh.polygons)
        center=sum((obj.matrix_world@v.co for v in mesh.vertices),Vector())/max(1,len(mesh.vertices))
        bad,_,old_gap,_=self.test_faces(obj,False)
        removed_components=0
        iterations=0
        while bad and iterations<16:
            remove_faces(mesh,bad)
            removed_components+=self.remove_tiny_patches(obj)
            self.bury_boundary(obj)
            bad,_,_,_=self.test_faces(obj,False)
            iterations+=1
        if bad:
            # No arbitrary unsupported sheets survive just to preserve the
            # decorative asset count. The full Terrain_ wall stays untouched.
            remove_faces(mesh,list(range(len(mesh.polygons))))
        if not mesh.polygons:
            entry={'name':obj.name,'kind':'wall_skin','position_godot':godot(center),
                'reason':'No coherent rock-skin patch passed face-interior contact validation',
                'removed_faces':original_faces}
            self.audit['removed_assets'].append(entry)
            bpy.data.objects.remove(obj,do_unlink=True)
            return
        _,samples,maximum,count=self.test_faces(obj,True)
        assert maximum<=MAX_FACE_GAP+.00001,(obj.name,maximum)
        entry={'name':obj.name,'kind':'wall_skin','position_godot':godot(center),
            'previous_max_face_gap_m':float(old_gap),'max_face_gap_m':float(maximum),
            'removed_faces':original_faces-len(mesh.polygons),'remaining_faces':len(mesh.polygons),
            'removed_tiny_components':removed_components,'tested_face_points':count,
            'face_samples':[{'triangle_index':f,'sample_kind':kind,'point_godot':godot(p),
                'surface_godot':godot(hit),'normal_godot':godot(normal),'gap_m':gap}
                for gap,f,kind,p,hit,normal in samples],
            'changed':original_faces!=len(mesh.polygons)}
        obj['formation_skin_contact_version']=VERSION
        obj['formation_skin_contact_report']=json.dumps(entry)
        self.audit['assets'].append(entry)
        self.refresh_scan_report(obj,entry)
        print('FACE_CONTACT',obj.name,'removed',entry['removed_faces'],'gap',round(maximum,5),flush=True)

    def refresh_scan_report(self,obj,entry):
        # surface_contact's cached report otherwise still names removed rim
        # vertices. Refresh it from the final retained topology for later runs.
        prior=obj.get('surface_contact_report')
        data=prior.to_dict() if hasattr(prior,'to_dict') else dict(prior or {})
        data['name']=obj.name
        data['vertices']=len(obj.data.vertices)
        boundary=boundary_indices(obj.data)
        data['open_rim_vertices']=len(boundary)
        data['rim_burial_m']=.027
        data['boundary_samples']=[]
        for i in boundary[::max(1,len(boundary)//12)][:12]:
            p=obj.matrix_world@obj.data.vertices[i].co
            hit,n,_,_=self.terrain.find_nearest(p)
            data['boundary_samples'].append({'vertex':godot(p),'surface':godot(hit),'normal':godot(n)})
        data['max_face_gap_m']=entry['max_face_gap_m']
        data['trimmed_bridging_faces']=entry['removed_faces']
        obj['surface_contact_report']=data
        subtree=self.report.get('rock_surface_contact',{})
        assets=subtree.get('assets',[])
        for i,asset in enumerate(assets):
            if asset['name']==obj.name:assets[i]=data;break

    def run(self):
        bpy.context.view_layer.update()
        targets=[o for o in bpy.data.objects if o.type=='MESH']
        for obj in targets:
            if obj.name.startswith(('MineralCluster_','CalciteCeiling_','Scree_','RockFormation_')):
                self.fit_minerals(obj)
            elif obj.name.startswith('RockScan_'):
                self.fit_skin(obj)
        kept={o.name for o in bpy.data.objects}
        if 'rock_surface_contact' in self.report:
            subtree=self.report['rock_surface_contact']
            subtree['assets']=[a for a in subtree['assets'] if a['name'] in kept]
            subtree['scan_count']=len(subtree['assets'])
        self.audit['counts']={kind:sum(a['kind']==kind for a in self.audit['assets'])
            for kind in ('floor_stalagmite','floor_scree','ceiling_calcite','wall_skin')}
        self.audit['removed_faces']=sum(a.get('removed_faces',0) for a in self.audit['assets']+self.audit['removed_assets'])
        self.audit['changed_asset_names']=sorted({a['name'] for a in self.audit['assets'] if a.get('changed')}|{a['name'] for a in self.audit['removed_assets']})
        self.report['formation_contact']=self.audit
        bpy.context.view_layer.update()
        return self.report


def fix_scene(layout,report):
    return FormationContact(layout,report).run()
