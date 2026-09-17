# 크리프 모션 영상 / Creep motion reel

[영상 재생 / Play video](creep_motions.mp4) · 1280×720 · 30fps · 22.53초 / seconds · H.264.

본편에 연결된 대기 → 걷기 → 물기 → 양손 연타 → 피격 → 사망 6개 모션이다. Mac Godot 4.7 Forward+/Vulkan에서 실제 게임 모델과 본편 포즈 함수를 사용해 676프레임을 촬영했다. 걷기는 제자리이며 AI 이동·실제 피해 판정은 이 소개 영상에서 실행하지 않는다. 물기 2회·양손 공격 3회·피격 2회를 보여주고 피격 사이와 사망 끝에서 자세를 잠시 유지한다. 음성·음악은 없다.

The six current gameplay motions are idle, walk, bite, two-hand attack, hit reaction and death. All 676 frames use the real game model and production pose function in Godot's Forward+/Vulkan renderer. Walking is in place; this presentation does not simulate AI travel or damage. Attacks and hit reactions repeat for visibility, with brief reaction/end-pose holds. There is no audio.

`creep_motion_reel` 헤드리스 검사 통과: 6개 표시 이름과 실제 클립 일치, 본 움직임, 원본 접촉 시점·사망 끝자세, 원정·커서·몸체 위치 보존. embedded 렌더 통과 및 6개 구간의 실제 PNG를 직접 검토했다. FFmpeg libx264로 30fps 인코딩하고 영상 676프레임 전체 디코딩을 통과했다. 생성 이미지나 프레임 보간을 사용하지 않았다. 본편 모델·애니메이션·전투 코드는 변경하지 않았다. 기존 이미지 UID 경고는 파일 경로로 정상 로드된다.

Headless timeline checks passed, as did windowless GPU capture. Frames from all six segments were opened for visual review. The MP4 was encoded at 30fps without generated/interpolated frames and fully decoded successfully. Game assets and combat behavior remain unchanged. Existing texture-UID warnings fall back to valid paths.

[시험 로그 / Tests](headless.log) · [렌더 로그 / Render](render.log) · [프레임 상태 / Frame states](capture_manifest.json) · [영상 정보와 구간 / Video metadata and chapters](video_metadata.json) · [디코딩 / Decode](decode.log).

![영상 미리보기 / Poster](poster.png)
