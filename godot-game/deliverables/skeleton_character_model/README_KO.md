# 해골 캐릭터 3D 모델

- 형식: glTF 2.0 Binary (`.glb`)
- 구조: 202개 개별 해부학 메시
- 폴리곤: 513,164 삼각형
- 단위/축: metre, Y-up
- 모델 정면: +Z
- Godot의 -Z 정면에 맞출 때: 루트 Y축을 180도 회전
- 스킨/내장 애니메이션: 없음

`skeleton_character_bodyparts3d.glb`는 중립 자세의 순수 3D 모델입니다. 게임에서 보인 관절 애니메이션과 사진 참조 자세는 Godot 프로젝트의 `scripts/enemy.gd`가 런타임에 생성합니다.

`weathered_bone_albedo.png`는 게임에서 사용한 노화된 뼈 색상 텍스처입니다. 이 모델은 UV 대신 Godot의 triplanar 매핑으로 텍스처를 적용했습니다.

사용하거나 재배포할 때는 `ATTRIBUTION.md`의 BodyParts3D 저작자 표시와 CC BY 4.0 링크를 함께 포함해야 합니다.
