extends RefCounted
## A presentation timeline; delegates all bone posing to the production actor.
const CREEP := preload("res://scripts/creep_enemy.gd")
const FPS := 30
const SEGMENTS := [
	{"id": "idle", "title": "01  대기  /  IDLE", "duration": 4.84, "note": "게임 적용 속도 · 1×"},
	{"id": "walk", "title": "02  걷기  /  WALK", "duration": 4.84, "note": "걷기 모션 · 이동 없이 제자리에서 확인"},
	{"id": "bite", "title": "03  물기  /  BITE", "duration": 3.20, "note": "게임 적용 속도 · 공격 2회 반복"},
	{"id": "punch", "title": "04  양손 연타  /  TWO-HAND ATTACK", "duration": 3.60, "note": "게임 적용 속도 · 공격 3회 반복"},
	{"id": "hit", "title": "05  피격  /  HIT REACTION", "duration": 2.60, "note": "피격 2회 · 각 반응 뒤 잠시 정지"},
	{"id": "death", "title": "06  원본 사망 클립  /  SOURCE DEATH", "duration": 3.40, "note": "비교용 원본 · 실제 사망은 래그돌 사용"},
]

static func sample(actor, id: String, seconds: float) -> Dictionary:
	var state := DungeonEnemy.AIState.IDLE
	var local_time := seconds
	var attack := -1
	match id:
		"walk": state = DungeonEnemy.AIState.CHASE
		"bite", "punch":
			attack = 0 if id == "bite" else 1
			var windup: float = CREEP.WINDUPS[attack]
			var active: float = CREEP.ACTIVE_TIMES[attack]
			local_time = fmod(seconds, windup + active + CREEP.RECOVERIES[attack])
			if local_time < windup:
				state = DungeonEnemy.AIState.WINDUP
			elif local_time < windup + active:
				state = DungeonEnemy.AIState.ACTIVE
				local_time -= windup
			else:
				state = DungeonEnemy.AIState.RECOVERY
				local_time -= windup + active
		"hit":
			state = DungeonEnemy.AIState.STAGGER
			local_time = minf(fmod(seconds, 1.30), DungeonEnemy.STAGGER_SECONDS)
		"death": state = DungeonEnemy.AIState.DEAD
	if actor.ai_state != state:
		actor._set_state(state)
	if attack >= 0:
		actor.attack_index = attack
	actor.state_time = local_time
	actor._update_visual_pose(0.0)
	return {"clip": actor.animation_clip, "sample": actor.animation_sample, "state": actor.ai_state}
