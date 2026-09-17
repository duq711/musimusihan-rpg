"""Shared final polish for the Blender source and the exported play scene."""
import bpy, math, json
import numpy as np
from mathutils import Vector
from pathlib import Path
ROOT=Path(__file__).resolve().parent

def finish_scene(layout, report):
    data=np.load(ROOT/'terrain_mesh.npz')
    xs,zs=data['xs'],data['zs']
    segments=[(np.array(a),np.array(b)) for c in layout['corridors'] for a,b in zip(c['points'][:-1],c['points'][1:])]
    a=np.array([x[0] for x in segments]); v=np.array([x[1]-x[0] for x in segments]); vv=(v*v).sum(axis=1)
    def route_distance(x,z):
        d=np.array([x,z])-a
        t=np.clip((d*v).sum(axis=1)/np.maximum(vv,.0001),0,1)
        return float(np.linalg.norm(d-t[:,None]*v,axis=1).min())
    def sample(grid,x,z):
        ix=int(np.clip(round((x-xs[0])/(xs[1]-xs[0])),0,len(xs)-1)); iz=int(np.clip(round((z-zs[0])/(zs[1]-zs[0])),0,len(zs)-1))
        return float(data[grid][iz,ix])
    moved=[]
    for index,entry in enumerate(report['lights']):
        p=entry['position']; x,y,z=p
        if route_distance(x,z)>1.05: continue
        candidate=None
        for radius in np.arange(.5,5.5,.5):
            options=[]
            for angle in np.arange(32)*math.tau/32:
                nx=x+math.cos(angle)*radius; nz=z+math.sin(angle)*radius
                if route_distance(nx,nz)>1.10 and sample('signed_distance',nx,nz)>.32:
                    options.append((nx,nz))
            if options:
                candidate=max(options,key=lambda q:sample('signed_distance',*q));break
        assert candidate, ('No safe lamp placement',index)
        nx,nz=candidate; dy=sample('floor',nx,nz)-sample('floor',x,z)
        delta=Vector((nx-x,-nz+z,dy))
        fixture=report['fixtures']['assets'][index]
        group=bpy.data.objects.get(fixture['name'])
        assert group, fixture['name']
        group.location+=delta
        for name in ['MineLight_%03d'%index,'LightMarker_%03d'%index]:
            obj=bpy.data.objects.get(name)
            if obj: obj.location+=delta
        entry['position']=[nx,y+dy,nz]
        fixture['position_godot']=[nx,fixture['position_godot'][1]+dy,nz]
        fixture['wick_godot']=entry['position'][:]
        for collision in report['fixtures'].get('collision_proxies',[]):
            if collision['asset']==fixture['name']:
                c=collision['center_godot'];collision['center_godot']=[c[0]+nx-x,c[1]+dy,c[2]+nz-z]
        moved.append(index)
    # Floor material belongs to gently sloped walkable faces. Assigning mud to
    # every upward-facing triangle on a low cliff created a saw-toothed fringe.
    fixed=0
    for obj in bpy.data.objects:
        if obj.type!='MESH' or not obj.name.startswith('Terrain_'):continue
        for face in obj.data.polygons:
            if face.material_index==4 and (face.normal.z<.72 or face.center.z>.18):
                p=face.center
                face.material_index=int(round(sample('geology',p.x,-p.y)))
                fixed+=1
    import bone_props
    bone_props.apply_portable_bone_material()
    bpy.context.view_layer.update()
    report['polish']={'route_safe_lamp_relocations':moved,'floor_fringe_faces_corrected':fixed,'portable_bone_material':True}
    return report
