# Creep 로컬 에셋 변환 / Local Creep asset conversion

이 저장소에는 변환 코드만 공유합니다. CGTrader의 [Creep Creature](https://www.cgtrader.com/free-3d-models/character/fantasy-character/creep-creature)는 **Royalty Free License (no AI)** 에셋입니다. 모델·텍스처 원본과 재사용 가능한 변환본을 공개 저장소에 업로드하지 않습니다. [공식 약관](https://www.cgtrader.com/pages/terms-and-conditions)의 게임 내 포함·추출 방지 조건을 따라야 합니다.

Only conversion code is shared here. Obtain the asset through its official page under its **Royalty Free License (no AI)**. Do not publish reusable source or converted model/texture files. Follow the official terms for incorporating the asset into a distributed game.

Blender 5.2.1 LTS에서 다음 명령을 실행합니다. 경로는 본인이 다운로드한 파일 위치로 바꿉니다. 스크립트는 네트워크 접속·다운로드·Git 작업을 하지 않습니다.

Run with Blender 5.2.1 LTS, replacing the input paths with your licensed local downloads. The script does not access the network, download files, or run Git.

```sh
/Applications/Blender.app/Contents/MacOS/Blender \
  --background --factory-startup --disable-autoexec --python-exit-code 1 \
  --python tools/build_creep_asset.py -- \
  --fbx /path/to/Creep.fbx --textures /path/to/tex.rar
```

변환 후 Godot 프로젝트가 새 GLB를 가져오게 합니다. 아래 명령은 편집기 창을 열지 않습니다. / Then import the GLB into Godot's resource cache without opening an editor window:

```sh
/path/to/Godot --headless --path godot-game --editor --import --quit
```

- `exports/Creep_20260917/source/`: 원본 FBX·RAR·해제한 텍스처 보존 / preserved source files.
- `exports/Creep_20260917/derived_textures/`: 2K 파생 텍스처 / resized 2K copies.
- `exports/Creep_20260917/build_manifest.json`: 해시·치수·클립·재질 확인 결과 / hashes, bounds, clips and materials.
- `godot-game/assets/licensed/creep/creep.glb`: 로컬 게임용 출력 / local runtime output.

모두 원본 자료가 포함되는 비공개 로컬 산출물입니다. `.gitignore` 적용 상태를 확인하고 바이너리를 강제 추가하지 마세요. 다른 버전의 입력 파일은 기존 원본을 덮어쓰지 않도록 `--staging`에 새 폴더를 지정합니다.

These outputs contain licensed content and must remain local. Keep them ignored by Git; never force-add the binaries. Use a different `--staging` directory for changed source versions instead of overwriting preserved originals.

원본 리그와 17개 애니메이션을 유지합니다. 대기 자세의 높이를 1.95m로 균등 조정하고 바닥을 Y=0, 전방을 Godot -Z로 맞춥니다. 전역 래퍼에서 변환하므로 개별 뼈 변환은 변경하지 않습니다. OpenGL normal과 원본 색·거칠기·금속·AO 맵을 연결하며 텍스처는 GLB 안에 포함합니다.

The full rig and 17 animations are preserved. A static parent transform normalizes the idle height to 1.95m, ground to Y=0 and forward to Godot -Z; individual bones remain unchanged. Original color, OpenGL normal, roughness, metallic and AO textures are embedded.

Godot용 변환본은 정점당 최대 8개 뼈 영향으로 제한합니다. 원본 최대 10개 중 한도를 넘는 정점은 62개이며, 상위 8개 유지·정규화 시 제외되는 가중치는 최대 5.22%입니다. 원본 가중치는 보관 파일에 그대로 남고 변환 보고서에 차이를 기록합니다.

The Godot copy keeps and renormalizes the strongest eight skin influences per vertex. The source has up to ten; 62 vertices exceed eight, with at most 5.22% discarded weight at a vertex. Original weights remain in the preserved source; the build manifest records the conversion limit.

| 원본 접미사 / Source suffix | 출력 / Output |
| --- | --- |
| Idle1_Action / Idle2_Action | idle / idle_crouched |
| Walk1_Action / Walk2_Action / Crouch_Action | walk_calm / walk / walk_crouched |
| Damage_Action / Death_Action | hit / death |
| Bite_Action / Punch_Action | bite / punch |
| Eating_Action / Roar_Action / Sniff_Action | eat / roar / sniff |
| JumpIn_Action / JumpOut_Action | spawn_jump / despawn_jump |
| Sleep_start_Action / Sleep_loop_Action / Sleep_finish_Action | sleep_start / sleep_loop / sleep_finish |

glTF에는 표준 반복 플래그가 없으므로 게임에서 `idle`·`walk` 반복, `hit`·`death`·공격 비반복을 설정합니다. 원본 공격 전체 4.8초는 그대로 보존됩니다. `punch`는 1.2초짜리 두 타격을 네 번, `bite`는 1.6초 물기를 세 번 반복하므로 단일 게임 공격으로 쓸 때 첫 사이클만 사용합니다. 원본 25fps를 유지하여 재생 시간이 바뀌지 않습니다.

Set animation loop modes in the game: glTF has no core loop flag. Full 4.8-second source attacks are retained. `punch` repeats a two-contact 1.2-second sequence four times; `bite` repeats a 1.6-second bite three times. Use only the first cycle for a single gameplay attack. Original 25fps timing is preserved.

Godot 기본 가져오기는 `_loop` 접미사를 해석하므로 GLB의 `sleep_loop`는 게임 리소스에서 `sleep`으로 표시되고 반복이 설정됩니다. 다른 16개 이름은 유지됩니다. `idle`·`walk` 길이는 4.84초, `hit`는 1.2초, `death`는 2.4초입니다.

Godot's default importer interprets the `_loop` suffix: GLB `sleep_loop` becomes `sleep` with looping enabled. The other 16 names remain unchanged. `idle` and `walk` last 4.84 seconds, `hit` 1.2 seconds, and `death` 2.4 seconds.
