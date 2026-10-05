# 래브라도 펫 진행 상태 / Labrador pet checkpoint

2026-10-05. 사용자는 무료 kenchoo 래브라도를 선택하고 동행 공격·숨겨진 아이템 물어오기·쓰담·급식을 요청했습니다. **실제 래브라도 설치는 아직 완료되지 않았습니다.** Sketchfab 다운로드가 로그인을 요구하며, Google 로그인 버튼 클릭은 특정 로그인 방식에 대한 사용자 승인이 없다는 자동 승인 검토 이유로 거부됐습니다. 로그인 승인 질문은 미응답 상태입니다. 새 계정이나 이용약관 동의는 진행하지 않았습니다.

The user selected the free kenchoo Labrador and requested combat support, hidden-item retrieval, petting and feeding. **Actual Labrador installation is unfinished.** Sketchfab requires sign-in; automatic approval review rejected the Google sign-in click because that specific authentication method had not been authorized. The approval question remains unanswered. No account or agreement was created or accepted.

## 확보한 원본 / Acquired source

- 모델: [Labrador Dog — kenchoo](https://sketchfab.com/3d-models/labrador-dog-1f56cfbab07e4fe49b5d9e521c82073a), 원작 [Dog — all of life](https://skfb.ly/oHLVz). 공개 페이지의 CC BY 4.0·약 52,800삼각형·26,900정점·simple idle 표기를 확인했습니다. 모델 파일·스킨·리그·텍스처는 아직 받거나 검사하지 않았습니다. / The public listing was checked; no model, skin, rig or texture has been acquired or inspected.
- 캡처: [Lifelike Agility and Play dataset](https://springernature.figshare.com/articles/dataset/Lifelike_Agility_and_Play_in_Quadrupedal_Robots_using_Reinforcement_Learning_and_Generative_Pre-trained_Models/24968946), DOI `10.6084/m9.figshare.24968946.v1`. 공식 API의 CC BY 4.0 및 다운로드 주소로 ZIP 73,545,752B를 받았고 공식 MD5 `746d592726eb7411f084518bfa1f3791`과 일치합니다. ZIP SHA256 `651a4099b4660f898a5bfcd24769ba4142a0ec30daa328a2aebc3d31b51b8b34`. / Downloaded from the official public API; archive hash verified.
- `asset-staging/labrador-pet-20261005/source/`: ZIP·원본 BVH 33개·공식 메타데이터를 보존합니다. 추출 BVH 371,140,520B의 해시는 모두 ZIP entry와 일치합니다. 원본 117,636프레임·120FPS; 32개는 76관절/61애니메이션 관절/366채널, 1개는 75/60/360입니다. / Raw source archive and captures are retained locally.
- 출처·제작자 전체 이름은 `source-manifest.json`에 있습니다. 파생 모션 배포 시 제작자·원본 링크·[CC BY 4.0](https://creativecommons.org/licenses/by/4.0/)·변경 사실을 함께 표기합니다. 연구 코드 저장소의 라이선스와 데이터셋 라이선스를 혼동하지 않습니다. / Retain attribution, source/license links and modification notices for derivatives; distinguish dataset licensing from research-code licensing.

## 준비 코드와 검증 / Prepared code and checks

`unity-game/Assets/RPG/Gameplay/Pets/`에 동행·물기·탐색·회수·쓰담·급식 모듈을 작성했습니다. 실제 prefab·입 소켓·16개 이름 있는 클립이 없으면 Spawn이 명확히 실패합니다. 회수는 원래 월드 스택을 예약하고 실제 패키지를 입 소켓에 옮기며, 가방이 차면 잔여품을 바닥에 보존합니다. 급식은 예약한 정확한 가방 스택에서 먹기 접촉 때 1개만 소비합니다. E 쓰담, 개를 바라보며 G 급식/취소, R 탐색입니다. 이 조작은 설치 후의 예정 조작이며 현재 실행본에 연결돼 있지 않습니다.

New companion modules require the actual prefab, mouth socket and sixteen named clips. Retrieval conserves the original scene stack and package; feeding consumes one unit from the reserved exact inventory stack at eating contact. Planned installed controls are E to pet, G to feed/cancel and R to search while focusing the dog. These controls are not yet connected in the playable app.

- 최종 Unity 6000.3.25f1 격리 PlayMode 검사 16/16 통과(거래 9·행동 7), 검사 사본과 최종 소스 해시 일치. 급식 지불 시점/1회성·취소·가방 교체·가득 참·재진입 복제 방지·일시정지·월드 비활성화 상태·벽/바닥 경로를 확인했습니다. 충돌/클립 시험용 fixture를 사용했으므로 실제 래브라도 화면 검사로 세지 않습니다. / Sixteen final transaction/behavior tests passed against explicit collision and clip fixtures; final source hashes match.
- 현재 본편 Unity Editor에서 새 코드가 컴파일됐고 컴파일 오류 0개입니다. / New code compiles in the current main Editor with no compiler errors.
- 독립 BVH FK와 Blender 5.2.1 LTS importer를 3캡처·9프레임·549관절 좌표에서 대조해 통과했습니다. 최대 차이 `1.7707e-6 m`, 허용 `0.0002 m`. / Source decoding verification passed; this is not skinned-model motion validation.
- `tools/dcc/labrador_pet_bvh.py`, `labrador_pet_capture_index.py`, `labrador_pet_source_verify.py`, `labrador_pet_retarget.py`와 `tools/unity_migration/run_pet_transaction_tests.py`를 보존했습니다. 리타기팅 도구는 실제 검사한 관절 매핑·neutral calibration을 요구합니다. / Reusable source and test tools are retained; rig mapping cannot be guessed.

## 남은 적용 / Remaining installation

로그인 후 공식 원본을 받아 리그·스킨·재질을 검사하고, 캡처 후보를 실제 리그에 적용해 발 접지·루프·전환을 검토해야 합니다. 검사한 6캡처의 턱 회전은 고정이어서 물기·집기·씹기·쓰담 반응을 추가 제작해야 합니다. 손의 쓰담 동작·먹이/그릇 비주얼은 이벤트 연결점만 준비했습니다. 실제 크리프 신체와 물기 접촉, 숨겨진 아이템 지도 배치, 원정/성소/F2 메뉴 연결, 영상과 최종 실행본 검증도 남았습니다.

Acquire and inspect the official model, retarget and visually review the captured candidates, then author missing bite/grip/chew/care details. Jaw rotation is constant in six inspected captures. Hand and bowl visuals only have event hooks. Actual Creep anatomy contact, authored hidden loot, expedition/hideout/F2 wiring, preview video and the final playable build remain pending.

현재 플레이용 `unity-game/Builds/MusimusihanRPG.app`·Dock/Applications 연결·이전 셰퍼드 제작 원본은 보존했습니다. 기존 작업 브랜치와 다른 작업의 변경은 이 체크포인트에 섞지 않습니다. 공개 체크포인트는 준비 코드·도구·출처·요약만 포함하며, 현재 로컬 Unity 본편 전체의 배포 완료나 설치 완료를 의미하지 않습니다.

The current playable app, launch links and previous Shepherd originals are preserved. This checkpoint contains only the prepared pet code, tools, provenance and summaries; it does not certify publication of the complete current local Unity baseline or a completed pet installation.

검수 로그·XML·이 작업의 Python 캐시는 요약 보존 후 정리합니다. 소스 BVH·공식 메타데이터·유일한 제작 원본·재사용 도구와 작은 검증 요약은 보존합니다. 실제 정리 수치와 여유 공간은 `asset-staging/labrador-pet-20261005/checkpoint-summary.json`에 기록합니다.

Reviewed logs/XML and this task's Python caches are cleaned after retaining summaries. Source captures, official metadata, originals, reusable tools and compact evidence are preserved. Cleanup counts and free space are recorded in `checkpoint-summary.json`.
