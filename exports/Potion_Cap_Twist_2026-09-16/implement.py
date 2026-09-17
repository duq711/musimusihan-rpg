from pathlib import Path
import json
p=Path('godot-game/scripts/potion_drink_visuals.gd');s=p.read_text();d=json.load(open('exports/Potion_Cap_Twist_2026-09-16/cap_solution.json'))
def vec(v):return 'Vector3('+', '.join(f'{x:.9f}' for x in v)+')'
B=d['hand_basis_in_cap']
constants='''# Bottle-top axis and fingertip contact were fitted against the supplied left-hand skin.
const CAP_HAND_CENTER := '''+vec(d['center_in_hand'])+'\nconst CAP_HAND_BASIS := Basis('+', '.join(vec([B[r][i] for r in range(3)]) for i in range(3))+')\nconst CAP_FINGER_POSE := {\n'+''.join('\t"'+n+'": '+vec(v)+',\n' for n,v in zip(['index','middle','ring','little','thumb'],d['amounts']))+'''}
var cap_turn := 0.0
var cap_hand_turn := 0.0
var cap_lift := 0.0
var cap_grip_strength := 0.0

'''
s=s.replace('func setup() -> void:',constants+'func setup() -> void:')
s=s.replace('const DRINK_DURATION := 5.8\nconst DRINK_END := 4.65','const DRINK_DURATION := 6.6\nconst DRINK_START := 3.0\nconst DRINK_END := 5.45\nconst POCKET_TIME := 6.15')
s=s.replace('elapsed < 5.35','elapsed < POCKET_TIME').replace('smoothstep(5.35, DRINK_DURATION, elapsed)','smoothstep(POCKET_TIME, DRINK_DURATION, elapsed)').replace('smoothstep(1.4, 2.0, elapsed)','smoothstep(2.5, DRINK_START, elapsed)').replace('smoothstep(DRINK_END, 5.15, elapsed)','smoothstep(DRINK_END, 5.95, elapsed)').replace('(elapsed - 2.0) / (DRINK_END - 2.0)','(elapsed - DRINK_START) / (DRINK_END - DRINK_START)').replace('smoothstep(4.95, 5.35, elapsed)','smoothstep(5.75, POCKET_TIME, elapsed)')
a=s.index('\tvar pull := smoothstep(0.90');b=s.index('\tliquid_up = ',a)
s=s[:a]+'\t_animate_cap(bottle_basis)\n'+s[b:]
s=s.replace('(\"마개 열기\" if elapsed < 1.5','(\"마개 돌려 열기\" if elapsed < 2.5')
method='''
func _animate_cap(bottle_basis: Basis) -> void:
	# Two short turns with a relaxed regrip. The stopper keeps its progress
	# while the fingers open and the wrist returns for the second turn.
	var first := smoothstep(0.98, 1.40, elapsed)
	var reset := smoothstep(1.44, 1.66, elapsed)
	var second := smoothstep(1.70, 2.14, elapsed)
	var release := smoothstep(1.39, 1.49, elapsed) * (1.0 - smoothstep(1.57, 1.70, elapsed))
	cap_turn = 0.85 * first + 0.95 * second
	cap_hand_turn = 0.85 * first * (1.0 - reset) + 0.95 * second
	cap_lift = 0.0015 * first + 0.002 * second + 0.062 * smoothstep(2.17, 2.42, elapsed)
	var withdraw := smoothstep(2.42, 2.80, elapsed)
	var retreat := Vector3(-0.50, -0.32, 0.02) * withdraw
	cork.position = Vector3(0, 4.795 + cap_lift / (MODEL_SCALE * BOTTLE_SIZE.y), 0)
	cork.rotation = Vector3(0, cap_turn, 0)
	cork.global_position += global_basis * retreat
	cork.visible = elapsed < 2.80
	left_arm.visible = elapsed < 2.80
	cap_grip_strength = smoothstep(0.76, 0.98, elapsed) * (1.0 - 0.80 * release)
	if not left_arm.visible: return
	# The thumb and index close first; the other fingers settle after them.
	var digit_index := 0
	for digit: String in CAP_FINGER_POSE:
		var lag := 0.0 if digit == "thumb" or digit == "index" else 0.025 * digit_index
		var close := smoothstep(0.76 + lag, 0.98 + lag, elapsed)
		var open_pose: Vector3 = CAP_FINGER_POSE[digit] - Vector3(0.25, 0.34, 0.25)
		var pose: Vector3 = open_pose.lerp(CAP_FINGER_POSE[digit], close)
		pose -= Vector3(0.14, 0.22, 0.16) * release
		left_arm.set_digit_flexion(digit, pose)
		digit_index += 1
	var approach := 1.0 - smoothstep(0.54, 0.98, elapsed)
	var hand_basis := bottle_basis * Basis(Vector3.UP, -1.65 + cap_hand_turn) * CAP_HAND_BASIS
	var contact := to_local(cork.global_position) + bottle_basis * Vector3(0, 0.016, 0)
	# Approach from the upper left; opening fingers gives the wrist room to reset.
	contact += Vector3(-0.22, 0.10, 0.04) * approach
	contact += bottle_basis * Vector3(-0.004, 0.004, 0.003) * release
	left_arm.transform = Transform3D(hand_basis, contact - hand_basis * CAP_HAND_CENTER)
	var elbow := left_arm.global_position + global_basis * (hand_basis.z * 0.23 + Vector3(-0.035, -0.025, 0.015))
	left_arm.fit_arm(to_global(Vector3(-0.60, -0.55, 0.02)), elbow)

'''
s=s.replace('func _rebuild_liquid() -> void:',method+'func _rebuild_liquid() -> void:');p.write_text(s)
# Allow the actual animation length to control its test and capture windows.
p=Path('godot-game/tests/potion_motion_test.gd');s=p.read_text().replace('for i in 345:', 'for i in ceili((player.potion_hands.DRINK_DURATION - 0.05) * 60.0):').replace('motion.elapsed > 2.2 and motion.elapsed < 4.5','motion.elapsed > motion.DRINK_START + 0.2 and motion.elapsed < motion.DRINK_END - 0.15').replace('motion.elapsed > 4.7','motion.elapsed > motion.DRINK_END + 0.05');p.write_text(s)
p=Path('godot-game/tests/potion_motion_preview.gd');s=p.read_text().replace('var count := 20 if sparse else 195','var count := 20 if sparse else ceili((player.potion_hands.DRINK_DURATION + 0.7) * 30.0)').replace('Splint capture','Potion capture');p.write_text(s)
p=Path('godot-game/tests/potion_test_room_test.gd');s=p.read_text().replace('room.player.advance_item_use(5.8)','room.player.advance_item_use(room.player.potion_hands.DRINK_DURATION)');p.write_text(s)
p=Path('godot-game/scripts/test_room_catalog.gd');s=p.read_text().replace('핏빛 회복약 마개 열기 → 네 번 꿀꺽 → 빈 병 · 5.8초','핏빛 회복약 마개 돌리기·다시 잡기 → 네 번 꿀꺽 → 빈 병 · 6.6초');p.write_text(s)
