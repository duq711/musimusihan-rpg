extends SceneTree
const R := preload("res://scripts/reference_sword_motion.gd")
const C := preload("res://scripts/sword_shield_choreography.gd")
var failures: Array[String] = []
func _init() -> void:
	for clip in ["walk", "run"]:
		var first := R.sample(clip, 0)
		var duration := float(R.clip_metadata(clip).duration_seconds)
		var low := 100.0
		var high := -100.0
		for i in range(121):
			var pose := R.sample(clip, duration * i / 120.0)
			low = minf(low, pose.origin.y)
			high = maxf(high, pose.origin.y)
			if pose.basis.y.dot(Vector3.UP) < .97: failures.append("Locomotion sword loses upright silhouette: " + clip)
		if high - low < .015 or high - low > .08: failures.append("Reference stride bob must be restrained and visible: " + clip)
		if not R.sample(clip, duration).is_equal_approx(first): failures.append("Stride loop seam: " + clip)
	var takeoff := R.sample("takeoff", .12).origin.y
	var air := R.sample("air", .15).origin.y
	var landing := R.sample("land", .07).origin.y
	if not (takeoff < air - .12 and landing < air - .10): failures.append("Jump must dip, rebound, then compress on landing")
	for clip in R.ATTACK_CLIPS:
		var dt := .00001
		var a := C.sword("active", .145-dt, 0, clip)
		var b := C.sword("active", .145, 0, clip)
		var c := C.sword("active", .145+dt, 0, clip)
		var lin := ((b.origin-a.origin)-(c.origin-b.origin)).length()/dt
		var aa := angular(a.basis,b.basis)/dt
		var ab := angular(b.basis,c.basis)/dt
		print(clip," contact linear difference=",lin," angular difference=",aa.distance_to(ab)," speeds=",aa," / ",ab)
		if lin > .04 or aa.distance_to(ab) > .08: failures.append("Contact velocity mismatch: "+clip)
	for f in failures: push_error(f)
	print("REFERENCE MOTION SHAPE ", "PASS" if failures.is_empty() else "FAIL")
	quit(0 if failures.is_empty() else 1)
func angular(a: Basis,b: Basis)->Vector3:
	var q := a.get_rotation_quaternion().inverse()*b.get_rotation_quaternion()
	if q.w < 0: q = -q
	var v := Vector3(q.x,q.y,q.z)
	return v.normalized()*2.0*atan2(v.length(),q.w) if v.length()>.00000001 else Vector3.ZERO
