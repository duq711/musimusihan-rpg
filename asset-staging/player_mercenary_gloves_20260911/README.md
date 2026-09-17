# 플레이어 양손 — 중세 용병 가죽 장갑

사용자의 최신 지시인 “그냥 적당히 중세 용병들이 쓸법한 장갑만”에 맞춰 사진 손가락 작업을 종료하고, 양손을 끝까지 덮는 소박한 갈색 가죽 장갑을 제작했다. 손등 보강 패널, 손가락 밑부분의 봉제선, 긴 손목 부분과 무광 가죽결을 사용한다.

최종 제작본은 `mac_output/iteration_02/`다. 독립 모델 검사, 자동 검사 7개, 실제 GPU 캡처 18개와 Blender 렌더 2장의 검토를 완료했다. 납품 위치는 `exports/Player_Mercenary_Gloves_2026-09-11/` 및 같은 이름의 ZIP이다. 검증 근거는 `validation_summary.json`을 따른다.

## 산출물

- `bilateral_mercenary_gloves.blend`: 양손의 편집 가능한 Blender 원본. 4K 텍스처를 파일 안에 포함한다.
- `left_mercenary_glove.glb`, `right_mercenary_glove.glb`: 기존 플레이어 손목 기준의 좌우 게임용 에셋.
- `realistic_hands_{basecolor,normal,roughness}.png`: 게임의 기존 가져오기 경로를 유지하는 실제 가죽 PBR 아틀라스.
- `review/gloves_dorsal.png`, `review/gloves_palmar.png`: 실제 모델의 양손 손등·손바닥 렌더. 이미지 생성 결과가 아니다.

원본은 이전 작업의 `player_fingers_detail_20260911/mac_output/iteration_10/`이며, 이전 제작 자료와 납품 553개 파일의 불변을 확인했다. 사진 손가락 후속 실험 자료도 원래 위치에 보존한다. 이 장갑 작업은 사용자 허용 범위에 따라 Mac Blender를 백그라운드로 실행했다.

## 모델과 게임 연결

별도 손톱 메시 10개를 제거하고 전체 손가락에 가죽을 적용했다. 노출 손가락 표면을 완만하게 정리하고 약 0.45 mm의 가죽 두께를 주었다. 원본에서 같은 위치에 겹쳐 있던 UV 경계 정점은 함께 움직여 엄지와 손가락에 틈이 생기지 않도록 했다. 양손이 사용하는 서로 다른 UV 영역을 모두 베이크했다.

기존 16개 본, 손당 15개 관절 보정의 상대 변위, UV, 가중치와 메시 토폴로지를 유지한다. 소매·손목의 형상과 장비 접촉 기준도 유지한다. 가죽결의 미세한 깊이는 실제 4K 노멀 지도이며, 모든 표면 디테일을 개별 기하로 만든 것은 아니다. 가까이 보면 원본 손끝의 얕은 굴곡은 남아 있다.

게임에는 `godot-game/assets/3d/player/hands_detailed/`의 기존 상세 프로파일 경로로 반영한다. 테스트룸의 **기본 → 캐릭터 그래픽 · 용병 가죽 장갑**에서 양손·활·상자 동작을, **손가락 마디별 관절**에서 각 마디의 실제 굽힘을 확인한다. 기본 외형 선택 규칙, 검·방패의 별도 전용 손, 전투·아이템 규칙은 기존 동작을 따른다.

## 검증 근거

`verification_report.json`은 독립 검사로 실제 Blender·GLB의 리그/형상/가중치/UV/보정과 연결된 텍스처를 확인한다. 각 손가락의 실제 UV 표본에서 이전 피부색이 새 가죽색으로 바뀌었는지도 별도로 검사한다. `review/visual_review.json`은 실제 두 방향 렌더 검토 기록이다.

Godot 검증은 `headless_tests02.log`와 `artifacts/visual_qa/{player_finger_joints,player_hands_detailed}/mercenary_gloves_02/`의 실제 GPU 캡처를 사용한다. 창·입력 포커스·커서·소리를 방해하지 않는 기존 숨김 실행기를 사용한다. 최종 보고서와 납품 파일은 검증 완료 뒤 함께 생성한다.

첫 시안 `iteration_01`은 한쪽의 오래된 텍스처와 엄지 틈 때문에 외형 검토에서 탈락했다. 해당 기록은 보존하며 최종 납품에는 포함하지 않는다.
