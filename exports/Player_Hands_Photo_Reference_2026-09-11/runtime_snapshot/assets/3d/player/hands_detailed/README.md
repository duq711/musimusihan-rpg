# 플레이어 사진 참고 맨손 모델

사용자가 이전 피부색 제작본의 현실감을 지적하고 손바닥·손등 사진을 제공하여, 2026-09-11 사진 기준으로 양손을 다시 제작했다. 현재 상세 손의 제작 위치는 `asset-staging/player_hands_reference_20260911/mac_output/final_04/`다. 좌우 게임 파일은 각각 `left_hand_reference.glb`, `right_hand_reference.glb`를 `left_hand_detailed.glb`, `right_hand_detailed.glb`라는 기존 경로로 연결한다. 편집 원본은 `bilateral_hands_reference.blend`다.

손가락은 마디 사이에서 가늘어지는 단면과 부드러운 손끝으로 바꾸고, 엄지 뿌리·손가락 사이·손바닥 살집과 중앙 오목함·손등 힘줄·손목 연결부를 조정했다. 이전 반장갑의 색과 덧붙인 봉제선은 없애고, 실제 연속 피부 12,036개 정점을 유지했다. 손목 끝을 당기던 엄지 웨이트는 Godot z10–18mm에서 부드럽게 손목 본으로 넘기고,18mm 아래쪽을 손목 본에 고정했다. 그 밖의 원래 웨이트는 유지했다. 손톱 5개는 짧고 얇은 곡면으로 다시 만들어 실제 손가락 표면에 맞췄다. 전완과 상완의 기존 복식 및 손목 연결부의 팔 쪽 고정 구간은 유지한다.

밝은 베이지색 피부에 옅은 혈색을 넣고, 원본 사진의 중앙 손바닥·손등과 손가락별 색 변화를 기존 피부색에 최대65% 혼합한다. 사진은 원본 그대로 보존하며 흰 배경이 유입되지 않도록 투영 범위를 제한한다. 손금과 마디 주름, 피부 미세결은 노멀맵에도 굽는다. 양손 공용4096×4096 base color·normal·roughness atlas3장을 `ReferenceUV`로 사용한다. 색은 sRGB, 노멀과 거칠기는 선형이며 노멀은 OpenGL 접선 공간이다. 텍스처는 Blender에 pack하고 각 GLB에도 embed한다.

## 관절과 게임 연결

각 손의16본·손목 기준·본의 기준 행렬과 `Joint_<digit>_<joint>` 교정 형상15개를 유지한다. `digit`은 thumb/index/middle/ring/little, `joint`는 뿌리부터0/1/2다. 교정 형상도 중립 피부와 같은 형태 변환을 거쳐 새로운 단면을 따른다. 중립 교정값은0이며, 실제 본의 굽힘에 따라 기존 공용 어댑터가0~1로 구동한다. 손톱은 각 말단 본에 묶인다.

`greybox_arm_visual.gd`와 `DungeonPlayer.set_hands_detailed_enabled(true)`로 기존 `detailed` 프로파일에 연결된다. `original / greybox / detailed`는 서로 배타적이며, 게임 초기값은 기존 외형이다. 기본 검·방패 전용 손과 전신 캐릭터를 교체하지 않는다.

테스트룸 → 기본 → **캐릭터 그래픽 · 사진 참고 맨손**에서 빈손·실제 활 당김과 놓기·상자 열기를 시험한다. **캐릭터 그래픽 · 손가락 마디별 관절**에서는 실제 양손의15개 슬라이더와 펴기·주먹·순차 동작을 확인한다. 다른 시험·초기화·종료 시 기존 외형과 원정 상태를 복구한다.

손목의 `wrist_flex_version=1`, `wrist_flex_start_z=0.026`, `wrist_flex_end_z=0.075` 메타데이터는 `wrist_cuff_deformer.gd`가 읽는다. 피부 끝(z≈20.7mm)보다 아래인26mm부터 변형해 실제 손목 굽힘 때 접합부가 벌어지지 않도록 한다. 손 쪽은 피부 단면과 연결되고, 팔 쪽은 실제 전완의 변환을 따라가며 법선·접선도 함께 갱신한다.

## 검증과 이전 제작 기록

이번 판정 근거는 `asset-staging/player_hands_reference_20260911/validation_summary.json`과 해당 제작 폴더의 기록을 따른다. Blender의 형상·웨이트·손톱·15관절·PBR·GLB 왕복 검증, 관련7개 Godot 헤드리스 검사, 숨김 실제 GPU18컷과 직접 시각 검토를 구분해 기록한다. 수치 검증만으로 사진과의 외형 일치를 보장하지 않는다.

최종 final04는 독립 검사와7개 자동 검사를 통과했고 실제18장을 검토했다. 주먹에서 손목이 벌어지던 문제는 수정했다. 강한 손목 굽힘에서는 연결된 피부/Cuff 경계에 얕은 단차가 남으며, 제작 기록의 `visual_review.json`에 외형 한계로 명시한다.

기존 그레이박스·상세·관절·손목·피부색 원본과 이전 납품은 덮어쓰지 않는다. 이전 피부색 제작본과 그 검증은 `asset-staging/player_hands_realism_20260911/README.md`에, 관절과 손목 구현 이력은 각각 `player_finger_joints_20260910/README.md`, `player_wrist_refinement_20260910/README.md`에 보존한다. 새 납품은 `exports/Player_Hands_Photo_Reference_2026-09-11/`다.
