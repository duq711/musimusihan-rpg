"""Author a thumb-only static corrective with Mac Blender; never edit its source."""
import bpy
import hashlib
import json
import math
import struct
from pathlib import Path
from mathutils import Matrix, Vector
from mathutils.bvhtree import BVHTree
from mathutils.kdtree import KDTree

root = Path(__file__).resolve().parent
project = root.parents[2]
source_blend = root.parents[1] / 'sword_hold_long_grip_integration/source/model/SwordHold_Static.blend'
source_glb = project / 'godot-game/assets/3d/player/sword_hold_long_grip/SwordHold_Static.glb'
source_hash = hashlib.sha256(source_glb.read_bytes()).hexdigest()
bpy.ops.wm.open_mainfile(filepath=str(source_blend))
hand = bpy.data.objects['RightHand_Glove']
axis_conversion = Matrix(((1,0,0,0),(0,0,1,0),(0,-1,0,0),(0,0,0,1)))
ready = Matrix(((0.6734562112,0.1384824613,-0.7261403196,0.3249563841),(-0.1673592395,0.9853534854,0.0327005009,-0.0035816696),(0.7200327879,0.0995039315,0.6867691389,-0.5892537756),(0,0,0,1)))
canonical = ready.inverted() @ axis_conversion @ hand.matrix_world
inverse = canonical.inverted()
before = [v.co.copy() for v in hand.data.vertices]
groups = {g.name:g.index for g in hand.vertex_groups}
weights = []
thumb_indices = []
for v in hand.data.vertices:
    influence = {g.group:g.weight for g in v.groups}
    w0 = influence.get(groups['thumb0'],0)
    w1 = influence.get(groups['thumb1'],0)
    w2 = influence.get(groups['thumb2'],0)
    weights.append(min(1.0,w0+w1+w2))
    if w1+w2>.5: thumb_indices.append(v.index)
hilt = bpy.data.objects['Sword_GripLeather']
hilt_frame = ready.inverted() @ axis_conversion @ hilt.matrix_world
hilt_tree = BVHTree.FromPolygons([hilt_frame @ v.co for v in hilt.data.vertices],[p.vertices for p in hilt.data.polygons],all_triangles=False)
pivot = Vector((.028,-.067,.040))

def corrected(degrees, lift=0.0):
    result=[]
    for i,point in enumerate(before):
        if weights[i]<=0:
            result.append(point.copy()); continue
        normalized=canonical @ point
        rotation=Matrix.Rotation(math.radians(degrees)*weights[i],3,'Y')
        result.append(inverse @ (pivot+rotation @ (normalized-pivot)+Vector((0,0,lift*weights[i]))))
    return result

def contact_report(points):
    gaps=[]
    for index in thumb_indices:
        point=canonical @ points[index]
        location,normal,_,distance=hilt_tree.find_nearest(point)
        gaps.append(distance if (point-location).dot(normal)>=0 else -distance)
    return {'minimum_hilt_gap_m':min(gaps),'penetrating_more_than_1mm':sum(v<-.001 for v in gaps),'contact_vertices_within_2mm':sum(-.0005<=v<=.002 for v in gaps),'sample_count':len(gaps)}

candidates=[]
for degrees in [0,6,12,18,24,30]:
    for lift in [0.0,.006,.010,.014,.018,.0202,.022]:
        points=corrected(degrees,lift)
        candidates.append({'degrees':degrees,'lift_m':lift,'contact':contact_report(points),'maximum_displacement_m':max((a-b).length for a,b in zip(points,before))})
valid=[v for v in candidates if v['contact']['minimum_hilt_gap_m']>=-.0002 and v['contact']['contact_vertices_within_2mm']>=5]
selected=min(valid,key=lambda v:v['maximum_displacement_m'])
angle=selected['degrees']; lift=selected['lift_m']
after=corrected(angle,lift)
original_corner_normals=[n.vector.copy() for n in hand.data.corner_normals]
original_corner_vertices=[loop.vertex_index for loop in hand.data.loops]
for vertex, point in zip(hand.data.vertices,after): vertex.co=point
hand.data.update()
updated_corner_normals=[n.vector.copy() for n in hand.data.corner_normals]

# Export a sparse corrective in the immutable GLB's exact vertex order. UVs,
# indices, materials and every unselected position remain source data at runtime.
payload=source_glb.read_bytes()
json_length=struct.unpack_from('<I',payload,12)[0]
document=json.loads(payload[20:20+json_length])
binary=payload[28+json_length:]
node=next(v for v in document['nodes'] if v.get('name')=='RightHand_Glove')
primitive=document['meshes'][node['mesh']]['primitives'][0]
def accessor(index):
    entry=document['accessors'][index]; view=document['bufferViews'][entry['bufferView']]
    start=view.get('byteOffset',0)+entry.get('byteOffset',0)
    return [Vector(struct.unpack_from('<fff',binary,start+i*view.get('byteStride',12))) for i in range(entry['count'])]
positions=accessor(primitive['attributes']['POSITION'])
normals=accessor(primitive['attributes']['NORMAL'])
tree=KDTree(len(before))
for i,point in enumerate(before): tree.insert(axis_conversion.to_3x3() @ point,i)
tree.balance()
corners={}
for i,vertex in enumerate(original_corner_vertices): corners.setdefault(vertex,[]).append(i)
changes=[]
contact_vertex_indices=[]
mapping_error=0.0
for i,point in enumerate(positions):
    _,source_index,distance=tree.find(point)
    mapping_error=max(mapping_error,distance)
    if source_index in thumb_indices: contact_vertex_indices.append(i)
    if (after[source_index]-before[source_index]).length<=1e-8: continue
    normal_blender=axis_conversion.to_3x3().inverted() @ normals[i]
    corner=max(corners[source_index],key=lambda c:original_corner_normals[c].dot(normal_blender))
    changes.append({'index':i,'source_position':list(positions[i]),'source_normal':list(normals[i]),'contact_sample':source_index in thumb_indices,'position':list(axis_conversion.to_3x3() @ after[source_index]),'normal':list((axis_conversion.to_3x3() @ updated_corner_normals[corner]).normalized())})
assert mapping_error<.000001, mapping_error
correction={'source_sha256':source_hash,'mesh':'RightHand_Glove','surface':0,'source_vertex_count':len(positions),'contact_vertex_indices':contact_vertex_indices,'changes':changes}
(root/'right_thumb_corrective.json').write_text(json.dumps(correction,separators=(',',':')))
bpy.ops.wm.save_as_mainfile(filepath=str(root/'RightHand_ThumbRefined.blend'))
bpy.ops.object.select_all(action='DESELECT')
hand.select_set(True)
bpy.context.view_layer.objects.active=hand
bpy.ops.export_scene.gltf(filepath=str(root/'RightHand_ThumbRefined.glb'),export_format='GLB',use_selection=True,export_animations=False,export_skins=False)
edge_reports=[]
for edge in hand.data.edges:
    a,b=edge.vertices
    length=(before[a]-before[b]).length
    edge_reports.append({'length_before_m':length,'length_after_m':(after[a]-after[b]).length,'displacement_difference_m':((after[a]-before[a])-(after[b]-before[b])).length})
edge_summary={'maximum_length_before_m':max(e['length_before_m'] for e in edge_reports),'maximum_length_after_m':max(e['length_after_m'] for e in edge_reports),'maximum_displacement_difference_m':max(e['displacement_difference_m'] for e in edge_reports),'maximum_length_ratio':max(e['length_after_m']/e['length_before_m'] for e in edge_reports if e['length_before_m']>.000001)}
report={'edge_continuity':edge_summary,'blender_version':bpy.app.version_string,'blender_binary':bpy.app.binary_path,'source_sha256':source_hash,'selected_degrees':angle,'selected_lift_m':lift,'pivot_canonical':list(pivot),'candidates':candidates,'before':contact_report(before),'after':contact_report(after),'source_vertex_count':len(before),'changed_source_vertices':sum((a-b).length>1e-8 for a,b in zip(after,before)),'changed_runtime_vertices':len(changes),'mapping_maximum_error_m':mapping_error,'maximum_displacement_m':max((a-b).length for a,b in zip(after,before)),'all_unselected_vertices_unchanged':all((a-b).length==0 for i,(a,b) in enumerate(zip(after,before)) if weights[i]==0),'source_preserved':hashlib.sha256(source_glb.read_bytes()).hexdigest()==source_hash}
(root/'thumb_validation.json').write_text(json.dumps(report,indent=2))
print('THUMB REFINEMENT',json.dumps(report))
