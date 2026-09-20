# 야영 배치·텐트 요리 검증 / Camp placement and tent cooking validation

이번 변경은 가방의 야영 도구에서 배치를 시작하고 실제 물리 판정에 따라 빨강/초록을 표시합니다. LMB 확정 때만 도구 하나를 소비하고 F/Esc로 미확정 배치를 취소합니다. 텐트 E 상호작용은 모닥불 앞의 착석·기존 세 요리로 이어지며 일어서도 설치물은 유지합니다.

This change starts placement from the inventory kit, displays real physical validity in red/green, spends one kit only on LMB confirmation and cancels unconfirmed placement with F/Esc. E on the tent opens seated cooking using the three existing recipes; standing up retains the camp.

## 자동 검사 / Automated checks

아래 14개 고유 검사는 최종 관련 실행에서 통과했습니다. / These fourteen distinct suites passed their final relevant runs:

- `camp_placement`, `camp_placement_room`, `camp_placement_preview`
- `camp_system`, `camp_flow`, `camp_hud`
- `cooking_system`, `cooking_hud`, `stress_system`
- `test_room`, `test_room_session`
- `inventory_model`, `item_details`, `item_detail_input`

실제 가방 버튼·상호작용 Area·배치 확정·자원 거래·취소·완료 보상·원정 복원을 확인합니다. 설치 비교 항목 전환 때 장애물 잔존 문제를 수정하고, 위험 접근으로 일어난 뒤 설치물이 남는 정책에 맞춰 회귀 검사를 갱신했습니다. 출혈은 야영 중에도 실제 피해와 스트레스를 발생시키므로 기존 스트레스 검사의 잘못된 무피해 기대값을 수정하고 치료 완료·중복 회복 방지 검사는 유지했습니다. `test_room` 종료의 ObjectDB 인스턴스 1개 경고는 남아 있으며 검사 실패는 없습니다.

Checks exercise the real inventory button, interaction Area, placement commit, resource transactions, cancellation, completion rewards and expedition restoration. Trial switches now remove placement obstacles. Tests distinguish persistent standing-up from full camp cleanup. Bleeding continues to cause real damage and stress during rest; the old zero-damage stress expectation was corrected while retaining treatment and reward checks. `test_room` still emits a one-instance ObjectDB exit warning, without an assertion failure.

설치 안내의 늦은 컨테이너 높이 변경을 반영하고 요리 진행률의 기본 0.01 반올림을 제거한 뒤, 공유 프리뷰 검사와 두 UI 회귀 검사도 통과했습니다. [최종 통과 로그](checks.txt)를 보존합니다.

After accounting for deferred prompt height and removing default 0.01 progress rounding, the shared preview fixture and both UI regressions passed. Final passing logs are retained alongside this report.

## 실제 화면 / Actual rendered output

숨김 `embedded` / Vulkan 렌더러의 5장 모두 통과하고 직접 검토했습니다. 1280×720 초록/빨강 미리보기·설치 텐트·진행 중 요리, 960×540 조리법 메뉴에서 안내·진행률·일어서기 버튼과 모닥불 시야를 확인했습니다. 원정·가방·커서·샌드박스와 촬영 전후 소스 해시는 보존됐습니다. 기존 디버그 경고는 GPU 로그에 남기고 스크립트 오류나 캡처 실패는 없습니다.

All five hidden embedded/Vulkan captures passed and were visually reviewed. The 1280×720 placement/deployment/cooking and 960×540 recipe views retain readable controls, accurate progress, accessible exit buttons and the fire in view. Expedition, bag, cursor, sandbox and source hashes were preserved. Existing debug warnings remain in the GPU log; there were no script or capture errors.

- [설치 가능 / Valid](../../visual_qa/camp_placement/final_20260920_01/01_valid_ground.png)
- [설치 불가 / Blocked](../../visual_qa/camp_placement/final_20260920_01/02_blocked_wall.png)
- [설치된 텐트 / Deployed](../../visual_qa/camp_placement/final_20260920_01/03_deployed_tent.png)
- [실제 요리 / Cooking](../../visual_qa/camp_placement/final_20260920_01/04_seated_cooking.png)
- [작은 화면 / Small layout](../../visual_qa/camp_placement/final_20260920_01/05_seated_recipes_small.png)
- [상태·소스 해시 / Manifest](../../visual_qa/camp_placement/final_20260920_01/capture_manifest.json), [GPU log](gpu.log)

## 범위 / Scope

실제 UI 콜백과 물리 조준 경로 검증이며 OS 마우스 캡처·하드웨어 키 입력·수동 플레이를 검증한 것은 아닙니다. 기존 전투·에셋 관련 진행 중인 변경은 이 작업의 커밋에서 제외합니다.

This verifies production UI callbacks and physical targeting, not native pointer capture, hardware key input or manual play. Concurrent combat/asset work is excluded from this task's commit.
