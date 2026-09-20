# 손목 비율 / Wrist proportions

장갑 손목 길이 62%, 중앙 폭과 깊이 73%. 손목 단면은 폭 6.9cm, 깊이 4.9cm다. 손바닥 아래쪽과 손가락(높이 0.795m 이하)의 정점 위치는 이전 모델과 1마이크로미터 정밀도에서 일치한다. 몸의 나머지 24개 메시와 1인칭 원본 해시는 보존했다.

English: Wrist cuff length is 62% and its central width/depth 73% of the previous model. Measured glove wrist is 6.9cm wide and 4.9cm deep. Lower-palm and finger vertices (height <=0.795m) match the previous model at micrometer precision. The other 24 body mesh signatures and FP source hashes are unchanged.

Asset regression / 에셋 검사: player_fullbody_fp_arms PASS. 손목 단면, 짧아진 장갑, 손끝과 소매 위치, 어깨, 재질, 구형 손 제거 검사 / checks wrist cross-section, shortened glove, fingertips, sleeve and shoulder placement, materials and retired-hand removal.

별도 제작 원본은 이 폴더의 build.py와 Gravebound_FP_Arms.blend. 이전 원본은 보존. 재생성은 앞선 player_fullbody_fp_arms_20260920의 원본 몸과 pose.json을 참조한다. / Editable sources are stored here; prior models are preserved. Rebuild uses the original body archive and pose.json from player_fullbody_fp_arms_20260920.

숨김 Vulkan 렌더 PASS: fullbody_wrist_20260921 폴더의 6장. 손목 확대·사선 전신·측면을 직접 검토했다. 입력·원정 상태 보존, 기존 경고 외 실행 오류 없음.
English: Hidden Vulkan rendering passed with six captures; visually reviewed the wrist close-up, quarter and side views. Input and expedition state were preserved, with no execution errors beyond existing warnings.
