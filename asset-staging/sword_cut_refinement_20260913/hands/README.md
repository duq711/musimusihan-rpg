# 양손검 파지 보정 · 2026-09-13

Mac `/Applications/Blender.app/Contents/MacOS/Blender` 5.2.1 LTS에서 백그라운드 CLI로 제작했습니다. `author_thumb.py`는 보존된 `asset-staging/sword_hold_long_grip_integration/source/model/SwordHold_Static.blend`를 열어 별도 `.blend`와 `.glb`를 저장합니다. 원본 런타임 GLB와 검 메시·재질·UV·기준 변환은 그대로입니다.

오른손은 원본 `thumb0/1/2` 가중치만 이용해 검 좌표 Z 방향으로 최대 20.2 mm 완만하게 들어올렸습니다. 검 접촉을 유지하는 후보 중 최대 이동이 가장 작은 후보를 선택했습니다. 원본 Blender 정점 11,396개 중 2,696개만 변경되며, 원본 GLB의 중복 UV 정점을 포함하면 14,177개 중 3,437개입니다. `right_thumb_corrective.json`은 원본 accessor의 위치·노멀과 보정 위치·노멀을 보관합니다. Godot가 import 과정에서 정점을 재정렬하고 약 1~2 µm 양자화하므로 runtime은 5 µm 이내 실제 원본 좌표 및 corner normal로 대응시킵니다. 정수 accessor 인덱스를 그대로 적용하지 않습니다. 게임에서 검·소매는 이 보정 경로로 들어가지 않습니다. 수정 모델과 sparse 보정은 같은 Blender 편집에서 추출됩니다.

왼손은 원본 모델·손가락 길이·팔 길이를 유지합니다. `long_grip_surface`가 켜진 양손검 보조 손에만 별도 손바닥 중심 `(0, -0.011, -0.074)`을 적용합니다. 끝마디만 맞추던 파지를 실제 스킨의 끝마디·중간마디(중지는 근위마디까지) 접촉으로 보완했습니다. 수납 후 손이 닿는 마지막 구간은 tension 0.75~0.89에서 원래 관절각과 다점 파지각을 부드럽게 혼합합니다. 방패 파지와 다른 무기 손에는 적용하지 않습니다.

검증:

- `godot-game/tests/sword_two_hand_grip_test.gd`: 실제 방패 수납 후 3방향 검 공격의 48시점에서 실제 스키닝 접촉점과 원본 손잡이 삼각형 거리를 검사합니다. 오른손 1,379개 엄지 표면 정점, 원본 GLB 해시, 허용된 보정 외 나머지 형상/UV/인덱스/재질, 공격 종료·원정·커서 복원도 검사합니다. 실제 import 삼각형의 최대 모서리 신장과 인접정점 변위차도 검사해 잘못된 정점 대응에서 생기는 가시·삼각형 붕괴를 검출합니다. 단독 실행에 staging이나 Blender가 필요하지 않습니다.
- `thumb_validation.json`: Blender 원본 엄지의 최대 14.402 mm 침투 → 파생 엄지 최소 +0.148 mm 간격, 1 mm 이상 침투 정점 0개.
- `left_contact_validation.json`: `runtime_contacts.json`의 실제 엔진 정점/스킨점을 Blender BVH로 독립 재검산했습니다. 실제 오른손 1,379표본 최소 +0.149 mm, 1 mm 이상 침투 0개, 2 mm 이내 접촉 29개. Godot 삼각형 계산과의 오차는 1 µm 미만입니다.
- 왼손 중간마디 최대 간격은 기존 12.78 mm → 1.32 mm, 새끼손가락 중간마디 최대 침투 7.69 mm → 최소 +0.60 mm입니다. 중지 근위마디 최대 간격 19.38 mm → 6.29 mm, 검지/중지/약지 손바닥 최대 간격 22.01 mm → 10.93 mm입니다. 새끼손가락 쪽 손바닥 뒤꿈치는 샤프트 접촉부가 아니며 최대 23.56 mm입니다.

재현:

```sh
./tests/run_headless_tests.sh sword_two_hand_grip sword_long_grip primary_shield_stow
```

수치 보고서를 새로 만들려면 `SWORD_TWO_HAND_CONTACT_REPORT`에 절대 출력 경로를 주고 새 테스트를 실행합니다. 제작 폴더 `runtime_contacts.json`으로 출력한 후 `analyze_contacts.py`를 Mac Blender 백그라운드로 실행하면 독립 BVH 보고서가 갱신됩니다. 실제 화면 판정은 부모 담당의 숨김 Godot 렌더 결과로 별도 수행합니다.
