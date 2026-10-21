# 방 소실 수정 / Room-visibility fix

> 후속 천장 검사에서 별도의 재질·메시 틈을 수정했습니다: [천장 소실 수정](UNITY_GOTHIC_CEILING_FIX_20261021.md). 이 문서의 문 시야 검사는 천장 전체의 검증을 의미하지 않습니다. / The later ceiling fix addresses separate sidedness and joint gaps; the doorway tests below do not establish correct upward rendering.

2026-10-21: 문밖의 특정 거리에서 방 바닥·천장·가구가 사라지고 일부 벽과 귀환 표식만 남는 문제를 수정했습니다. 사용자가 제공한35번 방 시점에서 원인을 재현했습니다.

Fixed the reported doorway-distance disappearance of floors, ceilings and furniture, reproduced at the supplied room35 view.

## 원인과 수정 / Cause and change

기존 최적화는 `roomBounds.SqrDistance(camera) <25`로 **방 경계5m 밖의 방 전체**를 껐습니다. 근사 방 경계와 문 시야 판정도 함께 사용했습니다. 귀환 표식·철문·일부 벽은 다른 렌더 묶음이라 남아 검은 빈 공간이 드러났습니다. 재현 위치는 방 경계에서6.153m이며 시야와 겹치는 방 메시52개가 모두 숨겨졌습니다.

The previous optimization disabled an entire room beyond5m from its bounds, alongside approximate room/door tests. Independently rendered gate/return marker/wall pieces remained. At the reported6.153m pose, all52 room batches intersecting the frustum were disabled.

수정본은 벽·바닥·천장과 건축 셸을 거리 때문에 끄지 않습니다. 개별 메시의 시야·원거리 제외는 Unity 카메라에 맡깁니다. 소품은 건축과 별도로 결합하며, 방 경계8m 이내에는 유지합니다. 멀리 있는 소품에는 실제 충돌 지형을 이용한 문 개구부9개 시선 검사와0.35초 유지 시간을 적용합니다. 거리만으로 방을 통째로 끄지 않습니다.

The fix retains structural room shells/floors/ceilings and uses native camera-frustum/far-plane culling. Loose props are batched separately, retained within8m of room bounds, and otherwise use9 aperture sight rays against actual geometry plus0.35s retention. Distance alone never removes an entire room.

전체 화면에서 모든 메시를 항상 그리는 중간안은 삼각형·그리기 비용이 컸으므로 채택하지 않았습니다. UI는 화면 해상도를 유지하고3D만 최대1280×900 범위에서 화면 비율에 맞춰 그립니다. 이 Mac의 전체 화면2940×1846에서는3D1280×804·UI2940×1846입니다. 새 렌더 표면은 입력을 가로채지 않으며 문·전투·저장 규칙은 유지했습니다.

The intermediate all-meshes-always-rendered variant was rejected for cost. Native-resolution UI is retained while3D rendering fits a1280×900 budget:1280×804 world and2940×1846 UI on the observed fullscreen size. The background surface does not intercept input; gate, combat and save rules are preserved.

## 검증 / Validation

- 최종489개 검사 통과: 기존115개 기능, 실제 열린 문 상태, 신고 시점,35개 방의359개 지지 바닥·직접 문 시야 사례,5m 경계9회 왕복. 테스트한 직접 시야에서 숨겨진 방 메시0개. /489 checks passed, including the prior115 functional checks, open gate, reported pose,359 supported/unobstructed doorway samples across35 rooms and9 boundary crossings. Zero incorrectly hidden room batches in those samples.
- 같은 최종 앱의 QA 전용 이전 판정으로52개 소실을 재현했고, 수정 판정에서는0개였습니다. / Same-player QA control reproduces52 hidden batches; the fixed mode has zero.
- 맵 패키지80개 파일의 SHA256 동일성을 확인했습니다. 저장 파일도 검사 전후 해시가 같습니다. / All80 map files remain byte-identical; the user-save hash is unchanged.
- 독립 Mac 전체 빌드 오류0개. 앱 서명·기존 Applications 경로·Dock 북마크를 재검사했습니다. 기존 원본 RPG 앱과 저장은 보존했습니다. / Full standalone build has zero errors. Signing, Applications path and Dock bookmark are verified; the previous original RPG app/save remain preserved.

## 프레임 측정 / Frame measurements

같은 Apple M4·Metal·2940×1846 출력·2x MSAA·실제 UI/가구/적/충돌,5개 동일 이동·회전 경로에서 워밍업90회 후 각600개 표본(전후 각각3,000개). 카메라와 UI를 실제로 렌더하고1px GPU 읽기로 동기화한 벽시계 시간입니다. 이전 판정은 전체 해상도3D, 수정 판정은 위3D 픽셀 예산을 사용하므로 변경된 내부 해상도를 명시합니다.

Same Apple M4/Metal/native2940×1846 output/2x MSAA, UI, furnished map, enemies and collision. Five matching movement/turn routes,90 warmup frames and600 samples each:3,000 per variant. Explicit world/UI rendering and synchronous1px GPU readback measure wall time. The control uses full-resolution3D; the fix uses the documented world-pixel budget.

| 경로 / Route | 평균 전→후 / mean ms | 최종 p95 / ms | 최종16.67ms 초과 / % |
| --- | ---: | ---: | ---: |
|35번 보급실 |14.122→12.388|18.019|13.167|
|33번 생활관 |15.739→10.701|14.399|2.000|
|1번 예배당 |15.268→8.415|11.001|0.500|
|30번 책장실 |18.388→11.900|17.514|7.667|
|신고된 문밖 시점 |11.999→7.975|10.636|0.000|

신고 위치와3개 경로는 p95가16.67ms 이내지만35·30번 방은 아직 목표를 넘는 순간이 남습니다. **모든 구간의 안정적60FPS를 인증하지 않습니다.** 숨김·무제한 오프스크린 처리 여유 검사이며 사용자 전경의 전체 플레이 인증도 아닙니다. 제출 삼각형 최대값은 경로별 약71만~253만 개였습니다. Draw Calls 카운터는 이 release player에서 제공되지 않아 null이며 별도의 메시 추정과 구분합니다. FrameTiming GPU 값은 동기 벽시계와 불일치하는 구간이 있어 성능 합격 판정에 사용하지 않았습니다.

Three routes, including the reported view, have p95 below16.67ms; rooms35 and30 still miss the target at times. **Constant60FPS across the game is not certified.** This is hidden uncapped offscreen capacity sampling, not a full foreground playthrough. Peak submitted triangle counters range approximately0.71–2.53 million. Unavailable draw counters remain null, separately from mesh estimates; inconsistent FrameTiming GPU values are diagnostic only.

## 실행과 기록 / Running and records

Dock의 **무시무시한 RPG - 고딕의 기원**은 같은 경로의 수정 앱을 가리킵니다. 새 아이콘을 중복 추가하지 않고 북마크만 복구했습니다. 기존 저장을 이어 사용할 수 있습니다.

The existing Gothic Origin Dock item points to the updated app at the same path; its bookmark was repaired without duplicate entries. Existing expedition saves remain usable.

- 실행본 / App: `unity-game/Builds/MusimusihanRPG-GothicOrigin.app`
- 소스 / Source: `unity-game/Assets/GothicOrigin/Runtime/OriginDungeonGeometry.cs`, `OriginPresentation.cs`, 관련 게임/UI/QA 코드. / Related game/UI/QA sources.
- 작은 검증·빌드·설치·정리 기록 / Compact receipts: `docs/validation/unity-gothic-visibility-20261021/`
- 재현 / Reproduce: `-originQa -originVisibilityQa`, `ORIGIN_QA_WIDTH=2940 ORIGIN_QA_HEIGHT=1846`. QA 전용 이전 판정은 `ORIGIN_QA_LEGACY_VISIBILITY=1 ORIGIN_QA_FULL_RESOLUTION=1`입니다. / Legacy switches are restricted to QA.

검토한 캡처·로그·중간 실행본·이전 앱 비교 사본·격리 프로젝트를 제거하고 소스·importer metadata·원본 에셋·최종 앱·요약을 보존합니다. 제거 할당량과 실제 여유 변화는 `cleanup.json`에 구분합니다.

Reviewed captures/logs/intermediate/comparison builds and the isolated project are removed. Production sources/metadata/originals/final app and compact receipts are retained; cleanup distinguishes allocation from observed free-space change.

실제 정리: 할당량 1451376640바이트 제거, 관찰된 여유 증가 735748096바이트, 정리 직후 여유 17438310400바이트. APFS 공유 블록과 동시 작업 때문에 두 수치는 다릅니다. / Actual cleanup allocation and observed free-space change are recorded separately.

수정 앱은 정상 네이티브 실행으로 제목 화면까지 확인했습니다. 현재 저장을 이어서 사용할 수 있고 Dock 연결도 유지됩니다. / Normal native title rendering and the preserved Dock target were verified; existing saves remain available.
