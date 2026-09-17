# 한손 검 손잡이 비례 수정본

`longsword.glb`는 검날과 가드, `HandGrip`, `BladeTip`을 보존한 대기용 모델이다. 게임 프로젝트 복사와 Godot 가져오기는 별도로 수행한다.

원본은 `source_longsword.glb`에 보관한다. 프로젝트 루트에서 다음 명령으로 같은 모델과 보고서를 재생성한다.

```sh
python3 asset-staging/sword_shield_single_pose/corrected_sword/correct_longsword.py --source asset-staging/sword_shield_single_pose/corrected_sword/source_longsword.glb
```

실제 GLB의 +Y 축을 확인한 뒤 자루와 감개를 `y' = -.026 + .60 × (y + .026)`으로 압축했다. 끝장식 목의 중심은 `-.171m`, 끝장식 높이는 기존의 65%, 폭과 두께는 80%다. 합쳐진 금속 메시의 삼각형 연결 성분을 구분해 가드와 칼날 정점은 건드리지 않았다. 비균일 축소된 금속 표면의 법선과 접선은 함께 변환했다.

`correction_report.json`에는 각 성분의 전후 경계와 원본·출력 해시, 검날 데이터와 가드 정점의 동일성 검증 결과가 있다. UV, 정점 AO 색상, 삼각형 순서는 보존했다. 아직 이 모델의 게임 내 렌더링 결과를 검증한 기록은 아니다.
