extends RefCounted
class_name TestRoomCatalog

const CATEGORIES: Array[String] = ["기본", "마법", "생존", "물품", "장면"]
const ALCHEMY_CATALOG := preload("res://scripts/alchemy_catalog.gd")
const HIDEOUT_RUIN_VIEWS := preload("res://scripts/hideout_ruin_views.gd")

# New gameplay systems must add an executable entry here in the same change.
# Items, spells and conditions are generated from the authoritative catalogs.
static func entries() -> Array[Dictionary]:
	var result: Array[Dictionary] = [
		_entry("movement", "기본", "이동 · 달리기 · 점프", "동쪽 장애물 코스 · WASD / Shift / Space", "movement"),
		_entry("performance", "기본", "성능 측정 켜기 / 끄기", "실제 FPS · 프레임 시간 · 창 크기별 3D 해상도 조절 · 장면을 옮겨 비교", "performance"),
		_entry("melee", "기본", "근접 · 차지 · 검격 방어", "무장 검지기와 대련 · LMB를 길게 눌러 차지", "armed"),
		_entry("shield", "기본", "방패 · 저스트 가드", "검·방패와 실제 공격자 · RMB 정면 피해 100% 차단 · 공격 직전 가드로 적 스턴 · 기력 0이면 방패를 들 수 없음", "armed", "shield_guard"),
		_entry("flail", "기본", "사슬철퇴 · 회전 투척", "좌측 2m 근접 / 우측 8m 투척 · LMB 타격 / RMB 회전 후 놓기", "flail"),
		_entry("archery", "기본", "활 · 화살 · 원거리 사격", "사냥활 + 화살 30개 · LMB 당기고 놓아 발사 / RMB 취소", "archery"),
		_entry("archery_accuracy", "기본", "활 반동 · 당기기별 정확도", "8m 과녁 · 0.1초 이하 낙하 / 길게 당겨 사격 · 조준선 확장 → 축소", "archery_accuracy"),
		_entry("archery_power", "기본", "활 피해 · 기력 유지", "0.1초 이하 낙하 · 피해 18 → 46 · 기력 초당 22 · 고갈 시 현재 힘으로 1발", "archery_power"),
		_entry("orc", "기본", "오크 · 도끼 근접 전투", "제공 모델과 도끼 · 추적/세 공격/피격/사망 · LMB 공격 / RMB 방어 · F2 재선택으로 회복·재생성", "orc"),
		_entry("skeleton", "기본", "해부학적 골격 · 적 AI", "무장 없는 성소지기 · 피격 / 경직 / 골절", "skeleton"),
		_entry("torch", "기본", "횃불 · 조명", "Unity 불꽃 애니메이션 · 기름 먹인 천 전체 연소 · F 점화 / 소등", "torch"),
		_entry("wall_equipment", "기본", "벽 접근 · 무기와 방패 표시", "북쪽 벽 앞으로 이동 · W 접근 / S 후퇴 · I 장비 교체 · F 횃불", "wall_equipment"),
		_entry("inventory", "기본", "인벤토리 · 장비 교체", "I로 가방 · 장착 / 해제 / 소비품 사용", "inventory"),
		_entry("inventory_details", "기본", "아이템 상세 · 이름표 · 버리기", "실제 검·갑옷·붕대 상세 · 이름표 저장 / 장착 / 버리기 · 가방을 닫고 바닥 물품 E 회수 · F2 재시험", "inventory_details"),
		_entry("dark_fantasy_gallery", "기본", "어둠의 오브젝트 도감 · 6방향", "현재 검·방패 모델과 실제 게임 오브젝트 · 정면·후면·좌·우·위·아래 비교 · F2 복귀", "dark_fantasy_gallery"),
		_entry("beef_jerky_assets", "기본", "육포 외형 · 불규칙한 8종", "첨부 육포 재질 · 긴 조각·넓은 조각·말린 조각·쌓인 묶음 · 도감 목록과 6방향으로 확인 · F2 복귀", "dark_fantasy_gallery", "beef_jerky_pile"),
		_entry("player_appearance", "기본", "플레이어 외형 · 3D 캐릭터", "실제 인벤토리 3D 초상 · 회전하여 두건·누비옷·가죽 장비 확인 · F2 재시험", "player_appearance"),
		_entry("player_arm_motion", "기본", "1인칭 팔 · 전신 외형 · 동작", "새 FP arms 양팔·손 · 정면 표적 LMB / RMB 가드 · 1 양손 파지 · 왼쪽 상자 E · I 장비 교체", "player_arm_motion"),
		_entry("player_hands_greybox", "기본", "캐릭터 그래픽 · 양손 그레이박스", "검·방패 보관과 횃불 소등 · 실제 양손·소매 비교 · 왼쪽 상자 E · I에서 활 장착 후 당기기", "player_hands_greybox"),
		_entry("player_hands_detailed", "기본", "캐릭터 그래픽 · 제공 모델 양손", "새 FP arms 제공 모델 · 좌우 원본 스킨·손가락 뼈대 · 상자 E · I 활", "player_hands_detailed"),
		_entry("player_finger_joints", "기본", "캐릭터 그래픽 · 손가락 마디별 관절", "제공 손의 15마디 굽힘 · 손등/손바닥/손목 옆면 · 펴기는 원본 자세로 복원 · F2 복귀", "player_finger_joints"),
		_entry("motion_sword", "기본", "1인칭 모션 · 긴 손잡이 검 파지", "새 긴 손잡이·비스듬한 오른손 파지 · 실제 표적에 LMB 준비/타격/회수 · 길게 눌러 강공격 · F2 재시험", "first_person_motion", "sword"),
		_entry("motion_shield_stow", "기본", "주무장 1번 · 방패 수납", "1 · 양손 파지 / 2m 표적 LMB 짧게 · 방패 왼쪽 화면 밖으로 · 양방향 끝까지 베기 / 길게 · 차지 / F2 재시험", "reference_sword_motion", "shield_stow"),
		_entry("motion_sword_draw", "기본", "영상 참고 검·방패 꺼내기", "멈춤 없이 좌측 하단으로 손 뻗기·이동 중 손가락 감기 → 왼쪽 허리에서 발검 → 검·방패 들기 · F2 반복 · LMB/RMB 전환", "reference_sword_motion", "draw"),
		_entry("motion_sword_run", "기본", "영상 참고 검 모션 · 걷기와 달리기", "Mac 제작 9클립 · W 걷기 / Shift 달리기 / 놓아 멈추기 · 세운 검과 낮은 방패의 보폭·반동 비교 · F2 재시험", "reference_sword_motion", "run"),
		_entry("motion_sword_jump", "기본", "영상 참고 검 모션 · 점프와 착지", "실제 충돌 바닥 · Space 도약·공중·착지의 손목·팔꿈치 연결 비교 · W / Shift 이동 점프 · F2 재시험", "reference_sword_motion", "jump"),
		_entry("motion_sword_sequence", "기본", "영상 참고 검 모션 · 달리기→점프→베기", "정면 9m 실제 표적 · W+Shift 접근 / Space 점프 / 가까이서 LMB 베기 · 이동→공격→방어 팔 연결 비교 · F2 재준비", "reference_sword_motion", "sequence"),
		_entry("motion_shield", "기본", "1인칭 모션 · 검과 방패", "새 긴 손잡이 검 파지와 방패 · LMB 세 베기 순환 · RMB 올리기/충격 · 방어 후 반격", "first_person_motion", "shield"),
		_entry("motion_shield_cut_right", "기본", "검과 방패 · 우측 대각 베기", "검·방패와 2m 정지 표적 · LMB로 우측 준비→대각 베기→회수 반복 · F2 재시험", "first_person_motion", "shield_cut_right"),
		_entry("motion_shield_cut_left", "기본", "검과 방패 · 좌측 역베기", "검·방패와 2m 정지 표적 · LMB로 좌측 준비→역베기→회수 반복 · F2 재시험", "first_person_motion", "shield_cut_left"),
		_entry("motion_shield_cut_overhead", "기본", "검과 방패 · 상단 내려베기", "새 내리찍기 동작 · 검·방패와 2m 정지 표적 · LMB로 준비→타격→회수 반복 · F2 재시험", "first_person_motion", "shield_cut_overhead"),
		_entry("motion_shield_raise", "기본", "검과 방패 · 방패 올리기", "RMB 가까운 낮은 방패 가드 · 화면 아래 넓은 윗테두리와 중앙 시야 확보 · 검 내림/해제 복귀 · F2 재시험", "first_person_motion", "shield_raise"),
		_entry("motion_shield_impact", "기본", "검과 방패 · 막힘 충격", "RMB 정면 피해 100% 차단·막힘 충격 · 직전 가드로 적 스턴 · 기력 고갈 시 방패 내림 · F2 회복", "first_person_motion", "shield_impact"),
		_entry("motion_bow", "기본", "1인칭 모션 · 활 당기기와 놓기", "실제 사냥활과 화살 30개 · 반쯤/끝까지 당겨 놓기 · 양손과 시위 비교", "first_person_motion", "bow"),
		_entry("motion_flail", "기본", "1인칭 모션 · 철퇴 회전과 회수", "실제 근접·원거리 표적 · LMB 휘두르기 · RMB 회전/투척/회수", "first_person_motion", "flail"),
		_entry("motion_staff", "기본", "1인칭 모션 · 지팡이와 시전", "실제 화염탄 선택과 정면 표적 · LMB 주문 시전 · 손목과 지팡이 반동", "first_person_motion", "staff"),
		_entry("motion_torch", "기본", "1인칭 모션 · 횃불과 보행", "F 아래에서 꺼내기·수납 · 수납 후 왼손 대기 표시 없음 · 시야 밖 조명 / WASD 보행", "first_person_motion", "torch"),
		_entry("motion_chest", "기본", "상자 모션 · 손 동작 없이 열기", "실제 닫힌 상자 · E 조사/뚜껑 열기 · 손 동작 없음 · F2 정리 후 재시험", "first_person_motion", "chest"),
		_entry("chest", "기본", "상자 조사 · 열기 · 수색", "현재 무기 유지 · E로 열기 · 손 동작 없음 / 재선택 시 닫힌 상자 재준비", "chest"),
		_entry("loot_container:wooden_barrel_01", "기본", "루팅 모델 · 나무통", "제공된 실제 나무통 · E 조사·수색 / F2 재선택 시 닫힌 통 재준비 · 현재 가방 유지", "loot_container", "wooden_barrel_01"),
		_entry("loot_container:wooden_crate_01", "기본", "루팅 모델 · 나무 상자 1", "제공된 실제 나무 상자 · E 조사·수색 / F2 재선택 시 닫힌 상자 재준비 · 현재 가방 유지", "loot_container", "wooden_crate_01"),
		_entry("loot_container:wooden_crate_02", "기본", "루팅 모델 · 나무 상자 2", "제공된 실제 나무 상자 · E 조사·수색 / F2 재선택 시 닫힌 상자 재준비 · 현재 가방 유지", "loot_container", "wooden_crate_02"),
		_entry("loot_container:treasure_chest", "기본", "루팅 모델 · 보물 상자", "제공된 실제 보물 상자 · E 조사·수색 / F2 재선택 시 닫힌 상자 재준비 · 현재 가방 유지", "loot_container", "treasure_chest"),
		_entry("traps", "기본", "함정 조사 · 타이밍 해제", "동쪽 룬 함정 2종 · E로 조사 후 바늘 정지", "traps"),
		_entry("ai", "기본", "적 AI 켜기 / 끄기", "기본은 정지 표적 · 대련 시작 시 AI 활성화", "ai"),
		_entry("respawn", "기본", "적 · 함정 · 상자 재생성", "소모된 시험 대상을 처음 상태로 되돌리기", "respawn"),
		_entry("extraction", "기본", "귀환문 · 생환 결과", "감시자 처치 조건을 해제하고 귀환문 앞으로 이동", "extraction"),
		_entry("death", "기본", "사망 · 결과 화면", "시험 캐릭터 사망 · R로 테스트룸 재시작", "death"),
		_entry("learn_books", "마법", "마법서 학습 시험", "습득 기록 초기화 + 모든 마법서 지급 · I에서 학습", "learn_books"),
		_entry("survival_controls", "생존", "상태 수치 직접 조절", "전체 체력 440·기력·포만감·수분·스트레스 · 부위 선택/실제 피해 · 전체 체력 조절은 시험 초기화", "survival_controls"),
		_entry("bandage_forearm", "생존", "붕대 사용 · 왼팔 감기", "왼팔에 실제 붕대 1개 사용 · 무기 수납 → 팔 들기 → 세 번 감기 → 당겨 찢기 → 무기 복귀 · F2 재선택으로 재보급·재생", "bandage_forearm", ""),
		_entry("splint_forearm", "생존", "부목 사용 · 왼팔 고정", "팔을 가로로 들고 위에 판자 놓기 → 붕대 세 번 감기 → 끝 눌러 고정 · 7.2초 완료 후 골절 치료 · F 취소 / F2 반복", "splint_forearm", ""),
		_entry("potion_drink", "생존", "물약 마시기 · 액체 출렁임", "마개 돌리기·다시 잡기 → 병목을 시점 아래 입에 대고 네 번 꿀꺽 → 빈 병 · 6.6초 완료 후 회복 · F 취소 / F2 반복", "potion_drink", ""),
		_entry("jerky_eat", "생존", "육포 먹기 · 꺼내서 한입씩", "제공 육포를 꺼내 입으로 가져가 먹기 · 8초 완료 후 1개 소비·포만감 32 회복 · F 취소 / F2 재보급·반복", "jerky_eat", ""),
		_entry("body_health", "생존", "장비·건강 통합 · 7부위 치료", "왼쪽 부위 치료 · 오른쪽 실제 장비/주머니/파우치/배낭 · 우클릭 상세 · 1~0 빠른 사용 / F2 재보급", "body_health", "damage"),
		_entry("timed_item_use", "기본", "아이템 사용 시간 · F 취소", "4 회복약 / 5 붕대 / 6 식량 / 7 물 · 중앙 남은 초 · F 취소 · 완료 시 소비·효과 / F2 재보급", "timed_item_use"),
		_entry("dungeon_combat_hud", "기본", "던전 전투 UI · 소지품과 경고", "1 검 · 2 활 · 3 횃불 · 4 약 · 5 붕대 · 6 음식 · 7 물 · 낮은 생존/부상/저주 경고 · F2 재시험", "dungeon_combat_hud"),
		_entry("storage_equipment", "기본", "허리 파우치·배낭 교체", "기본 장비 + 교체용 파우치·배낭 · I 우클릭 상세 → 장착하기 · 소지품 유지 / F2 재보급", "storage_equipment"),
		_entry("body_surgery", "생존", "회복 불가 부위 · 수술 후 치료", "왼팔 0 · 일반 회복약 실패 → 수술키트로 1 복구 → 회복약 · 실제 치료품 보급 / F2 재시험", "body_health", "surgery"),
		_entry("body_restoration", "생존", "고위 회복마법 · 부위 복구", "오른다리 0 · 지팡이와 고위 회복마법 · I에서 부위 선택 후 닫고 LMB로 1 복구 → 회복약 / F2 재시험", "body_health", "restoration"),
		_entry("camping", "생존", "야영 · 휴식과 응급처치", "안전 지대 · C 야영 / 휴식·식사·처치 · 야영 도구와 보급 각 2개", "camping"),
		_entry("cooking", "생존", "야영 · 요리하고 먹기", "C 야영 → 요리 · 실제 재료 보급 / 완성 즉시 식사 · F2 재시험", "cooking"),
		_entry("stress_meter", "생존", "스트레스 · 누적과 회복", "스트레스 30 · 허기·갈증·출혈 / F 소등 · C 야영으로 회복", "stress", "30"),
		_entry("stress_audio", "생존", "스트레스 · 환청", "스트레스 65 · 잠시 기다려 속삭임·발소리 확인 · C 야영", "stress", "65"),
		_entry("stress_vision", "생존", "스트레스 · 환영과 환청", "스트레스 90 · 비전투 실루엣과 소리 · F2 정리 / C 야영", "stress", "90"),
		_entry("needs", "생존", "배고픔 · 갈증", "포만감 / 수분 10 · 식량과 물 지급", "needs"),
		_entry("wounded", "생존", "부상 · 회복약 · 붕대", "체력 25 + 출혈 · 회복약과 붕대 지급", "wounded"),
		_entry("time", "생존", "생존 시간 10분 진행", "상태이상 지속 시간과 보급 소모를 즉시 확인", "time"),
		_entry("cleanse", "생존", "상태이상 해제 · 보급 회복", "포만감 / 수분 100 · 모든 상태이상 해제", "cleanse"),
		_entry("hideout_cooking", "장면", "은신처 · 화롯불 조리와 식사", "중앙 화롯불의 실제 냄비·꼬치 · 전체 조리법 재료 보급 / 완성 즉시 식사 · F2 재시험", "hideout_cooking"),
		_entry("hideout", "장면", "3D 은신처 · 생활 기능", "무작위 루팅 없음 · 개인 보관함 유지 · 상시 안내 없는 화면 · 2배 크기 중앙 점 조준선 / E 생활 기능 · I 가방 · M 지도 · Esc 일시정지 / F2 복귀·재시험", "scene", "res://hideout.tscn"),
		_entry("smithing_forge", "장면", "대장간 · 화로부터 검 완성", "실제 은신처 작업대 · 철 투입 / 풀무 / 모루 망치질 / 담금질 · F2 재보급", "smithing", "forge"),
		_entry("smithing_grip", "장면", "대장간 · 손잡이 교체", "실제 검과 재료 보급 · 손잡이를 교체해 공격 기력 비용 비교 · F2 재시험", "smithing", "grip"),
		_entry("smithing_blade", "장면", "대장간 · 칼날 보강", "실제 검의 날에 보강재 추가 · 근접 피해 변화 · F2 재시험", "smithing", "blade"),
		_entry("smithing_rune", "장면", "대장간 · 구멍 파기와 룬 삽입", "검에 구멍을 파고 룬 돌조각 장착 · 실제 검 강화 · F2 재보급", "smithing", "rune"),
		_entry("alchemy_brewing", "장면", "연금술 · 불과 모래시계", "은신처의 실제 연금대 · 포도주 / 생약초 / 풀무 / 끓임과 식힘 / 병입 · F2 재보급", "alchemy", "ember_cordial"),
		_entry("alchemy_grinding", "장면", "연금술 · 약초 빻기와 투입 순서", "붉은 봉합약 처방 · 절구 3회 / 생약초와 가루 구별 / 순서와 끓임 시간 · F2 재시험", "alchemy", "red_mending"),
		_entry("alchemy_distillation", "장면", "연금술 · 증류와 냉각", "달쑥 지혈 정수 처방 · 증류기 / 증류 진행 / 완성병 · 실제 재료와 결과물 · F2 재보급", "alchemy", "moon_distillate"),
		_entry("alchemy_quality", "장면", "연금술 · 자유 실험과 품질 비교", "쇠꽃 봉합유 처방 · 용매·양·빻기·온도·순서·마무리를 바꾸고 제조 기록 비교 · F2 재보급", "alchemy", "iron_salve"),
		_entry("distilling_brandy", "장면", "증류소 · 화롯불 브랜디 판매", "실제 연금대에서 술 증류 → 중개인 판매 · 품질별 수익 / 유료 재료 상시 공급 · F2 재보급", "distilling", "hearth_brandy"),
		_entry("distilling_absinthe", "장면", "증류소 · 달쑥 압생트 판매", "고가의 달쑥 증류주 제조 → 실제 크라운 수익 · 제조·판매 반복 / F2 재시험", "distilling", "moon_absinthe"),
		_entry("merchant", "장면", "중개인 · 거래 · 대화", "시험용 9,999 크라운 · 구매 / 판매 / 재고 확인", "scene", "res://merchant.tscn"),
		_entry("dungeon", "장면", "검은 성물실 · 전체 원정", "실제 던전과 귀환 흐름 · F2로 테스트룸 복귀", "scene", "res://main.tscn"),
		_entry("loot_spawn:reliquary", "장면", "루팅 배치 · 성물실 재입장", "보관 공간의 고정 후보 중 일부만 등장 · 실제 원정 / F2 복귀 후 재입장하여 빈 자리와 배치 비교", "scene", "res://main.tscn"),
		_entry("loot_spawn:blackwater_cave", "장면", "루팅 배치 · 폐광 재입장", "작업·보관 공간의 고정 후보 중 일부만 등장 · 실제 원정 / F2 복귀 후 재입장하여 빈 자리와 배치 비교", "scene", "res://cave_dungeon.tscn"),
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
	for room_id in HIDEOUT_RUIN_VIEWS.ordered_ids():
		var shot: Dictionary = HIDEOUT_RUIN_VIEWS.get_shot(room_id)
		result.append(_entry("hideout_ruin:" + room_id, "장면", "폐허 은신처 · " + str(shot.title), "실제 방의 붕괴 흔적·이끼·곰팡이·낙수 확인 · WASD 탐색 / E 생활 기능 / F 횃불 / F2 복귀", "hideout_ruin", room_id))
	for recipe_id in ALCHEMY_CATALOG.ordered_recipe_ids():
		var recipe: Dictionary = ALCHEMY_CATALOG.recipe(recipe_id)
		var liquor := str(recipe.get("product_type", "medicine")) == "liquor"
		result.append(_entry("alchemy_recipe:" + recipe_id, "장면", ("증류주 제조법 · " if liquor else "연금술 처방 · ") + str(recipe.name), str(recipe.description) + " · 실제 연금대에서 직접 제조 · F2 재보급", "distilling" if liquor else "alchemy", recipe_id))
	for spell_id in SpellCatalog.ordered_spell_ids():
		result.append(_entry("spell:" + spell_id, "마법", SpellCatalog.get_spell_name(spell_id), "지팡이 장착 + 주문 선택 · LMB로 직접 시전", "spell", spell_id))
	for condition_id in ExpeditionSession.CONDITION_DRAIN_BONUSES:
		result.append(_entry("condition:" + condition_id, "생존", ExpeditionSession.get_condition_display_name(condition_id), "부위·전신 상태이상의 이동/전투/회복/지속 피해 · 대응 치료품 보급 · F2 재개 후 I 치료 / 재선택 재보급", "condition", condition_id))
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
