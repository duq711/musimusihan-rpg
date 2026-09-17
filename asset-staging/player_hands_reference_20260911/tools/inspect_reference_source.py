"""Read-only physical hand, nail and arm-interface measurements for reference rebuild."""
import argparse
import hashlib
import json
from pathlib import Path
import sys

import bpy
from mathutils import Vector

DIGITS=('thumb','index','middle','ring','little')
PHYSICAL=12036


def descendants(obj):
    result=[]
    for child in obj.children:
        result.append(child);result.extend(descendants(child))
    return result


def bounds(points):
    return {'min_m':[min(p[i] for p in points) for i in range(3)],
            'max_m':[max(p[i] for p in points) for i in range(3)]}


def section(points,faces,center,axis,cross,dorsal):
    hits=[]
    for face in faces:
        for ia,ib in zip(face,face[1:]+face[:1]):
            a,b=points[ia],points[ib];da=(a-center).dot(axis);db=(b-center).dot(axis)
            if (da<0)!=(db<0):hits.append(a+(b-a)*(da/(da-db)))
    if not hits:return None
    x=[(p-center).dot(cross) for p in hits];z=[(p-center).dot(dorsal) for p in hits]
    real_center=center+cross*((min(x)+max(x))*.5)+dorsal*((min(z)+max(z))*.5)
    return {'width_mm':(max(x)-min(x))*1000,'thickness_mm':(max(z)-min(z))*1000,
            'intersection_points':len(hits),'measured_center_native':list(real_center),
            'bone_plane_center_offset_mm':(real_center-center).length*1000}


parser=argparse.ArgumentParser(description=__doc__)
parser.add_argument('--source-blend',type=Path,required=True)
parser.add_argument('--report',type=Path,required=True)
args=parser.parse_args(sys.argv[sys.argv.index('--')+1:])
assert bpy.app.background
source=args.source_blend.resolve();sha=lambda:hashlib.sha256(source.read_bytes()).hexdigest();original=sha()
bpy.ops.wm.open_mainfile(filepath=str(source))
scene=bpy.data.scenes['Bilateral_Realistic_Review'];bpy.context.window.scene=scene
report={'source':str(source),'source_sha256':original,'scene':scene.name,'sides':{},
        'coordinate_convention':'Native Blender: +Y fingers, +Z dorsal, -Y forearm; native Godot=(x,z,-y). All measurements in neutral geometry.',
        'physical_vertex_range_evidence':'First 12036 vertices are retained original anatomical surface; appended ranges are joined glove rolls/stitches/panels from previous authored build. Confirm triangle partition below.',
        'reference_limit':'The supplied two-view photo is uncalibrated and perspective/open-pose dependent. No metric body size is inferred from it.'}
for side in ('left','right'):
    holder=scene.objects[side.upper()+'_PreviewTranslationOnly'];objects=descendants(holder);inv=holder.matrix_world.inverted()
    skin=next(o for o in objects if o.type=='MESH' and 'Anatomical' in o.name)
    rig=next(o for o in objects if o.type=='ARMATURE')
    points=[inv@skin.matrix_world@v.co for v in skin.data.vertices]
    physical_faces=[list(p.vertices) for p in skin.data.polygons if max(p.vertices)<PHYSICAL]
    trim_faces=[p for p in skin.data.polygons if min(p.vertices)>=PHYSICAL]
    crossing=[p for p in skin.data.polygons if min(p.vertices)<PHYSICAL<=max(p.vertices)]
    groups={g.index:g.name for g in skin.vertex_groups}
    weights=[{groups[g.group]:g.weight for g in v.groups} for v in skin.data.vertices]
    material_counts={m.name:sum(len(p.vertices)-2 for p in skin.data.polygons if skin.data.materials[p.material_index]==m) for m in skin.data.materials}
    row={'skin':skin.name,'rig':rig.name,'vertices':len(points),'physical_vertices':PHYSICAL,
         'physical_triangles':sum(len(f)-2 for f in physical_faces),
         'trim_vertices':len(points)-PHYSICAL,'trim_triangles':sum(len(p.vertices)-2 for p in trim_faces),
         'physical_to_trim_crossing_faces':len(crossing),'material_triangle_counts':material_counts,
         'physical_bounds':bounds(points[:PHYSICAL]),'joint_keys':[k.name for k in skin.data.shape_keys.key_blocks],
         'bone_count':len(rig.data.bones),'wrist_native':list(inv@rig.matrix_world@rig.data.bones['wrist'].head_local),
         'bone_heads_native':{b.name:list(inv@rig.matrix_world@b.head_local) for b in rig.data.bones},
         'finger_sections':{},'palm_sections':{},'nails':{},'arm_parts':{}}
    for digit in DIGITS:
        face_subset=[f for f in physical_faces if sum(sum(v for name,v in weights[i].items() if name.startswith(digit)) for i in f)/len(f)>.60]
        frames=[]
        for j in range(3):
            matrix=inv@rig.matrix_world@rig.data.bones[digit+str(j)].matrix_local
            frames.append((matrix.translation,matrix.to_3x3().col[1].normalized(),matrix.to_3x3().col[0].normalized(),matrix.to_3x3().col[2].normalized()))
        sections={}
        for j,frame in enumerate(frames):
            sections['joint_'+str(j)]=section(points,face_subset,*frame)
            if j<2:
                center=(frame[0]+frames[j+1][0])*.5
                sections['segment_'+str(j)+'_mid']=section(points,face_subset,center,*frame[1:])
        base,axis,cross,dorsal=frames[2]
        owned=[p for i,p in enumerate(points[:PHYSICAL]) if sum(v for name,v in weights[i].items() if name.startswith(digit))>.60]
        distal=max((p-base).dot(axis) for p in owned)
        sections['distal_60_percent']=section(points,face_subset,base+axis*distal*.6,axis,cross,dorsal)
        sections['distal_85_percent']=section(points,face_subset,base+axis*distal*.85,axis,cross,dorsal)
        sections['bone_head_distances_mm']=[(frames[j+1][0]-frames[j][0]).length*1000 for j in range(2)]
        sections['last_pivot_to_tip_projection_mm']=distal*1000
        row['finger_sections'][digit]=sections
        nail=next(o for o in objects if o.type=='MESH' and o.name.startswith('Nail_'+digit))
        np=[inv@nail.matrix_world@v.co for v in nail.data.vertices]
        row['nails'][digit]={'object':nail.name,'vertices':len(np),'triangles':sum(len(p.vertices)-2 for p in nail.data.polygons),
                            'length_mm':(max(p.dot(axis) for p in np)-min(p.dot(axis) for p in np))*1000,
                            'width_mm':(max(p.dot(cross) for p in np)-min(p.dot(cross) for p in np))*1000,
                            'dorsal_envelope_mm':(max(p.dot(dorsal) for p in np)-min(p.dot(dorsal) for p in np))*1000,
                            'bone_group_names':[g.name for g in nail.vertex_groups]}
    for y in (.0,.02,.04,.06,.08):
        row['palm_sections'][str(y)]=section(points,physical_faces,Vector((0,y,0)),Vector((0,1,0)),Vector((1,0,0)),Vector((0,0,1)))
    for obj in objects:
        if obj.type=='MESH' and any(n in obj.name for n in ('Forearm','WristCuff','UpperArm')):
            pts=[inv@obj.matrix_world@v.co for v in obj.data.vertices]
            row['arm_parts'][obj.name]={'bounds':bounds(pts),'vertices':len(pts),
                                       'custom_properties':{k:v for k,v in obj.items() if k.startswith('wrist_flex')},
                                       'parent':obj.parent.name if obj.parent else None,'modifiers':[m.type for m in obj.modifiers]}
    report['sides'][side]=row
assert sha()==original
report['source_unchanged']=True
args.report.parent.mkdir(parents=True,exist_ok=True)
args.report.write_text(json.dumps(report,indent=2,ensure_ascii=False))
print('REFERENCE_SOURCE_READONLY_INSPECTION_COMPLETE',str(args.report),flush=True)
