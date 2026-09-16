# 입 접촉 동작 연결 / Continuous jerky bites

육포가 입 앞에서 멈춘 뒤 다시 움직이던 구간을 수정했습니다. 접근·베어 물기·손 내리기가 연속된 곡선을 따라 진행하며, 입에 가장 가까워지는 순간에도 손이 자연스럽게 옆과 아래로 움직입니다. 손가락 파지와 입 위치, 두 번 베어 무는 시점, 8초 음식 사용 규칙은 유지합니다.

Removed the fixed pose before each bite and the separate stop-and-restart tug. The hand now follows a continuous approach, bite and withdrawal curve, moving gently sideways and down through contact. Finger contact, mouth position, both bite events and the eight-second food-use rules are preserved.

## 영상 / Video

[수정한 전체 동작 / Updated full motion](jerky_continuous_bites.mp4)

실제 Godot 플레이어를 숨김 Vulkan 렌더러로 촬영한 960 × 540, 30fps 영상입니다. 8초 음식 사용과 장비 복귀를 포함합니다. 이전 제작 영상은 [기존 결과](../Jerky_Eating_2026-09-17/README.md)에 보존했습니다.

Recorded from the production Godot player with the hidden Vulkan renderer, at 960 × 540 and 30fps. It includes the eight-second food action and equipment return. The previous capture is preserved in the linked earlier result.

`F2 → 생존 → 육포 먹기 · 꺼내서 한입씩`에서 같은 동작을 실행합니다. F 취소·F2 재시험을 지원합니다.

Use the existing F2 → Survival → Eating beef jerky trial. F cancels and F2 lets you repeat it.

## 검증 / Validation

세 검사 모두 PASS. 접촉 전후 0.5초 구간에서 기존 첫/둘째 입의 정지 13/14프레임이 수정 후 모두 0프레임입니다. 실제 Vulkan 전체 262프레임을 촬영하고 입 접촉 연속 장면을 검토했습니다. 소비·장비 복귀, 원정·커서 및 촬영 소스 해시 보존도 통과했습니다.

All three suites pass. The old first/second bites froze for 13/14 frames within the sampled half-second contact windows; both now have zero frozen frames. Recorded 262 Vulkan frames and reviewed the contact sequences. Food completion, equipment return, expedition/cursor restoration and source hashes all pass.

![두 입 접촉의 연속 장면 / Both contact sequences](contact_sequence.jpg)

`jerky_motion`은 두 입 접촉 전후의 실제 손목과 손에 잡힌 육포 끝의 이동·회전을 60fps로 검사합니다. 연속 정지와 위치·회전의 급변을 검사하고, 베어 문 메시로 바뀌는 것을 움직임으로 계산하지 않습니다. 실제 피부 접촉은 `jerky_grip`, 소비·취소·장비 복귀와 원정 복원은 `jerky_test_room`에서 검사합니다.

The motion regression samples the actual wrist and held food end around both contacts at 60fps, detecting frozen intervals and abrupt pose jumps. Removing the bitten end cannot count as hand movement. The grip suite checks actual skin contact, while the test-room suite covers food use, cancellation, equipment return and session restoration.

- [모션 코드 / Motion code](../../godot-game/scripts/jerky_eat_visuals.gd)
- [연속 동작 회귀 검사 / Motion regression](../../godot-game/tests/jerky_motion_test.gd)
- [검증 결과 / Validation results](validation.json)
- [촬영 기록 / Capture manifest](capture_manifest.json)

```sh
godot-game/tests/run_headless_tests.sh jerky_motion jerky_grip jerky_test_room
JERKY_QA_ITERATION=continuous_bites_new GODOT_PREVIEW_TIMEOUT_SECONDS=600 godot-game/tests/run_embedded_preview.sh jerky_motion_preview.gd
```
