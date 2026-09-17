# 납품 파일 열기

- `Blender/bilateral_supplied_hands.blend`: 편집 가능한 양손·캐릭터 장면. 사용 텍스처 7개가 파일 안에 포함되어 있다.
- `GLB/`: 게임용 양손과 전신 캐릭터. GLB 안에도 텍스처가 포함되어 있다.
- `Textures/`: 양손·의상용 4K 색상·노멀·거칠기 원본 PNG.
- `Originals/`: 변경하지 않은 사용자 OBJ·ZTL 원본.
- `Preview/`: Blender 및 실제 게임 검토 이미지.
- `Verification/`, `validation_summary.json`, `SHA256.json`: 검증 결과와 무결성 기록.

아래 제작 기록의 `mac_output/`, `audit/`, `review/` 경로는 원래 게임 프로젝트의 제작 폴더를 기준으로 한다. 이 납품에서는 위 폴더를 사용한다.

---

# 제공 손 모델의 캐릭터 적용

사용자 요청: 현재 캐릭터의 손을 제거하고 제공한 `hand1.OBJ` / `left_hand.ZTL`을 자연스럽게 적용한다. 이후 지시에 따라 모든 Blender 작업은 MacBook 백그라운드에서 진행한다.

## 실제 제작

- `input/`은 제공 OBJ와 ZTL의 변경 없는 사본 및 SHA-256 기록이다. Blender가 직접 읽을 수 있는 OBJ를 실제 제작에 사용하고 ZTL은 보존한다.
- 원본의 연결된 손 본체와 별도 손톱 5개를 분리했다. 1,193,494삼각형의 원본을 한 손당 본체 45,000 + 손톱 3,000삼각형으로 직접 경량화했다. 이전 손 형상에 투사하거나 이전 정점의 보정 값을 가져오지 않았다.
- 좌표계는 손목 중심에서 +Y가 손가락, +Z가 손등이다. 원본 왼손을 강체 회전·이동·균일 배율로 정렬했으며 반대 손은 메시 좌표의 X 대칭과 면 방향 교정으로 제작했다. 음수 오브젝트 스케일은 사용하지 않는다.
- 원본에 없던 UV와 색·거칠기를 제작하고 원본 고밀도 표면을 4K 탄젠트 노멀에 구웠다. `supplied_hand_*` 세 장은 양손의 같은 UV에 연결된다. 기존 커프·토시·소매의 `realistic_hands_*` 세 장은 의상에 사용한다.
- 실제 손가락의 위치를 따라 16본을 배치하고 새로운 가중치와 15개 관절 교정 형상을 만들었다. 손톱은 각 원위지골에 강체 결합한다. 기본 자세는 원본의 굽은 손이며 굽힘 조작은 추가 회전이다.
- 1인칭 손목의 가려지는 막힌 끝은 커프의 손 쪽 고정 구간 안에 맞췄다. 끝이 팔을 따라 휘는 커프 구간까지 내려가지 않도록 길이를 줄이고 실제 안쪽 벽 안에 넣었다. 이 맞춤은 숨겨진 연결부에만 적용하며 보이는 손바닥·손가락 형상은 유지한다. 세부 수치와 변경 범위는 `mac_output/iteration_05/stump_containment_report.json`에 기록했다.
- 전신과 인벤토리가 공유하는 캐릭터에서 기존 손 22개 부품을 제거하고 새 손 2개·손톱 10개를 연결했다. 다른 28개 메시의 형상·UV·변환은 그대로 보존했다. 손목의 막힌 끝은 기존 토시 안에 숨긴다.
- 기본 일반 1인칭 손과 상세 시험은 새 좌우 GLB를 공유한다. 검 오른손과 방패 왼손의 파지 전용 에셋은 기존 별도 경로를 사용한다. 활·상자·빈손과 15마디 시험은 새 손으로 검증한다.

## 파일

`mac_output/iteration_05/bilateral_supplied_hands.blend`에는 새 양손 검토 장면, 전신 캐릭터 장면, 숨긴 고밀도 원본이 있다. 같은 폴더의 `left_hand_supplied.glb`, `right_hand_supplied.glb`, `gravebound_player_supplied_hands.glb`가 검증을 마친 현재 게임 적용본이다. 1인칭 손목은 커프의 고정 구간에 맞추고, 전신의 숨겨진 손목 끝은 기존 토시 안에 넣어 연결했다. 원본 게임 파일은 `baseline/`에 보존했다.

`tools/`에 경량화·좌표 정렬·리깅·미러링·베이크·조립·검증·렌더 스크립트를 보존한다. `audit/`에는 연결 진단 및 모델/게임 검증 결과를 기록하며 최종 완료 상태는 `validation_summary.json`을 따른다. 이전 장갑 납품과 제작 폴더는 변경하지 않는다.

## 검증 상태

현재 상태는 **검증 완료**다. `iteration_05`의 독립 Blender 검사, 메시 사전 검사, 실제 Blender 7개 화면 검토와 Godot 헤드리스 8개 검사가 통과했다. 근거는 `audit/final_native_audit_iteration_05.json`, `review/final_05/mesh_preflight.json`, `review/final_05/native_visual_review.json`, `audit/headless_final_05_summary.json`에 있다.

실제 Vulkan 화면은 새 양손 `supplied_hands_05`의 관절 12장과 상세 손 6장, 총 18장을 촬영·검토했다. 전신 5개 화면은 `player_appearance/supplied_hands_03`의 기존 검토를 재사용한다. 해당 전신 GLB의 SHA-256 `b25875dadb920303d7e8b0e58085973586b9cdf4cceb383159bcdb7e2c9fc92b`가 현재 적용본과 정확히 같음을 확인했으며, 이 5장은 새로 촬영한 양손 18장과 구분한다. 캡처 기록은 `../../godot-game/artifacts/visual_qa/`의 각 항목에 있다. 손목·소매 연결, 관절·활·상자 동작과 원정·가방·커서 복원을 확인했다. 전체 결과와 적용 파일 해시는 `validation_summary.json`에 보존한다. 검 오른손·방패 왼손의 전용 파지 모델은 기존 에셋을 계속 사용한다.

## 연결 진단

Blender MCP 주소와 설치는 유효했으나 실행 중인 Blender 소켓 서버가 없었다. Blender의 온라인 접근 설정이 꺼져 있어 확장 자동 시작도 중단됐다. 설정을 임의로 바꾸지 않고 정상 동작을 확인한 파일 기반 MCP 및 Blender CLI로 제작했다. 상세 근거는 `audit/mcp_connection_diagnosis.json`에 있다.
