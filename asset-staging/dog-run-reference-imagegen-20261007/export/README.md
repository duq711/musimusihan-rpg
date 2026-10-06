# 개 달리기 실제 자세 참고 시퀀스 / Dog-run reference sequence

내장 imagegen으로 만든 개별 PNG 16장과 대응하는 실제 영상 프레임입니다. 원본 바이트를 보존했고 리사이즈나 픽셀 편집을 하지 않았습니다.
Sixteen individual built-in imagegen PNGs with corresponding actual video references. Original output bytes are preserved, with no resizing or pixel edits.

frames/는 생성 이미지, sources/는 실제 자세 참고입니다. manifest.json에 시간·해시·프롬프트·검사 한계가 있습니다.
frames/ contains generated images; sources/ contains pose references. See manifest.json for timing, hashes, prompts and review limits.

HTTP 서버에서 index.html을 열면 프레임을 비교·재생할 수 있습니다. 기본 16fps는 미리보기 설정입니다. 원본 시간 옵션은 이미 느린 영상의 24fps 샘플 시간을 따릅니다. 실제 촬영 FPS는 확인되지 않았습니다.
Serve this folder over HTTP to compare and play frames. The default 16fps is a preview setting. Source timing follows the already slowed 24fps video; its original capture FPS is unknown.

실제 다리 단계와 굽힘·겹침을 참고한16장입니다. 일부 머리 위치·몸 크기·발 높이 차이가 남아 정밀 자세 복제나 매끄러운 루프 일치는 확인되지 않았습니다.
Sixteen frames broadly follow the actual leg phases, bends and overlaps. Head registration, scale and paw-height differences remain; exact pose replication and a seamless loop are unverified.

Source: https://youtu.be/CoL8Gtvxfl0
