# 원래 장갑 손의 비례 조정

사용자는 첫 이미지의 기존 장갑 손을 두 번째 사진의 **비율만** 참고해 수정하도록 명확히 정정했다. 장갑 제거·피부색 변경·주름 재제작은 요청 범위가 아니다. 이전 맨손 제작본은 잘못된 해석으로 생성된 이력이며 현재 채택 대상이 아니다.

기준은 `../player_hands_realism_20260911/mac_output/iteration_04/bilateral_hands_realistic.blend`다. 사용자가 첨부한 첫 이미지와 그 폴더의 `preview_finger_dorsum.png`는 디코딩한 픽셀이 모두 같음을 확인했다. 새 결과는 `mac_output/iteration_01/`에 저장한다.

## 비례만 바꾸는 방식

기존 피부·장갑·봉제선·손톱·소매의 모든 면, UV, 재질 배치, 가중치와 텍스처를 유지한다. 손 피부 12,036개 정점과 장갑 장식 2,952개 정점을 모두 보존했다. 재도색·재베이크·리메시·추가 조형을 하지 않는다. 형태가 바뀐 표면의 법선과 접선은 새 비례에 맞춰 갱신한다.

손바닥 폭은 0.82배, 손목 폭은 0.75배, 손바닥과 손목 두께는 0.85배로 조정했다. 사진에서 깊이는 직접 측정할 수 없으므로 두께는 보수적인 비례 조정으로 취급한다. 전완 쪽 native y≤−75mm는 그대로 두고 그 위로 부드럽게 연결한다. 장갑과 피부, 연결부 모두 같은 변환을 따른다.

| 손가락 | 단면 배율 | 길이 배율 |
|---|---:|---:|
| 엄지 | 0.78 | 1.02 |
| 검지 | 0.72 | 0.98 |
| 중지 | 0.73 | 1.00 |
| 약지 | 0.72 | 1.00 |
| 소지 | 0.68 | 0.90 |

기존 본이 실제 피부 단면 중심에서 벗어난 곳이 있으므로 실제 PIP 단면 중심을 기준으로 축소했다. 손톱·봉제선·Basis와 15개 관절 교정도 같은 변환을 적용했다. 손가락의 본 위치와 길이도 함께 맞추고 16개 본의 이름·계층과 로컬 X 굽힘 의미를 유지한다. 손목 기준점과 기존 장비 접촉점은 고정한다.

## 검토와 사용

`preview_finger_dorsum.png`는 사용자가 지목한 첫 이미지와 같은 카메라·조명·재질로 새 모델을 직접 렌더링한 결과다. `hand_dorsum.png`와 `hand_palm_upright.png`는 전체 비례 검토용이다. `hand_palm.png`는 초기 카메라의 상하 방향이 반대로 잡힌 검토 이력으로, 최종 표시용은 upright 파일을 사용한다.

Godot의 기존 상세 손 경로와 테스트룸의 **캐릭터 그래픽 · 장갑 손 비례 조정**에 연결한다. 자동 검사와 실제 게임 렌더 결과는 이 폴더의 `validation_summary.json`과 검증 로그를 따른다. 원래 피부색·장갑 재질을 바꾸지 않았다는 판정은 독립 검사와 텍스처 해시로 확인한다.

이전 제작·납품 파일 620개의 해시를 `baseline/preserved_artifacts.json`에 보존했다. MCP localhost9876 연결은 불가했으므로 이 양손 작업에 이미 허용된 Mac Blender 5.2.1 LTS의 백그라운드 실행을 사용했다.

재현: Blender의 `--background --threads 6 --python-exit-code 1 --python tools/build_proportions.py -- --source-dir <원본 realism04 폴더> --output-dir <새 출력 폴더>`를 사용한다. 원본 폴더에는 원래 `.blend`와 PBR 텍스처가 필요하다. 새 출력의 `bilateral_hands_proportions.blend`에는 텍스처가 내장돼 있어 편집과 렌더를 위해 별도 텍스처 설치가 필요하지 않다.

## 최종 검증과 납품 위치

독립 Blender·GLB 검사와 관련 헤드리스 검사 7개를 통과했다. 실제 Godot Vulkan 화면 18장(관절 12·게임 동작 6)과 Blender 렌더 4장을 직접 검토했다. 렌더 시 기존 장갑·손톱·피부 표현과 관절 굽힘·활·상자 접촉이 유지된다. 원본 GLB와 roughness PNG의 압축 바이트는 다르지만, 디코딩한 4096² 픽셀은 모두 동일하다. 나머지 두 GLB 텍스처와 별도 3종 텍스처도 보존 검사를 통과했다.

납품 폴더 `exports/Player_Hands_Proportions_2026-09-11/`와 같은 이름의 ZIP에서는 `.blend`, 양손 `.glb`, 텍스처와 검토 PNG가 최상위에 있다. 위 `mac_output/iteration_01/`은 제작 스테이징 경로이며 납품본에는 없다. 원본 보존 목록과 실행 로그는 `validation/`, 게임 캡처는 `godot_preview/`, 소스 사본은 `runtime_snapshot/`이다. 납품본에서 독립 검사를 다시 실행할 때는 `tools/verify_proportions.py -- --source-dir <원본 realism04 폴더> --output-dir <납품 폴더> --warp-module tools/proportion_math.py --support-dir tools/support` 인수를 사용한다.
