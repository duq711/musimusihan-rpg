# 양손 디테일 제작 도구

모든 Python 도구는 Blender의 Python으로 `--background`에서 실행한다. 기존 앱 세션에 연결하지 않으며, 원본 입력 파일을 수정하지 않는다. 제작·비교 렌더의 출력 디렉터리는 매번 새로운 경로를 사용한다.

- `build_hands_detailed.py`: 원본 양팔 및 플레이어 GLB를 읽어 양손 디테일, 편집 가능한 `.blend`, 개별 GLB와 검토 렌더를 만든다.
- `hand_detail_geometry.py`: 제작기의 동봉 모듈. 손 표면 조각, 곡면 손톱, 말린 장갑 끝과 봉제선, 소매 디테일을 생성한다.
- `verify_hands_detailed.py`: 원본과 출력물을 독립적으로 다시 열어 관절·스킨·손톱 부착·기하 변화를 검증한다.
- `render_detail_comparison.py`: 기존 그레이박스와 디테일을 같은 배율·조명에서 렌더한다.

프로젝트 루트에서 실행 예:

```sh
nice -n 10 /Applications/Blender.app/Contents/MacOS/Blender \
  --background --factory-startup --python-exit-code 1 \
  --python asset-staging/player_hands_detail_20260910/tools/build_hands_detailed.py \
  -- --input-dir asset-staging/player_hands_greybox_20260910/input \
  --output-dir asset-staging/player_hands_detail_20260910/mac_output/new_iteration

nice -n 10 /Applications/Blender.app/Contents/MacOS/Blender \
  --background --factory-startup --python-exit-code 1 \
  --python asset-staging/player_hands_detail_20260910/tools/verify_hands_detailed.py \
  -- --input-dir asset-staging/player_hands_greybox_20260910/input \
  --output-dir asset-staging/player_hands_detail_20260910/mac_output/new_iteration
```

GLB는 손목의 원래 좌표를 유지한다. `both_hands_detailed_preview.glb`는 좌우를 벌려 배치한 검토용이며, 게임에는 개별 `left_hand_detailed.glb`와 `right_hand_detailed.glb`를 사용한다. 제작기의 삼각형 예산은 한쪽 팔 전체를 기준으로 하며, 리깅의 관절 수를 줄이는 옵션이 아니다.
