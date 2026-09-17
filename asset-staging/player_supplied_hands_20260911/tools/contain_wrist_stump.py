"""Confine buried FPV skin to the cuff's non-deforming distal attachment."""
import bpy,json,sys,hashlib,shutil,numpy as np
from pathlib import Path
from mathutils import Vector
from mathutils.bvhtree import BVHTree
stage=Path(__file__).resolve().parents[1];project=stage.parents[1]
sys.path.insert(0,str(project/'asset-staging/player_mercenary_gloves_20260911/tools'))
from reference_export import export_native,descendants
old=stage/'mac_output/iteration_03';out=stage/'mac_output/iteration_05';out.mkdir(parents=True,exist_ok=False)
bpy.ops.wm.open_mainfile(filepath=str(old/'bilateral_supplied_hands.blend'))
scene=bpy.data.scenes['Bilateral_SuppliedHands_Review'];bpy.context.window.scene=scene
report={'reason':'Rigid supplied wrist stump must end before the actual flexible cuff starts at native y=-.014 m.',
    'source_blend_sha256':hashlib.sha256((old/'bilateral_supplied_hands.blend').read_bytes()).hexdigest(),'source_palm_and_digits_unchanged_from_native_y_m':-.010,'hands':{}}
for side in ('left','right'):
    body=bpy.data.objects['Supplied_AnatomicalHand_'+side];holder=bpy.data.objects[side.upper()+'_PreviewTranslationOnly'];m=body.data
    points=np.asarray([v.co[:] for v in m.vertices]);minimum=float(points[:,1].min());selected=points[:,1]<-.010
    cuff=bpy.data.objects['WristCuff_Surface_'+side]
    native=holder.matrix_world.inverted()@cuff.matrix_world
    tree=BVHTree.FromPolygons([native@v.co for v in cuff.data.vertices],[p.vertices[:] for p in cuff.data.polygons])
    misses=[0];clamps=[0]
    def fit(p):
        if p.y>=-.010:return p
        t=max(0.,min(1.,(-.010-p.y)/(-.010-minimum)));q=p.copy();q.y=-.010-.003*t
        ease=t*t*(3-2*t);center=Vector((.00142*(1 if side=='left' else -1),q.y,.01523));factor=1-.10*ease
        q.x=center.x+(p.x-center.x)*factor;q.z=center.z+(p.z-center.z)*factor
        radial=q-center
        if radial.length>1e-8:
            direction=radial.normalized();hit,normal,index,distance=tree.ray_cast(center,direction,.2)
            if hit is None:misses[0]+=1
            elif radial.length>distance-.0007:
                q=center+direction*max(.003,distance-.0007);clamps[0]+=1
        return q
    for key in m.shape_keys.key_blocks:
        for i in np.flatnonzero(selected):key.data[int(i)].co=fit(key.data[int(i)].co)
    for i in np.flatnonzero(selected):m.vertices[int(i)].co=fit(Vector(points[i]))
    if m.has_custom_normals:m.normals_split_custom_set([(0,0,0)]*len(m.loops))
    m.update();actual=np.asarray([v.co[:] for v in m.vertices])
    assert np.array_equal(points[~selected],actual[~selected]);assert actual[:,1].min()>-.014
    assert misses[0]==0,'Missing actual cuff inner-wall ray'
    report['hands'][side]={'hidden_attachment_vertices':int(selected.sum()),'minimum_before_y_m':minimum,'minimum_after_y_m':float(actual[:,1].min()),
        'positive_axial_scale':.003/(-.010-minimum),'maximum_hidden_vertex_shift_m':float(np.linalg.norm(actual-points,axis=1).max()),
        'actual_cuff_inner_wall_clearance_m':.0007,'radial_clamp_operations':clamps[0],'missing_cuff_rays':misses[0],
        'unchanged_palm_finger_vertices':int((~selected).sum()),'export':export_native(scene,descendants(holder),holder,out/(side+'_hand_supplied.glb'))}
for p in old.glob('*.png'):shutil.copy2(p,out/p.name)
for name in ('gravebound_player_supplied_hands.glb','attachment_report.json','wrist_binding_report.json'):shutil.copy2(old/name,out/name)
bpy.context.preferences.filepaths.save_version=0
bpy.ops.wm.save_as_mainfile(filepath=str(out/'bilateral_supplied_hands.blend'),check_existing=False)
report['blend_sha256']=hashlib.sha256((out/'bilateral_supplied_hands.blend').read_bytes()).hexdigest()
(out/'stump_containment_report.json').write_text(json.dumps(report,indent=2))
print('SUPPLIED_STUMP_CONTAINMENT_PASS',flush=True)
