# 팔꿈치에서 연결되는 두 축 / Two limb axes joined at the elbow

팔 전체가 하나의 직선이던 이전 모델을 수정했다. 위팔과 아래팔은 각각 곧게 유지하고 팔꿈치에서 약 16도 방향 차이를 둔다. 관절 주변 6cm 구간에서 두 축을 완만하게 연결하며 이전의 물결형 단면은 사용하지 않는다. 손, 손목, 소매 하단 및 다른 몸 부위는 보존한다. 편안하게 내린 정지 자세를 위한 제작 값이다.

English: Replace the previous single arm axis with individually straight upper-arm and forearm axes differing by about 16 degrees, joined smoothly over a local 6cm elbow region. Retain the restrained sleeve taper without repeated bulges or waves. Preserve complete hands, wrists, lower cuffs and other body parts. This angle is an authored relaxed static-pose choice.

검증 / Validation:
- player_fullbody_fp_arms PASS (격리 임포트 프로젝트, 동일 공식 시험·실행기 / isolated import project, identical official test and runner).
- audit_geometry.py PASS: 각 구간 직선성·두 축 각도 16.03도·손과 하단 소매 좌표·몸 메시 24개와 FP 원본 보존 / segment straightness, 16.03-degree axis angle, preserved hands/lower cuffs, 24 other body meshes and FP source hashes.
- audit_surface.py PASS: 소매 표면 가장자리와 면적 검사 / sleeve surface edge and area checks.

제작 / Production: build.py, Gravebound_FP_Arms.blend, gravebound_player_fp_arms.glb. 앞선 player_fullbody_fp_arms_20260920 원본 몸과 pose.json을 재사용한다 / reuse that earlier original-body and pose archive.

숨김 실제 Vulkan 렌더 PASS: relaxed_elbows_20260921의 8장. 무채색 측면에서 팔꿈치 각도를, 천 재질 확대와 전신에서 실루엣을 검토했다. 커서와 원정 상태 보존.
English: Hidden actual Vulkan rendering passed with eight captures. Reviewed the elbow angle in the neutral-material side view and the silhouette in textured close-up/full-body views. Cursor and expedition state were preserved.
