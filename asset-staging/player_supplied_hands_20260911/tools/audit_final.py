import bpy,sys,json,hashlib,numpy as np
from pathlib import Path
from mathutils import Vector
from mathutils.bvhtree import BVHTree
stage=Path(__file__).resolve().parents[1]
iteration=sys.argv[sys.argv.index('--')+1] if '--' in sys.argv else 'iteration_01'
out=stage/'mac_output'/iteration
bpy.ops.wm.open_mainfile(filepath=str(out/'bilateral_supplied_hands.blend'))
scene=bpy.data.scenes['Bilateral_SuppliedHands_Review'];bpy.context.window.scene=scene
report={'checks':{},'source_fidelity':{},'packed_maps':{}}
def coords(m):
    p=np.empty(len(m.vertices)*3,dtype=np.float32);m.vertices.foreach_get('co',p);return p.reshape(-1,3)
for digit in ('body','thumb','index','middle','ring','little'):
    stem='Supplied_AnatomicalHand' if digit=='body' else 'Nail_'+digit
    left=bpy.data.objects[stem+'_left'];right=bpy.data.objects[stem+'_right']
    a=coords(left.data);b=coords(right.data);expected=a*np.asarray((-1,1,1))
    visible=a[:,1]>=-.010 if digit=='body' else np.ones(len(a),dtype=bool)
    error=float(np.max(np.linalg.norm(expected[visible]-b[visible],axis=1)))
    assert error<1e-7
    high=bpy.data.objects['HighRes_'+('Supplied_AnatomicalHand' if digit=='body' else 'Nail_'+digit)]
    tree=BVHTree.FromPolygons([v.co for v in high.data.vertices],[p.vertices[:] for p in high.data.polygons])
    distances=np.asarray([tree.find_nearest(Vector(p))[3] for p in a])
    report['source_fidelity'][digit]={'visible_mirror_error_m':error,'low_vertices':len(a),'source_vertices':len(high.data.vertices),
        'visible_vertices_checked':int(visible.sum()),'buried_attachment_vertices_excluded':int((~visible).sum()),
        'visible_nearest_source_surface_max_m':float(distances[visible].max()),'visible_nearest_source_surface_p99_m':float(np.quantile(distances[visible],.99)),
        'scope':'Palm/fingers at native y >= -.010 m and all nails. The buried proximal attachment is intentionally contained inside each fitted cuff.'}
    assert np.quantile(distances[visible],.99)<.00075,'Unexpected visible low mesh departure from actual supplied source'
    if digit=='body':
        assert len(left.data.shape_keys.key_blocks)==16 and len(right.data.shape_keys.key_blocks)==16
for side in ('left','right'):
    rig=bpy.data.objects['Supplied_HandRig_'+side];assert len(rig.data.bones)==16
    assert all(b.matrix_basis==b.matrix_basis.Identity(4) for b in rig.pose.bones)
for role in ('Supplied_Skin','Supplied_Nail','Detailed_Glove','Detailed_Sleeve','Detailed_Trim'):
    mat=bpy.data.materials[role]
    for mode in ('basecolor','normal','roughness'):
        im=mat.node_tree.nodes['Baked_'+mode].image;assert tuple(im.size)==(4096,4096) and im.packed_file
        source=out/(('supplied_hand_' if role.startswith('Supplied_') else 'realistic_hands_')+mode+'.png')
        assert hashlib.sha256(im.packed_file.data).hexdigest()==hashlib.sha256(source.read_bytes()).hexdigest()
        report['packed_maps'][role+'/'+mode]={'sha256':hashlib.sha256(im.packed_file.data).hexdigest(),'size':list(im.size)}
char=bpy.data.scenes['Character_SuppliedHands_Review'];names=[o.name for o in char.objects]
assert sum(n.startswith('Gravebound_SuppliedHand_') for n in names)==2
assert sum(n.startswith('Gravebound_SuppliedNail_') for n in names)==10
assert not any(n.startswith(('Gravebound_Finger_','Gravebound_FingerlessGlove_')) for n in names)
report['checks']={'both_rigs_16_bones':True,'both_neutral_15_correctives':True,'old_character_hands_absent':True,'new_character_bodies':2,'new_character_nails':10,'all_material_maps_packed_and_match_png':True}
report['blend_sha256']=hashlib.sha256((out/'bilateral_supplied_hands.blend').read_bytes()).hexdigest()
(stage/('audit/final_native_audit_'+iteration+'.json')).write_text(json.dumps(report,indent=2))
print('SUPPLIED_NATIVE_AUDIT_PASS',flush=True)
