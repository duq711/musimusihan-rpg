"""Fit real 3-D model landmarks to the supplied image; no screenshot retouching."""
import numpy as np, math, json
from pathlib import Path
OUT=Path(__file__).resolve().parent
F=470/(2*math.tan(math.radians(38)))
def basis(e):
    x,y,z=e;cx,sx=math.cos(x),math.sin(x);cy,sy=math.cos(y),math.sin(y);cz,sz=math.cos(z),math.sin(z)
    return np.array([[cy,0,sy],[0,1,0],[-sy,0,cy]])@np.array([[1,0,0],[0,cx,-sx],[0,sx,cx]])@np.array([[cz,-sz,0],[sz,cz,0],[0,0,1]])
def project(v): return np.array([418+F*v[0]/-v[2],235-F*v[1]/-v[2]])
def ray(p): return np.array([(p[0]-418)/F,(235-p[1])/F,-1.])
def fit(fun,p):
    p=np.array(p,dtype=float);damping=.01
    for i in range(240):
        r=fun(p);jac=np.column_stack([(fun(p+np.eye(len(p))[j]*1e-5)-r)/1e-5 for j in range(len(p))])
        step=np.linalg.solve(jac.T@jac+np.eye(len(p))*damping,-jac.T@r)
        if np.linalg.norm(step)>.4:step*=.4/np.linalg.norm(step)
        q=p+step
        if np.sum(fun(q)**2)<np.sum(r**2):p=q;damping=max(1e-8,damping*.5)
        else:damping*=4
        if np.linalg.norm(step)<1e-9:break
    return p,float(np.sqrt(np.mean(fun(p)**2)))
rim=np.array([(16,400),(28,338),(63,262),(104,207),(157,156),(215,114),(269,87),(298,78),(343,82),(382,96),(411,127),(424,172),(419,225),(402,276),(378,322),(345,363),(302,409),(257,442),(215,462)])
def shield_res(p):
    n=basis([p[3],p[4],0])[:,2];c=p[:3]+n*.017
    result=[]
    for pixel in rim:
        d=ray(pixel);t=n@c/(n@d)
        result.append((np.linalg.norm(t*d-c)-.427)*F/t)
    return np.array(result)
p,error=fit(shield_res,[-.23,-.11,-.7,math.radians(25),math.radians(66)])
B=basis([p[3],p[4],math.radians(-10)])
def shield_contact(pixel,z):
    d=ray(pixel);n=B[:,2];c=p[:3]+n*z
    return B.T@(d*(n@c/(n@d))-p[:3])
grip=shield_contact([351,300],.095)
result={'shield_guard':{'origin':p[:3].tolist(),'degrees':[*np.degrees(p[3:]),-10],'rim_rms_pixels':error,'grip':grip.tolist(),'arm_strap':shield_contact([263,323],.14).tolist()}}
shield_poses={
 'idle': ([(0,424),(33,380),(75,342),(118,314),(164,296),(207,289),(250,295),(282,310),(307,338),(325,380),(336,424),(337,468)], [272,438], [-.4,-.5,-.7,0,50,-10]),
 'impact': ([(0,249),(61,190),(119,143),(179,105),(234,81),(280,74),(314,79),(335,95),(345,115),(337,156),(318,194),(286,233)], [279,243], [-.4,0,-.6,50,65,-10]),
 'riposte': ([(0,83),(39,82),(75,99),(115,138),(150,188),(177,249),(190,303),(190,350),(174,390),(153,413),(130,424)], [58,289], [-.65,-.1,-.6,0,80,20])}
for name,(pixels,grip_pixel,initial) in shield_poses.items():
    def residual(v):
        b=basis(v[3:]);n=b[:,2];c=v[:3]+n*.017;res=[]
        for pixel in pixels:
            d=ray(pixel);t=n@c/(n@d);res.append((np.linalg.norm(t*d-c)-.427)*F/t)
        res.extend((project(v[:3]+b@grip)-grip_pixel)*2)
        return np.array(res)
    initial=np.array(initial);initial[3:]=np.radians(initial[3:])
    q,e=fit(residual,initial)
    result['shield_'+name]={'origin':q[:3].tolist(),'degrees':np.degrees(q[3:]).tolist(),'rim_and_grip_rms_pixels':e}
sword_points=np.array([[0,1.035,0],[0,-.006,0],[-.123,.015,0],[.123,.015,0]])
poses={
'idle':([[575,97],[673,376],[616,390],[729,351]],[.682,-.37,-.80,-25.5,0,2.4]),
'guard':([[586,83],[658,357],[609,374],[719,334]],[.65,-.32,-.80,-26,0,0]),
'riposte':([[250,140],[591,228],[560,255],[607,207]],[.62,.005,-.95,18,-1,79])}
for name,(pixels,initial) in poses.items():
    pixels=np.array(pixels)
    def residual(v):
        B=basis(v[3:]);return (np.array([project(B@point+v[:3]) for point in sword_points])-pixels).flatten()
    initial=np.array(initial);initial[3:]=np.radians(initial[3:])
    q,e=fit(residual,initial)
    result['sword_'+name]={'origin':q[:3].tolist(),'degrees':np.degrees(q[3:]).tolist(),'rms_pixels':e}
print(json.dumps(result,indent=2));(OUT/'reference_calibration.json').write_text(json.dumps(result,indent=2))
