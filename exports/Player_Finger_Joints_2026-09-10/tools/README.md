# 제작 및 검증 도구

Blender 도구는 Blender 5.2.1 LTS에서 별도 백그라운드 프로세스로 실행했다. 명령의 경로는 실행 환경에 맞게 지정한다. 출력 디렉터리는 기존 원본과 분리한다.

```sh
blender --background --factory-startup --python-exit-code 1 \
  --python build_finger_joints.py -- \
  --input-dir /path/to/previous/detailed/iteration_03 \
  --output-dir /path/to/new/empty/output

blender --background --factory-startup --python-exit-code 1 \
  --python verify_finger_joints.py -- \
  --input-dir /path/to/original/greybox/input \
  --output-dir /path/to/articulated/output
```

제작 입력에는 기존 상세 납품의 `bilateral_hands_detailed.blend`, 좌우 상세 GLB, `build_report.json`이 필요하다. 독립 검증 입력에는 원래 플레이어의 `left_arm.glb`, `right_arm.glb`가 필요하다. 이 원본 자료는 프로젝트의 이전 제작 디렉터리에 보존되어 있으며 현재 패키지에 중복 포함하지 않는다.

`encode_joint_sequence.py`는 Pillow가 설치된 Python에서 실행한다. 실제 Godot GPU 캡처 디렉터리의 226개 순차 PNG와 `capture_manifest.json`을 검증하고, 같은 크기의 GIF로 인코딩한다. 각 PNG는 그대로 보존된다.

```sh
python3 encode_joint_sequence.py --capture-dir /path/to/fresh/GPU/captures
```

Godot 실행 코드는 이 게임 프로젝트에 통합되어 있다. 패키지의 GLB를 다른 엔진에서 사용할 경우 각 관절의 로컬 X축 회전과 `Joint_<digit>_<joint>` 교정 값을 함께 구동해야 한다. Blender에서 수동으로 검토하는 방법은 상위 디렉터리의 `README_BLENDER.md`에 있다.
