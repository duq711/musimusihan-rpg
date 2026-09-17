# 플레이어 양손 피부색·주름·골격 디테일

2026-09-11. 기존 손목 연결부 정리본을 바탕으로 실제 피부에 가까운 색과 손가락 주름, 마디 돌출, 손등 힘줄을 보강한 제작본입니다. 현재 플레이어의 짙은 반장갑과 팔 보호대, 누비소매를 유지했습니다.

- `bilateral_hands_realistic.blend`: 텍스처를 포함한 편집 가능한 양손 원본.
- `left_hand_realistic.glb`, `right_hand_realistic.glb`: 텍스처가 내장된 좌우 독립 게임 모델.
- `realistic_hands_basecolor.png`, `realistic_hands_normal.png`, `realistic_hands_roughness.png`: 양손 공용 4096×4096 PBR 텍스처. 색은 sRGB, 나머지는 선형 데이터이며 노멀은 OpenGL 방향입니다. GLB의 거칠기는 glTF 표준 녹색 채널에 저장됩니다.
- `realism_before_after_before.png`, `realism_before_after_after.png`: 같은 카메라·조명·중립 자세의 실제 Blender 전후 렌더.
- `bilateral_dorsum.png`, `preview_finger_dorsum.png`, `finger_palm_closeup.png`: 최종 모델의 양손 전체·손등 확대·손바닥 확대 실제 Blender 렌더. 전후 비교의 after는 손등 확대 이미지와 같습니다.
- `godot_preview/`: 현재 Godot 모델을 직접 촬영한 게임 화면과 캡처 기록. 추가 피부 확대 두 장은 별도 중립 검토 조명이며, 일반 게임 화면과 구분해 기록했습니다.
- `build_report.json`, `padding_verification_report.json`, `validation_summary.json`, `validation/`: 제작, 최종 독립 원본 검사, 게임 검증 근거. 형상·관절 전체 검사의 기준 보고서는 `validation/mac_output/iteration_03/verification_report.json`에 함께 보존합니다.
- `tools/`: 이번 제작·베이크·렌더·검증에 사용한 Python 소스.

피부는 따뜻한 중간 밝기의 살색에 손바닥·손등의 차이와 관절 주변의 옅은 혈색을 넣었습니다. 손톱은 살색 바탕·반달·밝은 끝을 구분했습니다. 손가락 마디에는 얕은 호형 주름을 넣고 마디의 돌출과 손등의 힘줄은 실제 표면 형상에도 더했습니다. 골격은 피부와 장갑 아래의 형태로 표현합니다.

최종본은 `iteration_04`입니다. 텍스처의 빈 여백만 채워 게임 거리에서 생기던 검은 금과 흰 반사 경계를 정리했으며, 기존 유효 픽셀8,453,226개는 세 맵 모두 그대로 보존했습니다. Blender 파일은 재질이 보이는 양손 카메라로 열리며, F12 기본 렌더는1600×1300·24샘플·denoise로 설정했습니다.

좌우 각각 63,970삼각형·9메시·16본·15개 관절 교정 형상을 유지합니다. 손톱, 팔 구간과 손목 연결부의 기하, 스킨 웨이트와 본 기준 자세를 보존합니다. 피부/장갑의 국소 조각은 최대 약0.612mm이며, 같은 변위를 모든 교정 형상에 적용합니다. 새 UV와 실제 노멀맵용 접선을 내보냈으며 Blender 전용 셰이더에 의존하지 않습니다.

Godot의 기존 `detailed` 외형에 연결됩니다. 테스트룸 → 기본 → **캐릭터 그래픽 · 양손 디테일 모델**에서 실제 빈손·활·상자 동작을, **캐릭터 그래픽 · 손가락 마디별 관절**에서 손등·손바닥·손목 옆면과 15개 마디 조절을 확인합니다. 게임 초기 외형 선택 방식과 시험 종료 시 원정·인벤토리 복원을 유지합니다.

관련 자동 검사7개와 실제 게임 화면18장의 상태 검사·직접 화면 검토를 완료했습니다. 기존 원본·이전 납품본422개도 해시로 보존했습니다. `runtime_snapshot/`은 현재 Godot 프로젝트의 연결 파일 보존본이며 독립 실행 프로젝트는 아닙니다. 최종 검사 수치와 검토 결과는 `validation_summary.json`을 기준으로 합니다.
