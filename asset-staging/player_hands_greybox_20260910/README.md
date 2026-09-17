# 플레이어 양손 그레이박스

캐릭터 그래픽 담당: 사용자 지정 작업명 ‘김형태’. 제작일: 2026-09-10.

현재 플레이어의 비율과 장갑·보호대·소매를 바탕으로 좌우 별도 그레이박스를 제작했다. 사용자의 후속 지시로 이번 작업은 **Mac Blender 5.2.1 백그라운드**에서 실행했다. Blender MCP는 등록되어 있었으나 `localhost:9876`에 접속되지 않아 설치된 Blender 실행 파일을 직접 사용했다.

## 최종 파일

- 최종 제작 원본: [mac_output/iteration_05](mac_output/iteration_05/).
- 편집 파일: `bilateral_hands_greybox.blend`. 양손 검토 장면과 기존 좌우 원본·전신 플레이어 참고 장면을 포함한다.
- 개별 게임 모델: `left_hand_greybox.glb`, `right_hand_greybox.glb`.
- 양손 비교 모델: `both_hands_greybox_preview.glb`. 보기 좋게 좌우를 이동한 검토용이며 개별 모델의 손목 좌표와 구별한다.
- 손등·손바닥·측면 이미지: `both_hands_dorsum.png`, `both_hands_palm.png`, `both_hands_side.png`.
- 배포용 복사본과 ZIP: `../../exports/Player_Hands_Greybox_2026-09-10/` 및 같은 이름의 ZIP.
- 게임 에셋: `../../godot-game/assets/3d/player/hands_greybox/`.

| 항목 | 왼손 | 오른손 |
|---|---:|---:|
| 원본 활성 삼각형 | 68,010 | 68,006 |
| 최종 삼각형 | 9,997 | 9,996 |
| 활성 메시 | 4 | 4 |
| 손가락/본 | 5 / 16 | 5 / 16 |
| 최종 GLB 크기 | 394,268 bytes | 393,704 bytes |
| 원본 전체 경계 대비 최대 변화 | 약 0.122mm | 약 0.087mm |

겹침 자국을 없애기 위해 원본 장갑의 중복 표면은 출력에서 제외했다. 연속된 손 표면 위에 장갑 부분을 회색으로 구분하여, 별도 표면끼리 교차하지 않는다. 노출된 손가락·장갑/커프·소매는 세 가지 비금속 무광 회색이다. 텍스처가 없으며, 손목과 16개 본의 바인드 위치는 보존한다. 단순화 후 최대 8개 웨이트를 지원하는 glTF로 출력했다. 최종 텍스처 아트나 새로운 전투 애니메이션을 제작한 것은 아니다.

## 실제 플레이 연결

`테스트룸 → 기본 → 캐릭터 그래픽 · 양손 그레이박스`를 선택한다.

- 실제 시험 가방에 검·방패를 보관하고 횃불을 꺼서 양손을 확인한다.
- `WASD`로 움직이며 손·소매를 보고, 왼쪽 상자를 `E`로 조사해 손가락과 뚜껑 접촉을 확인한다.
- `I`에서 활을 장착한 뒤 `LMB`를 누르고 놓아 실제 당김/발사에 따른 손가락 변형을 본다.
- `F2` 메뉴는 기존대로 시간을 멈춘다. 다른 시험 선택·초기화·장면 이동·종료 시 회색 보기가 해제된다.
- 원래 원정의 인벤토리 객체·장비 메타데이터와 상태를 보존하고 종료 시 복원한다.

`DungeonPlayer.set_hands_greybox_enabled()`는 플레이어 인스턴스 안의 보기 설정이다. 일반 손/활/횃불/지팡이/철퇴와 상자 손의 실제 동작에 연결되며 전투·상호작용 접촉 프레임은 바꾸지 않는다. 기본 검의 `SwordHold_Static.glb`와 방패 전용 모델은 기존 상태를 사용한다. 전신 `gravebound_player.glb`와 모든 기존 원본은 그대로다.

## 검증과 한계

- `mac_output/iteration_05/build_report.json`: 실제 Mac OS·Blender 실행 경로, 원본/출력 해시, 삼각형과 경계 검사.
- `mac_output/iteration_05/verification_report.json`: Blender 원본 재개방과 GLB 재가져오기 통과. 좌우 16개 본, 3개 회색 재질, 실제 손가락 10개 변형과 손목 고정, 웨이트, 좌우 엄지 방향 확인.
- `godot_greybox_final05.log`: 최종 에셋의 전용 헤드리스 검증 통과. 모델 변형뿐 아니라 실제 맨손/활/상자·레이어·시험 선택·F2·반복·초기화·종료와 상태 복원을 검사한다.
- `godot_tests_01.log`: 기존 `player_arm`, `weapon_hand_contacts`, `chest_hands`, `test_room_session` 4종 통과. 이 기록의 최초 그레이박스 입장 실패는 수정 후 위 최종 전용 검증에서 통과했다.
- 실제 Godot 화면 5종은 `../../godot-game/artifacts/visual_qa/player_hands_greybox/final_05/`에 있다. 검토된 창 없는 Forward+/Vulkan 경로로 외부 입력·마우스 캡처 없이 생성한다. 소스 해시·원정/인벤토리/커서 보존은 `capture_manifest.json`에 기록한다.
- **기존 실패:** `sword_long_grip_test`의 검 소매 어깨 정렬 검사는 이번 변경을 되돌린 격리 비교본에서도 동일한 1,161개 오류를 같은 순서로 냈다. `sword_baseline_comparison.json`, `sword_baseline_reverse.patch`, `sword_baseline_manifest.json`과 `sword_baseline_test.log`가 근거다. 역사적 Git 체크아웃은 없어서 이번 변경만 제거한 비교본을 사용했다. 검 동작을 수정하거나 이 검사를 통과했다고 보고하지 않는다.
- 기존 팔 검사와 새 검사 모두 종료 시 같은 ObjectDB 인스턴스 2개 경고가 있었다. 시험 프로세스는 종료했으며, 게임 전체 검사 통과나 최종 전투 손 파지 품질을 주장하지 않는다.

## 재제작과 원본 보존

[tools/README.md](tools/README.md)의 현재 제작기 `build_hands_greybox.py`와 검증기 `verify_hands_greybox.py`를 사용한다. `input/`은 원본 좌우 중립 팔·전신·기존 정면 화면의 사본이며 `source_inspection.json`에 출처 치수와 해시가 있다. 원본 해시 일치를 다시 확인했다.

처음 Windows 연결을 기다리며 만든 `preparation_validation.json`, `build_hands_greybox_windows.py`, 준비용 ZIP은 당시의 기록이다. 현재 완료 상태나 최종 산출물을 나타내지 않는다. `mac_output/iteration_01`~`04`는 제작/검토 이력이며 최종본은 `05`다. 기존 에셋의 CC0 인체 소스 및 프로젝트 제작 의상 출처 설명은 `input/SOURCE_ARMS_README.md`, `input/SOURCE_PLAYER_README.md`에 보존했다.
