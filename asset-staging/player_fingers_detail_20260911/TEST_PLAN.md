# 손가락 개별 디테일 검증 계획

이 문서는 후보 확정 전 읽기 검토 결과다. Godot 통합·자동 검사·GPU 검증을 실행했다는 뜻이 아니다. 이번 기준 이미지는 `reference/individual/`의 손가락 5개 × 손톱면/지문면 **10개 개별 PNG**다. 이전 합성 시트는 사용하지 않는다.

## 실제 이미지 이름과 경로

`detail_materials.py`는 Blender 이미지 datablock을 `FingerDetail_Packed_basecolor`, `FingerDetail_Packed_normal`, `FingerDetail_Packed_roughness`로 만든다. 파일 이름은 `realistic_hands_{basecolor,normal,roughness}.png`다. 직접 읽은 iteration03 양손 GLB의 `images[].name`도 `realistic_hands_*`를 유지한다. Blender 내부 이름만 보고 Godot 경로를 `FingerDetail_*`로 바꾸지 않는다.

최종 GLB를 기존 `hands_detailed/{left,right}_hand_detailed.glb`로 통합한 뒤 예상되는 Godot 추출 파일은 다음 6개다. 최종 import 결과와 실제 재질 연결로 다시 확인한다.

```text
res://assets/3d/player/hands_detailed/left_hand_detailed_realistic_hands_basecolor.png
res://assets/3d/player/hands_detailed/left_hand_detailed_realistic_hands_normal.png
res://assets/3d/player/hands_detailed/left_hand_detailed_realistic_hands_roughness.png
res://assets/3d/player/hands_detailed/right_hand_detailed_realistic_hands_basecolor.png
res://assets/3d/player/hands_detailed/right_hand_detailed_realistic_hands_normal.png
res://assets/3d/player/hands_detailed/right_hand_detailed_realistic_hands_roughness.png
```

기존 두 Godot preview의 `SOURCE_FILES`에는 이미 이 6개 PNG와 각각의 `.png.import`, GLB, 런타임 파일이 들어 있다. 경로가 동일하다는 것은 내용이 같다는 뜻이 아니다.

## 이전 맵을 잘못 읽는 경우를 잡는 확인 순서

1. **직렬화된 후보:** 저장한 blend를 다시 읽은 실제 packed bytes/픽셀과 새 베이크 PNG를 대조한다. GLB는 재질의 texture index → image index → bufferView를 따라간 실제 이미지로 검증한다. base color/normal RGB, roughness의 실제 G 채널을 대조한다. ORM 패킹이나 PNG 재압축 때문에 전체 PNG SHA가 다를 수 있으므로 의미 있는 채널의 decoded pixels로 판단한다.
2. **Godot import 산출물:** 최종 GLB의 위 payload와 게임에 추출된 6개 PNG를 동일한 방식으로 대조한다. 실제 imported texture 설정의 크기 제한·채널 remap·normal Y·mipmap 항목도 기록한다. 예전 import cache가 새 내용 대신 재사용되지 않았는지 확인한다.
3. **실제 재질이 읽는 데이터:** 기존 `PBRMaterialAudit`의 `get_active_material()`에서 얻은 albedo/normal/roughness texture 경로와 해당 `get_image()` 픽셀을 확인한다. 경로만 확인하지 않고 새 디스크 PNG를 직접 디코드한 값과 실제 사용 UV 표본을 비교한다. 현재 텍스처 설정은 lossless `compress/mode=0`, 원본 크기, 채널 remap 없음이므로 의미 채널의 기준 픽셀을 엄격하게 비교할 수 있다. 설정이 바뀌면 먼저 변환 원인을 설명하고 허용 오차를 결정한다.
4. **캡처 중 불변:** preview 해시 목록은 모두 존재하고 64자리 SHA인지 확인한다. 현재 `source_hashes()`는 없는 파일의 빈 SHA가 계속 유지되는 경우까지 막지는 않으므로 이 경계 검사를 보완할 필요가 있다. manifest에는 실제 연결 texture 경로·파일 SHA·읽은 표본 결과를 추가한다. 최종 후보 승인 후 기존 검사/preview 안에서만 구현하며 별도 게임 메뉴나 새 테스트 묶음은 만들지 않는다.

현 기존 PBR 검사의 UV·tangent·실제 피부 표본 분산은 유지한다. 그것만으로는 오래된 유효한 맵과 새 베이크를 구분할 수 없으므로 위 내용 연결 검사가 필요하다.

### iteration03 임시 읽기 근거

Godot를 실행하지 않고 생성된 양손 GLB를 직접 읽었다. 양쪽 결과가 같았다.

| 맵 | GLB 실제 image payload | 새 PNG와 비교 |
|---|---|---|
| basecolor | SHA `947dcf54b36d81f4262f4e5b22d41f8f6a790c729c43d06d66ad4a8801a2d077` | PNG bytes/RGB 전체 동일 |
| normal | SHA `0ab0debffd575cd3217cd03e5be356559a9cd9a2f4de3221faa1e1e5c71563c3` | PNG bytes/RGB 전체 동일 |
| roughness | SHA `3846470e2307a69757f862ca4af784b17ee09741f4e42cde679f419dfdf6925c` | 새 PNG SHA는 다르지만 G 4096² 픽셀 전체 동일 |

새 roughness PNG는 proportions01 원본과 비교해 각 RGB 채널에서 717,562개 픽셀이 바뀌었고 최대 차이는 13/255였다. 따라서 동일해 보이는 기존 파일명이나 iteration02와 같은 roughness payload를 근거로 stale라고 단정하지 않는다. 이 수치는 최종 후보의 승인·Godot 검증을 대신하지 않는다.

## 유지할 조형·동작 조건

- 현재 16본 rest/축/계층·UV·named weights·15 corrective를 유지한다. 실제 마디별 weighted skin 이동, pure-other 정확 0, 마디 간 독립성과 NaN/clamp/reset 검사를 그대로 둔다.
- axial 한계는 middle1/ring1 15mm, 나머지 14.2mm, 반경 40mm와 기존 진폭 조건을 유지한다. 새 조형으로 실패해도 결과에 맞춰 미리 완화하지 않는다.
- 손톱의 digit2 강체 부착 검사는 유지한다. 새 손톱 표면의 피부 관통/들뜸은 독립 Blender의 실제 posed surface 거리와 10개 개별 화면으로 확인한다. 강체 부착 PASS만으로 표면 접촉까지 보증하지 않는다.
- 원래 피부·장갑·소매·손톱·봉제선 역할, 장비 접촉, 손목 끝점·안쪽 압축·양의 Jacobian·실제 GPU 버퍼, 원정 객체·metadata 복원 조건을 유지한다.
- `player_hands_detailed`, `player_finger_joints`의 기존 테스트룸 항목을 사용한다. 새 디테일과 개별 기준 이미지 비교 설명만 갱신하고 메뉴를 늘리지 않는다.

## 후보 승인 및 import 이후 실행

Root가 최종 후보의 개별 10장과 independent source/GLB 검사를 승인하고 통합·import 종료를 알린 뒤, 별도 Godot 실행과 경합 없이 다음 7개를 한 번 실행한다. 새 로그 이름을 사용하고 실패 로그를 보존한다.

```sh
PLAYER_FINGER_JOINTS_QA_DIAGNOSTIC=1 ./tests/run_headless_tests.sh \
  player_finger_joints player_hands_detailed player_hands_greybox \
  player_arm weapon_hand_contacts chest_hands test_room_session
```

첫 두 핵심 검사 통과를 알리고 전체 결과를 확인한 뒤 소스를 동결한다. GPU 촬영은 Root가 기존 숨김 실행기로 담당한다. 카메라·게임 조명·실제 동작은 기존 조건 그대로다.

```sh
PLAYER_FINGER_JOINTS_QA_ITERATION=<새 이름> \
PLAYER_HANDS_REALISM_QA_CLOSEUPS=1 \
./tests/run_embedded_preview.sh player_finger_joints_preview.gd

PLAYER_HANDS_DETAILED_QA_ITERATION=<새 이름> \
./tests/run_embedded_preview.sh player_hands_detailed_preview.gd
```

관절 10장 + 중립 근접 2장 + 실제 손 동작 5장/같은 자세 그레이박스 1장 = **18장**이다. 손가락 기준 이미지 10장 및 고정 native Blender before/after 10장과는 서로 다른 증거다. 하나의 합성 비교 이미지로 대체하지 않는다. GPU에서는 손톱 경계, 지문·주름의 방향과 깊이, 피부색, 장갑 보존, mipmap 경계의 검은 금/흰 선, 활·상자 굽힘에서의 변형을 실제 이미지로 확인한다.

일반 게임이나 편집기 창, 외부 입력·커서·오디오를 사용하지 않는다. 이 계획 단계에서는 어떤 Godot 검사나 GPU 렌더도 실행하지 않았다.
