# 부목 양손 겹침 수정

오른팔 팔꿈치를 아래로 향하게 하고, 손가락·손목·소매가 왼손의 팔꿈치 쪽에서 움직이도록 일관된 방향으로 간격을 확보했습니다. 판자 지지에서 감기로 전환할 때 보정을 부드럽게 적용하며 롤 파지, 왼손 주먹 동작, 3회 감기와 7.2초 완료는 유지합니다.

- `splint_motion`: 통과. 60Hz 최대 손 이동 0.0319m, 손목 이음새 오차 0, 판자 접촉 오차 0.001m.
- 감기 중 양손 관절 및 오른쪽 소매 표본 간격 검사 통과. 모든 메시 삼각형을 검사한 것은 아닙니다.
- Mac embedded Vulkan 235프레임 실제 촬영, 주요 구간 시각 확인. 원정·커서·소스 보존 및 실제 시간 완료 확인.
- 최종 GIF: `splint_hand_clearance.gif`. 최종 원본: `../../godot-game/artifacts/visual_qa/splint_forearm/hand_clearance_02/`.
- 첫 시안은 `hand_clearance_01`에 보존. 최종 로그는 `tests_final.log`, `capture_final.log`.
