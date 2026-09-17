# 원래 장갑 손의 비례 조정

사용자 정정에 따라 기존 realism04 장갑 손의 비율만 두 번째 사진에 맞춰 조정한다. 장갑·기존 피부색·주름·손톱·봉제선·소매를 유지한다. 이전 맨손 모델은 담당자의 요청 해석 오류로 만들어진 미채택 이력이다.

현재 제작 원본은 `asset-staging/player_hands_proportions_20260911/mac_output/iteration_01/`의 `bilateral_hands_proportions.blend`다. 좌우 `*_hand_proportions.glb`를 이 폴더의 기존 `left_hand_detailed.glb`, `right_hand_detailed.glb` 경로에 연결한다.

전체 손 정점14,988개와5개 손톱,16본 이름·계층,15개 관절 교정을 보존한다. 비례 변환은 모든 키·봉제선·손톱과 해당 손가락 본에도 함께 적용한다. 기존 가중치·UV·면 재질 배치와 Skin/Glove/Sleeve/Nail/Trim의 PBR 표면 내용을 유지한다. 원래4096² basecolor/normal/roughness3장을 사용하며 새로 도색하거나 베이크하지 않는다.

`greybox_arm_visual.gd`와 `DungeonPlayer.set_hands_detailed_enabled(true)`의 기존 `detailed` 프로파일을 사용한다. 손목 기준·장비 접촉점과 팔 쪽 고정 구간을 유지하며 기존 Cuff메타데이터(version1, start.014, end.075)를 사용한다. 손목 코드는 바꾸지 않는다.

테스트룸 → 기본 → **캐릭터 그래픽 · 장갑 손 비례 조정**에서 빈손·활·상자 동작을, **캐릭터 그래픽 · 손가락 마디별 관절**에서15개 마디 슬라이더를 확인한다. 게임 초기 외형 선택과 원정 격리·복구 방식은 기존대로다.

제작 기록과 실제 검증 상태는 `asset-staging/player_hands_proportions_20260911/README.md`, `validation_summary.json`을 따른다. 이전 원본·제작·납품은 별도로 보존한다.
