"""Small anatomical form changes to the accepted, broadened neck.

Input/output are Blender world coordinates in metres; +Y faces forward.
The source was probed from Gravebound_Sturdy_Neck_Shoulders.blend: its
exposed anterior neck is at Z=1.445--1.500 and Y=+0.049--+0.075.  The
chin begins to project beyond Y=+0.08 near Z=1.50, so it is protected.
This function neither reads Blender data nor changes topology or UVs.
"""
import math
from mathutils import Vector


def _smooth(t):
    t = max(0.0, min(1.0, t))
    return t * t * (3.0 - 2.0 * t)


def deform_neck(p):
    """Soften the conical flare and imply broad, relaxed neck muscles.

    No displacement at/below the collar or at/above the protected face.
    Broad angular fields avoid thin tendons, grooves and skin wrinkles.
    """
    x, y, z = p.x, p.y, p.z
    if z <= 1.445 or z >= 1.510:
        return Vector((x, y, z))

    # The original lower opening and upper facial surface stay fixed.
    lower = _smooth((z - 1.445) / 0.014)
    upper = 1.0 - _smooth((z - 1.493) / 0.017)
    # Protect the chin's projecting underside as well as the height mask.
    chin = _smooth((z - 1.490) / 0.010) * _smooth((y - 0.070) / 0.012)
    weight = lower * upper * (1.0 - chin)
    if weight <= 0.0:
        return Vector((x, y, z))

    cy = y - 0.007
    radius = math.hypot(x, cy)
    if radius < 1e-8:
        return Vector((x, y, z))

    # Angle zero is the front of the throat; pi/2 is the side of the neck.
    theta = math.atan2(abs(x), cy)
    rise = _smooth((z - 1.450) / 0.055)
    scm_angle = 0.32 + 0.80 * rise
    # A wide shallow oblique swelling, not a carved line: paired relaxed
    # sternocleidomastoid flow from the lower front toward the jaw sides.
    muscle = 0.0026 * math.exp(-((theta - scm_angle) / 0.31) ** 2)
    # Relieve the oversized lower side flare while retaining the sturdy
    # baseline width.  The rounded side contracts by under two millimetres.
    flare = 0.0018 * math.exp(-((z - 1.466) / 0.020) ** 2)
    flare *= math.exp(-((theta - 1.40) / 0.56) ** 2)
    radial = weight * (muscle - flare)
    return Vector((x + radial * x / radius,
                   y + radial * cy / radius,
                   z))
