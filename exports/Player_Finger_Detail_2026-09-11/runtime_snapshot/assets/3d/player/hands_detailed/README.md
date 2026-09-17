# 개별 손가락 기준 피부 디테일

각 손가락의 손톱 면과 지문 면을 각각 한 장씩 생성한 독립 기준 이미지 10장을 바탕으로 피부결·관절 주름·지문 루프·손톱 세로결을 보강했다. 기존 장갑·전체 손 비례·따뜻한 피부색·소매·봉제선은 유지한다.

현재 적용본은 `asset-staging/player_fingers_detail_20260911/mac_output/iteration_10/bilateral_hands_finger_detail.blend`다. 좌우 `*_hand_finger_detail.glb`를 이 폴더의 `left_hand_detailed.glb`, `right_hand_detailed.glb`에 연결하는 경로를 사용한다. 엄지 방향 수정본의 독립 Blender/GLB·80개 손톱 부착 검사와 Godot 헤드리스 7개·실제 렌더 18장이 통과했으며 실제 적용 파일의 SHA와 상태는 제작 폴더의 `godot_integration.json`, `validation_summary.json`을 따른다. 이전 비례 원본은 `asset-staging/player_hands_proportions_20260911/`에 보존한다.

손의 원래 14,988정점·5손톱·16본의 기본 자세·UV·가중치를 유지한다. 노출 피부의 마디·패드 조형은 최대 약 0.62mm이고, 이번 엄지 축 회전에 따른 정점 이동은 별도로 측정한다. 엄지 피부와 손톱을 함께 회전하고 15관절 보정 벡터도 같은 방향으로 변환한다. 미세 주름과 지문은 `iteration_08`에서 베이크한 4096² basecolor/normal/roughness를 재사용하며 세 맵은 Blender와 GLB에 내장한다. 다른 네 손가락과 장갑·소매·봉제선은 이번 회전의 대상이 아니다.

기존 `detailed` 프로파일과 손목·장비 접촉을 사용한다. 테스트룸 → 기본 → **캐릭터 그래픽 · 손가락 피부 디테일**에서 빈손·활·상자 동작을, **캐릭터 그래픽 · 손가락 마디별 관절**에서15개 마디를 확인한다. 초기 외형 선택과 원정·가방·커서 복구는 유지한다.

기준사진은 스타일과 디테일 참고용이다. 실제 게임 모델의 기존 굽힘 자세와 실루엣을 유지하므로 사진과 픽셀 단위로 일치하는 복원은 아니다. 제작·검증 결과는 새 제작 폴더의 `README.md`, `iteration_review.json`, `validation_summary.json`에 기록한다.

엄지 손톱 후속 수정: `iteration_08`의 길이 25.6→19.0mm, 중심 1.1mm 이동, 손끝 간격 4.37→3.10mm 보정에 이어, `iteration_10`은 엄지 길이 축을 중심으로 왼손 +60°·오른손 −60° 회전을 적용한다. 지문 면이 손 안쪽을, 손톱 면이 바깥쪽을 향하도록 수정한 후보를 사선·옆면과 8개 굽힘 자세에서 확인한다. 다른 손톱의 길이와 방향은 유지한다.
