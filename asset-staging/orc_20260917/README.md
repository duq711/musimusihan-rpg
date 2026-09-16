# 오크 제작 자료 / Orc production sources

`source_used.zip`에는 사용한 12개 애니메이션 FBX, 원본 기본 메시·도끼 FBX, albedo/normal/AO/metallic/gloss TGA가 들어 있다. 사용자가 제공한 Downloads 원본은 이동·변경하지 않았다. 나머지 제공 파일도 `source_manifest.json`에 크기와 SHA-256을 기록했다.

The archive preserves the original files used by the conversion. Downloads originals remain untouched; the manifest also records the other supplied files.

1. `prepare_textures.py`: Pillow로 텍스처 해상도 조절·gloss 반전. / Resize textures and invert gloss.
2. Godot 4.7 `--headless --path asset-staging/orc_20260917/import_project --script build.gd`: 모든 실제 클립과 스킨을 게임 리소스로 저장. / Build the game resource with original clips and skinning.
3. 프로젝트 루트 경로와 Downloads 위치는 현재 Mac 기준이므로 다른 환경에서는 스크립트의 ROOT와 입력 경로를 조정한다. / Adjust local paths when reproducing on another machine.

Blender 5.2 FBX importer의 `KeyError: ork_Reference` 때문에 Godot FBXDocument로 변환했다. 제작 중간의 inspect/measure 스크립트와 로그는 로컬 진단 자료이며 납품 원본과 구분한다. / Godot's FBX importer was used after Blender failed on the original binding.
