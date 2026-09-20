# 의상과 맞춘 소매 / Outfit-matched sleeves

기존 소매 UV와 직조 무늬를 보존하고, 천에만 별도 알베도 보정을 적용했다(채도 80% 감소, 밝기 72%). 무광 의상과 맞도록 거칠기 0.9, 금속성 0으로 설정했다. 노출 손목 피부 144개 면(각 팔)의 재질과 UV를 보존하고 장갑은 변경하지 않았다.

English: Preserve the sleeve UV layout and weave. Apply a separate cloth albedo grade (80% desaturation, 72% brightness), roughness 0.9 and metallic 0 to match the matte outfit. Preserve the material and UVs of 144 exposed skin faces per arm and leave gloves unchanged.

- Blender 형상 검사 PASS: 28개 메시의 정점·면·변환 모두 유지 / all 28 meshes retain vertices, faces and transforms.
- player_fullbody_fp_arms PASS: 전용 천 재질, 피부·손 재질과 크기 검사 / dedicated graded cloth material, skin/hand maps and geometry checks.
- player_appearance PASS: F2·인벤토리·회전·원정 복원 확인. 기존 ObjectDB 2개 종료 경고 기록 / F2, inventory, rotation and expedition restoration passed; two existing ObjectDB exit warnings remain.
- Godot GPU 전신·소매 상세 렌더: matching_sleeves_20260921_verified / Full-body and sleeve-detail captures.

제작 / Production: build.py, Gravebound_Matching_Sleeves.blend, gravebound_player_matching_sleeves.glb.
입력 / Input: player_relaxed_elbows_20260921/Gravebound_FP_Arms.blend.
