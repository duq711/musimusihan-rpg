"""Repair only zero glTF tangents from their actual neighboring triangle UV frame."""
import argparse,hashlib,json,math,struct
from pathlib import Path

def sub(a,b):return tuple(x-y for x,y in zip(a,b))
def add(a,b):return tuple(x+y for x,y in zip(a,b))
def mul(a,t):return tuple(x*t for x in a)
def dot(a,b):return sum(x*y for x,y in zip(a,b))
def cross(a,b):return(a[1]*b[2]-a[2]*b[1],a[2]*b[0]-a[0]*b[2],a[0]*b[1]-a[1]*b[0])
def length(a):return math.sqrt(dot(a,a))
def norm(a):return mul(a,1/length(a))
def digest(blob):return hashlib.sha256(blob).hexdigest()
p=argparse.ArgumentParser(description=__doc__);p.add_argument('--input-glb',type=Path,required=True);p.add_argument('--output-glb',type=Path,required=True);p.add_argument('--report',type=Path,required=True);a=p.parse_args();assert a.input_glb.resolve()!=a.output_glb.resolve();assert not a.output_glb.exists()
source=a.input_glb.read_bytes();blob=bytearray(source);size=struct.unpack_from('<I',blob,12)[0];doc=json.loads(blob[20:20+size]);base=20+size+8

def accessor(index):
 ac=doc['accessors'][index];view=doc['bufferViews'][ac['bufferView']];count={'SCALAR':1,'VEC2':2,'VEC3':3,'VEC4':4}[ac['type']];fmt={5126:'f',5123:'H',5125:'I'}[ac['componentType']];stride=view.get('byteStride',struct.calcsize(fmt)*count);off=base+view.get('byteOffset',0)+ac.get('byteOffset',0)
 return [struct.unpack_from('<'+fmt*count,blob,off+i*stride)for i in range(ac['count'])],off,stride
repairs=[];allowed=set()
for mesh in doc['meshes']:
 for primitive_id,primitive in enumerate(mesh['primitives']):
  attrs=primitive['attributes']
  if'TANGENT'not in attrs:continue
  tangents,offset,stride=accessor(attrs['TANGENT']);bad=[i for i,t in enumerate(tangents)if length(t[:3])<1e-6]
  if not bad:continue
  positions=accessor(attrs['POSITION'])[0];normals=accessor(attrs['NORMAL'])[0];uvs=accessor(attrs['TEXCOORD_0'])[0];flat=[v[0]for v in accessor(primitive['indices'])[0]];triangles=[flat[i:i+3]for i in range(0,len(flat),3)]
  for index in bad:
   total_t,total_b=(0.,0.,0.),(0.,0.,0.);neighbors=[];normal=norm(normals[index])
   for face in triangles:
    if index not in face:continue
    ia,ib,ic=face;e1=sub(positions[ib],positions[ia]);e2=sub(positions[ic],positions[ia]);q1=sub(uvs[ib],uvs[ia]);q2=sub(uvs[ic],uvs[ia]);det=q1[0]*q2[1]-q1[1]*q2[0];area=.5*length(cross(e1,e2))
    assert abs(det)>1e-12 and area>1e-14,'Cannot invent a tangent for a degenerate UV/geometry face'
    tangent=mul(sub(mul(e1,q2[1]),mul(e2,q1[1])),1/det);bitangent=mul(sub(mul(e2,q1[0]),mul(e1,q2[0])),1/det)
    total_t=add(total_t,mul(tangent,area));total_b=add(total_b,mul(bitangent,area));neighbors.append({'indices':face,'uv_determinant':det,'triangle_area_m2':area,'dPdu':tangent})
   tangent=norm(sub(total_t,mul(normal,dot(total_t,normal))));sign=-1. if dot(cross(normal,tangent),total_b)<0 else 1.;repaired=(*tangent,sign);at=offset+index*stride;struct.pack_into('<4f',blob,at,*repaired);allowed.update(range(at,at+16));actual=struct.unpack_from('<4f',blob,at)
   assert abs(length(actual[:3])-1)<1e-6 and abs(dot(actual[:3],normal))<1e-6
   repairs.append({'mesh':mesh['name'],'primitive':primitive_id,'vertex':index,'before':tangents[index],'after':actual,'normal_dot_tangent':dot(actual[:3],normal),'incident_triangles':neighbors,'binary_offset':at})
assert repairs,'No zero tangent found';changed=[i for i,(x,y)in enumerate(zip(source,blob))if x!=y];assert set(changed)<=allowed;assert source[:base]==blob[:base]
a.output_glb.parent.mkdir(parents=True,exist_ok=True);a.output_glb.write_bytes(blob);report={'method':'Triangle-area-weighted actual UV dPdu, projected into unchanged authored normal plane; handedness from actual dPdv','input_sha256':digest(source),'output_sha256':digest(blob),'changed_byte_count':len(changed),'changed_tangent_records':repairs,'all_other_glb_bytes_identical':True};a.report.write_text(json.dumps(report,indent=2));print(json.dumps(report,indent=2))
