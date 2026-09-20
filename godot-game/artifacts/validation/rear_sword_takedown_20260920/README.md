# 검 후방 제압 검수 / Rear sword takedown validation

2026-09-20 · MacBook · Godot 4.7 · 실제 게임 코드와 에셋 / Production code and assets.

## 결과와 조작 / Result and controls

미인지 상태로 서 있는 크리프의 뒤에 검을 들고 접근하면 **[E] 검 · 후방 제압** 안내가 나온다. E로 깊게 찌르기 → 발검 → 크게 목 베기를 실행한다. 찌르기·발검 동안에는 살아 있고, 마지막 베기에서만 실제 머리 메시를 분리하며 사망·보상을 한 번 처리한다. 몸과 머리는 물리로 쓰러진다. 기력 비용은 24이며 기존 부상 비용 배율이 적용된다.

Supported swords: `rusted_sword`, `forged_longsword`, `forged_arming_sword`. Press **E** close behind an unaware upright Creep: deep stab → withdrawal → broad neck cut. The target stays alive through withdrawal; the final cut alone detaches its actual head and grants one defeat/reward, followed by physical collapse. Base stamina cost is 24 with existing injury modifiers.

F2 → 기본 → **검 제압 · 미인지 후방**. 같은 메뉴의 **경계 상태 비교**, **정면 비교**는 제압 거절과 정상 AI를 비교한다. 다시 선택하면 회복·재생성되고, 테스트 종료 시 원래 원정이 복원된다. 기존 단검 암살도 미인지 적에게만 적용된다.

F2 offers real unaware-rear, alerted and front trials. Replay heals/respawns; leaving restores the original expedition. Existing dagger assassination now also requires an unaware target.

## 실제 영상 / Actual rendering

[9초 전체 영상](rear_sword_takedown.mp4): 0–6초 검 제압, 6–9초 경계 적 거절. 960×540, 30fps/270프레임, 실제 물리 60Hz. 생성 이미지·합성이 아니라 숨김 GPU에서 실제 Player와 Creep AI를 실행한 결과다. 제압 후 3.5–4.3초에만 검수 카메라를 내려 시체와 떨어진 머리를 확인한다. 무음·비활성 실행으로 사용자 포커스와 커서를 유지했다.

[Full 9-second video](rear_sword_takedown.mp4): sword takedown for 0–6s, alerted refusal for 6–9s. Actual hidden GPU rendering at 960×540/30fps with 60Hz physics, using production Player and live Creep AI. A capture-only downward look after the completed takedown exposes the physical corpse/head; no contact, damage, severance or corpse position is forced.

![깊게 찌르기 / Deep stab](rear_sword_stab.png)
![목 베기 / Neck cut](rear_sword_death.png)
![물리로 떨어진 머리 / Detached physical head](rear_sword_final.png)

## 검증 / Checks

- `rear_takedown`: PASS. 실제 피부 삼각형과 검 정점으로 55% 관입, 검 밑동이 피부 밖에 남음, 발검 후 목의 실제 절단면 접촉을 검사했다. 1.15m와 최대 범위에 가까운 1.49m에서 성공, 긴 프레임에서도 접촉 순서·한 번의 사망/보상을 확인했다. 정면·경계·높이·거리·다른 월드·벽·잘못된 무기·기력 부족, 취소와 원정 복원도 포함한다.
- `rear_takedown_trial`, `test_room`: PASS. 실제 F2 등록·배치·공개 E 동작 경로, 일시정지·재시험·전체 초기화·원정 복원.
- `dagger_assassination`: PASS. 경계 중인 적의 등 뒤에는 일반 피해만 적용된다.
- `creep_execution`, `creep_enemy`, `test_room_session`: PASS. 기존 처형·적·세션 관련 회귀.
- 실제 GPU: PASS. 원본/검수 소스 해시·원정·커서 보존, 머리 분리와 물리 이동, 마지막 베기에서만 사망, 경계 적 거절. 제압 중 최대 어깨 보정은 **1.81cm**, 팔 길이는 34cm/26cm로 유지됐다. 최종 이미지들을 직접 열어 확인했다.

All seven relevant suites passed. Core evidence independently checks actual skin entry and blade depth, real neck-plane contact, reachable fixed-length arms, long-tick ordering, cancellation and one death/reward. Actual F2/session checks and live GPU rendering also passed. The final capture's maximum shoulder adjustment was 1.81cm, with 34cm/26cm arm segments preserved.

첫 렌더에서는 목 베기 위치가 너무 멀어 어깨가 약 73cm 전진했다. 최종 버전은 준비 중 필요할 때 1.15m까지 접근하고, 발검하며 약 .82m까지 짧게 전진한 뒤 검날 앞쪽(끝에서 10% 뒤)으로 목을 벤다. 전진은 실제 캐릭터 충돌을 사용한다. 낮은 장애물에 막혀 팔이 닿지 않으면 제압을 취소하고 살아 있는 적을 풀어 준다. 검의 원래 길이·그립·공용 팔 솔버는 바꾸지 않았다.

The first capture exposed an unreachable neck cut. The final revision uses collision-tested approach steps and the forward cutting edge, retaining the original sword/grip/arm solver. An obstructed, unreachable finish cancels instead of moving through the obstacle or detaching the arm visually.

초기 검사에서 몸통 진입·출구 교차 2회를 요구했던 조건도 수정했다. 실제 몸통은 분리 제작된 열린 피부 메시이며, 별도 절단면이 닫아 주는 구조다. 최종 검사는 실제 검날-피부 교차와 독립 진입점·55% 깊이를 검사한다. 관통 출구가 보인다고 주장하지 않는다.

The initial two-intersection test assumption was invalid for the split open torso surface. The final check independently crosses the real blade with posed skin and measures insertion; it does not claim a visible through-body exit.

## 범위와 남은 한계 / Scope and limitations

- [사용자 링크](https://youtu.be/EsBYKoMkSOo)의 2:09–2:14 프레임은 **미확인**. 링크 표시 문자와 실제 연결 주소가 달라 실제 연결 주소를 확인했지만 해당 영상을 조용히 재생할 수 없었다. 이번 동작은 사용자가 명시한 순서를 기준으로 제작했으며 원본 영상과 프레임 단위 일치를 주장하지 않는다.
- 제압은 현재 분리 가능한 머리 모델을 갖춘 서 있는 크리프와 위 검 3종에 적용된다. 다른 무기는 프로필을 따로 추가해야 하며 검 동작을 자동 재사용하지 않는다. 별도 은신 수치·경보 전파 시스템은 추가하지 않았다.
- 실제 입력 경로와 동일한 공개 게임 API를 검사했다. OS 키보드 E·마우스 포커스 및 모든 던전 배치의 수동 플레이는 **미확인**이다. 영상은 검수 장면의 실제 1인칭 렌더다.
- `test_room` 종료 시 ObjectDB 2개 잔존 경고가 있다. 해당 기능 검사는 통과했지만 이 공통 종료 경고는 이번 변경에서 해결하지 않았다. 렌더 로그의 기존 정적 경고도 보존했다.

The linked 2:09–2:14 reference frames were not available for direct viewing; exact motion matching is unverified. Scope is the upright Creep and the three configured swords. OS keyboard/focus routing and manual play in every dungeon layout are unverified. The common test-room exit still reports two ObjectDB instances; assertions pass, and that warning is retained in the log.

## 증거 파일 / Evidence

- `capture_summary.json`: 단계별 실제 좌표·피부 관입·부위 분리·최대 팔 도달·원본 해시.
- `capture_manifest_full.json.gz`: 전체 물리 틱 기록을 압축 보존한 원본 캡처 manifest.
- `core_test.log`, `integration_tests.log`, `dagger_unaware_test.log`, `regression_tests.log`, `render.log`.
- `rear_sword_*.png`, `alerted_denial_denied.png`: 동일 최종 실행에서 저장한 원본 화면.

The compact summary and losslessly compressed full manifest preserve the measured evidence and source hashes. Stills and the video come from the same final capture. GitHub publication is recorded in the task's final response after remote verification.

게시용 사본도 핵심·F2 검사 2종과 실제 GPU 270프레임을 추가 통과했다. 로컬 영상에는 작업 시작 전에 존재한 상처 효과가 보존되어 있다. 게시용 코드에서는 그 별도 진행 중 변경을 제외하고 기존 커밋의 절단 구조를 유지했으며, 목 베기·머리 분리·랙돌 결과를 별도로 렌더링하고 직접 열어 확인했다. `publication_*` 파일에 증거를 남긴다.

The isolated publication-source copy additionally passed core/F2 checks and a 270-frame GPU run. The local video preserves pre-existing wound-effect work; that unrelated work is excluded from this commit. The published baseline cut structure was separately rendered and visually reviewed for neck cutting, detached-head physics and collapse; evidence is in `publication_*`.
