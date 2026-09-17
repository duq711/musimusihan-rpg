from pathlib import Path
import math,json
root=Path(__file__).resolve().parent
def dot(a,b):return sum(x*y for x,y in zip(a,b))
def add(a,b):return [x+y for x,y in zip(a,b)]
def sub(a,b):return [x-y for x,y in zip(a,b)]
def mul(a,k):return [x*k for x in a]
def norm(a):return math.sqrt(dot(a,a))
def cross(a,b):return [a[1]*b[2]-a[2]*b[1],a[2]*b[0]-a[0]*b[2],a[0]*b[1]-a[1]*b[0]]
def constraints(a,b):
 d=sub(b['center'],a['center']); axes=a['axes']+b['axes']+[cross(x,y) for x in a['axes'] for y in b['axes']]
 result=[]
 for n in axes:
  length=norm(n)
  if length<1e-6:continue
  n=mul(n,1/length)
  radius=sum((h+.01)*abs(dot(axis,n)) for h,axis in zip(a['half_extents'],a['axes']))+sum((h+.01)*abs(dot(axis,n)) for h,axis in zip(b['half_extents'],b['axes']))
  center=dot(d,n);result.append((n,center-radius,center+radius))
 return result

def minimum_translation(cs,mask=(1,1,1)):
 work=[]
 for n,lo,hi in cs:
  n=[x*m for x,m in zip(n,mask)];length2=dot(n,n)
  if length2<1e-14:
   if lo>0 or hi<0:return None
  else:work.append((n,lo,hi,length2))
 x=[0.,0.,0.];corrections=[[0.,0.,0.] for _ in work]
 for _ in range(2000):
  before=x[:]
  for i,(n,lo,hi,length2) in enumerate(work):
   y=add(x,corrections[i]);value=dot(n,y);x=add(y,mul(n,(max(lo,min(hi,value))-value)/length2));corrections[i]=sub(y,x)
  violation=max([max(lo-dot(n,x),dot(n,x)-hi,0) for n,lo,hi,_ in work],default=0)
  if norm(sub(x,before))<1e-10 and violation<1e-8:break
 if violation>1e-5:return None
 return {'offset_m':[round(v,5) for v in x],'length_m':round(norm(x),5)}
raw=json.loads((root/'clash_diagnostic_v3.json').read_text());report={}
for version,record in raw['samples'].items():
 rows=[]
 for f in record['frames']:
  cs=constraints(f['player'],f['enemy'])
  rows.append({'time':round(f['player_time'],6),'enemy_time':round(f['enemy_time'],6),'overlap':f['overlap'],'player_health':f['player_health'],'player_center':f['player']['center'],'enemy_center':f['enemy']['center'],'minimum_translation':minimum_translation(cs),'depth_only':minimum_translation(cs,(0,0,1)),'palm_xz_only':minimum_translation(cs,(1,0,1)),'tip':f['tip'],'grip':f['grip']})
 report[version]={'clashed':record['clashed'],'enemy_name':record['enemy_name'],'frames':rows}
(root/'clash_proxy_analysis_v3.json').write_text(json.dumps(report,indent=2)+'\n')
for version,record in report.items():
 print(version,'clashed=',record['clashed'],'enemy=',record['enemy_name'])
 for f in record['frames']:
  print(f['time'],'overlap',f['overlap'],'hp',f['player_health'],'nearest',f['minimum_translation'],'depth',f['depth_only'],'xz',f['palm_xz_only'])
