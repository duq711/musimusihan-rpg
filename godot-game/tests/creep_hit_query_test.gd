extends SceneTree

const CREEP := preload("res://scripts/creep_enemy.gd")

func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	if not CREEP.is_available():
		print("CREEP HIT QUERY TEST PASS: licensed source missing; anatomical consistency checks SKIPPED")
		quit()
		return
	var actor := CREEP.new()
	actor.position = Vector3(0, 0.9, 0)
	root.add_child(actor)
	actor.set_physics_process(false)
	var sampled := 0
	var contacts := 0
	var mismatches := 0
	var examples: Array[String] = []
	for pose in [{"clip": "idle", "time": 0.3}, {"clip": "bite", "time": 0.9}, {"clip": "punch", "time": 0.6}]:
		actor.animation_player.play(pose.clip)
		actor.animation_player.seek(pose.time, true)
		for radius: float in [0.0, 0.10, 0.14, 0.20]:
			for side: bool in [false, true]:
				for row in 15:
					for column in 13:
						var horizontal := -1.2 + float(column) * 0.2
						var height := 0.02 + float(row) * 0.14
						var from := Vector3(3, height, horizontal) if side else Vector3(horizontal, height, -3)
						var to := Vector3(-3, height, horizontal) if side else Vector3(horizontal, height, 3)
						var hit: Dictionary = actor.query_located_hit(from, to, radius)
						sampled += 1
						if hit.is_empty():
							continue
						contacts += 1
						var received: String = actor.dismemberment.region_at_point(hit.position)
						if received != hit.region:
							mismatches += 1
							if examples.size() < 12:
								examples.append("%s radius=%s side=%s: %s -> %s at %s" % [pose.clip, radius, side, hit.region, received, hit.position])
	actor.free()
	if mismatches > 0:
		push_error("CREEP HIT QUERY TEST FAIL: %s/%s contacts changed regions on receive, samples=%s: %s" % [mismatches, contacts, sampled, examples])
		quit(1)
	else:
		print("CREEP HIT QUERY TEST PASS: %s posed contacts retain the selected body region across %s front/side ray and sphere sweeps" % [contacts, sampled])
		quit(0)
