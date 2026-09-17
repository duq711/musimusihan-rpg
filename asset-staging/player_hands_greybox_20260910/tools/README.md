# 현재 제작 도구

사용자는 2026-09-10 이번 양손 작업을 Mac에서 진행하도록 명시했다. `build_hands_greybox.py`와 `verify_hands_greybox.py`는 실제 Mac Blender 5.2.1 백그라운드 실행을 통과했다. 기존 창/원본을 수정하지 않고 새 출력 폴더만 사용한다.

저장소 루트에서 새 폴더 이름으로 실행한다.

```sh
nice -n 10 /Applications/Blender.app/Contents/MacOS/Blender --background --factory-startup --python-exit-code 1 --python asset-staging/player_hands_greybox_20260910/tools/build_hands_greybox.py -- --input-dir asset-staging/player_hands_greybox_20260910/input --output-dir asset-staging/player_hands_greybox_20260910/mac_output/new_revision
nice -n 10 /Applications/Blender.app/Contents/MacOS/Blender --background --factory-startup --python-exit-code 1 --python asset-staging/player_hands_greybox_20260910/tools/verify_hands_greybox.py -- --output-dir asset-staging/player_hands_greybox_20260910/mac_output/new_revision
```

제작기는 양손을 개별 장면에 읽고 복제한다. 겹친 장갑 껍질은 복제 출력에서 제외하고 실제 손 표면에 장갑 영역을 표시한다. Armature 앞의 디시메이션으로 한쪽 약 10,000삼각형을 목표로 하며 본·바인드 포즈·웨이트·경계·원본 해시를 검사한다. GLB는 활성 장면만 내보내고 최대 8개 웨이트를 지원한다. 원본 파일과 원본 Blender 장면은 보존한다.

검증기는 편집 원본과 좌우 GLB를 다시 열어 16본·회색 재질·웨이트·좌우 방향과 손가락별 실제 스킨 변형, 손목 고정을 검사한다. Godot 접촉/통합 검증은 프로젝트 테스트룸과 테스트를 별도로 실행한다. 시각 품질은 반드시 실제 렌더를 보고 판단한다.

`build_hands_greybox_windows.py`와 `run_windows.ps1`는 처음 준비한 Windows 전용 이력이다. 이후 실행 중 발견한 활성 장면 내보내기 수정과 단일 손 표면 개선은 현재 `build_hands_greybox.py`에 들어 있다. 현재 작업 재제작에는 위 명령을 사용한다.
