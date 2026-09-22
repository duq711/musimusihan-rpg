"""Whole-body fitting coordinates: metres, +Z up, +Y forward.
Targets come from calibrated front/back landmarks and both side views.
"""
import math
from mathutils import Vector

def smooth(t):
 t=max(0.,min(1.,t));return t*t*(3.-2.*t)
class Curve:
 """Monotone cubic interpolation, including exact target landmarks."""
 def __init__(self,knots):
  self.x=[p[0] for p in knots];self.y=[p[1] for p in knots]
  d=[(self.y[i+1]-self.y[i])/(self.x[i+1]-self.x[i]) for i in range(len(knots)-1)]
  self.m=[d[0]]+[0. if a*b<=0 else 2*a*b/(a+b) for a,b in zip(d,d[1:])]+[d[-1]]
 def __call__(self,x):
  if x<=self.x[0]:return self.y[0]+self.m[0]*(x-self.x[0])
  if x>=self.x[-1]:return self.y[-1]+self.m[-1]*(x-self.x[-1])
  i=next(i for i in range(len(self.x)-1) if x<=self.x[i+1]);h=self.x[i+1]-self.x[i];t=(x-self.x[i])/h
  return (2*t**3-3*t*t+1)*self.y[i]+(t**3-2*t*t+t)*h*self.m[i]+(-2*t**3+3*t*t)*self.y[i+1]+(t**3-t*t)*h*self.m[i+1]
HEIGHT=Curve([(.0076724,.0076724),(.12,.12),(.46546,.43541),(.55,.53576),(.815,.78162),(1.08437,.98483),(1.20,1.14),(1.31,1.278),(1.36,1.37368),(1.455,1.449),(1.51,1.51),(1.719888,1.719888)])
WIDTH=Curve([(.80,1.),(.95,1.04),(1.08437,.96),(1.15,.925),(1.20,.84),(1.23,.817),(1.26,.88),(1.30,.91),(1.40,.94),(1.47,1.02),(1.51,1.025),(1.72,1.025)])
DEPTH=Curve([(.80,1.),(.95,1.),(1.08437,.86),(1.15,.91),(1.20,.98),(1.30,1.06),(1.40,1.),(1.51,1.),(1.72,1.)])
# Positive-X limb guides. Shared wrist coordinates are measured, not guessed.
OLD_S=Vector((.23347,.00461,1.36));OLD_E=Vector((.27757,.00414,1.1292));OLD_W=Vector((.32124,.07538,.88172))
NEW_S=Vector((.205,.0046,1.37368));NEW_E=Vector((.278,.014,1.15793));NEW_W=Vector((.3794,.075,.93089))

def segment(p,a,b,c,d,radius):
 axis=(b-a).normalized();newaxis=(d-c).normalized();delta=p-a
 parallel=axis*delta.dot(axis);perpendicular=delta-parallel
 rotation=axis.rotation_difference(newaxis)
 return c+rotation@(parallel*((d-c).length/(b-a).length)+perpendicular*radius)

def body(p):
 return Vector((p.x*WIDTH(p.z),p.y*DEPTH(p.z),HEIGHT(p.z)))

def articulated_arm(p):
 side=1. if p.x>=0 else -1.;q=Vector((abs(p.x),p.y,p.z))
 radius=.89+.07*(1.-smooth((p.z-.94)/.12))
 upper=segment(q,OLD_S,OLD_E,NEW_S,NEW_E,.86)
 fore=segment(q,OLD_E,OLD_W,NEW_E,NEW_W,radius)
 # A broad taper extends across the same shared wrist field on sleeve/hand;
 # avoid a narrow pinch followed by a wide cuff.
 taper=smooth((fore.z-.88)/.065)*(1.-smooth((fore.z-.965)/.16))
 center=NEW_E.lerp(NEW_W,(NEW_E.z-fore.z)/(NEW_E.z-NEW_W.z))
 fore.x=center.x+(fore.x-center.x)*(1.-.23*taper)-.010*taper
 fore.y=center.y+(fore.y-center.y)*(1.-.18*taper)
 t=smooth((p.z-(OLD_E.z-.035))/.070)
 out=fore.lerp(upper,t);out.x*=side
 return out

def shared_upper(p):
 mix=smooth((abs(p.x)-.135)/.085)
 q=body(p).lerp(articulated_arm(p),mix)
 # Raise the shoulder slope beneath the clavicle without raising the neck.
 q.z+=.014*math.exp(-((abs(q.x)-.18)/.082)**2)*smooth((q.z-1.35)/.065)
 q.x*=1.-.045*math.exp(-((q.z-1.322)/.055)**2)*smooth((abs(q.x)-.17)/.07)
 return q

def torso(p):
 blend=smooth((p.z-1.24)/.040)
 return body(p).lerp(shared_upper(p),blend)

def arm(p):
 blend=smooth((p.z-1.24)/.040)
 return articulated_arm(p).lerp(shared_upper(p),blend)

# Filled by the build from measured source cross-sections and photo contours.
LEG_SOURCE={};LEG_TARGET_CENTER=None;LEG_TARGET_WIDTH=None
PELVIS_JOIN=Curve([(0.,0.),(.040,.006),(.210,.214),(.300,.300)])
SHIN_BACK=Curve([(.007,.052),(.28,.052),(.42,.040),(.52,.020),(.85,0.),(1.,0.)])

def leg(p):
 side=1. if p.x>=0 else -1.;z=HEIGHT(p.z);q=body(p)
 source_center,source_width=LEG_SOURCE[side]
 half=source_width(p.z)/2
 radial=(abs(p.x)-source_center(p.z))/max(half,.018)
 target_center=LEG_TARGET_CENTER(z);target_width=LEG_TARGET_WIDTH(z)
 fitted_x=side*(target_center+radial*target_width/2)
 # Plane silhouettes jump from two thighs to a joined pelvis. Interpolating
 # their extrema produces a horizontal ledge. A continuous monotone spatial
 # map closes the crotch while keeping the centre seam fixed instead.
 join=smooth((p.z-.765)/.035)
 fitted_x=fitted_x*(1.-join)+side*PELVIS_JOIN(abs(p.x))*join
 blend=1.-smooth((p.z-.818)/.065)
 q.x=q.x*(1.-blend)+fitted_x*blend
 # A foot is one rigidly proportioned volume, not a stack of leg sections.
 # Fit width/length around its ankle, then blend into the boot shaft.
 foot=1.-smooth((p.z-.10)/.10)
 dx=(abs(p.x)-(.1432 if side>0 else .1560))*.82
 dy=(p.y-.005)*.85;angle=.085
 fx=side*(.200+math.cos(angle)*dx+math.sin(angle)*dy)
 fy=.005+math.cos(angle)*dy-math.sin(angle)*dx
 q.x=q.x*(1.-foot)+fx*foot;q.y=q.y*(1.-foot)+fy*foot
 # Both side references, aligned at the pelvis, place the ankle behind the
 # old forward-bowed shin. Keep the pelvis fixed and move the knee less.
 q.y-=SHIN_BACK(q.z)
 return q
