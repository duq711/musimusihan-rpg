# 검·방패 가죽 표면 생성

- 방식: Codex imagegen 스킬의 내장 image_gen 도구
- 게임 적용 파일: `godot-game/assets/ai/sword_shield/worn_charcoal_leather.png`
- 용도: 실제 관절형 손의 장갑, 팔 보호대, 방패 뒤 가죽 끈, 검 손잡이에 사용하는 알베도.
- 원본 출력은 Codex generated_images에 보존하고 위 프로젝트 경로로 복사했습니다.
- 이 이미지는 게임 화면이나 모션 캡처가 아닌 재질 자료입니다.

## 최종 프롬프트

Use case: photorealistic-natural. Asset type: seamless physically based game texture, albedo only, square 2048x2048. Create a completely flat orthographic macro scan of worn medieval charcoal-brown leather, the kind used for dark fingerless swordsman gloves and segmented forearm bracers in a highly realistic first-person medieval game. The leather is dark desaturated warm gray brown, with fine irregular natural grain, compressed shallow wrinkling, faded gray rubbed patches, tiny scratches, restrained old wear and slight grime. Rich subtle large-to-small surface variation, physically believable old supple leather, not new brown vinyl, not fabric or denim. Fill the entire frame with this single material, consistent physical scale of a roughly 25 cm square piece. Fully even diffuse cross-polarized lighting, no specular highlights, no illumination gradient, no cast shadows, no ambient-occlusion vignette. No stitches, seams, bands, folds that rise into silhouettes, hands, objects, text, borders, logos or watermarks. Tileable on all four edges. This will be wrapped onto an actual articulated 3D glove and bracer, so surface marks must be nondirectional, evenly distributed, and not form recognizable repeated emblems.
