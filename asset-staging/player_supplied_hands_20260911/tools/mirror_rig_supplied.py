"""Mirror supplied low geometry in mesh data, preserve UV intent, rebuild right rig."""
import copy
import hashlib
import json
from pathlib import Path
import sys

import bpy
import numpy as np
from mathutils import Matrix

HERE=Path(__file__).resolve().parent
sys.path.insert(0,str(HERE))
from rig_supplied import DIGITS,coordinates,rig_hand

STAGE=HERE.parent
SOURCE=STAGE/'geometry/supplied_left_prepared.blend'
LANDMARKS=STAGE/'geometry/canonical_landmarks.json'
OUTPUT=STAGE/'geometry/supplied_right_rigged.blend'
REFLECTED=STAGE/'geometry/canonical_landmarks_right.json'

def sha(p):return hashlib.sha256(Path(p).read_bytes()).hexdigest()

def reflected_landmarks(original):
    result=copy.deepcopy(original)
    def reflect(value):return[-float(value[0]),float(value[1]),float(value[2])]
    for key in ('wrist','wrist_head','wrist_tail','wrist_cap_center','wrist_cap_canonical'):
        if key in result:result[key]=reflect(result[key])
    for d,record in result['digits'].items():
        for key in ('root','pip','dip','tip','nail_centroid','nail_outward_normal','nail_normal','dorsal_normal'):
            if key in record:record[key]=reflect(record[key])
        record['points']=[reflect(p)for p in record['points']]
    reflection=np.diag((-1.,1.,1.,1.))
    result['source_to_canonical_matrix']=(reflection@np.asarray(original['source_to_canonical_matrix'])).tolist()
    result['side']='right'
    result['coordinate_system']='+Y fingers, +Z dorsum, -X right-hand radial/thumb side; metres'
    result['right_hand_method']='Geometric X reflection of the supplied left hand; reflected points/nail normals with a newly authored right skeleton. No negative object or parent scale.'
    result['source_left_landmarks_sha256']=sha(LANDMARKS)
    return result

def reflect_mesh(obj):
    assert np.max(np.abs(np.asarray(obj.matrix_world)-np.eye(4)))<1e-8
    mesh=obj.data;before=coordinates(obj);faces=[tuple(p.vertices)for p in mesh.polygons]
    normals=np.asarray([p.normal[:]for p in mesh.polygons])
    layers={u.name:[{mesh.loops[i].vertex_index:tuple(u.data[i].uv)for i in p.loop_indices}for p in mesh.polygons]for u in mesh.uv_layers}
    materials=[p.material_index for p in mesh.polygons];smooth=[p.use_smooth for p in mesh.polygons]
    for v in mesh.vertices:v.co.x=-v.co.x
    mesh.flip_normals();mesh.update()
    # Explicitly restore per-face/per-vertex UV correspondence even if a Blender
    # version's winding operation changes the corner custom-data permutation.
    for layer in mesh.uv_layers:
        for p in mesh.polygons:
            assert set(p.vertices)==set(faces[p.index])
            for i in p.loop_indices:layer.data[i].uv=layers[layer.name][p.index][mesh.loops[i].vertex_index]
    mesh.update()
    after=coordinates(obj);expected=before.copy();expected[:,0]*=-1
    error=float(np.linalg.norm(after-expected,axis=1).max());assert error<1e-8
    current_normals=np.asarray([p.normal[:]for p in mesh.polygons]);expected_normals=normals.copy();expected_normals[:,0]*=-1
    alignment=np.sum(current_normals*expected_normals,axis=1)
    assert float(alignment.min())>.9999,'Reflected face winding is inconsistent with outward source winding'
    uv_error=0.
    for layer in mesh.uv_layers:
        for p in mesh.polygons:
            for i in p.loop_indices:
                old=layers[layer.name][p.index][mesh.loops[i].vertex_index]
                uv_error=max(uv_error,float(np.linalg.norm(np.asarray(layer.data[i].uv)-old)))
    assert uv_error==0. and materials==[p.material_index for p in mesh.polygons]and smooth==[p.use_smooth for p in mesh.polygons]
    assert np.max(np.abs(np.asarray(obj.matrix_world)-np.eye(4)))<1e-8
    old_name=obj.name;obj.name=old_name+'_Right';mesh.name=obj.name+'_Mesh'
    obj['source_reflection']='X reflection in mesh coordinates, with corrected outward face winding and unchanged UV-to-vertex correspondence'
    return{'source_low_object':old_name,'right_low_object':obj.name,'vertices':len(mesh.vertices),'faces':len(mesh.polygons),
        'maximum_reflection_error_m':error,'minimum_reflected_outward_normal_alignment':float(alignment.min()),
        'maximum_per_corner_uv_error':uv_error,'uv_layers':list(layers),'identity_object_transform':True,
        'tangent_intent':'UVs remain attached to their corresponding reflected vertices; outward winding corrected. Exporter must derive tangents from the reflected geometry and UVs.'}

def main():
    assert bpy.app.background and not OUTPUT.exists()and not REFLECTED.exists()
    inputs={str(p):sha(p)for p in (SOURCE,LANDMARKS,HERE/'rig_supplied.py')}
    original=json.loads(LANDMARKS.read_text());landmarks=reflected_landmarks(original)
    bpy.ops.wm.open_mainfile(filepath=str(SOURCE))
    scene=bpy.context.scene;scene.name='Supplied_Right_Hand_Rigged'
    body=bpy.data.objects['Supplied_AnatomicalHand'];nails={d:bpy.data.objects['Nail_'+d]for d in DIGITS}
    reflection={o.name:reflect_mesh(o)for o in [body,*nails.values()]}
    collection=bpy.data.collections.get('Prepared_Gameplay_Hand')
    if collection:collection.name='Prepared_Gameplay_Right_Hand'
    rig,report=rig_hand(body,nails,landmarks,side='right')
    for o in [body,*nails.values(),rig]:
        assert np.max(np.abs(np.asarray(o.matrix_world)-np.eye(4)))<1e-8
        assert np.max(np.abs(np.asarray(o.matrix_basis)-np.eye(4)))<1e-8
        assert np.linalg.det(np.asarray(o.matrix_world)[:3,:3])>.999999
    REFLECTED.write_text(json.dumps(landmarks,indent=2)+'\n')
    scene['canonical_landmarks_json']=str(REFLECTED)
    scene['right_hand_reflection_only_in_mesh_data']=True
    scene['source_geometry_preserved_in_collection']='Source_High_Resolution'
    scene['high_resolution_note']='Hidden frozen original LEFT source retained for audit; right gameplay geometry is its reflected simplified counterpart.'
    bpy.context.preferences.filepaths.save_version=0
    bpy.ops.wm.save_as_mainfile(filepath=str(OUTPUT),check_existing=False,compress=True)
    assert all(sha(p)==value for p,value in inputs.items())
    report.update(source_inputs_sha256=inputs,reflection=reflection,reflected_landmarks_file=str(REFLECTED),
        reflected_landmarks_sha256=sha(REFLECTED),rigged_blend_sha256=sha(OUTPUT),
        script_sha256=sha(Path(__file__)),all_gameplay_meshes_and_rig_have_identity_transforms=True)
    OUTPUT.with_suffix('.rig_report.json').write_text(json.dumps(report,indent=2)+'\n')
    print('SUPPLIED_RIGHT_HAND_RIG_COMPLETE',str(OUTPUT),flush=True)

if __name__=='__main__':main()
