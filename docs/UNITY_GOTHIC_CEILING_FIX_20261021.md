# 천장 소실 수정 / Ceiling visibility fix — 2026-10-21

사용자가 올린28번 방의 검은 천장과 떠 있는 회색 아치가 이번 작업 대상입니다. 이전 문밖 방 소실 검사만으로 천장까지 검증했다고 판단할 수 없었습니다.

This work addresses the black ceiling and exposed grey ribs reported in room28. The previous doorway tests did not establish correct upward rendering.

## 원인과 수정 / Cause and fix

- 기존1~29번 방의 천장 재질은 glTF `doubleSided=true`입니다. 고딕 재질 변환에서 이 설정이 사라지고 셰이더가 `Cull Back`을 강제했습니다. / The original ceilings declare `doubleSided=true`; the paint conversion lost this setting and forced back-face culling.
- 가져온 glTF 재질별 양면 설정을 전달하고, 셰이더가 `_Cull`을 사용합니다. 양면의 뒷면 조명 법선도 뒤집습니다. 일반 제작 재질은 기본 뒷면 제외를 유지합니다. / Preserve per-material glTF sidedness, use configurable shader culling and face-aware lighting normals; ordinary newly authored materials retain their default back-face culling.
- 별도로 발견한34번 방 천장 돌 사이에는 기존 곡선을 따르는 모르타르 뒷면을 추가하고,35번 방 문 위 틈에는 기존 벽 재질의 채움 면을 추가했습니다. 총96개 삼각형이며 기존 배칭으로 합칩니다. 문은 원래2m 폭·3.8m 중앙 높이를 유지합니다. / Add mortar behind room34 vault joints and wall spandrel backing at room35, following existing profiles:96 triangles, merged by the existing batcher. Preserve the2m doorway and3.8m crown clearance.
- 원본 GLB·맵 패키지를 변경하지 않습니다. / Preserve the original GLBs and map package.

## 검사 방법 / Validation method

실제 Mac ARM64 Unity/Metal 플레이어,2940×1846 출력·1280×804 월드·2x MSAA를 사용합니다. 사용자 저장 대신 QA 전용 저장을 쓰고 물리 입력·소리·포인터 잠금을 차단합니다. 정상 플레이의 입력에는 영향을 주지 않습니다.

Use the real Mac ARM64 Unity/Metal player at2940×1846 output,1280×804 world and2x MSAA, with isolated QA saves, muted sound and no physical-input/pointer capture. Normal player input is unaffected.

28번 방의 저장된 시점과35개 방의 네 방향·65/85도 올려다보기280개 시야를 렌더합니다. 카메라 배경을 검사 중에만 자홍색으로 설정하고 전체 월드 화면을4px 간격으로 검사합니다. 어두운 석재나 그림자를 구멍으로 오인하지 않습니다. 0.2% 이상 노출을 실패로 처리하며 작은 잔여 픽셀도 요약에 기록합니다. 제한된 지점의 표본 검사이며 모든 위치의 완벽한 메시 폐쇄를 증명하지 않습니다.

Render the saved room28 pose and280 upward views: four headings at65/85 degrees across35 rooms. Temporarily use a magenta clear colour and sample the entire world image on a4px grid, distinguishing real uncovered pixels from painted darkness. Fail at0.2% exposure; retain the maximum residual fraction. This samples selected positions rather than proving watertight geometry everywhere.

같은 하드웨어·해상도·5개 이동/회전 경로에서 각90회 워밍업 뒤600개씩, 전후 각각3,000프레임을 측정합니다. 실제 카메라/UI 렌더와1px GPU 동기 읽기의 벽시계 시간이며 전경 전체 플레이나 고정60FPS 인증은 아닙니다. 불가한 Draw Calls 값은 null로 보존합니다.

Measure five matching movement/turn routes,90 warmup frames and600 samples each:3,000 per variant, with real camera/UI rendering and synchronous1px GPU readback. These uncapped background wall times do not certify a complete foreground playthrough or constant60FPS. Unavailable draw-call counters remain null.

## 결과 / Results

- 최종771개 검사 통과, 오류0개. 이전 설정 490개 검사도 통과하면서 문제를 재현했습니다. / Final771 checks passed with zero failures; the control passes its490 checks while reproducing the issue.
- 35개 방·280개 위쪽 시야 중 기준 이상 구멍: 229→0. 저장된28번 시점의 노출 비율: 19.022%→0.003%. / Above-threshold uncovered views: 229→0; saved room28 pose: 19.022%→0.003%.
- 최종280개 시야의 최대 잔여 노출 비율은 0.01555%이며0.2% 실패 기준 미만입니다. 모든 픽셀이 완전히 닫혔다고 주장하지 않습니다. / Maximum residual exposure is 0.01555%, below the0.2% failure threshold; this is not a claim of zero exposed pixels everywhere.
- 기존115개 기능 및35개 방의359개 유효 문 시야·9회 경계 왕복 검사 유지. / Retain the prior115 functional checks,359 supported doorway views across35 rooms and9 boundary crossings.
- 원본 맵 패키지80개 파일·사용자 저장 해시 동일. 제작 소스와 importer metadata가 빌드에 사용한 복사본과 모두 동일합니다. / All80 original map files and the user-save hash are unchanged; production sources/metadata match the build inputs.
- Unity6000.6.3f1 ARM64 전체 빌드 오류0개. 엄격한 앱 서명, Applications 링크,16개 Dock 항목 수·기존 순서·현재 앱 북마크 검사 통과. / Unity6000.6.3f1 ARM64 full build has zero errors; strict signature, Applications link and all16 Dock entries/order/current bookmark are verified.

| 경로 / Route | 평균 ms 전→후 / mean | p95 ms 전→후 |16.67ms 초과 % 전→후 |
| --- | ---: | ---: | ---: |
| 28번 신고 저장 시점 / saved report pose | 6.171→7.007 | 10.777→12.232 | 0.167→0.333 |
| 28번 위쪽 / upward | 5.918→4.268 | 11.959→9.227 | 1.000→0.167 |
| 35번 보급실 / supply room | 14.027→13.834 | 18.736→18.197 | 18.500→14.667 |
| 33번 생활관 / living quarters | 11.373→12.358 | 18.049→18.175 | 11.833→13.000 |
| 1번 예배당 / chapel | 10.607→9.527 | 17.307→13.169 | 5.833→1.833 |

35·33번 방의 최종 p95는16.67ms를 넘습니다. 아직 모든 구간에서 안정적인60FPS를 충족하지 않습니다. 신고 시점과28번 위쪽 시점은 p95가16.67ms 이내입니다. 약28만~253만 개의 제출 삼각형 카운터가 관측됐으며 새 보강이 제출되는35번 경로는64개 증가했습니다. 두 번의 백그라운드 실행은 다른 Mac 활동·열 상태의 영향을 받을 수 있으므로 작은 시간 차이를 성능 개선으로 단정하지 않습니다.

Rooms35 and33 still have p95 above16.67ms, so stable60FPS throughout is not achieved. The reported and upward room28 views remain below the p95 budget. Submitted-triangle counters range approximately0.28–2.53 million, with64 additional triangles on the room35 route. Background activity and thermal state can affect the runs; small timing differences are not presented as performance gains.

## 산출물 / Artifacts

- 실행본 / Playable app: `unity-game/Builds/MusimusihanRPG-GothicOrigin.app`
- 소스 / Sources: `unity-game/Assets/GothicOrigin/Runtime/OriginPaint.cs`, `OriginDungeonWorld.cs`, `OriginDungeonGeometry.cs`, `OriginCeilingQa.cs`, `OriginQa.cs`; `Resources/OriginInkPaint.shader`.
- 재현 도구 / Reproduction: `tools/unity-gothic-origin-20261021/run_ceiling_qa.py <app> <output>`.
- 작은 검증·빌드·설치·정리 기록 / Compact receipts: `docs/validation/unity-gothic-ceiling-20261021/`.

QA 전용 `ORIGIN_QA_LEGACY_SIDEDNESS=1`은 이전 뒷면 제외와 보강 전 형상을 재현합니다. 정상 실행에서는 이 환경변수를 사용하지 않습니다. 원본 소스·에셋·importer metadata·최신 앱·Applications/Dock 연결은 보존하고, 검토한 임시 검사 자료와 격리 프로젝트는 결과 기록 후 정리합니다.

The isolated `ORIGIN_QA_LEGACY_SIDEDNESS=1` control reproduces the old culling and geometry before backing. Normal execution ignores this control. Preserve production sources/assets/metadata/latest app/Applications/Dock links; remove reviewed temporary captures, logs and the isolated project after retaining results.

수정 앱을 정상 네이티브 실행하여 제목 화면과 이어서 하기 버튼을 확인했고 현재 실행 상태로 두었습니다. QA 경로와 실제 플레이 경로를 구분했습니다. / Normal native launch and the title/Continue button were visually verified; the updated player remains running. QA paths are separate from the playable app.

정리: 할당량 1380806656바이트 제거, 관찰된 여유 변화 627847168바이트, 정리 직후 여유 17036603392바이트. APFS 공유 블록 때문에 두 값은 다릅니다. / Cleanup: removed allocation 1380806656 bytes; observed free-space change 627847168 bytes; free after cleanup 17036603392 bytes. Shared APFS blocks make these different measures.
