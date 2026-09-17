"""Replace only nail plates in an approved reference-hand geometry scene."""
import argparse
import hashlib
import json
import sys
from pathlib import Path

import bpy
from mathutils import Vector
from mathutils.bvhtree import BVHTree
sys.path.insert(0,str(Path(__file__).resolve().parent))
from build_reference_hands import collect
from reference_geometry import nail_plate, smooth, DIGITS


def sha(path):return hashlib.sha256(path.read_bytes()).hexdigest()

def frozen_payload(hands, allow_cuff_band=False):
    result={}
    for side,(holder,objects,rig,skin,nails) in hands.items():
        row={}
        for obj in [holder,*objects]:
            if obj in nails:continue
            item={'matrix_world':[list(v) for v in obj.matrix_world],
                  'matrix_basis':[list(v) for v in obj.matrix_basis],
                  'parent':obj.parent.name if obj.parent else None,
                  'properties':dict(obj.items())}
            if obj.type=='ARMATURE':
                item['bones']={b.name:{'parent':b.parent.name if b.parent else None,
                      'rest':[list(r) for r in b.matrix_local],
                      'pose':[list(r) for r in rig.pose.bones[b.name].matrix_basis]} for b in rig.data.bones}
            if obj.type=='MESH':
                mesh=obj.data
                item['vertices']=[list(v.co) for v in mesh.vertices]
                if allow_cuff_band and 'WristCuff' in obj.name:
                    transform=holder.matrix_world.inverted()@obj.matrix_world
                    item['vertices']=[None if -.025<(transform@v.co).y<0. else list(v.co) for v in mesh.vertices]
                item['faces']=[list(p.vertices) for p in mesh.polygons]
                item['weights']=[[(g.group,g.weight) for g in v.groups] for v in mesh.vertices]
                item['groups']=[g.name for g in obj.vertex_groups]
                item['materials']=[m.name if m else None for m in mesh.materials]
                item['face_materials']=[p.material_index for p in mesh.polygons]
                item['uv']={layer.name:[list(v.uv) for v in layer.data] for layer in mesh.uv_layers}
                if mesh.shape_keys:
                    item['keys']={k.name:{'value':k.value,'points':[list(v.co) for v in k.data]} for k in mesh.shape_keys.key_blocks}
            row[obj.name]=item
        result[side]=row
    return hashlib.sha256(json.dumps(result,sort_keys=True,default=str).encode()).hexdigest()


def repair_wrist_overlap(obj,holder,skin):
    transform=holder.matrix_world.inverted()@obj.matrix_world;inverse=transform.inverted()
    original=[transform@v.co for v in obj.data.vertices]
    moved=[]
    for i,p in enumerate(original):
        # Cuff outer rings end at 33*64. Leave its inner wall and every vertex
        # beyond this authorized axial band untouched, including the forearm end.
        z=-p.y
        if i>=33*64 or not .010<z<.025:continue
        lift=.00035*smooth(.011,.0175,z)*(1.-smooth(.022,.025,z))
        if lift<1e-10:continue
        q=p+Vector((p.x,0,p.z)).normalized()*lift
        obj.data.vertices[i].co=inverse@q;moved.append(i)
    obj.data.update()
    current=[transform@v.co for v in obj.data.vertices]
    protected=max((a-b).length for a,b in zip(original,current) if not -.025<a.y<0.)
    proximal=max((a-b).length for a,b in zip(original,current) if a.y<=-.075)
    assert protected<1e-9 and proximal<1e-9
    skin_matrix=holder.matrix_world.inverted()@skin.matrix_world
    skin_points=[skin_matrix@v.co for v in skin.data.vertices]
    outer_faces=[list(p.vertices) for p in obj.data.polygons if max(p.vertices)<33*64]
    cover={}
    for label,points in [('before',original),('after',current)]:
        tree=BVHTree.FromPolygons(points,outer_faces);values=[]
        for p in skin_points:
            if not -.022<p.y<-.019:continue
            direction=Vector((p.x,0,p.z)).normalized();center=Vector((0,p.y,0))
            hit=tree.ray_cast(center+direction*.1,-direction,.15)
            assert hit[0] is not None
            values.append((hit[0]-p).dot(direction))
        cover[label]={'samples':len(values),'minimum_cuff_cover_m':min(values),'maximum_cuff_cover_m':max(values)}
    assert cover['after']['minimum_cuff_cover_m']>.00012,'Cutoff remains exposed'
    return {'object':obj.name,'authorized_native_y_band_m':[-.025,0.],
            'changed_outer_vertices':len(moved),'maximum_radial_move_m':max((a-b).length for a,b in zip(original,current)),
            'protected_outside_band_error_m':protected,'proximal_y_le_minus075_error_m':proximal,
            'skin_cutoff_coverage':cover,'geometry_faces_weights_metadata_uv_unchanged':True}


def main():
    p=argparse.ArgumentParser();p.add_argument('--source',type=Path,required=True);p.add_argument('--output',type=Path,required=True)
    args=p.parse_args(sys.argv[sys.argv.index('--')+1:])
    source=args.source.resolve();output=args.output.resolve()
    assert bpy.app.background and source.is_file()
    assert not output.exists() or not any(output.iterdir()), 'Repair output must be new/empty'
    source_sha=sha(source);source_report=source.with_name('geometry_report.json')
    report=json.loads(source_report.read_text());assert report['geometry_blend_sha256']==source_sha
    bpy.ops.wm.open_mainfile(filepath=str(source));scene=bpy.data.scenes['Bilateral_Reference_Review'];bpy.context.window.scene=scene
    hands=collect(scene);before=frozen_payload(hands);rows={}
    for side,(holder,objects,rig,skin,nails) in hands.items():
        transform=holder.matrix_world.inverted()@skin.matrix_world
        points=[transform@v.co for v in skin.data.vertices]
        faces=[list(p.vertices) for p in skin.data.polygons]
        group_names={g.index:g.name for g in skin.vertex_groups}
        rows[side]=[]
        for digit in DIGITS:
            weights=[sum(g.weight for g in v.groups if group_names[g.group].startswith(digit)) for v in skin.data.vertices]
            nail=next(o for o in nails if o.name.startswith('Nail_'+digit))
            old={'vertices':len(nail.data.vertices),'triangles':sum(len(p.vertices)-2 for p in nail.data.polygons)}
            row=nail_plate(nail,skin,rig,holder,digit,points,faces,weights);row['replaced_plate']=old
            rows[side].append(row)
            print('NAIL_REPAIRED',side,digit,json.dumps(row),flush=True)
        report['hands'][side]['nails']=rows[side]
    after=frozen_payload(hands);assert before==after,'Nail-only repair altered frozen hand/rig/cuff payload'
    cuff_protected_before=frozen_payload(hands,True);cuff_rows={}
    for side,(holder,objects,rig,skin,nails) in hands.items():
        cuff=next(o for o in objects if o.type=='MESH' and 'WristCuff' in o.name)
        cuff_rows[side]=repair_wrist_overlap(cuff,holder,skin)
        report['hands'][side]['wrist_overlap_repair']=cuff_rows[side]
    cuff_protected_after=frozen_payload(hands,True)
    assert cuff_protected_before==cuff_protected_after,'Cuff repair altered protected payload'
    output.mkdir(parents=True,exist_ok=True);target=output/source.name
    bpy.context.preferences.filepaths.save_version=0
    bpy.ops.wm.save_as_mainfile(filepath=str(target))
    assert sha(source)==source_sha
    report['geometry_blend_sha256']=sha(target)
    report['status']='nail_repaired_pending_independent_validation_and_visual_review'
    report['nail_repair']={'input_geometry03':str(source),'input_sha256':source_sha,
                         'frozen_skin_keys_weights_bones_cuff_before_sha256':before,
                         'frozen_skin_keys_weights_bones_cuff_after_sha256':after,
                         'nail_phase_non_nail_payload_exact':True,'source_file_unchanged':True,
                         'cuff_band_protected_before_sha256':cuff_protected_before,
                         'cuff_band_protected_after_sha256':cuff_protected_after,
                         'all_except_nails_and_authorized_cuff_band_exact':True,'wrist_overlap_repair':cuff_rows,
                         'method':'Dense projected triangular top, actual top vertex/triangle interior clearance checks and local outward-only surface fitting.',
                         'notes':'Inherited original source and geometry facts retain original04 provenance. Replaced ten nails and resolved independently confirmed skin/cuff intersection only in authorized distal cuff band.',
                         'render_status':'No new render performed by this repair helper; inherited clay views document pre-repair geometry03 only.'}
    report['prior_geometry_renders']=report.pop('renders',{})
    (output/'geometry_report.json').write_text(json.dumps(report,indent=2,ensure_ascii=False))
    print('NAIL_REPAIR_COMPLETE',str(target),flush=True)

if __name__=='__main__':main()
