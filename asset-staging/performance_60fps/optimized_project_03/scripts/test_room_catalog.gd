extends RefCounted
class_name TestRoomCatalog

const CATEGORIES: Array[String] = ["기본", "마법", "생존", "물품", "장면"]

# New gameplay systems must add an executable entry here in the same change.
# Items, spells and conditions are generated from the authoritative catalogs.
static func entries() -> Array[Dictionary]:
	var result: Array[Dictionary] = [
		_entry("movement", "기본", "이동 · 달리기 · 점프", "동쪽 장애물 코스 · WASD / Shift / Space", "movement"),
		_entry("performance", "기본", "성능 측정 켜기 / 끄기", "실제 FPS · 프레임 시간 · 창 크기별 3D 해상도 조절 · 장면을 옮겨 비교", "performance"),
		_entry("melee", "기본", "근접 · 차지 · 검격 방어", "무장 검지기와 대련 · LMB를 길게 눌러 차지", "armed"),
		_entry("shield", "기본", "방패 · 저스트 가드", "RMB 방어 · 공격 직전 가드 / 기력 소모 확인", "armed"),
		_entry("flail", "기본", "사슬철퇴 · 회전 투척", "좌측 2m 근접 / 우측 8m 투척 · LMB 타격 / RMB 회전 후 놓기", "flail"),
		_entry("archery", "기본", "활 · 화살 · 원거리 사격", "사냥활 + 화살 30개 · LMB 당기고 놓아 발사 / RMB 취소", "archery"),
		_entry("archery_accuracy", "기본", "활 반동 · 당기기별 정확도", "8m 과녁 · 0.1초 이하 낙하 / 길게 당겨 사격 · 조준선 확장 → 축소", "archery_accuracy"),
		_entry("archery_power", "기본", "활 피해 · 기력 유지", "0.1초 이하 낙하 · 피해 18 → 46 · 기력 초당 22 · 고갈 시 현재 힘으로 1발", "archery_power"),
		_entry("skeleton", "기본", "해부학적 골격 · 적 AI", "무장 없는 성소지기 · 피격 / 경직 / 골절", "skeleton"),
		_entry("torch", "기본", "횃불 · 조명", "F로 점화 / 소등 · 기존 횃불 조명 사용", "torch"),
		_entry("wall_equipment", "기본", "벽 접근 · 무기와 방패 표시", "북쪽 벽 앞으로 이동 · W 접근 / S 후퇴 · I 장비 교체 · F 횃불", "wall_equipment"),
		_entry("inventory", "기본", "인벤토리 · 장비 교체", "I로 가방 · 장착 / 해제 / 소비품 사용", "inventory"),
		_entry("dark_fantasy_gallery", "기본", "어둠의 오브젝트 도감 · 6방향", "실제 게임 오브젝트 · 정면·후면·좌·우·위·아래 비교 · F2 복귀", "dark_fantasy_gallery"),
		_entry("player_appearance", "기본", "플레이어 외형 · 3D 캐릭터", "실제 인벤토리 3D 초상 · 회전하여 두건·누비옷·가죽 장비 확인 · F2 재시험", "player_appearance"),
		_entry("player_arm_motion", "기본", "1인칭 팔 · 전신 외형 · 동작", "현재 장비 유지 · 정면 표적 LMB / RMB 가드 · 왼쪽 상자 E · I 외형 비교", "player_arm_motion"),
		_entry("chest", "기본", "상자 조사 · 맨손 열기 · 수색", "현재 무기 유지 · E로 맨손 열기 / 재선택 시 닫힌 상자 재준비", "chest"),
		_entry("traps", "기본", "함정 조사 · 타이밍 해제", "동쪽 룬 함정 2종 · E로 조사 후 바늘 정지", "traps"),
		_entry("ai", "기본", "적 AI 켜기 / 끄기", "기본은 정지 표적 · 대련 시작 시 AI 활성화", "ai"),
		_entry("respawn", "기본", "적 · 함정 · 상자 재생성", "소모된 시험 대상을 처음 상태로 되돌리기", "respawn"),
		_entry("extraction", "기본", "귀환문 · 생환 결과", "감시자 처치 조건을 해제하고 귀환문 앞으로 이동", "extraction"),
		_entry("death", "기본", "사망 · 결과 화면", "시험 캐릭터 사망 · R로 테스트룸 재시작", "death"),
		_entry("learn_books", "마법", "마법서 학습 시험", "습득 기록 초기화 + 모든 마법서 지급 · I에서 학습", "learn_books"),
		_entry("survival_controls", "생존", "상태 수치 직접 조절", "체력·기력·포만감·수분·스트레스 · 슬라이더 / 숫자 입력 · 현재 시험에 즉시 반영", "survival_controls"),
		_entry("camping", "생존", "야영 · 휴식과 응급처치", "안전 지대 · C 야영 / 휴식·식사·처치 · 야영 도구와 보급 각 2개", "camping"),
		_entry("cooking", "생존", "야영 · 요리하고 먹기", "C 야영 → 요리 · 실제 재료 보급 / 완성 즉시 식사 · F2 재시험", "cooking"),
		_entry("stress_meter", "생존", "스트레스 · 누적과 회복", "스트레스 30 · 허기·갈증·출혈 / F 소등 · C 야영으로 회복", "stress", "30"),
		_entry("stress_audio", "생존", "스트레스 · 환청", "스트레스 65 · 잠시 기다려 속삭임·발소리 확인 · C 야영", "stress", "65"),
		_entry("stress_vision", "생존", "스트레스 · 환영과 환청", "스트레스 90 · 비전투 실루엣과 소리 · F2 정리 / C 야영", "stress", "90"),
		_entry("needs", "생존", "배고픔 · 갈증", "포만감 / 수분 10 · 식량과 물 지급", "needs"),
		_entry("wounded", "생존", "부상 · 회복약 · 붕대", "체력 25 + 출혈 · 회복약과 붕대 지급", "wounded"),
		_entry("time", "생존", "생존 시간 10분 진행", "상태이상 지속 시간과 보급 소모를 즉시 확인", "time"),
		_entry("cleanse", "생존", "상태이상 해제 · 보급 회복", "포만감 / 수분 100 · 모든 상태이상 해제", "cleanse"),
		_entry("hideout", "장면", "3D 은신처 · 생활 기능", "침상 / 보관함 / 화로 / 식사 / 세면 / 원정 지도", "scene", "res://hideout.tscn"),
		_entry("merchant", "장면", "중개인 · 거래 · 대화", "시험용 9,999 크라운 · 구매 / 판매 / 재고 확인", "scene", "res://merchant.tscn"),
		_entry("dungeon", "장면", "검은 성물실 · 전체 원정", "실제 던전과 귀환 흐름 · F2로 테스트룸 복귀", "scene", "res://main.tscn"),
		_entry("cave_dungeon", "장면", "검은 물길 동굴 · 131m × 139m", "지도 기반 18개 공동 · 중앙 채석장 · 침수 갱도와 거수 유골 · F2 복귀 후 재입장", "scene", "res://cave_dungeon.tscn"),
		_entry("cave_zone:entrance", "장면", "폐광 · 입구 소품과 지지대", "흙·암벽 재질과 벽등·횃불빛 비교 · 가까운 등불 그림자·자갈 접지와 성능 표시 확인 · F2 복귀", "cave_zone", "entrance"),
		_entry("cave_zone:grand_quarry", "장면", "폐광 · 거대 중앙 채석장", "중앙 암석섬 · 지질과 채굴 흔적 · 실제 공동으로 직접 입장", "cave_zone", "grand_quarry"),
		_entry("cave_zone:bone_cavern", "장면", "폐광 · 거수의 무덤", "괴물의 두개골·척추·갈비뼈와 암굴 · F2 복귀", "cave_zone", "bone_cavern"),
		_entry("cave_zone:upper_pool", "장면", "폐광 · 서쪽 침수 갱도", "상부·하부 물웅덩이와 연결 다리 · 실제 탐색과 상자", "cave_zone", "upper_pool"),
		_entry("cave_zone:west_pool", "장면", "폐광 · 물가 걷기와 파동", "젖은 암벽·흙·차가운 수면과 따뜻한 벽등 · 오른쪽 물로 걸어가 파동 확인 · F 횃불 비교", "cave_zone", "west_pool"),
		_entry("cave_zone:pillar_shrine", "장면", "폐광 · 기둥 성소", "기둥·옛 성소·북동쪽 귀환문 · 실제 감시자와 전리품", "cave_zone", "pillar_shrine"),
		_entry("cave_zone:hoistroom", "장면", "폐광 · 승강기실", "목재 승강기·자재·저수지 · 붕괴한 채굴 시설", "cave_zone", "hoistroom"),
		_entry("cave_zone:longlake", "장면", "폐광 · 긴 지하호수", "남동쪽 긴 수면과 작은 암석섬 · 굽은 호숫가 탐색", "cave_zone", "longlake"),
		_entry("cave_zone:workshops", "장면", "폐광 · 연속 작업실", "남쪽 작업대와 보관 시설 · 실제 연결 갱도와 함정", "cave_zone", "workshops"),
	]
	for spell_id in SpellCatalog.ordered_spell_ids():
		result.append(_entry("spell:" + spell_id, "마법", SpellCatalog.get_spell_name(spell_id), "지팡이 장착 + 주문 선택 · LMB로 직접 시전", "spell", spell_id))
	for condition_id in ExpeditionSession.CONDITION_DRAIN_BONUSES:
		result.append(_entry("condition:" + condition_id, "생존", ExpeditionSession.get_condition_display_name(condition_id), "상태이상 적용 · 소모 배율과 HUD 확인", "condition", condition_id))
	for item_id in ExpeditionInventory.ITEM_DEFINITIONS:
		var definition := ExpeditionInventory.get_item_definition(item_id)
		var note := str(definition.get("summary", ""))
		if item_id in ["holy_oil_flask", "lamp_oil", "grave_key"]:
			note += " · 현재 사용 효과 미구현"
		elif item_id in ["wanderer_hood", "patched_mail"]:
			note += " · 현재 장비 UI 확인용"
		result.append(_entry("item:" + item_id, "물품", ExpeditionInventory.get_item_name(item_id), note + " · 1개 지급", "item", item_id))
	return result


static func _entry(id: String, category: String, title: String, detail: String, action: String, payload := "") -> Dictionary:
	return {"id": id, "category": category, "title": title, "detail": detail, "action": action, "payload": payload}
