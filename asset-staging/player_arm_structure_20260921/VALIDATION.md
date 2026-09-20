# 팔 전체 구조 재형성 / Whole-arm structure reconstruction

사용자 제공 사람 팔 그림을 기준으로 어깨, 위팔, 팔꿈치, 전완 상부와 하부를 구분해 소매 중심선과 단면을 다시 만들었다. 기존 형상 일부를 옮기는 방식 대신, 원본 메시를 121개 높이에서 절단 측정해 새 프로필로 재형성했다. 천 재질을 유지하고 새 연속 소매 표면에 원본 표면의 UV를 보간한다. 손·손목과 소매 최하단은 앞선 복원본을 보존한다.

English: Rebuild sleeve centerlines and cross-sections around the shoulder, upper arm, elbow and proximal/distal forearm, guided by the user-provided arm reference. Sample the original surface at 121 heights and remap to a continuous profile rather than locally displacing the old elbow. Replace the upper sleeve topology with a continuous loft and transfer source UVs. Preserve fabric materials, complete hands and the restored lower cuffs.

- player_fullbody_fp_arms PASS.
- audit_geometry.py PASS: 양손과 하단 소매 좌표 보존, 다른 24개 몸 메시·1인칭 원본 해시 보존 / unchanged hands/lower cuffs, 24 other meshes and first-person source hashes.
- 단면 관계 / Section relationships: upper arm 13.7cm, elbow 10.6cm, proximal forearm 12.7cm, distal forearm 11.0cm. 소매 외피 측정이며 해부학적 뼈 치수가 아니다 / these measure the clothed surface, not anatomical bone dimensions.
- 무채색 검토는 실제 게임 모델에 임시 단색 재질을 덮는 캡처이며 출시 재질에는 영향 없음 / neutral-material captures temporarily override the real mesh material without changing the production asset.

제작 / Production: build.py, Gravebound_FP_Arms.blend, gravebound_player_fp_arms.glb. 재생성에는 앞선 player_fullbody_fp_arms_20260920의 원본 몸과 pose.json 사용 / rebuild uses that earlier original-body and pose archive.

표면 재제작 / Surface rebuild: 팔꿈치의 원본 단차를 제거하고, 원본 소매 하단 0.935m의 절단 경계에서 81개 연속 단면을 연결했다. 새 면의 UV는 원본 표면의 가장 가까운 삼각면에서 보간했다. 어깨 캡은 망토 안쪽으로 좁혀 넣었다.
English: Remove the original elbow step and loft 81 continuous sections from the original cuff boundary at 0.935m. Transfer UVs by barycentric interpolation on the closest source triangles. Tuck the closed shoulder cap under the mantle.

audit_surface.py PASS: 재제작 상부의 열린 모서리 없음 및 면적 검사. 최종 모델 에셋 검사는 격리 임포트 프로젝트에서 동일 공식 실행기·시험·외형 스크립트로 통과했다.
English: Surface audit passes closed-edge and positive-area checks for the rebuilt upper sleeve. The final asset test passes in the isolated import project using the identical official runner, test and appearance script.

최종 실제 Vulkan 렌더 PASS: arm_structure_20260921_final의 8장. 전신·팔 확대와 무채색 정면·측면을 검토했다. 커서와 원정 상태 보존, 기존 스크립트 경고 외 실행 오류 없음.
English: Final actual Vulkan rendering passed with eight captures. Reviewed full-body, arm detail and neutral-material front/side views. Cursor and expedition state were preserved; existing script warnings remain without execution errors.
