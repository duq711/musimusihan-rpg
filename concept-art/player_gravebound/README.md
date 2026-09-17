# 플레이어 캐릭터 컨셉과 게임 적용

Codex 내장 ImageGen으로 정면 컨셉을 생성하고, 같은 캐릭터의 후면·측면 참고 이미지를 추가 생성했습니다. CLI/API 대체 생성은 사용하지 않았습니다.

- [정면 컨셉](concept_front.png) · [정확한 정면 프롬프트](prompt.txt)
- [후면 컨셉](concept_back.png) · [정확한 후면 프롬프트](prompt_back.txt)
- [측면 컨셉](concept_side.png) · [정확한 측면 프롬프트](prompt_side.txt)
- [게임에 연결된 3D 모델](../../godot-game/assets/3d/player/gravebound_player.glb)
- [수정 가능한 Blender 원본](../../asset-staging/player_gravebound/gravebound_player.blend) · [제작·재현 안내](../../asset-staging/player_gravebound/README.md)

어두운 두건과 어깨 덮개, 회갈색 누비옷, 가죽 벨트와 주머니, 손가락이 드러나는 장갑과 낡은 장화를 실제 입체 메시로 구성했습니다. 정면·후면·측면의 이미지를 입체 표면에 맞춰 재질로 옮기며 본편 조명에 반응하는 PBR 재질을 사용합니다.

플레이어 전신과 인벤토리는 같은 모델을 사용합니다. 1인칭 손·소매도 같은 GLB 메시와 재질을 공유하며 손가락 관절로 손잡이를 쥡니다. `I` 인벤토리 또는 `테스트룸 → 기본 → 플레이어 외형 · 3D 캐릭터`에서 `‹`·`›`로 회전하고 `정면`으로 복구할 수 있습니다. 전신은 인벤토리 관찰용으로 편안히 서 있는 정적인 자세이며, 기존 1인칭 손·장비 동작은 유지합니다.

[1인칭 팔·손 동작의 후속 적용 및 실제 화면](../../godot-game/artifacts/visual_qa/player_arms/README.md)

## 실제 게임 렌더 비교 기록

모든 아래 화면은 Godot의 실제 Forward+ / Vulkan 렌더러로 출력했습니다. 창과 포커스 이동 없이 독립된 뷰포트에서 본편 모델·인벤토리·폐광을 구성하며, 사용자 데스크톱을 캡처하지 않습니다. Blender 검토 이미지는 제작 폴더에 별도로 구분해 보존합니다.

| 비교 단계 | 확인한 점과 다음 수정 |
|---|---|
| `iteration_01` | 앞뒤 방향, 소매와 어깨 연결, 겹친 장화와 측면 재질 경계 확인. 초기 앞뒤 반전 때문에 이 폴더의 `player_back.png`가 얼굴이 보이는 정면입니다. |
| `iteration_02` | 앞뒤 방향 교정, 연속 장화와 어깨 형태, UV 재질 결합. 인벤토리와 폐광에서 회전·복귀 버튼의 실제 클릭 통과. |
| `iteration_03_lighting` | 컨셉과 같은 전신 구도로 맞추고 푸른 반사와 강한 윤곽광을 낮춰 천과 가죽의 색을 조정. |
| `iteration_04_geometry_03` | 목과 뒤 망토 연결, 중복 장식 수정. 후면 재질 디테일과 보호대 겹침을 추가 점검. |
| `iteration_05_geometry_04` | 새 후면 컨셉으로 등과 망토 재질을 개선하고 소매·보호대 겹침 해소. 회전 시 보이는 넓은 단색 측면을 발견해 측면 참고를 추가 생성. |
| `final` — 모델 5차 | 측면 컨셉을 부위별 재질에 연결하고 목의 천결 보완. 텍스처 베이크 간섭으로 생긴 소매의 밝은 얼룩 수정. 인벤토리 회전 버튼을 장식보다 위에 표시. |

전체 비교 폴더: [Godot 실제 화면과 검증 로그](../../godot-game/artifacts/visual_qa/player_appearance/).

## 컨셉과 최종 Godot 화면

| 방향 | ImageGen 컨셉 | 실제 게임 모델 렌더 |
|---|---|---|
| 정면 | ![정면 컨셉](concept_front.png) | ![Godot 정면](../../godot-game/artifacts/visual_qa/player_appearance/final/player_front.png) |
| 후면 | ![후면 컨셉](concept_back.png) | ![Godot 후면](../../godot-game/artifacts/visual_qa/player_appearance/final/player_back.png) |
| 측면 | ![측면 컨셉](concept_side.png) | ![Godot 측면](../../godot-game/artifacts/visual_qa/player_appearance/final/player_side.png) |

[폐광 내 인벤토리 화면](../../godot-game/artifacts/visual_qa/player_appearance/final/player_inventory_in_game.png) · [1인칭 게임 화면](../../godot-game/artifacts/visual_qa/player_appearance/final/player_in_game.png) · [촬영 및 클릭 검증 기록](../../godot-game/artifacts/visual_qa/player_appearance/final/capture_manifest.json)

## 검증

- 전체 자동 검증: `full_suite.log` — 50개 통과, 0개 실패.
- 최종 모델 5차 및 버튼 수정 후 관련 검증: `final_validation.log` — 외형·인벤토리·1인칭 렌더러 3개 통과, 0개 실패.
- 최종 실제 렌더: `final_capture.log` — 9장 촬영 및 인벤토리 두 경로의 실제 회전·복귀 클릭 통과. 기록된 모델·초상 스크립트 SHA-256과 최종 파일의 일치도 확인했습니다.
- 외형 검증은 실제 GLB 메시·PBR 재질·1인칭 제외·공유 초상·일시정지 중 회전·반복 F2·던전 왕복·초기화·원정 복원을 확인합니다.
- 실제 화면 촬영은 인벤토리의 버튼 위치에 클릭을 전달해 30도 회전과 정면 복귀를 확인하고 원정 상태·커서 보존 결과를 각 `capture_manifest.json`에 기록합니다.
- 실행기에서 Godot이 스크립트 오류에도 종료 코드 0을 반환하는 경우를 실패로 처리하도록 보강했습니다.

[방해 없는 실제 렌더러 실행 방법](../../godot-game/tests/EMBEDDED_RENDERING.md)
