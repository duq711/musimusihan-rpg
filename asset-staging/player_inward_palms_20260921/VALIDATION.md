# 몸을 향한 손바닥 / Inward-facing palms

양손을 전완 축 주위로 좌우 반대 방향 90° 회전했다. 손바닥의 안쪽 정렬 내적은 양쪽 모두 0.9856이다. 손목과 소매 끝은 손과 같은 변환을 적용하고, 소매 회전은 0.95–1.135m 높이에서 팔꿈치 방향으로 부드럽게 사라진다. 옷자락과의 겹침을 피하도록 손과 하단 소매를 바깥으로 1.5cm 이동했다.

English: Rotate hands 90° in opposite directions around the forearm axes. Both palm normals have 0.9856 inward alignment. Apply the same transformation to the wrist and lower cuff, smoothly blending out through the sleeve at heights 0.95–1.135m. Move hands and lower cuffs outward by 1.5cm to clear the coat.

피부·장갑·소매 재질, UV, 손가락 굽힘과 크기를 보존한다. 일인칭 원본과 장비 동작은 변경하지 않았다.

English: Preserve skin, glove and sleeve materials, UVs, finger curl and hand dimensions. First-person source assets and equipment behavior are unchanged.

- Blender 제작 검사 PASS: 몸통 24개 메시 보존, UV·면 유지, 손과 소매 끝의 변환 일치 / 24 body meshes preserved, unchanged UVs/topology, matching hand/cuff transformation.
- 관통 검사 PASS: 최종 Blender 모델 양손과 몸통 사이 삼각면 겹침 0. 표본 정점→표면 최소 거리 왼손 23.53mm, 오른손 9.56mm (정확한 전체 삼각면 간 최단거리 수치는 아님) / zero triangle overlap pairs; sampled vertex-to-surface distances 23.53mm left and 9.56mm right, not exact triangle clearance.
- player_fullbody_fp_arms PASS: 손목 크기를 회전 전 좌표계로 환산해 검증; 안쪽 손 방향, 소매와 재질 회귀 / inverse-transform cuff dimensions, inward hand orientation, sleeve/material regression.
- player_appearance PASS: 기존 캐릭터·인벤토리·F2·원정 복원. 격리 검증 캐시의 UID 경로 대체 경고 및 기존 ObjectDB 종료 경고는 로그에 기록 / appearance, inventory, F2 and expedition restoration; isolated-cache UID fallback warnings and existing ObjectDB exit warnings are logged.
- Godot 실제 렌더 / actual GPU captures: godot-game/artifacts/visual_qa/player_appearance/inward_palms_20260921_verified/

제작 / Production: build.py → Gravebound_Inward_Palms.blend, gravebound_player_inward_palms.glb, build_report.json. 원본 / Source: ../player_natural_hands_20260921/Gravebound_Natural_Hands.blend.
