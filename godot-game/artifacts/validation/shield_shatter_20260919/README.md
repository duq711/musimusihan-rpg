# 방패 완전 파손 검수 / Shield destruction validation

내구도 5의 실제 게임 방패로 마지막 공격을 막은 뒤 장비가 사라지고, 목재 21·금속 9·가죽 2의 실제 3D 파편 32개가 물리적으로 흩어져 바닥에 충돌한다. 마지막 타격은 정상 방어되어 체력이 유지된다. 방패·원정 데이터는 독립 시험 세션에서 검사했다.

The actual production shield, starting at five durability, blocks its final hit and is removed from equipment. Its 32 physical 3D fragments (21 wood, nine metal, two leather) scatter and contact the floor. The breaking hit still preserves player health. Equipment and expedition state were tested in an isolated session.

## 영상·스틸 / Video and stills

[무음 실제 GPU 영상 / Silent actual GPU recording](shield_shatter.mp4) — 1280×720, 30 fps, 240 frames, 8 seconds. 전체 240프레임 디코딩·해상도·연속 시각·무음 스트림 검사를 통과했다. All 240 frames, dimensions, continuous timestamps and absence of audio were verified by a full decode.

- [break.png](break.png)
- [burst.png](burst.png)
- [floor.png](floor.png)
- [last_intact.png](last_intact.png)
- [ready.png](ready.png)
- [settled.png](settled.png)

0.9–1.7초에는 흩어진 파편을 보기 위해 실제 플레이어 카메라만 아래로 움직였다. 이 움직임은 **검수 촬영용**이며 실제 게임에서 강제로 아래를 보는 동작을 추가한 것이 아니다. 파편 위치·회전을 촬영용으로 덮어쓰지 않았다. 0.8초 마지막 방어 이후의 이동은 실제 물리 계산이다.

At 0.9–1.7 seconds only the production player camera looks down for inspection. This is **a capture inspection move**, not a forced gameplay look-down. No debris position or rotation is overridden; movement after the final block at 0.8 seconds comes from actual physics.

## 검증·실패 이력 / Validation and failure history

| 검사 / Suite | 결과 / Result | 실행 근거 / Run evidence |
| --- | --- | --- |
| `shield_damage_test.gd` | PASS | 초기 회귀 / initial regression |
| `shield_guard_test.gd` | PASS | 초기 회귀 / initial regression |
| `primary_shield_stow_test.gd` | PASS | 초기 회귀 / initial regression |
| `first_person_renderer_test.gd` | PASS | 초기 회귀 / initial regression |
| `test_room_test.gd` | PASS | 초기 회귀 / initial regression |
| `test_room_session_test.gd` | PASS | 초기 회귀 / initial regression |
| `shield_shatter_test.gd` | PASS | 최종 검사 / final check |

7종 중 1종은 최종 로그, 6종은 초기 회귀 로그의 통과 근거를 사용한다. [초기 로그](headless_initial.log)와 [최종 로그](headless_final.log)를 모두 보존했다. 초기 실행의 파손 검사는 충돌체 2개가 바닥 아래 −0.0559m/−0.0632m까지 들어가 **실패**했다. 이 실패를 숨기거나 초기 전체 실행을 통과로 바꾸지 않았다. 최종 검사와 [GPU 촬영](render_final.log)은 별도 증거다. 표의 실행 출처가 각 검증의 근거다.

Of seven unique suites, 1 use passing evidence from the final log and 6 from the initial regression log. Both logs are preserved. The initial shatter check **failed** when two collider bottoms reached −0.0559m/−0.0632m below the floor. That failure remains in the original log. The final pass and GPU capture are separate evidence; the table identifies each suite's actual run source.

GPU 마지막 기록: 바닥 접촉 이력이 있는 파편 32/32개, 정착 판정 31/32개, 충돌체 최소 높이 -0.016550m. 세부 숫자와 전체 프레임 상태는 [capture_manifest.json](capture_manifest.json), 검증 요약은 [summary.json](summary.json)에 있다. 파편은 WORLD2와만 충돌하고 월드 렌더 층 1에 그려지며, 원정·인벤토리·커서와 명시적 파편 정리가 보존됐다.

Final GPU record: 32/32 fragments had floor contacts, 31/32 met the settling criterion, and the lowest collider point was -0.016550m. Full per-frame state is in the capture manifest. Fragments collide only with WORLD2 and render on world layer one; original expedition/inventory/cursor state and explicit debris cleanup were verified.

## 원본·제작 검증 / Provenance and authoring validation

촬영에 사용한 소스 95개의 SHA-256이 촬영 전후 및 패키징 시점의 현재 파일과 일치한다. [모델 제작 검증 원본](../../../../asset-staging/shield_shatter_20260919/manifest.json)과 [보존 사본](model_manifest.json)의 파편 GLB 해시도 촬영 해시와 같다. [원시 GPU JPG 240장·촬영 폴더](../../visual_qa/shield_shatter/shield_shatter_20260919_04/)는 원래 위치에 유지하며, 이 폴더에는 중복 복사하지 않았다. [프레임 원본 해시](frame_sources.sha256)와 [MP4 전체 디코딩 해시](decoded_frames.sha256)를 보존했다. 추가 접촉 PNG가 있으면 기존 여섯 장과 함께 포함한다.

All 95 recorded source SHA-256 hashes match the current files, including checks before and after packaging. The authoring manifest and copied manifest identify the same fragment GLB used by the GPU capture. The 240 original JPGs remain in the linked capture directory; their hashes and the full MP4 decode hashes are retained here. Any extra contact-detail PNGs are included with the six primary stills.

## 한계·경고 / Limits and warnings

- 무음 영상이며 수동 OS 입력, 앱 포커스, 하드웨어 커서 동작을 시험하지 않았다. Silent recording; manual OS input, app focus and hardware cursor behavior were not tested.
- 평평한 바닥을 검증했으며 경사면·계단은 미검증이다. Flat floor verified; slopes and stairs unverified.
- 파편 수명은 24초다. 8초 영상에는 자동 소멸 순간이 포함되지 않으며 명시적 정리만 이 촬영에서 검사했다. Fragment lifetime is 24 seconds; the eight-second video checks explicit cleanup but does not show timed expiry.
- 물리 충돌은 각 파편의 볼록 외곽 근사다. 곡선 철테·손잡이의 빈 공간까지 정밀 충돌을 구현한 것은 아니다. Collision uses one convex hull per fragment, approximating curved rim/strap hollows.

보존한 실행 경고 / Preserved runtime warnings:

- WARNING: 2 ObjectDB instances were leaked at exit (run with `--verbose` for details).
- WARNING: Integer division. Decimal part will be discarded.
- WARNING: The class variable "_cuff" is declared but never used in the class.
- WARNING: The class variable "_forearm" is declared but never used in the class.
- WARNING: The class variable "_upper_arm" is declared but never used in the class.
- WARNING: The function parameter "seed" has the same name as a built-in function.
- WARNING: The local "for" iterator variable "name" is shadowing an already-declared property in the base class "Node".
- WARNING: The local function parameter "owner" is shadowing an already-declared property in the base class "Node".
- WARNING: The local function parameter "shield" is shadowing an already-declared function at line 118 in the current class.
- WARNING: The local variable "basis" is shadowing an already-declared property in the base class "Node3D".
- WARNING: The local variable "rotation" is shadowing an already-declared property in the base class "Node3D".
- WARNING: The local variable "scale" is shadowing an already-declared property in the base class "Node3D".
- WARNING: The local variable "target" is shadowing an already-declared variable at line 41 in the current class.
- WARNING: The parameter "blade_steel" is never used in the function "_build_sword_visual()". If this is intended, prefix it with an underscore: "_blade_steel".
- WARNING: The parameter "dark_steel" is never used in the function "_build_sword_visual()". If this is intended, prefix it with an underscore: "_dark_steel".
- WARNING: The parameter "iron" is never used in the function "_build_shield()". If this is intended, prefix it with an underscore: "_iron".
- WARNING: The parameter "leather" is never used in the function "_build_shield()". If this is intended, prefix it with an underscore: "_leather".
- WARNING: The parameter "preserve_authored_elbow" is never used in the function "fit_arm()". If this is intended, prefix it with an underscore: "_preserve_authored_elbow".
- WARNING: The parameter "rusted_steel" is never used in the function "_build_sword_visual()". If this is intended, prefix it with an underscore: "_rusted_steel".
- WARNING: The variable "axis" is declared below in the parent block.
- WARNING: The variable "correction" is declared below in the parent block.
- WARNING: The variable "delta" is declared below in the parent block.
- WARNING: The variable "finger_axis" is declared below in the parent block.
- WARNING: The variable "fitted" is declared below in the parent block.
- WARNING: The variable "pole" is declared below in the parent block.
- WARNING: The variable "result" is declared below in the parent block.
- WARNING: The variable "seed" has the same name as a built-in function.
- WARNING: The variable "shoulder" is declared below in the parent block.
- WARNING: The variable "wrap" has the same name as a built-in function.
- WARNING: The variable "wrist" is declared below in the parent block.
- WARNING: Values of the ternary operator are not mutually compatible.
