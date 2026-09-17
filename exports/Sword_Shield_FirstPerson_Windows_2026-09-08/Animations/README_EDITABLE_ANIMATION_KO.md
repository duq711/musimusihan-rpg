# Windows 편집 안내

`Sword_Shield_Captured_Motion.blend`를 Blender에서 여세요. **Blender 5.2.1 LTS에서 저장·재오픈 검증**했습니다. 기본 장면은 `ready`, 시작 프레임은 1이며 실제 1인칭 카메라가 포함됩니다.

- 위쪽 Scene 선택기: `ready`, `right_diagonal`, `left_reverse`, `overhead`, `shield_raise`, `block_impact`.
- `.blend`: **30fps, 프레임 1–34**. Outliner의 `LeftHand`/`RightHand` 아래 `HandRig`를 선택하고 Pose Mode에서 실제 손가락 뼈를 편집하세요. 한 손당 16개 뼈이며, 검·방패·소매에도 별도 변환 키가 있습니다.
- 동작별 `.glb`: 먼저 Blender fps를 30으로 설정한 뒤 가져오세요. glTF는 0초부터라 Blender에서 **프레임 0–33**을 사용합니다. 각 파일에 전체 장비와 양손, 애니메이션 1개가 들어 있습니다.
- 모두 실제 게임의 **34개 기록 표본을 베이크한 FK 키프레임**입니다. 프레임 사이 보간은 선형입니다. 새 모션이나 AI 영상이 아니며, IK 제어 리그와 게임 입력·피해 로직은 포함하지 않습니다.
- 사용된 이미지 7개는 `.blend`와 GLB 안에 내장되어 있습니다. 외부 이미지 없이 열립니다. Material Preview에서 재질을 확인하세요. 렌더러의 조명·색 관리에 따라 밝기는 달라질 수 있습니다.

검·방패의 기존 atlas UV와 정점 AO를 보존했습니다. GLB는 표준 albedo 범위에 맞춰 1보다 큰 검날 테두리·실밥 색 배수만 1로 제한하며, 원래 값은 material extras와 .blend에 남아 있습니다. 패키지의 `concept_forged_steel.png`는 현재 메시와 연결되지 않은 과거 재질용이므로 애니메이션 파일에는 포함되지 않습니다.

재오픈 검증: 6장면의 대표 5프레임에서 실제 피부·뼈·무기·소매·카메라를 대조했습니다. 피부 최대 오차는 .blend **0.000929mm**, GLB 재가져오기 **0.000943mm**입니다. 자세한 기록은 `animation_export_report.json`, `reopen_validation.json`에 있습니다.
