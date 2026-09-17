"""Fit new camera-space sword poses to directly viewed native source frames.

Screen observations constrain visible joints only. Offscreen key poses and depth
are authored choices, never reconstructed source 3D. No prior motion is reused.
"""
from pathlib import Path
import json
import math
import numpy as np
from scipy.optimize import least_squares
from scipy.spatial.transform import Rotation, Slerp
from scipy.interpolate import PchipInterpolator

ROOT = Path(__file__).resolve().parent
S = np.array([[.6734562112,.1384824613,-.7261403196,.3249563841],[-.1673592395,.9853534854,.0327005009,-.0035816696],[.7200327879,.0995039315,.6867691389,-.5892537756],[0,0,0,1]])
W0 = np.array([.0679751875,-.1080001335,.0524637313])
E0 = np.array([.2366280243,-.1080001099,.2503430693])
H0 = np.array([.4571740416,-.1080000789,.5091083575])
H = (S @ np.r_[H0,1])[:3]
G0 = np.array([0,-.009,0])
TIP = np.array([0,1.035,0])
U,F = np.linalg.norm(H0-E0), np.linalg.norm(E0-W0)
TAN = math.tan(math.radians(76)/2)
ASPECT = 16/9

def project(p):
    d = max(.015, -p[2])
    return np.array([.5+p[0]/(2*d*TAN*ASPECT), .5-p[1]/(2*d*TAN)])

def unproject(p,d):
    return np.array([(p[0]-.5)*2*d*TAN*ASPECT, (.5-p[1])*2*d*TAN, -d])

# source frame, observed wrist, observed guard, tilt, observed tip,
# chosen wrist for offscreen/one-point phases, initial guard depth, initial Euler.
KEYS = [
 [1040,None,[.812,.847],-6.6,None,[.87,1.08],.38,[-5,-42,6.6]],
 [1042,[.987,.810],[.812,.625],-15,None,None,.22,[30,-35,15]],
 [1044,[.992,.376],[.814,.303],-16.7,None,None,.22,[40,-30,16.7]],
 [1047,None,None,None,None,[1.03,-.32],.23,[0,75,0]],
 [1055,None,None,None,None,[1.03,-.32],.23,[0,75,0]],
 [1074,None,None,None,None,[1.03,-.32],.23,[0,75,0]],
 [1078,None,None,None,None,[1.03,-.32],.23,[0,75,0]],
 [1080,[.812,.264],None,None,None,None,.28,[-15,87,-2]],
 [1082,[.635,.722],[.602,.464],8.1,None,None,.28,[-18,87,-8]],
 [1083,[.551,.918],[.526,.671],9,None,None,.27,[-22,87,-9]],
 [1084,None,[.461,.869],12.5,[.549,.163],None,.30,[-50,85,-12]],
 [1086,None,None,11.9,[.487,.625],[.40,1.53],.26,[-58,85,-12]],
 [1089,None,None,None,None,[.39,1.75],.25,[-120,75,-8]],
 [1099,None,None,None,None,[.56,1.74],.25,[-120,40,18]],
 [1110,None,None,None,None,[.84,1.50],.28,[-112,-35,24]],
 [1118,None,[.793,.974],-24.1,[.630,.349],None,.36,[-40,-40,24]],
 [1125,None,[.816,.783],-6.3,None,[.88,1.02],.38,[-5,-42,6.3]],
 [1133,None,[.816,.825],-3.1,None,[.88,1.065],.38,[-5,-42,3.1]],
]

def solve_key(k):
    fr,w,g,tilt,tip,offw,dep,euler=k
    rot0=Rotation.from_euler('xyz',euler,degrees=True)
    if g is not None:
        p0=unproject(g,dep)-rot0.apply(G0)
    else:
        p0=unproject(w or offw,dep)-rot0.apply(W0)
    x0=np.r_[p0,rot0.as_rotvec()]
    def residual(x):
        rot=Rotation.from_rotvec(x[3:]); p=x[:3]
        wrist=p+rot.apply(W0); tip3=p+rot.apply(TIP); guard=p+rot.apply(G0)
        result=[]
        for loc,target in ((wrist,w),(guard,g),(tip3,tip)):
            if target is not None:
                result.extend((project(loc)-target)*120)
        if offw is not None:
            result.extend((project(wrist)-offw)* (90 if w is None and g is None else 9))
        if tilt is not None:
            near=p+rot.apply(G0+np.array([0,.15,0]))
            dv=project(near)-project(guard)
            angle=math.atan2(dv[0]*1280,-dv[1]*720)
            d=(angle-math.radians(tilt)+math.pi)%(2*math.pi)-math.pi
            result.append(d*12)
        r=np.linalg.norm(wrist-H)
        result.extend([max(0,r-(U+F-.005))*500, max(0,.10-r)*500])
        result.append((p[2]+dep)*1.8)
        result.extend((rot0.inv()*rot).as_rotvec()* .20)
        if fr==1080: result.append(max(0,project(guard)[1]+.04)*120)
        if fr in [1089,1099,1110]:
            result.extend([max(0,1.14-project(tip3)[1])*120,max(0,1.15-project(guard)[1])*120])
        # Edge-on blade during fast downward pass. Blade normal is canonical Z.
        if 1080<=fr<=1086:
            normal=rot.apply([0,0,1]); view=-p/max(np.linalg.norm(p),1e-9)
            result.append(np.dot(normal,view)*1.3)
        result.extend([max(0,wrist[2]+.08)*200,max(0,p[2]+.07)*200])
        return result
    res=least_squares(residual,x0,max_nfev=1200,ftol=1e-12,xtol=1e-12,gtol=1e-12)
    rot=Rotation.from_rotvec(res.x[3:]); p=res.x[:3]; wrist=p+rot.apply(W0)
    return {'source_frame':fr,'time_seconds':(fr-1040)/60,'position':p.tolist(),
            'rotation_xyzw':rot.as_quat().tolist(),'wrist_camera':wrist.tolist(),
            'guard_screen':project(p+rot.apply(G0)).tolist(),'wrist_screen':project(wrist).tolist(),
            'tip_screen':project(p+rot.apply(TIP)).tolist(),'reach_m':float(np.linalg.norm(wrist-H)),
            'target_wrist':w,'target_guard':g,'target_tip':tip,'target_tilt':tilt,
            'authored_offscreen_wrist':offw,'objective_cost':float(res.cost)}

def solve_elbow(wrist,angle=0):
    d=wrist-H; r=np.linalg.norm(d); a=d/r
    x=(U*U-F*F+r*r)/(2*r)
    pole=np.array([.75,-.72,.28]); b=pole-a*np.dot(pole,a); b/=np.linalg.norm(b)
    c=np.cross(a,b)
    return H+a*x+(b*math.cos(angle)+c*math.sin(angle))*math.sqrt(max(0,U*U-x*x))

def bottom_exit(wrist,elbow):
    d=elbow-wrist;den=d[1]-d[2]*TAN
    u=(wrist[2]*TAN-wrist[1])/den if abs(den)>1e-8 else 100
    p=wrist+d*u
    return project(p)[0] if p[2]<-.025 and 0<u<1 else 10

def main():
    keys=[solve_key(k) for k in KEYS]
    ts=np.array([k['time_seconds'] for k in keys])
    positions=PchipInterpolator(ts,np.array([k['position'] for k in keys]),axis=0)
    slerp=Slerp(ts,Rotation.from_quat([k['rotation_xyzw'] for k in keys]))
    bendkeys=[]
    for fr,target in [(1082,.745),(1083,.58)]:
        k=next(k for k in keys if k['source_frame']==fr);w=np.array(k['wrist_camera'])
        angles=np.linspace(-1.4,1.4,1401)
        costs=[(bottom_exit(w,solve_elbow(w,a))-target)**2+.00008*a*a for a in angles]
        bendkeys.append(float(angles[np.argmin(costs)]))
    bend=PchipInterpolator([0,40/60,42/60,43/60,46/60,1.55],[0,0,*bendkeys,0,0])
    frames=[]
    for i in range(187):
        t=i/120; rot=slerp(t); pos=positions(t); wrist=pos+rot.apply(W0)
        r=np.linalg.norm(wrist-H)
        # Depth/translation adjustment keeps the hand attached, never bone scaling.
        if r>U+F-.002:
            correction=(wrist-H)*((U+F-.002)/r-1)
            pos+=correction; wrist+=correction
        elbow=solve_elbow(wrist,float(bend(t)))
        frames.append({'time_seconds':t,'position':pos.tolist(),'rotation_xyzw':rot.as_quat().tolist(),
                       'shoulder':H.tolist(),'elbow':elbow.tolist(),'wrist':wrist.tolist(),
                       'reach_before_projection_m':float(r), 'depth_adjustment_m':float(max(0,r-(U+F-.002)))})
    out={'status':'authored_screen_fit_proposal_not_blender_evaluated','reference_native_fps':60,
         'camera_fov_y_degrees':76,'source_fov_known':False,'sample_hz':120,'duration_seconds':1.55,
         'source_window_seconds':[1040/60,1133/60],'canonical_source_ready_rows':S.tolist(),
         'W0':W0.tolist(),'E0':E0.tolist(),'H0':H0.tolist(),'keys':keys,'frames':frames,
         'method':'visible point least squares; chosen depth; PCHIP translation and shortest SLERP; fixed shoulder exact two-bone elbow',
         'max_depth_adjustment_m':max(f['depth_adjustment_m'] for f in frames),'authored_elbow_circle_angles':bendkeys}
    (ROOT/'pose_fit_proposal.json').write_text(json.dumps(out,indent=2),encoding='utf-8')
    print(json.dumps({'keys':[{k:v for k,v in row.items() if k in ['source_frame','guard_screen','wrist_screen','reach_m','objective_cost']} for row in keys], 'max_depth_adjustment_m':out['max_depth_adjustment_m']},indent=2))

if __name__=='__main__': main()
