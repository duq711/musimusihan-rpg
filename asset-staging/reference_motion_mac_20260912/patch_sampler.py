from pathlib import Path
p=Path('godot-game/scripts/reference_sword_motion.gd');s=p.read_text();a=s.index('\tvar rotation: Quaternion = before.rotation\n');b=s.index('\n\treturn Transform3D(Basis(rotation), position)',a)
s=s[:a]+'''	# Spherical Bezier tangents share the same angular velocity at each knot.
	# Godot's squad time interpolation visibly kinks at inserted, uneven hit keys.
	var qa: Quaternion = before.rotation
	var qb: Quaternion = after.rotation
	var va := _rotation_velocity(pre.rotation, qa, qb, -pre_time, interval)
	var vb := _rotation_velocity(qa, qb, post.rotation, interval, post_time - interval)
	var ca := qa * _rotation_exp(va * interval / 3.0)
	var cb := qb * _rotation_exp(-vb * interval / 3.0)
	var ab := qa.slerp(ca, amount)
	var bc := ca.slerp(cb, amount)
	var cd := cb.slerp(qb, amount)
	var rotation := ab.slerp(bc, amount).slerp(bc.slerp(cd, amount), amount).normalized()'''+s[b:]
a=s.index('\n\nstatic func sample_right_arm')
s=s[:a]+'''

static func _rotation_log(q: Quaternion) -> Vector3:
	if q.w < 0.0: q = -q
	var v := Vector3(q.x, q.y, q.z)
	return v * (2.0 * atan2(v.length(), q.w) / v.length()) if v.length() > 0.00000001 else Vector3.ZERO

static func _rotation_exp(v: Vector3) -> Quaternion:
	return Quaternion(v.normalized(), v.length()) if v.length() > 0.00000001 else Quaternion.IDENTITY

static func _rotation_velocity(a: Quaternion, b: Quaternion, c: Quaternion, before: float, after: float) -> Vector3:
	if minf(before, after) <= 0.0000001: return Vector3.ZERO
	return (-_rotation_log(b.inverse() * a) / before * after + _rotation_log(b.inverse() * c) / after * before) / (before + after)
'''+s[a:];p.write_text(s)
