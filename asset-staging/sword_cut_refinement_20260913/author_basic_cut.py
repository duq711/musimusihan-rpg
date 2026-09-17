"""Re-author only the forehand sword/attached arm on Mac Blender.

The cut follows a diagonal arc with its cutting edge leading. The
left reverse, all combat clocks, shield tracks and original meshes are copied
unchanged. Dense samples and editable Blender controls are separate outputs.
"""
import bpy
import hashlib
import json
import math
import platform
from pathlib import Path
from mathutils import Vector, Matrix, Quaternion

ROOT = Path(__file__).resolve().parent
SOURCE = ROOT / 'baseline/godot-game/assets/animations/reference_sword_motion/motion_manifest.json'
OUT = ROOT / 'motion_v3'
OUT.mkdir(exist_ok=True)
V = Vector
GRIP = V((0, -.108, .002))
WRIST = V((.0679751875, -.1080001335, .0524637313))
SHOULDER = V((.29, -.34, .10))
PLANE_NORMAL = V((0, 0, 1))


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


assert platform.system() == 'Darwin', 'This authoring task is assigned to MacBook.'
manifest = json.loads(SOURCE.read_text())
clip = manifest['clips']['right_diagonal']
ready_row = manifest['clips']['idle']['tracks']['sword'][0]
ready = (V(ready_row['position']), quat(ready_row))
near_ready = held((.32, -.43, -.46), (-.21, .97, -.12), V((0, 0, 1)), -30)
prep = held((.39, -.18, -.48), (.70, .70, -.15))
keys = [
    (0, ready),
    (.34, prep),
    (.62, prep),
    (.65, held((.38, -.19, -.50), (.55, .80, -.28))),
    (.682, held((.25, -.22, -.55), (-.40, .78, -.47))),
    # The edge passes through the opponent, with the tip already on the left.
    (.71, held((.08, -.26, -.57), (-.87, .18, -.45))),
    (.755, held((-.14, -.30, -.58), (-.98, .02, -.21))),
    (.80, held((-.23, -.32, -.54), (-.97, -.08, -.23))),
    # Momentum continues to the left, then the hands withdraw below the cut.
    (.855, held((-.25, -.33, -.51), (-.95, -.13, -.28))),
    (.95, held((-.23, -.37, -.53), (-.89, -.16, -.43))),
    (1.08, held((-.07, -.43, -.53), (-.78, .03, -.625), PLANE_NORMAL, 0)),
    (1.22, held((.20, -.44, -.47), (-.44, .59, -.676), PLANE_NORMAL, -20)),
    (1.30, near_ready),
    (1.42, ready),
]

bpy.ops.object.select_all(action='SELECT')
bpy.ops.object.delete(use_global=False)
bpy.context.scene.render.fps = 120
controls = {}
for name in ('sword', 'shoulder', 'elbow', 'wrist'):
    obj = bpy.data.objects.new('right_diagonal_' + name, None)
    bpy.context.collection.objects.link(obj)
    obj.rotation_mode = 'QUATERNION'
    controls[name] = obj

original_other_clips = {name: data for name, data in manifest['clips'].items() if name != 'right_diagonal'}
for i, row in enumerate(clip['tracks']['sword']):
    time = row['time_seconds']
    p, q = sample(keys, time)
    # The last 120ms is a single shortest arc into the exact existing idle.
    if time >= 1.30:
        u = min(1, max(0, (time - 1.30) / .12))
        q = near_ready[1].slerp(ready[1], u*u*(3 - 2*u))
    row['position'] = list(p)
    row['rotation_xyzw'] = [q.x, q.y, q.z, q.w]
    joints = arm(p, q)
    joints['time_seconds'] = time
    clip['right_arm'][i] = joints
    controls['sword'].location = p
    controls['sword'].rotation_quaternion = q
    controls['sword'].keyframe_insert('location', frame=time*120 + 1)
    controls['sword'].keyframe_insert('rotation_quaternion', frame=time*120 + 1)
    for name in ('shoulder', 'elbow', 'wrist'):
        controls[name].location = joints[name]
        controls[name].keyframe_insert('location', frame=time*120 + 1)

manifest['basic_cut_refinement'] = {
    'date': '2026-09-13', 'execution_os': platform.system(),
    'blender_version': bpy.app.version_string, 'source_preserved': True,
    'source_sha256': hashlib.sha256(SOURCE.read_bytes()).hexdigest(),
    'script_sha256': hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
    'changed': 'right_diagonal sword and dependent right_arm only; edge-led diagonal cut, continuous left follow-through and low recovery',
    'preserved': 'left_reverse and all other clips, original models, shield track, attack timing, duration, sampler',
}
assert all(manifest['clips'][name] == data for name, data in original_other_clips.items())
bpy.context.scene.frame_end = 172
bpy.ops.wm.save_as_mainfile(filepath=str(OUT / 'RightToLeft_Cut_Controls.blend'))
(OUT / 'motion_manifest.json').write_text(json.dumps(manifest, separators=(',', ':')))
(OUT / 'authored_keys.json').write_text(json.dumps([{'time_seconds': t, 'position': list(p), 'rotation_xyzw': [q.x, q.y, q.z, q.w]} for t, (p, q) in keys], indent=2))
print('BASIC CUT AUTHOR PASS: right_diagonal only; source and reverse preserved')
