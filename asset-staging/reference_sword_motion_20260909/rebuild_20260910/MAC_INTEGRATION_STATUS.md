# Windows iteration_07 → Mac Godot 통합

2026-09-10 진행 기록. 사용자가 Windows에서 완성한 결과를 Mac 게임에 적용하도록 요청했다.

- 실제 완성 범위: 내리찍기(overhead) 하나, 1.55초, 120 Hz 관절/검/방패 샘플 187개. 달리기·점프·다른 베기는 신규 Windows 납품에 포함되지 않는다.
- 실제 Windows 자료 50개를 `../windows_output/final_overhead_received_20260910/`에 수신했다. ZIP SHA-256 `236b770ecf70ee5114458290789341573495c50dac8cf9687e9b0d407380ff0e`, ZIP CRC 및 내부 49개 파일의 크기/SHA-256 검증 통과.
- `arm_pose_samples.json` SHA-256 `3c383aacbfb138a1c3ac19686f4a555d06ef2e311575aeefd7c2a529045254b0`.
- `prepare_overhead_partial_manifest.py`로 실제 키 값을 변경/재샘플링하지 않고 명시적인 부분 납품 스키마로 포장했다. 준비 파일은 `mac_integration/overhead_manifest.json`, SHA-256 `af97875bed7c2cbe2a60458a9cb4e24f27643e13040eb069abfbbc2315d2c643`.
- **실제 내리찍기 동작을 기존 팔 모델에 적용했다.** 사용자의 적용 재요청에 따라 수신된 manifest를 값 변경 없이 `godot-game/assets/animations/reference_sword_motion/overhead_manifest.json`에 설치했다. 새 7본·3스킨 소매 GLB는 여전히 미수신·미적용이며, 기존 소매에서 재생하는 현재 상태를 Windows 최종 모델 전체 적용으로 취급하지 않는다.
- 필요한 GLB: Windows `delivery/GodotPreview/assets/Overhead_Final.glb`, 18,986,536 bytes, SHA-256 `a0df768367d78a487573101e780b881869b52b17ddd6daeaaea9cbcf6b24f319`.
- Mac에 이미 있는 동일한 텍스처 바이트를 재사용하는 전송을 요청했지만 GLB 전송 출력은 아직 없다. `reassemble_asset_segments.py`는 원본 파일의 완전한 SHA-256 동일성을 요구한다. 이 작업은 모델링/재생성 작업이 아니다.
- 로더는 실제 partial overhead만 인식하고, 미납품 클립은 기존 게임 동작을 사용한다. 전체 8개 클립 납품 여부는 별도 `full_delivery_available()`로 구분한다.
- 테스트룸의 기존 `motion_shield_cut_overhead`가 실제 설치 동작을 재생한다. `reference_sword_overhead_runtime` 1 PASS / 0 FAIL: 검·방패·S/E/W·기존 팔 표면, 실제 피해/기력, 다른 베기/달리기/점프 유지, F2/원정 복원 통과. 결과는 `actual_motion_checked=true`, `actual_sleeve_checked=false`, `rigid_segment_fit`, `full_eight_clip_delivery=false`이다. 관련 4개 회귀 검사도 통과했다(`mac_motion_installed_regression.log`).
- 준비 코드 검증: `reference_sword_partial_data_test`, `reference_sword_arm_player_test` 2 PASS, 0 FAIL. 두 검증은 데이터 구조/분석용 fixture 검사이며 실제 GLB 통합 완료 근거가 아니다.
- 실제 받은 JSON의 숫자는 Godot에서 float로 읽히므로 단위 축척과 화면비 배열을 int 배열과 비교하던 로딩 오류를 수정했다. 숫자 값/배열 크기/유한성 검사는 그대로 유지한다. 실제 staging manifest를 읽기 전용으로 파싱하여 187키 검증 통과했고, 기존 데이터/공유 시간 검사도 통과했다(`actual_partial_decode_fixed.log`: 2 PASS, 0 FAIL). 실제 스킨/게임 재생 검증과는 구분한다.
- 기존 팔에서 실제 설치 모션의 숨김 Vulkan Godot 프리뷰가 통과했다. 대기/달리기/점프/우측 베기/역베기/내리찍기 6개 실제 시퀀스, 1280×720·60fps·470 PNG를 저장했고 원정/입력 상태와 소스 해시 보존을 확인했다. `overhead_motion_only` 검토 모드는 새 소매 미적용을 명시하며 최종 소매 필수 검증과 구분한다. Windows 원본 Blender 파일과 Mac 원본 static GLB는 보존한다.
- 실제 게임 영상: `godot-game/artifacts/visual_qa/reference_sword_motion/mac_overhead_runtime_20260910_01/mac_game_overhead_applied.mp4` (470프레임, 60fps, 7.833초). 원본 PNG를 임의 보간하지 않고 전부 인코딩/디코딩 검증했고 장면 위 별도 제목 띠에 신규 동작/기존 동작/새 소매 미적용을 표시했다. 원본 영상과 시각적으로 동일하다고 주장하지 않는다.

## 마지막 전송 확인

Windows 작업은 조회 가능하지만 GLB 전송과 짧은 파일 존재 확인 요청이 연속 세 번 `completed`, `error=null`, 출력 0개로 끝났다. 그 사실만 확인했으며 Windows 연결 해제나 Blender 고장으로 단정하지 않는다. 관련 반환값은 `windows_transfer_unavailable_1788975700.json`에 보존했다. 동일한 요청 반복을 중단하고, 사용자가 최종 ZIP/GLB를 Mac에 보관한 경로를 확인 중이다. 현재 Mac 다운로드 폴더에서는 이전 `SwordHold_Static.glb`만 발견했다.

수신할 파일은 `Overhead_Final_Godot_Blender_20260910.zip` 또는 내부 `delivery/GodotPreview/assets/Overhead_Final.glb`이다. ZIP의 나머지 편집 원본은 Windows에 보존해도 되며, 게임 통합에는 검증된 최종 GLB와 이미 받은 동작 JSON을 함께 사용한다.
