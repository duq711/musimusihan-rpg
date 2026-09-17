# 오크 NPC / Orc NPC

사용자가 2026-09-17 제공한 `animation fbx/`, `Base mesh FBX/`, `texture/`의 리깅된 오크와 양손 도끼. 출처·제작자·라이선스 문서는 제공 폴더에서 발견되지 않아 별도 저자나 라이선스를 추정하지 않았다.

Rigged orc and both axes supplied by the user on 2026-09-17. No author or license document was found in the supplied folders; none is invented here.

## 게임 연결 / Runtime

- `orc.scn`: 원본 스킨, 뼈대, 12개 애니메이션, 내장 텍스처. / Original skin, rig, 12 clips and embedded textures.
- `scripts/orc_enemy.gd`: 기존 `DungeonEnemy`의 탐지·추적·피격·방패 방어·처치 보상을 사용한다. / Uses existing enemy detection, chase, damage, shield and reward behavior.
- FBX의 +Z 정면을 게임의 -Z 정면으로 회전한다. 수평 루트 이동은 제거하고 수직 움직임을 유지한다. 실제 이동은 기존 충돌 캐릭터가 처리한다. / Rotates +Z facing to -Z and removes horizontal root travel; the physics character owns movement.
- 대기 `idle1`, 추적 `run`/`walk`, 공격 `atack1..3`, 경직 `gethit`의 첫 반응, 사망 `death`. 나머지 idle2/roar/jump/wound는 원본 클립으로 보존하지만 이번 AI가 자동 실행하지 않는다. / Remaining clips are preserved, not newly wired into AI.
- 준비 0.7초, 활성 0.24초, 복귀 0.92초의 기존 전투 시간을 유지한다. 활성 0.09초의 1회 타격에 각 클립의 실제 타격 자세를 맞췄다. / Retains existing attack windows and maps each source strike to the single damage event.
- 도끼는 원본 스킨으로 손을 따른다. 검 전용 검날 충돌 프록시를 도끼로 위장하지 않는다. 기존 정면 방패 방어·저스트 가드는 적용된다. / Axes follow their original rig; shield blocking works, but the sword-only blade-clash proxy is not used for axes.

## 변환 / Conversion

Godot 4.7 FBXDocument(ufbx)로 가져왔다. Mac Blender 5.2의 FBX 가져오기는 이 파일의 `ork_Reference` 바인드 처리에서 KeyError가 발생했다. 원본을 수정하지 않고 Godot의 지원 경로로 변환했다. 몸 텍스처 2K, 도끼 1K, mipmaps. gloss를 반전해 roughness를 만들고 metallic/normal/AO는 제공 데이터를 사용한다. 별도 emission/height 맵은 보존한 원본 목록에 기록하며 런타임에 적용하지 않는다.

Imported using Godot 4.7 FBXDocument after Blender's importer failed on this FBX binding. Body maps are 2K and axe maps 1K, with mipmaps. Gloss is inverted to roughness; supplied metallic, normal and AO maps are used.

재현 자료: 저장소 루트의 `asset-staging/orc_20260917/prepare_textures.py`, `import_project/build.gd`, `source_manifest.json`, `source_used.zip`. 원본 Downloads 폴더는 보존한다. SCN과 원본 압축파일은 Git LFS를 사용한다.

Reproduction materials and original source archive are in `asset-staging/orc_20260917/`; the Downloads originals remain untouched. Binary assets use Git LFS.
