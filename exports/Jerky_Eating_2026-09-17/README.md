# 육포 꺼내 먹기 / Drawing and eating jerky

제작한 불규칙 육포를 오른손으로 꺼내고, 두 번 베어 문 뒤 손을 내리는 8초 모션입니다. [참고 영상 1:45–1:53](https://www.youtube.com/watch?v=kaJqMSBgi00&t=105s)의 동작 흐름을 브라우저에서 확인해 적용했습니다. 원본 영상의 소시지 대신 기존 육포의 긴 조각을 사용합니다.

This eight-second action draws the authored irregular jerky with the right hand, takes two bites, and lowers the hand. The draw/bite/pause rhythm follows the linked 1:45–1:53 reference. It uses the existing long jerky strip in place of the reference's sausage.

## 영상 / Video

[전체 영상 / Complete motion](jerky_eating.mp4) — 960 × 540, 30 fps, 8.73 seconds, silent. Eight seconds of actual item use plus the equipment return. The recording comes from the production `DungeonPlayer` in the isolated test fixture using the real Vulkan renderer; it is not a generated illustration.

![전체 동작 단계 / Motion contact sheet](sequence_contact_sheet.jpg)

## 게임에서 실행 / Play in-game

`F2 → 생존 → 육포 먹기 · 꺼내서 한입씩`

시험용 육포 3개·포만감 35를 준비합니다. 완료 시 1개 소비·포만감 32 회복. F 취소, F2 메뉴 복귀·재선택으로 반복합니다. 손가락 파지는 실제 스킨 표면에 맞췄고, 베어 문 조각은 손에 잡힌 부분과 원본 재질을 유지합니다. 팔꿈치는 1인칭 화면 밖으로 연결됩니다.

The survival trial supplies three portions and starts the real food-use action. Completion consumes one and restores 32 hunger. F cancels; F2 opens the menu for another trial. Thumb/index contact is fitted to the real hand skin, and the bitten meshes retain the held end and source material. The elbow stays outside the first-person frame.

## 제작 파일 / Production files

- [모션과 베어 문 메시 / Motion and bitten meshes](../../godot-game/scripts/jerky_eat_visuals.gd)
- [원본 육포 / Original jerky](../../godot-game/assets/3d/items/beef_jerky/README.md)
- [파지 측정 / Grip measurements](../../godot-game/assets/3d/items/beef_jerky/production/GRIP_CALIBRATION.md)
- [촬영 매니페스트 / Capture manifest](capture_manifest.json)

원본 GLB·텍스처·제작 파일은 변경하지 않았습니다. 이번 모션의 제작 원본은 Godot 스크립트이며 별도의 Blender 애니메이션 파일을 만들지 않습니다.

The original GLB, textures and modeling sources are unchanged. This animation is authored in the Godot script; there is no separate Blender animation file.

## 검증 / Validation

- `jerky_item_use` — PASS: 8초 완료 경계, 단일 소비, 포만감 상한, 소지 재검사, F/가방 취소. / Completion boundary, atomic consumption, hunger limit, ownership recheck and cancellation.
- `jerky_test_room` — PASS: 자동 물품 등록, 실제 사용·무기 복귀, F2·재보급·회복·초기화와 원정/가방 참조/커서 복원. / Production trial, catalog, equipment return, repeat/reset and exact session restoration.
- `timed_item_use` — PASS: 기존 소모품 사용 회귀. / Existing consumable regression.
- `jerky_motion` — PASS: 두 입 접촉, 눈·코 아래 위치, 손/육포 이동 연속성, 끝부분만 감소, 반복·취소·장비 복구. / Both mouth contacts, below-eye placement, continuous movement, bite geometry, repeat/cancel and equipment restoration.
- `jerky_grip` — PASS: 실제 피부 2,031개 정점과 육포 삼각형을 6시점에서 비교. 패드 간격 2mm 미만, 피부 정점 관통 허용치 1.5mm. / Real skin-versus-food geometry at six motion samples; pad gaps under 2mm and vertex penetration tolerance of 1.5mm.
- 실제 화면 / Render: Godot 4.7, Vulkan Forward+, Apple M4, 숨김 `embedded` 드라이버에서 **262프레임 + 옆면 진단 10장**. 소비·포만감·장비 복귀, 원정·커서 및 촬영 소스 해시 보존 PASS. / All timed-use and preservation checks passed.

전체 동작의 주요 프레임과 두 입 접촉 구도를 직접 검토했습니다. GUI 창이나 OS 입력을 사용하지 않았으므로 실제 키보드·운영체제 포커스 시험을 주장하지 않습니다. 촬영 로그에는 기존 공통 스크립트 경고가 있으며 새 모션의 스크립트 오류는 없습니다.

Key frames throughout the motion and both bite compositions were visually reviewed. Capture used no desktop window or OS input; it does not claim hardware-input/focus testing. The log contains existing shared-script warnings and no new motion script errors.

재현 / Reproduce from the repository root:

```sh
godot-game/tests/run_headless_tests.sh jerky_item_use jerky_test_room timed_item_use jerky_motion jerky_grip
JERKY_QA_ITERATION=new_capture GODOT_PREVIEW_TIMEOUT_SECONDS=600 godot-game/tests/run_embedded_preview.sh jerky_motion_preview.gd
```
