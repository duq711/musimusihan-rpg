# 양손 파지와 검·방패 동작 참고

2026-09-07. 무기를 손에 쥔 인물의 준비 자세, 세 가지 베기, 방패 올리기와 막힘 충격을 Codex 내장 ImageGen으로 생성했다. 무기만 놓은 회전 도면이 아니라 손·손목·팔꿈치가 연결된 동작을 위한 자료다.

| 동작 | 생성한 상·하·좌·우 참고 |
| --- | --- |
| 준비 파지 | [동일 준비 자세 네 방향](ready_four_directions_reference.png) |
| 우측 대각 베기 | [준비·타격·후속·복귀 네 단계](right_diagonal_reference.png) |
| 좌측 역베기 | [준비·타격·후속·복귀 네 단계](left_reverse_reference.png) |
| 상단 내려베기 | [준비·타격·후속·복귀 네 단계](overhead_reference.png) |
| 방패 올리기 | [준비·들기·덮기·정착](shield_raise_reference.png) |
| 방패 막힘 충격 | [가드·압축·반동·복귀](block_impact_reference.png) |

[1인칭 베기 참고](first_person_attack_keys_reference.png), [1인칭 방어 참고](first_person_guard_keys_reference.png), [최초 파지 연구](ready_grip_v1.png)도 보존했다. 총 9개의 원본 시트이며 생성 이미지 자체는 수정하지 않았다.

정확한 프롬프트와 생성 경로는 [최초 생성 기록](ready_grip_generation.json), [베기 프롬프트](action_generation_prompts.json), [베기 생성 기록](action_generation_records.json), [추가 프롬프트](remaining_generation_prompts.json), [추가 생성 기록](remaining_generation_records.json)에 있다. 생성 방식은 내장 ImageGen이며 별도 유료 API나 외부 영상 생성 서비스를 사용하지 않았다.

생성 이미지에는 일부 방향 중복과 동작 불일치가 있다. 최초 파지 시트는 외부 방향을 반복해 네 방향 시트를 다시 생성했다. 방패가 수평으로 누운 일부 중간 칸과 내려베기 후에도 날이 서 있는 일부 칸은 물리적인 동작 지침으로 사용하지 않았다. 실제 구현에서는 오른손 검·왼손 방패, 동일한 손잡이 접촉, 팔 연결과 연속된 베기 궤적을 유지했다.

새 소매의 제작 원본은 [build_sleeves.py](build_sleeves.py), 손 피부·스킨 가중치 보존 결과는 [제작 보고서](generated_sleeves/sleeve_build_report.json)에 있다. 게임에 적용된 모델은 `../../godot-game/assets/3d/player/sword_shield/`에 있다.

생성 참고와 실제 게임 화면은 [게임 검토 기록](../../godot-game/artifacts/visual_qa/sword_shield_choreography/REVIEW.md)에서 비교한다. `build_review.py`는 실제 촬영 PNG의 픽셀을 보존하여 재생 화면·APNG·주요 프레임 모음을 만들고 원본과의 일치를 검증한다.
