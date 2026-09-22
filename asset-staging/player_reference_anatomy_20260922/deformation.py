"""Reference-guided clothed anatomy; world metres, +Z up and +Y forward."""
import math
from mathutils import Vector

def smooth(t):
    t=max(0.,min(1.,t)); return t*t*(3.-2.*t)
def gauss(value,center,width):return math.exp(-((value-center)/width)**2)

def garment(p):
    x,y,z=abs(p.x),p.y,p.z
    if z<=.920:return p.copy()
    side=1. if p.x>=0 else -1.
    trunk=1.-smooth((x-.185)/.065)
    height=smooth((z-1.105)/.075)*(1.-smooth((z-1.395)/.060))
    # Flatten the cylindrical cross-section, while widening the rib cage.
    chest=gauss(z,1.305,.115)
    waist=gauss(z,1.17,.055)
    dx=p.x*(.115*chest-.025*waist)*trunk*height
    yy=y*(1.-.17*trunk*height)
    # Two broad pectoral volumes under cloth, not engraved muscle grooves.
    front=smooth((y-.012)/.065)
    yy+=.027*gauss(x,.108,.070)*gauss(z,1.320,.067)*front*height
    # Connect the pectoral/axillary root to the anterior deltoid.
    join=gauss(x,.203,.052)*gauss(z,1.337,.066)*smooth(abs(y)/.040)
    yy+=(.015 if y>=0 else -.009)*join
    # Redistribute sleeve volume below the deltoid and taper toward the elbow.
    arm=smooth((x-.183)/.047)
    bulk=.17*gauss(z,1.275,.078)*smooth((z-1.17)/.040)*(1.-smooth((z-1.375)/.055))
    center=.270-.27*(z-1.27)
    dx+=side*(x-center)*bulk*arm
    yy+=(y-.004)*bulk*arm
    # A shorter trapezius slope, a flatter clavicular span and a raised outer cap.
    roof=(.012*gauss(x,.224,.071)+.006*gauss(x,.073,.052))*smooth((z-1.300)/.135)
    # Bring the over-wide shoulder/upper-arm centers inward as one continuous
    # field. The offset eases to zero before the preserved wrist and hand.
    dx-=side*.020*smooth((x-.050)/.210)*smooth((z-1.015)/.305)
    # Lower the authored elbow without moving the cuff/hand, increasing the
    # upper-arm share and shortening the formerly longer lower segment.
    elbow=.026*smooth((z-.920)/.235)*(1.-smooth((z-1.155)/.220))*smooth((x-.185)/.050)
    zz=z+roof-elbow
    # Lower the anterior crew-neck opening and fit it to the neck column.
    near_neck=(1.-smooth((x-.078)/.055))*(1.-smooth((abs(y-.007)-.065)/.045))*smooth((z-1.40)/.045)
    dx-=p.x*.055*near_neck
    yy=.007+(yy-.007)*(1.-.055*near_neck)
    anterior=smooth((y+.008)/.065)
    zz-=.006*near_neck*anterior
    return Vector((p.x+dx,yy,zz))

def neck(p):
    x,y,z=p
    if z>=1.51:return p.copy()
    lower=1.-smooth((z-1.465)/.045)
    # Extend the donor neck behind the new lower neckline; face stays exact.
    zz=z-.010*lower
    xx=x*(1.-.050*lower)
    yy=.009+(y-.009)*(1.-.06*lower)
    # Broad paired neck attachments, faded out at the supplied jaw.
    shape=smooth((z-1.44)/.017)*(1.-smooth((z-1.485)/.025))
    track=.029+.55*(z-1.45)
    ridge=.0035*gauss(abs(x),track,.018)*smooth((y-.02)/.04)*shape
    yy+=ridge-.0025*gauss(x,0,.024)*smooth((y-.025)/.04)*shape
    return Vector((xx,yy,zz))
