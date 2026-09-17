import struct,json
from mathutils import Matrix
f=open('/Users/duq711gmail.com/Downloads/fp_arms.glb','rb');f.read(12);n,t=struct.unpack('<II',f.read(8));d=json.loads(f.read(n));n,t=struct.unpack('<II',f.read(8));buf=f.read(n);bv=d['bufferViews'][5]
for j,i in enumerate(d['skins'][0]['joints']):
 a=struct.unpack_from('<16f',buf,bv['byteOffset']+j*64);m=Matrix([a[k:k+4] for k in range(0,16,4)]).transposed().inverted()
 if j<29:print(d['nodes'][i]['name'],list(m.translation))
