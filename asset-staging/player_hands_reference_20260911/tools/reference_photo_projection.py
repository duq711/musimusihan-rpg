"""Bake-only anatomical projection of the untouched user photo onto bare skin.

This creates point attributes, not an atlas UV layer or modified bitmap. Photo
RGB is decoded by Blender, multiplied once by PHOTO_LINEAR_TINT and blended at
most PHOTO_MAX_BLEND into the existing procedural pigment. White background and
missing attributes (including the cuff) fall back to that procedural pigment.
"""
import hashlib
import math
from pathlib import Path

import bpy
from mathutils import Vector

DIGITS = ('thumb', 'index', 'middle', 'ring', 'little')
ATTRIBUTE_NAMES = ('ReferencePhotoPalm', 'ReferencePhotoBack',
                   'ReferencePhotoFingerPalm', 'ReferencePhotoFingerBack',
                   'ReferencePhotoWeights')
PHOTO_PATH = Path(__file__).resolve().parents[1] / 'reference/user_hand_photo.png'
PHOTO_IMAGE_NAME = 'Reference_User_Hand_Photo_Unmodified'
PHOTO_LINEAR_TINT = (.73, .62, .56, 1.)
PHOTO_MAX_BLEND = .65
PHOTO_SIZE = (800, 553)
# Pixel coordinates are measured on the original image; each final point lies
# inside its finger tip. No skin/background replacement is written to the image.
LANDMARKS = {
    'palm': {
        'index': ((219,275),(238,216),(250,170),(260,140)),
        'middle': ((181,258),(184,199),(183,150),(183,113)),
        'ring': ((148,268),(133,211),(122,164),(116,141)),
        'little': ((127,286),(93,253),(78,222),(67,201)),
        'thumb': ((227,367),(274,328),(310,309),(345,300)),
    },
    'back': {
        'index': ((563,276),(545,203),(538,156),(532,124)),
        'middle': ((604,267),(610,196),(616,147),(620,108)),
        'ring': ((637,291),(661,235),(679,188),(691,146)),
        'little': ((660,322),(699,281),(728,255),(750,231)),
        'thumb': ((534,377),(476,353),(441,328),(402,307)),
    },
}
# These are deliberately narrower than the photographed silhouettes. Projection
# samples the skin interior even around side surfaces and tiny image highlights.
PHOTO_HALF_WIDTHS = {'thumb': (13., 12., 9., 5.), 'index': (11., 9., 8., 5.),
                    'middle': (12., 10., 8., 5.), 'ring': (10., 9., 7., 4.),
                    'little': (8., 7., 6., 3.5)}


def smooth(a, b, value):
    t = max(0., min(1., (value-a)/(b-a)))
    return t*t*(3.-2.*t)


def photo_image():
    assert PHOTO_PATH.is_file(), 'The unchanged user hand photograph is required.'
    image = bpy.data.images.get(PHOTO_IMAGE_NAME)
    if image is None:
        image = bpy.data.images.load(str(PHOTO_PATH), check_existing=False)
        image.name = PHOTO_IMAGE_NAME
    assert tuple(image.size) == PHOTO_SIZE, 'Unexpected reference image dimensions.'
    image.colorspace_settings.name = 'sRGB'
    if image.packed_file is None:
        image.pack()
    return image


def _uv(pixel, interior_gate=0.):
    # Image textures use XY; Z carries the independent anatomical interior gate.
    return (pixel[0]/PHOTO_SIZE[0], 1.-pixel[1]/PHOTO_SIZE[1], interior_gate)


def prepare_photo_uv(skin, rig, holder, points, owners, frames):
    """Add anatomy-aligned photo fields without changing geometry or deform data."""
    assert len(points) == len(owners) == len(skin.data.vertices)
    image = photo_image()
    thumb_sign = 1. if frames['thumb',0][0].x > frames['middle',0][0].x else -1.
    palm_end = sum(frames[d,0][0].y for d in ('index','middle','ring'))/3.
    wrist_points = [p for p,o in zip(points,owners) if o == 'wrist' and .035 < p.y < .075]
    xs = sorted(p.x for p in wrist_points)
    assert len(xs) > 20 and palm_end > .06
    center_x = (xs[2]+xs[-3])*.5
    half_width = max(.025, (xs[-3]-xs[2])*.5)
    transforms = {}
    for digit in DIGITS:
        center, axis, dorsal, across, radius = frames[digit,0]
        centers = [frames[digit,j][0].copy() for j in range(3)]
        distal_center, distal_axis = frames[digit,2][:2]
        owned = [p for p,o in zip(points,owners) if o == digit]
        tip_length = max((p-distal_center).dot(distal_axis) for p in owned)
        centers.append(distal_center+distal_axis*tip_length)
        levels = [(p-center).dot(axis) for p in centers]
        assert all(b > a+1e-5 for a,b in zip(levels,levels[1:])), 'Nonmonotonic '+digit+' frame'
        radii = [frames[digit,j][4] for j in range(3)] + [max(.003, frames[digit,2][4]*.64)]
        transforms[digit] = (center,axis,centers,levels,radii)
    attributes = {}
    for name in ATTRIBUTE_NAMES:
        previous = skin.data.attributes.get(name)
        if previous: skin.data.attributes.remove(previous)
        attributes[name] = skin.data.attributes.new(name=name,type='FLOAT_VECTOR',domain='POINT')
    native = holder.matrix_world.inverted() @ skin.matrix_world
    normal_matrix = native.to_3x3().inverted().transposed()
    counts = {digit: 0 for digit in DIGITS}
    for vertex, point, owner in zip(skin.data.vertices, points, owners):
        index = vertex.index
        u = thumb_sign*(point.x-center_x)/half_width
        v = (point.y-.010)/(palm_end-.010)
        body = {'palm': Vector((165.+u*60.+v*15.,436.-v*180.)),
                'back': Vector((566.-u*62.+v*40.,440.-v*190.))}
        body_gate = ((1.-smooth(.50,.80,abs(u))) * smooth(.10,.25,v)
                     * (1.-smooth(.72,.96,v)))
        finger_pixels = {side: pixel.copy() for side,pixel in body.items()}
        blend = 0.
        normal = (normal_matrix @ vertex.normal).normalized()
        facing_axis = Vector((0,0,1))
        if owner in DIGITS:
            counts[owner] += 1
            center, axis, centers, levels, radii = transforms[owner]
            t = (point-center).dot(axis)
            segment = next((j for j in range(3) if t <= levels[j+1]), 2)
            amount = max(0.,min(1.,(t-levels[segment])/(levels[segment+1]-levels[segment])))
            local_center = centers[segment].lerp(centers[segment+1],amount)
            jf = min(segment,2)
            across = frames[owner,jf][3]
            facing_axis = frames[owner,jf][2]
            radius = radii[segment]*(1-amount)+radii[segment+1]*amount
            radial = max(-1.,min(1.,thumb_sign*(point-local_center).dot(across)/radius))
            width = PHOTO_HALF_WIDTHS[owner][segment]*(1-amount)+PHOTO_HALF_WIDTHS[owner][segment+1]*amount
            for side in ('palm','back'):
                first,last = (Vector(p) for p in LANDMARKS[side][owner][segment:segment+2])
                tangent = (last-first).normalized()
                photo_across = Vector((-tangent.y,tangent.x))*(1. if side=='palm' else -1.)
                finger_pixels[side] = first.lerp(last,amount)+photo_across*(radial*width*.80)
            # Both projections are sampled separately through the joint root;
            # interpolating their UVs would drag the photo across white gaps.
            blend = smooth(.025,.045,t) if owner!='thumb' else smooth(.045,.065,t)
        facing = normal.dot(facing_axis)
        gate = smooth(.010,.035,point.y)
        palm = smooth(.10,.72,-facing)*gate
        back = smooth(.10,.72,facing)*gate
        attributes['ReferencePhotoPalm'].data[index].vector = _uv(body['palm'],body_gate)
        attributes['ReferencePhotoBack'].data[index].vector = _uv(body['back'],body_gate)
        attributes['ReferencePhotoFingerPalm'].data[index].vector = _uv(finger_pixels['palm'])
        attributes['ReferencePhotoFingerBack'].data[index].vector = _uv(finger_pixels['back'])
        attributes['ReferencePhotoWeights'].data[index].vector = (blend,palm,back)
    return {'status':'photo_fields_ready_pending_visual_review','attributes':list(ATTRIBUTE_NAMES),
            'photo_path':str(PHOTO_PATH),'photo_sha256':hashlib.sha256(PHOTO_PATH.read_bytes()).hexdigest(),
            'photo_size':list(image.size),'packed_original':bool(image.packed_file),
            'geometry_weights_keys_atlas_uv_unchanged':True,'digit_vertex_counts':counts,
            'projection':'Main palm/back plus five independent joint-frame finger projections; finger photo fades in above the broad MCP/web region.',
            'landmarks_image_pixels':LANDMARKS,'palm_native_end_y':palm_end,
            'thumb_sign':thumb_sign,'linear_rgb_multiplier':list(PHOTO_LINEAR_TINT[:3]),
            'maximum_photo_blend':PHOTO_MAX_BLEND,
            'body_interior_fade':{'abs_u':[.50,.80],'v_low':[.10,.25],'v_high':[.72,.96]},
            'background_rule':'Smooth R-G confidence 0.04..0.10 and R-B 0.06..0.15, multiplied by anatomical body-interior gate; no bitmap replacement.',
            'missing_attribute_behavior':'Zero photo-facing weights, so cuff and other non-photo surfaces retain procedural pigment.'}


def photo_pigment(n, base):
    """Return a portable bake color socket; no displacement or duplicate lighting."""
    image = photo_image()
    finger, palm, back = n.attribute('ReferencePhotoWeights',True)
    def clamp(value):
        return n.math('MINIMUM',n.math('MAXIMUM',value,0.),1.)
    def confidence_ramp(value,low,high):
        t=clamp(n.math('DIVIDE',n.math('SUBTRACT',value,low),high-low))
        return n.math('MULTIPLY',n.math('MULTIPLY',t,t),n.math('SUBTRACT',3.,n.math('MULTIPLY',2.,t)))
    def sample(attribute,body=False):
        tex = n.new('ShaderNodeTexImage',attribute+'_OriginalPhoto')
        tex.image=image;tex.interpolation='Linear';tex.extension='CLIP'
        n.links.new(n.attribute(attribute).outputs['Vector'],tex.inputs['Vector'])
        sep=n.new('ShaderNodeSeparateColor');sep.mode='RGB'
        n.links.new(tex.outputs['Color'],sep.inputs['Color'])
        red,green,blue=sep.outputs[:3]
        warm=confidence_ramp(n.math('SUBTRACT',red,green),.04,.10)
        chroma=confidence_ramp(n.math('SUBTRACT',red,blue),.06,.15)
        confidence=n.math('MULTIPLY',n.math('MULTIPLY',warm,chroma),tex.outputs['Alpha'])
        if body:
            confidence=n.math('MULTIPLY',confidence,n.attribute(attribute,True)[2])
        adjusted=n.mix(1.,tex.outputs['Color'],PHOTO_LINEAR_TINT,'MULTIPLY')
        return adjusted,confidence
    result=base
    for side,weight in (('Palm',palm),('Back',back)):
        main_color,main_mask=sample('ReferencePhoto'+side,body=True)
        digit_color,digit_mask=sample('ReferencePhotoFinger'+side)
        main=n.mix(main_mask,base,main_color)
        digit=n.mix(digit_mask,base,digit_color)
        projected=n.mix(finger,main,digit)
        result=n.mix(n.math('MULTIPLY',weight,PHOTO_MAX_BLEND),result,projected)
    return result
