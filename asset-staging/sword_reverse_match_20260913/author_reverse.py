"""Mirror the accepted forehand's cutting path using proper rotations.
Right-hand mesh chirality is preserved. Right-arm joints are re-solved from
its actual local wrist; only the reverse clip changes. Mac Blender authoring.
"""
import bpy, hashlib, json, math, platform
from pathlib import Path
from mathutils import Vector, Matrix, Quaternion
ROOT=Path(__file__).resolve().parent
SOURCE=ROOT/'baseline/godot-game/assets/animations/reference_sword_motion/motion_manifest.json'
OUT=ROOT/'candidate_01';OUT.mkdir(exist_ok=True)
V=Vector
GRIP=V((0,-.108,.002))
WRIST=V((.0679751875,-.1080001335,.0524637313))
SHOULDER=V((.29,-.34,.10))
PLANE_NORMAL=V((0,0,1))
def quat(row):
    x, y, z, w = row['rotation_xyzw']
    return Quaternion((w, x, y, z))


def held(palm, direction, normal=PLANE_NORMAL, bank=8):
    y = V(direction).normalized()
    z = V(normal) - y * y.dot(normal)
    z.normalize()
    z = Quaternion(y, math.radians(bank)) @ z
    q = Matrix((y.cross(z), y, z)).transposed().to_quaternion()
    return V(palm) - q @ GRIP, q


def log_rotation(q):
    q = q.normalized()
    if q.w < 0:
        q.negate()
    v = V((q.x, q.y, q.z))
    return v.normalized() * (2 * math.atan2(v.length, q.w)) if v.length > 1e-8 else V((0, 0, 0))


def exp_rotation(v):
    return Quaternion(v.normalized(), v.length) if v.length > 1e-8 else Quaternion()


def sample(keys, time):
    i = next((i for i in range(len(keys) - 1) if time <= keys[i + 1][0]), len(keys) - 2)
    times = [row[0] for row in keys]
    positions = [row[1][0] for row in keys]
    rotations = [row[1][1] for row in keys]
    dt = times[i + 1] - times[i]
    t = min(1, max(0, (time - times[i]) / dt))

    def position_tangent(k):
        if k in (0, len(keys) - 1):
            return V((0, 0, 0))
        before = (positions[k] - positions[k - 1]) / (times[k] - times[k - 1])
        after = (positions[k + 1] - positions[k]) / (times[k + 1] - times[k])
        return V(tuple(2 * a * b / (a + b) if a * b > 0 else 0 for a, b in zip(before, after)))

    def angular_tangent(k):
        if k in (0, len(keys) - 1) or abs(times[k] - 1.30) < 1e-8:
            return V((0, 0, 0))
        qa = rotations[k]
        db, da = times[k] - times[k - 1], times[k + 1] - times[k]
        before = -log_rotation(qa.inverted() @ rotations[k - 1]) / db
        after = log_rotation(qa.inverted() @ rotations[k + 1]) / da
        if before.dot(after) <= 0:
            return V((0, 0, 0))
        direction = (before.normalized() + after.normalized()).normalized()
        return direction * (2 * before.length * after.length / (before.length + after.length))

    p = (positions[i] * (2*t**3 - 3*t*t + 1)
         + position_tangent(i) * dt * (t**3 - 2*t*t + t)
         + positions[i + 1] * (-2*t**3 + 3*t*t)
         + position_tangent(i + 1) * dt * (t**3 - t*t))
    a, d = rotations[i], rotations[i + 1]
    b = a @ exp_rotation(angular_tangent(i) * dt / 3)
    c = d @ exp_rotation(-angular_tangent(i + 1) * dt / 3)
    ab, bc, cd = a.slerp(b, t), b.slerp(c, t), c.slerp(d, t)
    q = ab.slerp(bc, t).slerp(bc.slerp(cd, t), t).normalized()
    return p, q


def arm(p, q):
    wrist = p + q @ WRIST
    offset = wrist - SHOULDER
    axis = offset.normalized()
    reach = min(.595, max(.081, offset.length))
    shoulder = wrist - axis * reach
    hint = V((.70, -.70, .23))
    bend = (hint - axis * hint.dot(axis)).normalized()
    along = (.34**2 - .26**2 + reach**2) / (2 * reach)
    elbow = shoulder + axis * along + bend * math.sqrt(max(0, .34**2 - along**2))
    return {name: list(value) for name, value in [('shoulder', shoulder), ('elbow', elbow), ('wrist', wrist)]}




assert platform.system()=='Darwin'
original=json.loads(SOURCE.read_text());manifest=json.loads(SOURCE.read_text())
forehand=original['clips']['right_diagonal']
reverse=manifest['clips']['left_reverse']
ready_row=original['clips']['idle']['tracks']['sword'][0]
ready=(V(ready_row['position']),quat(ready_row))
ready_grip=ready[0]+ready[1]@GRIP
mirror=Matrix.Diagonal(V((-1,1,1)))

def reflected(row):
    p,q=V(row['position']),quat(row)
    b=q.to_matrix()
    # Two reflections produce a rotation, never a mirrored/scaled hand mesh.
    basis=Matrix((-(mirror@b.col[0]),mirror@b.col[1],mirror@b.col[2])).transposed()
    assert abs(basis.determinant()-1)<1e-5
    rotation=basis.to_quaternion()
    return mirror@(p+q@GRIP)-rotation@GRIP,rotation

prep_row=min(forehand['tracks']['sword'],key=lambda row:abs(row['time_seconds']-.62))
prep=reflected(prep_row)
mirrored_ready=reflected(ready_row)
return_offset=ready_grip-mirror@ready_grip
source_rows=forehand['tracks']['sword']
assert [r['time_seconds'] for r in source_rows]==[r['time_seconds'] for r in reverse['tracks']['sword']]
bpy.ops.object.select_all(action='SELECT');bpy.ops.object.delete(use_global=False)
bpy.context.scene.render.fps=120
controls={}
for name in ('sword','shoulder','elbow','wrist'):
    ob=bpy.data.objects.new('left_reverse_'+name,None);bpy.context.collection.objects.link(ob)
    ob.rotation_mode='QUATERNION';controls[name]=ob
previous=None
max_shoulder_shift=0
for i,row in enumerate(reverse['tracks']['sword']):
    t=row['time_seconds']
    p,q=reflected(source_rows[i])
    if t<.62:
        u=min(1,max(0,t/.34));u=u*u*(3-2*u)
        q=ready[1].slerp(prep[1],u)
        palm=ready_grip.lerp(prep[0]+prep[1]@GRIP,u)
        p=palm-q@GRIP
    elif t>.88:
        u=min(1,max(0,(t-.88)/(1.42-.88)));u=u*u*(3-2*u)
        palm=p+q@GRIP+return_offset*u
        q=q.slerp(ready[1],u)
        p=palm-q@GRIP
    if previous is not None and previous.dot(q)<0:q.negate()
    previous=q.copy()
    row['position']=list(p);row['rotation_xyzw']=[q.x,q.y,q.z,q.w]
    joints=arm(p,q);joints['time_seconds']=t;reverse['right_arm'][i]=joints
    max_shoulder_shift=max(max_shoulder_shift,(V(joints['shoulder'])-SHOULDER).length)
    controls['sword'].location=p;controls['sword'].rotation_quaternion=q
    controls['sword'].keyframe_insert('location',frame=t*120+1)
    controls['sword'].keyframe_insert('rotation_quaternion',frame=t*120+1)
    for name in ('shoulder','elbow','wrist'):
        controls[name].location=joints[name];controls[name].keyframe_insert('location',frame=t*120+1)
for name,data in original['clips'].items():
    if name!='left_reverse':assert manifest['clips'][name]==data
assert reverse['tracks']['shield']==original['clips']['left_reverse']['tracks']['shield']
assert reverse['timing']==original['clips']['left_reverse']['timing']
manifest['reverse_edge_alignment']={
    'date':'2026-09-13','execution_os':platform.system(),'blender_version':bpy.app.version_string,
    'source_preserved':True,'source_sha256':hashlib.sha256(SOURCE.read_bytes()).hexdigest(),
    'script_sha256':hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
    'accepted_forehand_sha256':hashlib.sha256(json.dumps(forehand,sort_keys=True,separators=(',',':')).encode()).hexdigest(),
    'changed':'left_reverse sword and actual right-arm joints; camera-X mirrored accepted cut, proper rotations, shared right-side idle recovery',
    'preserved':'accepted right_diagonal, all other clips, shield tracks, original model bytes, duration and combat clocks',
    'max_authored_shoulder_compensation_m':max_shoulder_shift,
}
bpy.context.scene.frame_end=172
bpy.ops.wm.save_as_mainfile(filepath=str(OUT/'Reverse_From_Accepted_Forehand.blend'))
(OUT/'motion_manifest.json').write_text(json.dumps(manifest,separators=(',',':')))
print('REVERSE MATCH AUTHOR PASS: accepted forehand unchanged; proper rotation; actual wrist IK; same combat timing')
print('MAX SHOULDER COMPENSATION M',max_shoulder_shift)
