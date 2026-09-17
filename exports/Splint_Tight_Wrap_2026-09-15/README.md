# 밀착 붕대

큰 타원으로 감싸던 붕대를 현재 자세의 실제 소매 스킨 단면으로 교체했습니다. 41개 단면, 64개 방향으로 주름 외곽을 감싸고 판자는 실제 상자 외곽으로 포함합니다. 붕대 폭을 16개 면으로 나눠 주름을 따라가며 약 3mm 여유와 겹침당 0.4mm 두께를 적용합니다. 전체 화면 확대·기존 팔 체형·판자 위치는 유지합니다.

검증: splint_motion 통과. Vulkan/embedded 235프레임 촬영과 원정·커서·소스 보존 확인. 최종 영상 tight_wrap_final. 전체 표면의 무관통을 수치 증명한 것은 아니며 실제 주요 화면을 검토했습니다.

- splint_tight_wrap.gif: 전체 동작
- before_after.png: 왼쪽 수정 전 / 오른쪽 수정 후
- contact_sheet.png: 주요 단계
- tests_final.log, capture_final.log, manifest.json: 검증 기록
