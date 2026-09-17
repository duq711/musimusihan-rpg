#!/usr/bin/env python3
"""Stage only the actual rear hand loop and its sewn surface; no engine calls.

The merged GLB is identified by welded triangle connectivity, not a spatial
slice through the shield. All other components and all UV/AO/index data remain
bit-identical. Source GLB is preserved for reproducible byte-level auditing.
"""
from __future__ import annotations
import collections
import copy
import hashlib
import importlib.util
import json
import math
from pathlib import Path

STAGE = Path(__file__).resolve().parent
ROOT = STAGE.parents[2]
spec = importlib.util.spec_from_file_location("preserved_glb", STAGE.parent/"corrected_sword/correct_longsword.py")
helper = importlib.util.module_from_spec(spec)
spec.loader.exec_module(helper)
GLB = helper.GLB

THETA = math.radians(-4)
SIN, COS = math.sin(THETA), math.cos(THETA)
A = (COS, -SIN, 0.0)
SPAN, WIDTH, HEIGHT = .235, .044, .145
INNER, OUTER = .0525, .080
RADIUS_U, RADIUS_N = .015, .011

def add(a,b): return tuple(x+y for x,y in zip(a,b))
def sub(a,b): return tuple(x-y for x,y in zip(a,b))
def mul(a,s): return tuple(x*s for x in a)
def dot(a,b): return sum(x*y for x,y in zip(a,b))
def cross(a,b): return (a[1]*b[2]-a[2]*b[1],a[2]*b[0]-a[0]*b[2],a[0]*b[1]-a[1]*b[0])
def norm(a): return math.sqrt(dot(a,a))
def unit(a): return mul(a,1/max(norm(a),1e-15))
def mix(a,b,t): return add(mul(a,1-t),mul(b,t))
def sha(data): return hashlib.sha256(data).hexdigest()
def key(p): return tuple(round(x,6) for x in p)
def bounds(points): return {"min":[min(p[k] for p in points) for k in range(3)],"max":[max(p[k] for p in points) for k in range(3)]}

def uv(p):
    x,y = p[0]+.18,p[1]-.015
    return x*COS-y*SIN,x*SIN+y*COS

def depth(v):
    x,y = -.18+v*SIN,.015+v*COS
    base = .004-.025*max(0,1-(x*x+y*y)/(.415*.415))
    t = v/SPAN+.5
    return base+HEIGHT*max(0,math.sin(math.pi*t))**.62

def center(v): return (-.18+v*SIN,.015+v*COS,-depth(v))
def frame(v):
    h = 1e-6
    derivative = (depth(v+h)-depth(v-h))/(2*h)
    return unit((-derivative*SIN,-derivative*COS,-1.0))
def blend(v):
    t = min(1,max(0,(abs(v)-INNER)/(OUTER-INNER)))
    return 1-t*t*(3-2*t)
def ellipse(v,phi): return add(center(v),add(mul(A,RADIUS_U*math.cos(phi)),mul(frame(v),RADIUS_N*math.sin(phi))))
def original_midpoint(row,col):
    v = (row/64-.5)*SPAN
    u = (col/8-.5)*WIDTH
    p = add(center(v),mul(A,u))
    return add(p,(0,0,-.0005*math.cos(col/8*math.tau)))


def components(glb,mesh,materials):
    parents,coordinates,references,triangles = {},{},collections.defaultdict(set),[]
    def find(k):
        parents.setdefault(k,k)
        while parents[k]!=k: parents[k]=parents[parents[k]];k=parents[k]
        return k
    def union(a,b): parents[find(b)]=find(a)
    for pi,primitive in enumerate(mesh["primitives"]):
        if primitive["material"] not in materials: continue
        positions = glb.read(primitive["attributes"]["POSITION"])
        indices = [v[0] for v in glb.read(primitive["indices"])]
        for vi,p in enumerate(positions):
            k=key(p);find(k);coordinates[k]=p;references[k].add((pi,vi))
        for index in range(0,len(indices),3):
            refs=tuple((pi,vi) for vi in indices[index:index+3])
            ks=tuple(key(positions[vi]) for _,vi in refs)
            union(ks[0],ks[1]);union(ks[0],ks[2]);triangles.append((ks,refs,primitive["material"]))
    result=collections.defaultdict(lambda:{"keys":set(),"triangles":[],"materials":collections.Counter()})
    for ks,refs,material in triangles:
        component=result[find(ks[0])]
        component["keys"].update(ks);component["triangles"].append(refs);component["materials"][material]+=1
    for component in result.values():
        component["references"] = sorted({r for k in component["keys"] for r in references[k]})
        component["bounds"] = bounds([coordinates[k] for k in component["keys"]])
    return list(result.values()),coordinates,references


def component_hash(glb,mesh,refs):
    digest=hashlib.sha256()
    for pi,vi in refs:
        for semantic,accessor in sorted(mesh["primitives"][pi]["attributes"].items()):
            digest.update(semantic.encode());digest.update(glb.raw(accessor,vi))
    return digest.hexdigest()


def refresh_frames(before,after,mesh,component,changed):
    # Weld original geometric vertices across split material/UV boundaries,
    # then calculate normals from the actual transformed solid triangles.
    sums=collections.defaultdict(lambda:(0.,0.,0.))
    tangent_sums=collections.defaultdict(lambda:(0.,0.,0.))
    old_arrays={pi:{sem:before.read(a) for sem,a in pr["attributes"].items()} for pi,pr in enumerate(mesh["primitives"])}
    new_positions={pi:after.read(pr["attributes"]["POSITION"]) for pi,pr in enumerate(mesh["primitives"])}
    for refs in component["triangles"]:
        pp=[new_positions[pi][vi] for pi,vi in refs]
        normal=cross(sub(pp[1],pp[0]),sub(pp[2],pp[0]))
        oldpp=[old_arrays[pi]["POSITION"][vi] for pi,vi in refs]
        original_cross=cross(sub(oldpp[1],oldpp[0]),sub(oldpp[2],oldpp[0]))
        old_normal=tuple(sum(old_arrays[pi]["NORMAL"][vi][k] for pi,vi in refs) for k in range(3))
        if dot(original_cross,old_normal)<0: normal=mul(normal,-1)
        tex=[old_arrays[pi]["TEXCOORD_0"][vi] for pi,vi in refs]
        du1,dv1=tex[1][0]-tex[0][0],tex[1][1]-tex[0][1]
        du2,dv2=tex[2][0]-tex[0][0],tex[2][1]-tex[0][1]
        determinant=du1*dv2-du2*dv1
        tangent=mul(sub(mul(sub(pp[1],pp[0]),dv2),mul(sub(pp[2],pp[0]),dv1)),1/determinant) if abs(determinant)>1e-12 else (0.,0.,0.)
        for pi,vi in refs:
            k=key(old_arrays[pi]["POSITION"][vi]);sums[k]=add(sums[k],normal)
            tangent_sums[(pi,vi)]=add(tangent_sums[(pi,vi)],tangent)
    for pi,vi in changed:
        attributes=mesh["primitives"][pi]["attributes"]
        normal=unit(sums[key(old_arrays[pi]["POSITION"][vi])])
        assert norm(normal)>.9
        after.write(attributes["NORMAL"],vi,normal)
        tangent=tangent_sums[(pi,vi)]
        tangent=unit(sub(tangent,mul(normal,dot(tangent,normal))))
        if norm(tangent)<.9:
            tangent=old_arrays[pi]["TANGENT"][vi][:3]
            tangent=unit(sub(tangent,mul(normal,dot(tangent,normal))))
        after.write(attributes["TANGENT"],vi,(*tangent,old_arrays[pi]["TANGENT"][vi][3]))


def main():
    source_path=STAGE/"source_round_shield.glb"
    if not source_path.exists(): source_path.write_bytes((ROOT/"godot-game/assets/3d/player/sword_shield/round_shield.glb").read_bytes())
    raw=source_path.read_bytes();before,after=GLB(raw),GLB(raw)
    node=before.named_node("SwordsmanRoundShield_Surface")
    assert not any(k in node for k in ("matrix","rotation","translation","scale"))
    mesh=before.doc["meshes"][node["mesh"]]
    material_ids={m["name"]:i for i,m in enumerate(before.doc["materials"])}
    loop_parts,coordinates,references=components(before,mesh,{material_ids["FP_ShieldEnarmes"],material_ids["FP_ShieldLeatherEdge"]})
    candidates=[c for c in loop_parts if c["materials"]=={material_ids["FP_ShieldEnarmes"]:2048,material_ids["FP_ShieldLeatherEdge"]:288} and c["bounds"]["max"][0]<0]
    assert len(candidates)==1 and len(candidates[0]["keys"])==1170
    loop=candidates[0]
    old_arrays={pi:{sem:before.read(a) for sem,a in pr["attributes"].items()} for pi,pr in enumerate(mesh["primitives"])}
    # Recover actual authored grid from paired solidify vertices. The nearest
    # midpoint must lie exactly 2mm away; each midpoint must have two sides.
    grid_centers={(j,i):original_midpoint(j,i) for j in range(65) for i in range(9)}
    mapping,occupied={},set()
    for k in loop["keys"]:
        p=coordinates[k]
        row,col=min(grid_centers,key=lambda ij:norm(sub(p,grid_centers[ij])))
        midpoint=grid_centers[row,col]
        error=abs(norm(sub(p,midpoint))-.002)
        assert error<1e-6,(row,col,error)
        v=(row/64-.5)*SPAN
        normal=frame(max(-SPAN*.49999,min(SPAN*.49999,v)))
        positive=dot(sub(p,midpoint),normal)>0
        phi_index=8-col if positive else 9+col
        grid_key=(row,phi_index)
        assert grid_key not in occupied
        occupied.add(grid_key);mapping[k]=grid_key
    assert len(occupied)==65*18
    changed=set();target_positions={}
    for k,(row,phi_index) in mapping.items():
        v=(row/64-.5)*SPAN
        p=coordinates[k]
        value=mix(p,ellipse(v,math.radians(10+20*phi_index)),blend(v)) if abs(v)<OUTER else p
        target_positions[row,phi_index]=value
        if abs(v)>=OUTER: continue
        for pi,vi in references[k]:
            after.write(mesh["primitives"][pi]["attributes"]["POSITION"],vi,value);changed.add((pi,vi))
    refresh_frames(before,after,mesh,loop,changed)
    # Exact face map for the solver: the exporter may choose either diagonal.
    grid_triangles=[];cells=collections.defaultdict(list)
    for refs in loop["triangles"]:
        tri=[mapping[key(old_arrays[pi]["POSITION"][vi])] for pi,vi in refs]
        grid_triangles.append(tri)
        rows={p[0] for p in tri};phis={p[1] for p in tri}
        if len(rows)==2 and len(phis)==2:
            j=min(rows);i=17 if phis=={0,17} else min(phis)
            cells[j,i].append(tri)
    assert len(cells)==64*18 and all(len(t)==2 for t in cells.values())

    def surface(v,phi):
        row=min(63,max(0,math.floor((v/SPAN+.5)*64)))
        angle=((math.degrees(phi)-10)/20)%18
        i=int(math.floor(angle));s=angle-i;t=(v/SPAN+.5)*64-row
        for triangle in cells[row,i]:
            st=[((idx-i)%18,float(r-row)) for r,idx in triangle]
            (x0,y0),(x1,y1),(x2,y2)=st
            denom=(y1-y2)*(x0-x2)+(x2-x1)*(y0-y2)
            wa=((y1-y2)*(s-x2)+(x2-x1)*(t-y2))/denom
            wb=((y2-y0)*(s-x2)+(x0-x2)*(t-y2))/denom;wc=1-wa-wb
            if min(wa,wb,wc)<-1e-8:continue
            p0,p1,p2=[target_positions[tuple(g)] for g in triangle]
            p=add(add(mul(p0,wa),mul(p1,wb)),mul(p2,wc))
            n=unit(cross(sub(p1,p0),sub(p2,p0)))
            expected=add(mul(A,math.cos(phi)/RADIUS_U),mul(frame(v),math.sin(phi)/RADIUS_N))
            if dot(n,expected)<0:n=mul(n,-1)
            return p,n
        raise AssertionError((v,phi))

    stitch_parts,stitch_points,stitch_refs=components(before,mesh,{material_ids["FP_ShieldStitch"]})
    stitch_changes=[];all_changed=set(changed)
    for stitch in stitch_parts:
        centroid=tuple(sum(stitch_points[k][a] for k in stitch["keys"])/len(stitch["keys"]) for a in range(3))
        u,v=uv(centroid)
        # Every rear-grip stitch is one independent 16-triangle tube. The
        # forearm strap belongs to the other half of the merged mesh.
        if abs(abs(u)-.018)>.001 or abs(v)>.12 or centroid[0]>-.10:continue
        assert sum(stitch["materials"].values())==16
        sign=1 if u>0 else -1
        row=min(range(30),key=lambda j:abs(v-((.03+j*.031+.0045)-.5)*SPAN))
        parameters=[(.03+row*.031-.5)*SPAN,(.03+row*.031+.009-.5)*SPAN]
        if all(abs(value)>=OUTER for value in parameters):continue
        old_centers=[add(add(center(value),mul(A,sign*.018)),(0,0,-.0025)) for value in parameters]
        # Same normalized transverse position as the leather's original grid.
        phi=math.radians(90-80*(sign*.018/(WIDTH*.5)))
        new_centers=[]
        for value,old in zip(parameters,old_centers):
            if abs(value)>=OUTER:new_centers.append(old);continue
            p,n=surface(value,phi)
            # Exact transformed triangle surface plus a 0.5mm seam clearance.
            # The tube radius is 0.45mm, so its underside stays on the leather.
            new_centers.append(add(p,mul(n,.0005)))
        old_t=unit(sub(old_centers[1],old_centers[0]));new_t=unit(sub(new_centers[1],new_centers[0]))
        old_a=unit(sub(A,mul(old_t,dot(A,old_t))));old_n=unit(cross(old_t,old_a))
        new_a=unit(sub(A,mul(new_t,dot(A,new_t))));new_n=unit(cross(new_t,new_a))
        changed_stitch=set()
        for k in stitch["keys"]:
            p=stitch_points[k];endpoint=min((0,1),key=lambda i:norm(sub(p,old_centers[i])))
            if abs(parameters[endpoint])>=OUTER:continue
            residual=sub(p,old_centers[endpoint]);assert norm(residual)<.000451
            value=add(new_centers[endpoint],add(add(mul(new_a,dot(residual,old_a)),mul(new_n,dot(residual,old_n))),mul(new_t,dot(residual,old_t))))
            for pi,vi in stitch_refs[k]:
                after.write(mesh["primitives"][pi]["attributes"]["POSITION"],vi,value);changed_stitch.add((pi,vi))
        refresh_frames(before,after,mesh,stitch,changed_stitch)
        all_changed.update(changed_stitch)
        stitch_changes.append({"side":sign,"authored_row":row,"endpoint_v":parameters,"changed_vertex_attributes":len(changed_stitch),"triangle_surface_clearance_m":.0005})

    # Strict source-preservation audit over every single primitive attribute.
    protected=hashlib.sha256();protected_after=hashlib.sha256();changed_bytes=set()
    touched_accessors=set()
    for pi,pr in enumerate(mesh["primitives"]):
        assert before.raw(pr["indices"])==after.raw(pr["indices"])
        for semantic,accessor in pr["attributes"].items():
            for vi in range(before.doc["accessors"][accessor]["count"]):
                old,new=before.raw(accessor,vi),after.raw(accessor,vi)
                if (pi,vi) in all_changed and semantic in ("POSITION","NORMAL","TANGENT"):
                    _,_,offset,stride,size=after.layout(accessor)
                    changed_bytes.update(range(offset+vi*stride,offset+vi*stride+size));touched_accessors.add(accessor)
                else:
                    assert old==new,(pi,vi,semantic)
                    protected.update(old);protected_after.update(new)
    assert all(a==b or i in changed_bytes for i,(a,b) in enumerate(zip(before.bin,after.bin)))
    for accessor in touched_accessors: after.refresh_bounds(accessor)
    assert before.doc["nodes"]==after.doc["nodes"] and before.doc["materials"]==after.doc["materials"] and before.doc["meshes"]==after.doc["meshes"]
    saved=after.encode();output_path=STAGE/"round_shield.glb";output_path.write_bytes(saved)
    reread=GLB(saved);assert reread.bin==after.bin
    loop_positions=[after.read(mesh["primitives"][pi]["attributes"]["POSITION"])[vi] for pi,vi in loop["references"]]
    preserved_parts=[]
    for component in loop_parts:
        if component is loop:continue
        digest=component_hash(before,mesh,component["references"])
        assert digest==component_hash(after,mesh,component["references"])
        preserved_parts.append({"bounds":component["bounds"],"triangle_counts":dict(component["materials"]),"unchanged_attributes_sha256":digest})
    surface_record={"coordinate_system":"GLB Y-up shield-local, before player's Y=PI", "v_rows":[(j/64-.5)*SPAN for j in range(65)],"phi_degrees":[10+20*i for i in range(18)],"vertices":[[target_positions[j,i] for i in range(18)] for j in range(65)],"triangles_row_phi":grid_triangles,"central_formula":"C(v)+A*.015*cos(phi)+N(v)*.011*sin(phi)","transition":"lerp(original,ellipse,1-smoothstep(.0525,.080,abs(v)))"}
    (STAGE/"actual_surface.json").write_text(json.dumps(surface_record,separators=(",",":"))+"\n")
    report={"source_sha256":sha(raw),"output_sha256":sha(saved),"source_file":source_path.name,"output_file":output_path.name,
            "only_changed_loop":{"welded_vertices":1170,"triangles":2336,"before":loop["bounds"],"after":bounds(loop_positions),"changed_vertex_attributes":len(changed)},
            "nominal_padded_cross_section_m":[.030,.022],"sampled_padded_width_m":.030*math.cos(math.pi/18),"sample_angles_degrees":"10,30,...,350 (18 closed vertices per row)","central_half_length_m":INNER,"transition_ends_m":OUTER,
            "changed_stitch_components":len(stitch_changes),"stitches":stitch_changes,"unmodified_leather_components":preserved_parts,
            "all_other_attribute_bytes_sha256":protected.hexdigest(),"preserved_attribute_bytes_sha256":protected_after.hexdigest(),
            "all_original_nodes_markers_materials_uv_ao_indices_unchanged":True,"front_boards_boss_rim_forearm_strap_mounts_rivets_preserved":True,"outside_abs_v_080_loop_and_stitch_vertices_preserved":True,
            "normal_tangent_method":"recompute only changed vertex frames from actual transformed triangle geometry and unchanged UV; untouched vertex frames preserved",
            "production_copy_import_engine_validation":"pending; root only"}
    (STAGE/"preservation_report.json").write_text(json.dumps(report,indent=2)+"\n")
    print(json.dumps({"source":report["source_sha256"],"output":report["output_sha256"],"changed_loop_vertices":len(changed),"changed_stitches":len(stitch_changes)}))


if __name__=="__main__":main()
