#!/usr/bin/env python3
"""Shorten actual finger phalanges without scaling hand width, palm or sleeves.

Read the corrected, pre-extension GLBs. Keep MCP anchors and thumb metacarpal;
scale only phalange-local Y and downstream joint translations by 0.8. Refit
the original skin and original glove with their unchanged four bone weights.
This stages GLBs only. No production asset, Blender or Godot is invoked.
"""
from __future__ import annotations
import copy
import hashlib
import importlib.util
import json
import math
from pathlib import Path

STAGE=Path(__file__).resolve().parent
SOURCE=STAGE/"source_corrected_arms"
spec=importlib.util.spec_from_file_location("preserved_glb",STAGE.parent/"corrected_sword/correct_longsword.py")
helper=importlib.util.module_from_spec(spec);spec.loader.exec_module(helper)
helper.WIDTH["MAT4"]=16
GLB=helper.GLB
DIGITS=("little","ring","middle","index","thumb")
PHALANGES={d+str(i) for d in DIGITS for i in range(3) if d!="thumb" or i>0}
TRANSLATIONS={d+str(i) for d in DIGITS for i in (1,2) if d!="thumb" or i==2}
FACTOR=.8

def sha(data):return hashlib.sha256(data).hexdigest()
def norm(a):return math.sqrt(sum(x*x for x in a))
def unit(a):return tuple(x/max(1e-15,norm(a)) for x in a)
def identity():return [[float(i==j) for j in range(4)] for i in range(4)]
def mm(a,b):return [[sum(a[i][k]*b[k][j] for k in range(4)) for j in range(4)] for i in range(4)]
def point(m,p):return tuple(sum(m[i][j]*p[j] for j in range(3))+m[i][3] for i in range(3))
def vector(m,p):return tuple(sum(m[i][j]*p[j] for j in range(3)) for i in range(3))
def inverse(m):
    a,b,c=m[0][:3];d,e,f=m[1][:3];g,h,i=m[2][:3]
    determinant=a*(e*i-f*h)-b*(d*i-f*g)+c*(d*h-e*g)
    assert abs(determinant)>1e-10
    r=identity();q=[[e*i-f*h,c*h-b*i,b*f-c*e],[f*g-d*i,a*i-c*g,c*d-a*f],[d*h-e*g,b*g-a*h,a*e-b*d]]
    for row in range(3):
        for col in range(3):r[row][col]=q[row][col]/determinant
        r[row][3]=-sum(r[row][col]*m[col][3] for col in range(3))
    return r
def transpose3(m):return [[m[j][i] for j in range(3)] for i in range(3)]
def from_glb(values):return [[values[col*4+row] for col in range(4)] for row in range(4)]
def to_glb(m):return tuple(m[row][col] for col in range(4) for row in range(4))
def local_transform(node):
    if "matrix" in node:return from_glb(node["matrix"])
    x,y,z,w=node.get("rotation",[0,0,0,1]);r=norm((x,y,z,w));x,y,z,w=x/r,y/r,z/r,w/r
    m=[[1-2*(y*y+z*z),2*(x*y-z*w),2*(x*z+y*w),0],[2*(x*y+z*w),1-2*(x*x+z*z),2*(y*z-x*w),0],[2*(x*z-y*w),2*(y*z+x*w),1-2*(x*x+y*y),0],[0,0,0,1]]
    scale=node.get("scale",[1,1,1]);position=node.get("translation",[0,0,0])
    for i in range(3):
        for j in range(3):m[i][j]*=scale[j]
        m[i][3]=position[i]
    return m
def globals_for(document):
    nodes=document["nodes"];parents={c:i for i,n in enumerate(nodes) for c in n.get("children",[])};result={}
    def get(index):
        if index not in result:result[index]=mm(get(parents[index]) if index in parents else identity(),local_transform(nodes[index]))
        return result[index]
    for index in range(len(nodes)):get(index)
    return result
def bounds(points):return {"min":[min(p[k] for p in points) for k in range(3)],"max":[max(p[k] for p in points) for k in range(3)]}
def mesh_hash(glb,node):
    mesh=glb.doc["meshes"][node["mesh"]];h=hashlib.sha256(json.dumps({"node":node,"mesh":mesh},sort_keys=True).encode())
    for p in mesh["primitives"]:
        for a in [p["indices"]]+list(p["attributes"].values()):h.update(glb.raw(a))
    return h.hexdigest()


def stage(side):
    source_path=SOURCE/f"{side}_arm.glb"
    if not source_path.exists():source_path.write_bytes((STAGE.parent/"corrected_arms"/source_path.name).read_bytes())
    original=source_path.read_bytes();before,after=GLB(original),GLB(original)
    lookup={n["name"].split(".")[0]:i for i,n in enumerate(before.doc["nodes"])}
    old_global=globals_for(before.doc)
    for name in TRANSLATIONS:
        node=after.doc["nodes"][lookup[name]]
        node["translation"]=[x*FACTOR for x in node["translation"]]
    new_global=globals_for(after.doc)
    anchors={}
    for name in ("wrist","thumb0","thumb1","little0","ring0","middle0","index0"):
        old=point(old_global[lookup[name]],(0,0,0));new=point(new_global[lookup[name]],(0,0,0))
        assert old==new
        anchors[name]=old
    for name in PHALANGES:
        old,new=old_global[lookup[name]],new_global[lookup[name]]
        assert all(old[i][j]==new[i][j] for i in range(3) for j in range(3))
    source_hand=before.doc["nodes"][lookup["ContinuousAnatomicalHand"]]
    skin_index=source_hand["skin"];skin=before.doc["skins"][skin_index]
    names=[before.doc["nodes"][j]["name"] for j in skin["joints"]]
    ib_accessor=skin["inverseBindMatrices"]
    old_binds=[from_glb(v) for v in before.read(ib_accessor)]
    new_binds=[];deformations=[]
    along=identity();along[1][1]=FACTOR
    for bind,bone in enumerate(skin["joints"]):
        name=names[bind];old_ib=old_binds[bind];new_ib=copy.deepcopy(old_ib)
        shift=[new_global[bone][i][3]-old_global[bone][i][3] for i in range(3)]
        if any(x!=0 for x in shift):
            inverse_global=inverse(new_global[bone])
            for i in range(3):new_ib[i][3]-=sum(inverse_global[i][j]*shift[j] for j in range(3))
            after.write(ib_accessor,bind,to_glb(new_ib))
        new_binds.append(new_ib)
        deformations.append(mm(mm(new_global[bone],along),old_ib) if name in PHALANGES else identity())
        old_bind_identity=mm(old_global[bone],old_ib);new_bind_identity=mm(new_global[bone],new_ib)
        assert max(abs(old_bind_identity[i][j]-new_bind_identity[i][j]) for i in range(4) for j in range(4))<1e-12
    modified_accessors={ib_accessor};allowed_bytes=set();mesh_records=[];pure_cross_error=0.;pure_length_error=0.;pure_count=0
    pure_palm_count=0;blend_palm_count=0;blend_palm_shift=0.;finger_record={d:[] for d in DIGITS}
    # Only the two attached hand meshes are changed. The original full binary
    # also contains unused donor meshes, which remain byte-for-byte preserved.
    hand_nodes=[after.doc["nodes"][lookup[name]] for name in ("ContinuousAnatomicalHand","FingerlessLeatherGlove")]
    for node in hand_nodes:
        before_points,after_points=[],[]
        for primitive in after.doc["meshes"][node["mesh"]]["primitives"]:
            attributes=primitive["attributes"];data={k:before.read(a) for k,a in attributes.items()}
            for vi,p in enumerate(data["POSITION"]):
                joints,weights=data["JOINTS_0"][vi],data["WEIGHTS_0"][vi]
                active=[(j,w) for j,w in zip(joints,weights) if w>0 and names[j] in PHALANGES]
                value=p
                if active:
                    # Delta form exactly preserves unaffected wrist/metacarpal
                    # influences, including tiny original weight-sum roundoff.
                    value=tuple(p[k]+sum(w*(point(deformations[j],p)[k]-p[k]) for j,w in active) for k in range(3))
                    jacobian=identity()
                    for row in range(3):
                        for col in range(3):jacobian[row][col]+=sum(w*(deformations[j][row][col]-float(row==col)) for j,w in active)
                    normal=unit(vector(transpose3(inverse(jacobian)),data["NORMAL"][vi]))
                    tangent=vector(jacobian,data["TANGENT"][vi][:3]);projection=sum(tangent[k]*normal[k] for k in range(3));tangent=unit(tuple(tangent[k]-projection*normal[k] for k in range(3)))
                    assert all(math.isfinite(x) for x in value+normal+tangent)
                    assert norm(normal)>.99 and norm(tangent)>.99
                    for semantic,result in (("POSITION",value),("NORMAL",normal),("TANGENT",tangent+(data["TANGENT"][vi][3],))):
                        accessor=attributes[semantic];after.write(accessor,vi,result);modified_accessors.add(accessor)
                        _,_,offset,stride,size=after.layout(accessor);allowed_bytes.update(range(offset+vi*stride,offset+vi*stride+size))
                before_points.append(p);after_points.append(value)
                used=[(j,w) for j,w in zip(joints,weights) if w>0]
                if len(used)==1 and used[0][1]==1 and names[used[0][0]] in PHALANGES:
                    j=used[0][0];old_local=point(old_binds[j],p);new_local=point(new_binds[j],value)
                    pure_cross_error=max(pure_cross_error,abs(old_local[0]-new_local[0]),abs(old_local[2]-new_local[2]))
                    pure_length_error=max(pure_length_error,abs(new_local[1]-old_local[1]*FACTOR));pure_count+=1
                    if str(node["name"]).startswith("Continuous") and names[j].endswith("2"):
                        finger_record[names[j][:-1]].append((old_local,new_local))
                wrist_weight=sum(w for j,w in used if names[j]=="wrist")
                if wrist_weight==1 and len(used)==1:
                    assert value==p
                    for semantic,accessor in attributes.items():assert before.raw(accessor,vi)==after.raw(accessor,vi)
                    pure_palm_count+=1
                elif wrist_weight>.55:
                    blend_palm_count+=1;blend_palm_shift=max(blend_palm_shift,norm(tuple(value[k]-p[k] for k in range(3))))
            for semantic,accessor in attributes.items():
                if semantic not in ("POSITION","NORMAL","TANGENT"):assert before.raw(accessor)==after.raw(accessor)
            assert before.raw(primitive["indices"])==after.raw(primitive["indices"])
        mesh_records.append({"name":node["name"],"before_bounds":bounds(before_points),"after_bounds":bounds(after_points),"vertices":len(before_points),"weights_uv_indices_materials_preserved":True})
    assert pure_cross_error<1e-6 and pure_length_error<1e-6
    for bind in range(len(names)):
        _,_,offset,stride,size=after.layout(ib_accessor)
        # Only inverse-bind translation entries may change. No basis or bind
        # ordering is regenerated; those original values are preserved.
        allowed_bytes.update(range(offset+bind*stride+12*4,offset+bind*stride+15*4))
        assert before.raw(ib_accessor,bind)[:48]==after.raw(ib_accessor,bind)[:48]
        assert before.raw(ib_accessor,bind)[60:]==after.raw(ib_accessor,bind)[60:]
    assert len(before.bin)==len(after.bin)
    assert all(a==b or i in allowed_bytes for i,(a,b) in enumerate(zip(before.bin,after.bin)))
    protected=[]
    for index,node in enumerate(before.doc["nodes"]):
        expected=copy.deepcopy(node)
        if node["name"] in TRANSLATIONS:expected["translation"]=[x*FACTOR for x in expected["translation"]]
        assert after.doc["nodes"][index]==expected
        if "mesh" in node and "skin" not in node:
            digest=mesh_hash(before,node);assert digest==mesh_hash(after,node)
            protected.append({"name":node["name"],"unchanged_sha256":digest})
    for name in ("materials","textures","images","samplers","skins","meshes"):
        assert before.doc.get(name)==after.doc.get(name)
    for accessor in modified_accessors:after.refresh_bounds(accessor)
    output=after.encode();path=STAGE/f"{side}_arm.glb";path.write_bytes(output)
    saved=GLB(output)
    saved_global=globals_for(saved.doc)
    saved_binds=[from_glb(v) for v in saved.read(ib_accessor)]
    saved_bind_error=0.;saved_original_bind_error=0.;saved_bind_drift=0.
    for j,bone in enumerate(skin["joints"]):
        old_product=mm(old_global[bone],old_binds[j]);new_product=mm(saved_global[bone],saved_binds[j])
        saved_original_bind_error=max(saved_original_bind_error,max(abs(old_product[r][c]-float(r==c)) for r in range(4) for c in range(4)))
        saved_bind_error=max(saved_bind_error,max(abs(new_product[r][c]-float(r==c)) for r in range(4) for c in range(4)))
        saved_bind_drift=max(saved_bind_drift,max(abs(old_product[r][c]-new_product[r][c]) for r in range(4) for c in range(4)))
    assert saved_bind_error<1e-6 and saved_bind_drift<1e-7
    saved_geometry_error=0.;saved_cross_error=0.;saved_length_error=0.;saved_vertex_count=0
    for node in hand_nodes:
        for primitive in saved.doc["meshes"][node["mesh"]]["primitives"]:
            attrs=primitive["attributes"];old_positions=before.read(attrs["POSITION"]);actual_positions=saved.read(attrs["POSITION"])
            joints=before.read(attrs["JOINTS_0"]);weights=before.read(attrs["WEIGHTS_0"])
            for p,actual,js,ws in zip(old_positions,actual_positions,joints,weights):
                active=[(j,w) for j,w in zip(js,ws) if w>0 and names[j] in PHALANGES]
                expected=tuple(p[k]+sum(w*(point(deformations[j],p)[k]-p[k]) for j,w in active) for k in range(3))
                saved_geometry_error=max(saved_geometry_error,norm(tuple(actual[k]-expected[k] for k in range(3))))
                used=[(j,w) for j,w in zip(js,ws) if w>0]
                if len(used)==1 and used[0][1]==1 and names[used[0][0]] in PHALANGES:
                    j=used[0][0];old_local=point(old_binds[j],p);new_local=point(saved_binds[j],actual)
                    saved_cross_error=max(saved_cross_error,abs(old_local[0]-new_local[0]),abs(old_local[2]-new_local[2]))
                    saved_length_error=max(saved_length_error,abs(new_local[1]-old_local[1]*FACTOR))
                saved_vertex_count+=1
            for semantic,accessor in attrs.items():
                if semantic not in ("POSITION","NORMAL","TANGENT"):assert before.raw(accessor)==saved.raw(accessor)
            assert before.raw(primitive["indices"])==saved.raw(primitive["indices"])
    assert saved_geometry_error<1e-7 and saved_cross_error<1e-7 and saved_length_error<1e-7
    final_float32={"verified_actual_vertices":saved_vertex_count,"weighted_geometry_max_error_m":saved_geometry_error,
        "pure_phalanx_local_xz_max_error_m":saved_cross_error,"pure_phalanx_y_factor_max_error_m":saved_length_error,
        "rest_times_inverse_bind_max_identity_error":saved_bind_error,"source_rest_times_inverse_bind_max_identity_error":saved_original_bind_error,
        "rest_times_inverse_bind_max_change":saved_bind_drift,"weights_uv_indices_rechecked_byte_exact":True}
    lengths=[]
    for digit in DIGITS:
        chain=[]
        for child in (1,2):
            bone=lookup[digit+str(child)];old=norm(before.doc["nodes"][bone]["translation"]);new=norm(after.doc["nodes"][bone]["translation"])
            assert abs(new-old*(1 if digit=="thumb" and child==1 else FACTOR))<1e-12
            chain.append({"parent":digit+str(child-1),"child":digit+str(child),"old_m":old,"new_m":new})
        leaf=finger_record[digit];assert leaf
        chain.append({"distal_measurement":"actual single-bone distal skin extent in bone-local Y (GLB has no leaf tail length)","sample_count":len(leaf),"old_y_bounds":[min(v[0][1] for v in leaf),max(v[0][1] for v in leaf)],"new_y_bounds":[min(v[1][1] for v in leaf),max(v[1][1] for v in leaf)]})
        lengths.append({"digit":digit,"segments":chain})
    return {"side":side,"source_sha256":sha(original),"output_sha256":sha(output),"source":str(source_path.relative_to(STAGE)),"output":path.name,
            "longitudinal_factor":FACTOR,"saved_float32_validation":final_float32,"preserved_global_anchors_y_up":anchors,"actual_joint_and_skin_lengths":lengths,"meshes":mesh_records,
            "pure_phalanx_vertex_count":pure_count,"maximum_pure_local_xz_change_m":pure_cross_error,"maximum_pure_local_y_scale_error_m":pure_length_error,
            "unchanged_pure_wrist_palm_vertices":pure_palm_count,"blended_wrist_finger_junction_vertices":blend_palm_count,"maximum_blended_wrist_finger_junction_shift_m":blend_palm_shift,
            "original_rigid_meshes":protected,"joint_rotations_scales_and_names_unchanged":True,"skin_weights_uv_materials_topology_unchanged":True,"all_other_original_binary_bytes_preserved":True,
            "bind_change":"only downstream inverse-bind translation elements; original basis/order preserved","geometry_method":"Pnew=P+sum(affected original weights*(Gnew*scaleY(.8)*oldInverseBind*P-P)); wrist and thumb metacarpal influences identity",
            "normal_method":"inverse-transpose of weighted local deformation Jacobian; UV tangent transformed and orthogonalized; unaffected palm vertices untouched",
            "whole_hand_node_scale_added":False,"engine_import_and_gameplay_validation":"pending; root only"}


def main():
    SOURCE.mkdir(parents=True,exist_ok=True)
    report={"source_stage":"corrected_arms before added glove extensions","arms":[stage(side) for side in ("left","right")]}
    (STAGE/"preservation_report.json").write_text(json.dumps(report,indent=2)+"\n")
    print(json.dumps([{k:a[k] for k in ("side","output_sha256","maximum_pure_local_xz_change_m","unchanged_pure_wrist_palm_vertices","maximum_blended_wrist_finger_junction_shift_m")} for a in report["arms"]],indent=2))


if __name__=="__main__":main()
