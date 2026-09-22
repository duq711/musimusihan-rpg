# 참고 비율 수정본 독립 검토 / Independent reference anatomy audit

Candidate GLB SHA-256: `6fc422a8219ad9d6b431fb800efb22b2277e5235e29aa9ed8fb85129d5d825d7`.

이 검토는 이전 `Gravebound_Neck_Arm_Flow.blend`와 현재 `Gravebound_Reference_Anatomy.blend`를 백그라운드 Blender에서 읽기 전용으로 비교했습니다. 원본과 런타임은 수정하지 않았습니다. The script compares source and candidate meshes without altering either file.

## 보존과 연결 / Preservation and continuity

- 얼굴 Z≥1.510 m의 모든 정점은 정확히 보존됩니다. Both hands, eyes, trousers, boots, belt and pouches are among 16 exactly preserved meshes, including vertices, topology, normals, UV and material names.
- 소매 Z≤.920 m는 정확히 보존되어 손목과 손 연결을 유지합니다. Sleeve cuffs at or below .920 m are unchanged.
- 모든 메시의 토폴로지·UV·머티리얼 이름이 유지됩니다. All mesh topology, UVs and material names are unchanged.
- 몸통–소매의 기존 공유 위치 229/228개를 비교한 수정 후 최대 간격은 0.000121 mm 미만입니다. Shared torso/sleeve boundaries remain effectively coincident.
- 원래 팔꿈치 Z1.155±.003 m 구간의 평균 하강량은 25.77 mm입니다. The authored elbow region is lowered by 25.77 mm on average.

## 단면 변화 / Cross-section changes

| Slice | Before width × depth | After width × depth |
|---|---:|---:|
| Lower neck, Z1.460 | 139.8 × 74.3 mm¹ | 129.5 × 119.2 mm |
| Neck, Z1.480 | 131.8 × 132.4 mm | 124.6 × 123.5 mm |
| Chest, Z1.300 | 386.6 × 276.7 mm | 396.3 × 238.7 mm |
| Lower chest, Z1.250 | 369.8 × 289.7 mm | 377.9 × 241.5 mm |
| Upper arm, Z1.200 | 117.6 × 102.1 mm | 117.1 × 113.2 mm |
| Upper arm, Z1.250 | 116.0 × 98.9 mm | 108.7 × 121.1 mm |
| Forearm, Z1.075 | 110.9 × 104.2 mm | 114.6 × 102.0 mm |
| Forearm, Z1.100 | 115.1 × 101.7 mm | 116.1 × 101.3 mm |

¹ The old neck ends obliquely here; its small depth is a partial section, not the full circumference. The candidate neck extends 10 mm farther into the shirt. Slice differences therefore combine reshaping and vertical relocation, not just scaling.

가슴의 깊이/폭은 약 .716에서 .602으로 바뀌어 둥근 원통 단면을 줄였습니다. 아래 목은 더 평행한 기둥으로 정리되었습니다. The chest is broader and shallower, while the neck flares less toward the base. Full surface judgement still requires the actual renders.

## 법선과 퇴화 / Normals and degeneracy

새로 퇴화한 삼각형은 없습니다. 머리·양팔에 새로 뒤집힌 삼각형이나 법선은 없습니다. 몸통 목둘레에는 극도로 가느다란 기존 삼각형 4개의 수치상 방향 변화가 있습니다. 원래 면적은 2.1×10⁻¹²–9.7×10⁻¹² m²이며, 변형 후에도 최대 6.5×10⁻¹¹ m²입니다. 정밀도에 민감한 목둘레의 거의 일직선인 삼각형이며, 유의미한 크기(원래 면적 ≥10⁻¹⁰ m²)의 새 법선 반전은 0개입니다. 세부 위치는 `geometry_audit.json`에 남겼습니다.

No new degenerate triangles were introduced. Four pre-existing microscopic collar slivers change numerical winding after deformation; no significant-area triangle, arm triangle or head triangle gains an opposed normal. A separate 7,163-point volume-grid check finds no nonpositive local Jacobian; minimum determinant .3337. This is a bounded local-fold check, not exhaustive self-intersection certification.

## 팔뚝 검증 구간 / Forearm test window

이전 고정 높이 Z1.02–1.12 m 구간의 AABB 깊이는 129.9 mm에서 135.0 mm로 늘어나지만, 팔꿈치가 내려가 같은 높이에서 더 위쪽 원본 정점을 포함하기 때문입니다. 새 구간은 원본 Z1.032–1.145 m에 해당합니다. 실제 얇은 단면의 깊이는 Z1.075에서 102.0 mm, Z1.100에서 101.3 mm입니다. 기울어진 축의 10 cm 구간 전체 AABB를 인체 단면의 두께로 해석하면 안 됩니다.

The old fixed 100 mm height-window AABB grows because the elbow relocation changes which source vertices it includes. Actual forearm section depth remains about 102 mm. Use local slices or the same anatomical vertex region for thickness validation; do not reshape a healthy shaft solely to fit the old world-height AABB.
