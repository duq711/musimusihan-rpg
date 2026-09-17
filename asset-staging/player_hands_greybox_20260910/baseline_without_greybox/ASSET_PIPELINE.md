# Dark-fantasy visual asset pipeline

이 패스는 유료 에셋 구매 없이 제작했다. 비트맵은 Codex 내장 ImageGen으로 생성했고, 장비·소품·감시자·롤백 모델을 포함한 GLB 14종은 Godot 4.7의 `SurfaceTool`, 기본 메시, `GLTFDocument`로 절차 생성했다. 성소지기에는 공식 BodyParts3D CC BY 4.0 데이터를 게임용 GLB로 재포장한 고해상도 골격 1종을 추가해 전체 GLB는 15종이다.

## 결과물

- AI 적 콘셉트 원본(런타임에서는 사용하지 않음): `assets/ai/enemies/`
- AI 재질: `assets/ai/materials/`
- AI VFX: `assets/ai/vfx/`
- AI 성소 이동 지도: `assets/ui/sanctuary_route_map.png`
- 3D GLB: `assets/3d/dark_fantasy/`
- 런타임 적 GLB: `sanctuary_warden_3d.glb`, `anatomical_skeleton_cc_by_4.glb`
- 롤백 전용 구형 성소지기: `ossuary_keeper_3d.glb`, `reference_skeleton_3d.glb` — 런타임 미사용
- 렌더 QA: `artifacts/visual_qa/`
- 재사용 가능한 화면 캡처 하네스: `tests/visual_capture.gd`
- 시각 구조 회귀 테스트: `tests/visual_asset_test.gd`

원본 스타일 기준은 `../concept-art/01_hanging_cathedral_descent.png`와 `../concept-art/02_flooded_ossuary_stalker.png`다. 새 골격은 사용자가 제공한 단일 정면 참고 이미지의 비율·노화된 뼈 색·비대칭 자세를 기준으로 통합했다. 사진 한 장에 보이지 않는 후면과 실제 입체 해부 구조는 BodyParts3D 데이터로 보완했으며, 원본 사진의 픽셀·워터마크·흰 배경은 게임에 포함하지 않았다. 이동 지도는 사용자가 제공한 상용 게임 화면을 레이아웃·사용 흐름 참고로만 사용해 새로 생성했으며, 해당 화면의 픽셀·로고·문구·고유 건축물은 포함하지 않았다. 생성 원본 `../generated-assets/sanctuary-route-map.png`을 동일한 SHA-256으로 런타임 경로에 복사했다.

## ImageGen 최종 프롬프트 세트

각 항목은 별개의 생성 호출로 만들었다. 적 컷아웃은 최초 콘셉트와 색 기준으로만 보존하며, 현재 게임에는 같은 실루엣을 바탕으로 만든 실제 3D GLB를 사용한다. 모든 컷아웃은 실제 알파 채널을 확인했다.

1. **Sanctuary warden** — `Production-ready full-body isolated realistic dark-fantasy sanctuary sword warden; hooded undead knight, corroded black plate and mail, long weathered sword, teal spectral eye light, grim wet Gothic styling, front three-quarter game cutout, genuine transparent background, no floor, scenery, text, UI, frame, or checkerboard.`
2. **Legacy Ossuary keeper concept** — `Production-ready full-body isolated realistic starving ossuary keeper; emaciated hooded corpse, hanging skin and bone charms, corroded cleaver, cyan-teal glowing eyes, wet black Gothic styling, front three-quarter game cutout, genuine transparent background, no floor, scenery, text, UI, frame, or checkerboard.` 이 이미지는 구형 `ossuary_keeper_3d.glb`의 콘셉트 기록일 뿐이며 현재 런타임 골격에는 사용하지 않는다.
3. **Ossuary wall** — `Seamless square realistic ancient black cathedral masonry base-color texture; wet rough blocks, deep mortar, eroded skull reliefs, soot and mineral streaks, neutral flat lighting, tileable edges, no perspective, objects, text, border, or vignette.`
4. **Wet flagstone** — `Seamless square realistic wet ancient cathedral flagstone floor base-color texture; irregular black slabs, deep joints, damp grime and subtle cold reflections, orthographic neutral lighting, tileable edges, no perspective, objects, text, border, or vignette.`
5. **Extraction portal** — `Create a production-ready transparent PNG game VFX sprite for a realistic first-person dark fantasy dungeon. Subject: an oval Gothic extraction portal seal viewed perfectly front-on, formed from concentric weathered occult runes, thin broken iron filigree, smoky cyan-teal spectral energy, subtle sparks, and a dim cold core. Grim, ancient, dangerous, restrained photorealistic rendering; blackened metal and bone-white engraved markings; strong readable silhouette. The seal itself must fill most of the canvas and remain centered. True transparent background and transparent empty spaces; no wall, no doorway, no floor, no scenery, no text, no UI, no frame, no checkerboard. Single isolated asset.`
6. **Trap rune** — `Create a production-ready transparent PNG game VFX decal for a realistic first-person dark fantasy dungeon. Subject: a circular top-down trap rune made from cracked cyan-teal occult lines, ancient sanctuary glyphs, small blood-dark iron pins, soot, and restrained ghostly glow. Perfect orthographic top-down view, centered, strong readable ring-and-cross geometry, weathered and dangerous, photorealistic material response. True transparent background around and between the rune strokes; no floor tile, no stone slab, no scenery, no text, no UI, no frame, no checkerboard. Single isolated asset.`
7. **Torch flame** — `Create a production-ready transparent PNG VFX sprite for a realistic dark fantasy torch. Subject: one tall irregular flame with a white-hot yellow core, amber-orange body, deep ember-red wisps, a few tiny sparks and faint smoke, dramatic but physically believable. Perfect front view, centered, fills most of the canvas vertically. True transparent background; no torch handle, no brazier, no wall, no ground, no scenery, no text, no UI, no frame, no checkerboard. Single isolated asset.`
8. **Ancient oak** — `Create a production-ready seamless square PBR base-color texture for realistic dark fantasy game assets. Material: centuries-old blackened oak planks from a Gothic reliquary chest and round shield, dense natural wood grain, split fibers, shallow knife scars, soot, waxy grime in crevices, faint dried dark stains, restrained brown-black palette. Perfectly tileable on all four edges, orthographic surface scan, evenly lit and color-neutral, no perspective, no vignette, no cast shadows, no metal, no objects, no text, no symbols, no border. High-frequency detail but readable at game scale.`
9. **Pitted black iron** — `Create a production-ready seamless square PBR base-color texture for realistic dark fantasy game assets. Material: pitted blackened medieval iron and aged sword steel, fine hammer marks, patches of reddish-brown rust, worn cold silver edges, oily soot, small scratches, restrained nearly-black gunmetal palette. Perfectly tileable on all four edges, orthographic surface scan, evenly lit and color-neutral, no perspective, no vignette, no cast shadows, no object silhouette, no blade shape, no text, no symbols, no border. High-frequency detail suitable for weapons, shield rims, chains, and chest bands.`
10. **Sanctuary route map** — `Use case: stylized-concept. Asset type: mobile dark-fantasy RPG destination map background artwork. Primary request: Create a production-ready travel map for the underground refuge district of the Sanctuary of Echoes. Show a safe Pilgrim's Hideaway at the center, a small merchant workshop glowing with warm firelight in the left/lower region, and a threatening monastery dungeon gateway leaking deep shadow and subtle red fissure-light in the right/upper region. The two destinations must read instantly as distinct landmarks, with calm open visual space around them for later UI pins. Scene/backdrop: A subterranean sanctuary zone enclosed by sheer cliffs, ruined medieval masonry, broken cloisters, and cavern walls. Narrow paths and small stone bridges connect the central refuge, merchant workshop, and dungeon gate. Style/medium: Painterly isometric game map, realistic environment concept art, grim medieval dark fantasy. Composition/framing: Portrait 4:5 crop; top-down oblique/isometric view; merchant left/lower, dungeon right/upper, central hideaway readable. Lighting/mood: Dim smoky cavern atmosphere; warm ember-amber merchant light against cold dungeon shadow and restrained crimson fissures. Constraints: Background artwork only; no UI, buttons, pins, icons, labels, words, letters, numbers, logos, watermark, modern objects, or prominent characters; original setting and architecture only.`

감시자 1차 결과의 옅은 체크무늬 배경은 별도 편집 호출로 제거했다: `Remove the pale checkerboard and faint floor completely; preserve the exact armored character, sword, edges, and canvas; output genuine transparency.`

## 통합 원칙

- 기존 충돌, 적 AI, 공격 판정, 상호작용 영역은 유지한다.
- 런타임 적은 87메시 감시자 `sanctuary_warden_3d.glb`와 202파트·513,164삼각형 무장 없는 골격 `anatomical_skeleton_cc_by_4.glb`이며, `Sprite3D`나 빌보드를 전혀 사용하지 않는다. 구형 성소지기 두 모델은 롤백용으로만 남겨 두고 런타임에서는 불러오지 않는다.
- 새 골격은 12쌍의 갈비뼈, 24개 척추, 분리된 요골·척골과 경골·비골, 좌우 각각 손뼈 27개와 발뼈 26개, 24파트 두개골과 발광하지 않는 빈 안와로 구성한다. 갑옷·후드·망토·무기 메시를 포함하지 않는다.
- `PelvisPivot`, `TorsoPivot`, `HeadPivot`, 좌우 어깨·팔·다리 피벗과 `ElbowLPivot`·`ElbowRPivot`, `WristLPivot`·`WristRPivot`, `KneeLPivot`·`KneeRPivot`, `AnkleLPivot`·`AnkleRPivot`을 AI 상태에 따라 직접 회전해 대기·추적·공격 준비·사진 참조 타격·경직·사망 자세를 만든다. 감시자의 `WeaponPivot`은 기존 검 애니메이션에 사용한다.
- 적 모델은 발바닥 `y=0`, 정면 `-Z` 계약을 따르고, 시각 메시에는 충돌을 넣지 않아 기존 캡슐 하나만 판정에 사용한다.
- 검·방패·횃불 GLB는 기존 카메라 피벗의 자식으로 장착한다.
- 상자 뚜껑 GLB 파츠는 기존 `LidPivot` 아래로 재배치해 열림 애니메이션을 유지한다.
- 함정 GLB는 시각 전용이며 기존 `Spikes`와 트리거 영역을 유지한다.
- 벽·바닥은 월드 트라이플래너 매핑으로 박스 크기에 따른 늘어짐을 줄인다.
- 포털·불꽃은 AI 알파 텍스처, 발광 재질, `CPUParticles3D`를 조합한다.

## BodyParts3D 출처와 변경

`anatomical_skeleton_cc_by_4.glb`는 BodyParts3D release 4.0의 99% OBJ archive에서 완전한 골격을 이루는 공식 `FJ…` 요소 202개를 선택해 만들었다. 원본 정점과 해부 형상은 유지한 채 OBJ를 GLB로 묶고, mm/Z-up 좌표만 metre/Y-up으로 bake했다. 라이선스는 CC BY 4.0이며 필수 저작자 표시, 공식 링크, 변경 내역, 원본·GLB SHA-256은 [`THIRD_PARTY_ASSETS.md`](THIRD_PARTY_ASSETS.md)에 기록했다.

## 렌더러와 검증

데스크톱 기본 렌더러는 Forward+이며 TAA, SSAO, SSIL, glow를 켰다. Windows의 RTX 4090에서는 Vulkan/Forward+를 사용하고, 모바일 설정은 Compatibility를 유지한다. 현재 작업 호스트는 Apple M4이므로 4090 자체 측정은 하지 못했지만 Metal/Forward+와 OpenGL Compatibility 양쪽에서 실제 프레임 렌더를 완료했다.

검증 스크립트:

```sh
godot --headless --path . --script res://tests/visual_asset_test.gd
godot --headless --path . --script res://tests/smoke_test.gd
```

적 전용 렌더 회귀는 `DARK_QA_VIEW=enemy_front|enemy_side|enemy_close|enemy_attack|enemy_reference`와 `DARK_QA_VARIANT=warden|keeper|skeleton`을 `tests/visual_capture.gd`에 넘겨 촬영한다. 자동 테스트는 두 적 아래 `Sprite3D`가 0개인지, 감시자의 무기 메시, 골격의 202개 공식 ID·좌우 12쌍 갈비뼈·24개 척추·24파트 두개골·좌우 손뼈 27개·좌우 발뼈 26개·빈 안와·관절 계층, 공통 캡슐·독립 피격 재질·실제 손 메시의 공격 포즈 이동까지 확인한다.
