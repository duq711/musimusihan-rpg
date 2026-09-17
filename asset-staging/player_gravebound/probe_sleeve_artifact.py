import bpy,json
from pathlib import Path
ROOT=Path('/Users/duq711gmail.com/Documents/ChatGPT/무시무시한 rpg');W=ROOT/'asset-staging/player_gravebound'
bpy.ops.wm.open_mainfile(filepath=str(W/'gravebound_player.blend'))
images={}
for k,p in [('front',ROOT/'concept-art/player_gravebound/concept_front.png'),('back',ROOT/'concept-art/player_gravebound/concept_back.png'),('atlas',W/'gravebound_atlas.png')]:
 im=bpy.data.images.load(str(p));images[k]=(list(im.pixels[:]),im.size[:])
def sample(k,u,v):
 pix,(w,h)=images[k];x=max(0,min(w-1,int(u*w)));y=max(0,min(h-1,int(v*h)));i=(y*w+x)*4;return pix[i:i+3]
S=1.78/1392
for name in ['Gravebound_Sleeve_L','Gravebound_Sleeve_R']:
 o=bpy.data.objects[name];uv=o.data.uv_layers['Atlas'];rs=[]
 for p in o.data.polygons:
  x,y,z=p.center;py=1454-z/S
  if not 440<py<555:continue
  q=[uv.data[i].uv for i in p.loop_indices];u=sum(i.x for i in q)/len(q);v=sum(i.y for i in q)/len(q);c=sample('atlas',u,v);fU=(x/S+512)/1024;V=1-py/1536
  rs.append({'brightness':sum(c)/3,'atlas':c,'xyz':[x,y,z],'normal':list(p.normal),'px':x/S+512,'py':py,'front':sample('front',fU,V),'back':sample('back',1-fU,V),'atlas_uv':[u,v]})
 print(name,json.dumps(sorted(rs,key=lambda x:x['brightness'],reverse=True)[:12]))
