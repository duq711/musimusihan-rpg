# 방패 파손 제작 / Shield damage production

Mac Blender 5.2.1에서 기존 방패의 복사본을 가공했습니다. 원본 `godot-game/assets/3d/player/sword_shield/round_shield.glb`는 상 단계로 그대로 사용합니다. `build_shield_damage.py`는 원본을 읽어 중·하 단계의 `.blend` 및 별도 GLB를 만듭니다. 사용자의 팔·손·파지 마커는 변경하지 않습니다.

Copies of the existing shield were fractured in Mac Blender 5.2.1. The original GLB remains the high stage. The build script creates separate medium/low Blender sources and GLBs while preserving the arms, hands and all grip markers.

- 중 / Medium: 위쪽 두 부분의 철테 단절·불규칙한 나무 결 파단·가는 관통 균열 / Two upper rim breaks, uneven exposed wood ends and a narrow through-crack.
- 하 / Low: 같은 파손 확대·옆면 추가 결손·넓어진 상단 파편 경계 / Expanded damage, side losses and a larger broken upper silhouette.
- Blender X/Z 평면의 위쪽 왼편 105–120° 파손은 실제 기본 대기·가드 양쪽에서 보입니다. / Damage in the upper-left 105–120° arc is visible in both production idle and guard.
- 닳은 겉면의 UV·꼭짓점 음영 색을 보존하며 새 목재 단면에는 별도 거친 재질을 씁니다. / Outer UVs and vertex occlusion colors are retained; exposed end grain uses a separate rough material.
- 원래 철테는 열린 U자 단면입니다. 절단 후 Boolean의 잘못된 외부 뚜껑 면을 제외하고, 메시 정점이 원래 원형 범위를 넘지 않는지 검사합니다. / The original iron rim is an open U profile. Invalid Boolean exterior caps are excluded and vertex bounds are checked against the original disk.

생성: `/Applications/Blender.app/Contents/MacOS/Blender --background --threads 2 --python asset-staging/shield_damage_20260919/build_shield_damage.py` (프로젝트 루트에서 실행). 실제 코드의 마모·임계값·시험 결과는 `godot-game/docs/SHIELD_DAMAGE.md`를 따릅니다. `baseline/`은 로컬 변경 전 보존본이며 공유 산출물에 포함하지 않습니다.

Run the command above from the project root. Runtime wear, thresholds and validation are documented in `godot-game/docs/SHIELD_DAMAGE.md`. The local `baseline/` archive is retained separately and excluded from publication.
