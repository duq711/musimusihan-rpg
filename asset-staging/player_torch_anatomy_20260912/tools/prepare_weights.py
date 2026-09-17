import numpy as np,json
from pathlib import Path
s=Path(__file__).resolve().parents[1];x=np.load(s/'audit/fit_input.npz');d={k:x[k] for k in x.files};v=x['vertices'];W=x['weights'].copy();old=W.copy();names=list(x['names'])
def smooth(a,b,x):
 t=np.clip((x-a)/(b-a),0,1);return t*t*(3-2*t)
# Keep the metacarpal palm anchored. Blend only near each MCP crease;
# thenar retains partial CMC influence rather than following it as a rigid sheet.
for n in ['index0','middle0','ring0','little0']:
 i=names.index(n);root=x['bones'][i,:3,3];keep=smooth(root[1]-.035,root[1]+.008,v[:,1]);amount=W[:,i]*(1-keep);W[:,i]-=amount;W[:,0]+=amount
i=names.index('thumb0');keep=.25+.75*smooth(.025,.070,v[:,0]);amount=W[:,i]*(1-keep);W[:,i]-=amount;W[:,0]+=amount
W/=W.sum(axis=1)[:,None];d['weights']=W;np.savez(s/'audit/fit_input_reweighted.npz',**d)
(s/'audit/weight_changes.json').write_text(json.dumps({'changed_vertices':int((np.max(abs(W-old),axis=1)>1e-6).sum()),'geometry_changed':False,'purpose':'Anchor metacarpal palm; retain partial thenar thumb influence','maximum_sum_error':float(abs(W.sum(1)-1).max())},indent=2))
