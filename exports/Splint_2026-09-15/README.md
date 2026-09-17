# 나무 부목 · 왼팔 착용

- `wood_linen_splint.blend`: Mac Blender 5.2.1 원본, 스트랩별 애니메이션 포함.
- `wood_linen_splint.glb`: 표면 결 텍스처 5개와 스트랩 애니메이션 3개를 내장한 게임 에셋.
- `splint_use_visuals.gd`: 현재 Godot 프로젝트의 기존 손 리그·붕대 기반 클래스를 사용하는 8.6초 양손 착용 동작. 이 파일 하나만 별도 프로젝트에 복사해서 실행할 수 있는 독립 캐릭터 리그는 아니다.
- `splint_preview.gif`: 실제 Godot의 창 없는 Vulkan 화면에서 만든 동작 미리보기.

게임에서 `F2 → 생존 → 부목 사용 · 왼팔 고정`으로 반복한다. 본편 건강 화면에서는 왼팔 선택 → 나무 부목 사용 → 가방 닫기 순서다.

골절 해소·소비는 기존 사용 시점에 한 번 적용한다. 현재 소매를 유지하며, 소매 걷기 변형·다른 팔다리용 착용 모션·완료 후 영구 착용은 포함하지 않는다. 검증 근거는 프로젝트 `asset-staging/splint_20260915/output/validation_summary.json`에 있다.
