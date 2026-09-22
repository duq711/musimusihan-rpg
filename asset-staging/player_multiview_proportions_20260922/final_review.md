# 최종 비율 검토 / Final proportion review

Model SHA-256: `3f4638ee9fe2e7f0925969eb63d4aba669316892ea21373f280f2a4d0b8e2af9`.

## 직접 본 결과 / Visual review

최종 정면·후면·양측면의 실제 렌더와 클레이 화면을 제공된 참조 사진과 비교했습니다. 이전 시안의 가랑이 수평 턱, 소매 끝의 갑작스러운 좁아짐, 쐐기처럼 찌그러진 발, 정강이가 앞으로 밀려 보이는 자세가 완화되었습니다. 목·몸통·팔·골반·다리의 큰 비율을 함께 맞춘 수정본으로 판단합니다. 확인한 각도에서는 추가로 큰 비율 변경을 요구할 구조적 단절을 발견하지 못했습니다.

The final actual front, back and both side renders, including clay views, were compared with the supplied references. The earlier horizontal crotch ledge, abrupt sleeve pinch, wedge-shaped foot distortion and forward-displaced shins have been reduced. The revision now coordinates the major neck, torso, arm, pelvis and leg proportions. No further large structural discontinuity requiring another broad proportion change was identified in the reviewed views.

## 측정 근거 / Quantitative evidence

1086×1448 원본 프레임에서 비교했습니다. 참조의 추정 두개골 정수리 y36과 밑창 y1401에 대응하는 모델 높이는 1.712215677m입니다. 머리카락을 복제하려고 얼굴을 늘리지는 않았습니다. 아래 값은 선택한 높이의 **투영 실루엣 폭 차이**이며 해부학적 오차율이 아닙니다. 한쪽 윤곽 판독 오차는 약 ±3px입니다.

The native 1086×1448 frame is retained. A 1.712215677m model height corresponds to the estimated reference skull crown at y36 and sole at y1401. Face geometry was not enlarged merely to imitate hair volume. These are selected-row projected silhouette-width differences, not anatomical error rates; each edge has approximately ±3px reading uncertainty.

| 부위 / Region | 중앙 절대 차이 / Median absolute difference | 최대 절대 차이 / Maximum |
|---|---:|---:|
| 정면 몸통 중심, 5높이 / Front core torso, 5 rows | 1px | 4px |
| 정면 어깨 외곽, 5높이 / Front shoulder envelope, 5 rows | 6px | 12px |
| 정면 각 팔, 9높이 / Each front arm, 9 rows | 4–5px | 12px |
| 정면 각 다리, 11높이 / Each front leg, 11 rows | 1–2px | 11–13px |
| 정면 가랑이 틈, 9높이 / Front crotch gap, 9 rows | 1px | 3px |
| 후면 몸통 중심 / Back core torso | 8px | 10px |
| 후면 어깨 외곽 / Back shoulder envelope | 24px | 30px |

후면 어깨 상단 외곽은 참조보다 아직 좁은 구간이 있고, 최대 폭 차이 30px는 앞면 보정 단위로 약 3.8cm입니다. 의복과 앞뒤 사진의 자세·원근 차이를 포함하므로 정면과 후면이 모두 픽셀 단위로 일치한다고 주장하지 않습니다.

Some upper rear shoulder rows remain narrower than the reference, with a maximum total-width difference of 30px (about 3.8cm at the front calibration). This includes garment, pose and perspective differences; the front and back are not claimed to match pixel-for-pixel.

## 측면 하체 재확인 / Side lower-body check

전역 카메라 위치 차이를 잘못 해석하지 않도록, 손·주머니 아래의 윗허벅지 y800/820/840 중앙값을 각 측면의 기준으로 삼았습니다. y1000 무릎 부근의 잔차는 양쪽 약 ±0.5px입니다. y1180 정강이 부근의 앞쏠림 잔차는 오른쪽을 보는 측면 11.5px(약1.44cm), 왼쪽을 보는 측면 15px(약1.88cm)입니다. 이전 시안의 약6.3/6.8cm보다 줄었으며, 두 측면에서 과도한 C자 굽음이 크게 완화된 것을 직접 확인했습니다.

Each side was anchored to the median upper-thigh centre at y800/820/840, below the hands and pouches, rather than subtracting an unrelated chest offset. Residual displacement around y1000 is approximately ±0.5px. At y1180 the remaining forward displacement is 11.5px / 15px (about 1.44 / 1.88cm), reduced from approximately 6.3 / 6.8cm in the previous iteration. The excessive C-shaped lower-leg profile is visibly reduced in both side views.

## 남는 한계 / Remaining limits

- 참조는 동일한 정사영 3D 스캔이 아닙니다. 측면은 발바닥 프레임 위치가 약20px 다르고 가까운 다리·먼 다리의 겹침도 다릅니다.
- 모델은 상의·장갑·부츠를 유지합니다. 참조의 맨팔·맨몸과 옷의 외곽이 완전히 같을 수는 없습니다. 주머니와 벨트는 몸통 핵심 비율에서 제외했습니다.
- 팔이 겹친 측면 상체 외곽을 순수 흉곽 깊이라고 부르지 않습니다. 얼굴·머리카락 정체성은 이 작업의 비율 점수 대상이 아닙니다.
- 목·어깨와 바지 주름의 표면 디테일은 사진보다 단순합니다. 이번 검토는 큰 비율과 연결의 개선을 확인하며, 해부학적 완벽함이나 사진의 완전한 복제를 선언하지 않습니다.

The photographs are not a calibrated orthographic scan. Side framing and near/far-leg overlap differ; the retained shirt, gloves and boots also change the outline. Belt/pouches and head/hair identity are excluded from core ratios. Side upper-body width includes arm occlusion and is not isolated chest depth. Surface detail remains simpler than the photographs. This review supports the major proportion and continuity improvements, not perfect anatomy or an exact photographic replica.

## 비교 산출물 / Review artifacts

- `compare.html`: 4방향 참조·모델 경계 슬라이더, 실제 의상/클레이, 실루엣 윤곽, 행별 측정선.
- `comparison_report.json`: 원본/렌더 해시 및 전체 측정 데이터. `compare_references.py`로 재생성할 수 있습니다.
- `side_alignment_review.json`: 골반 기준의 측면 하체 위치 비교.
- `comparison_http_check.json`: 기존 뷰어를 변경하지 않는 임시 loopback 서버에서 14개 허용 경로의 HTTP 응답과 원본 바이트 일치를 확인한 기록.

The generated JavaScript passes syntax checking. All 12 image paths resolve to the intended local assets. The HTTP route check covers the page, JSON, four unmodified reference PNGs and eight actual rendered PNGs; interactive browser operation is a separate final delivery check.
