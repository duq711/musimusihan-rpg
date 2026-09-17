# 플레이어 양손 디테일 모델

2026-09-10 현재 플레이어 양손 그레이박스의 후속 디테일 작업. 최초 상세 형상의 제작 원본 및 보고서는 `asset-staging/player_hands_detail_20260910/mac_output/iteration_03/`에 보존한다. 같은 날 **손가락 마디마다 관절 효과**를 추가한 제작본은 `asset-staging/player_finger_joints_20260910/mac_output/iteration_02/`에 보존한다. 현재 게임용 GLB는 후속 **손등–손목–팔 연결부 정리** 제작본인 `asset-staging/player_wrist_refinement_20260910/mac_output/iteration_02/`에서 가져왔다. 이전 상세·관절 원본과 납품본은 보존한다.

현재 좌우 각각 63,970삼각형, 9개 메시, 16개 손 본으로 구성된다. 원본 중립 팔의 크기·손목 좌표·본 기준 행렬을 유지한다. 손톱 5개는 각 손가락 말단 본에 묶이고, 손의 봉제선은 해부학 손 메시, 팔 디테일은 원래 팔 구간 메시에 합쳐져 기존 그립·팔 맞춤 동작을 따른다.

재질은 `Detailed_Skin`, `Detailed_Glove`, `Detailed_Sleeve`, `Detailed_Nail`, `Detailed_Trim`이다. 형태 검토용 중립 회색이며 컬러 텍스처와 노멀맵 베이크는 포함하지 않는다.

`greybox_arm_visual.gd`의 공용 스킨 어댑터와 `DungeonPlayer.set_hands_detailed_enabled(true)`로 연결된다. `original / greybox / detailed`는 서로 배타적이며 게임 초기값은 기존 외형이다. 테스트룸 → 기본 → **캐릭터 그래픽 · 양손 디테일 모델**에서 빈손, 실제 활 당김·놓기, 상자 열기를 시험한다. 다른 시험·초기화·종료 시 기존 외형으로 복구된다.

별도로 제작된 기본 검·방패 전용 손 모델과 전신 캐릭터는 이 파일로 교체하지 않는다. 기존 그레이박스 항목은 비교용으로 유지한다. 개별 GLB가 게임용이며, 납품의 `both_hands_detailed_preview.glb`는 좌우를 벌려 배치한 검토용이다.

자동 검증: `tests/run_headless_tests.sh player_hands_detailed player_hands_greybox`. 실제 화면은 창 없는 전용 `player_hands_detailed_preview.gd` 하네스로 확인한다.

## 마디별 관절과 피부 교정

손목 정리 이전 `left_hand_detailed.glb`와 `right_hand_detailed.glb`는 위 관절 제작본의 `left_hand_articulated.glb`, `right_hand_articulated.glb`에 대응한다. 편집 가능한 원본은 `bilateral_hands_articulated.blend`이며, 관절 납품 패키지 위치는 `exports/Player_Finger_Joints_2026-09-10/`이다. 별도 외형 프로파일을 추가하지 않고 기존 `detailed` 선택에서 사용한다.

각 손의 `ContinuousAnatomicalHand*`에 `Joint_<digit>_<joint>` 교정 형상 15개가 있다. `digit`은 `thumb / index / middle / ring / little`, `joint`는 뿌리부터 `0 / 1 / 2`이다. 중립값은 모두 0이며, 실제 본의 굽힘각을 해당 마디의 최대 각도로 나눈 값에 따라 0~1로 적용한다. 손가락의 최대 굽힘각은 90° / 110° / 80°, 엄지는 60° / 70° / 80°이다. 기존 활·상자·자연스러운 손 자세의 각도와 타이밍은 공용 어댑터를 통해 그대로 전달한다.

손톱 5개는 기존 말단 본에 단단하게 연결된 메시와 웨이트를 유지하며 교정 형상을 추가하지 않는다. 완전히 굽혔을 때 손톱 아래 피부가 같이 따라가도록 피부 웨이트만 왼손 1,134개·오른손 1,133개 정점에서 조정하고 4mm 구간으로 부드럽게 연결했다. 중립 정점 좌표·토폴로지·16개 본의 기준 자세·손목 기준·기존 팔 구간과 재질은 유지한다.

`테스트룸 → 기본 → 캐릭터 그래픽 · 손가락 마디별 관절`은 같은 실제 플레이어의 두 손을 가까이 올린다. 양손/왼손/오른손, 손등/손바닥/손목 옆면을 선택하고 15개 슬라이더로 각 마디를 따로 굽힌다. 펴기·주먹·마디 순차 버튼도 같은 본과 교정 형상을 구동한다. 세계를 일시정지한 동안만 임시 자세를 유지하며 F2·Esc·닫기·다른 시험·초기화·종료 시 정리한다. 기존 상세 손 시험에서는 활과 상자의 실제 동작에 교정 형상이 자연스럽게 연동된다.

Blender 독립 검증은 `iteration_02/verification_report.json`의 `passed`로 확인했다. 좌우 각각 57,346삼각형·9개 메시·16본과 교정 형상 15개를 확인했으며, `nail_attachment_verification.json`과 `nail_attachment_right_verification.json`의 중립·전체 최대 굽힘·엄지 가운데·각 손가락 끝마디 최대 굽힘 검사에서 손톱 정점과 면 중심의 피부 표면 거리 최대값은 각각 약 0.735mm와 0.666mm였다. 이는 Blender 모델 검증이며 Godot 자동 검증과 실제 화면 검토 근거는 아래 및 관절 제작 기록에 별도로 보존한다.

Godot 자동 검증 명령은 `./tests/run_headless_tests.sh player_finger_joints player_hands_detailed player_hands_greybox`이다. 실제 화면 검토는 `PLAYER_FINGER_JOINTS_QA_ITERATION=<새 이름> ./tests/run_embedded_preview.sh player_finger_joints_preview.gd`로 실행하며, `artifacts/visual_qa/player_finger_joints/<새 이름>/`에 열린 손·손바닥·손목 옆면·뿌리·가운데·끝·주먹·활·상자·실제 조절 UI 10장과 기록을 보존한다. 최종 관절 자동 검증은 `godot_joint_final04.log`에서 통과했다. 관련 7개 테스트와 실제 `final_04` 렌더 235개(정지 9장·순차 226프레임)의 상태·소스·원정 복원 검사도 통과했다. 모든 15개 슬라이더와 수치 표시가 1280×720 화면에 들어오고, 실제 테스트룸과 같은 CanvasLayer 70에 UI가 표시되는 것을 확인했다. 상세 기록과 GIF는 관절 납품 패키지에 있다.

## 손등–손목–팔 연결부 정리 (2026-09-11)

현재 게임의 두 GLB는 `left_hand_wrist_refined.glb`, `right_hand_wrist_refined.glb`와 동일하다. 편집 원본은 `bilateral_hands_wrist_refined.blend`다. 손등의 벌어진 끝을 좁히고 튀어나온 손목 표면을 정리했다. 얇은 중공 연결부는 손 표면에 맞춘 둥근 끝단을 가진다. 전완 보호대의 끝은 손목의 유연한 구간과 겹쳐 자르지 않도록 국소적으로 짧게 조정했다. 원래 전완의 native z≥0.100m 영역은 정확히 유지한다.

`WristCuff`의 `wrist_flex_version=1`, `wrist_flex_start_z=0.014`, `wrist_flex_end_z=0.075` 메타데이터를 `scripts/wrist_cuff_deformer.gd`가 읽는다. 손 쪽 끝은 고정하고 팔 쪽 끝은 실제 전완 맞춤 변환을 따른다. 실제 손목 본을 팔 맞춤의 기준으로 삼고, 중심 경로와 각 단면을 함께 회전시킨다. 큰 굽힘에서는 안쪽만 연속적으로 압축하며 바깥쪽 윤곽과 굽힘에 수직인 폭을 유지한다. 법선·접선도 같은 변형의 미분에 맞춰 갱신한다. 각 인스턴스의 동적 메시만 수정하며 원본 메시·손목 접촉 좌표·손가락 30관절과 교정 형상·손톱·웨이트를 유지한다.

독립 Blender 검증은 손목 국소 변경, 전완 보호 영역, 16본과 15개 교정 형상의 보존, 얇은 연결부의 폐합·면 방향, 양쪽 GLB 왕복 좌표를 통과했다. 손목 정리 단계의 최종 Godot 검증과 실제 화면 근거는 `asset-staging/player_wrist_refinement_20260910/README.md`에 기록한다.
