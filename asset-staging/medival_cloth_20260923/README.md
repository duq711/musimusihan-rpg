# 제공 의상 · 움직이는 옷자락 / Supplied outfit with moving hems

사용자가 제공한 `Medival.blend`, `.obj`, `.fbx`, `.mtl`, `Textures.rar`의 복사본은 `source/`에 보존했습니다. `build.py`는 이 원본을 읽어 현재 플레이어 체형에 맞춘 `Medival_Retargeted.blend`와 텍스처를 포함한 `Medival_Retargeted.glb`를 새로 만듭니다. Mac Blender의 백그라운드 모드에서 이 디렉터리의 `build.py`를 실행하며 `bsdtar`가 필요합니다. `textures/`는 RAR에서 추출되거나 빌드 중 생성되는 자료입니다.

상의·바지·벨트는 원본 UV와 컬러·노멀·거칠기 맵을 사용합니다. 원본 불투명도 맵은 어깨와 겨드랑이에 커다란 투명 영역을 만들었으므로 상의 몸판만 불투명 양면 재질로 바꿨습니다. 앞·뒤 옷자락은 원본 가장자리와 투명 마감을 유지하며 각각 약 500개 삼각형의 별도 메시입니다. `structure_report.json`에 이름, 크기, 상단 고정점 정보가 있습니다.

게임은 `godot-game/assets/3d/player/medival_outfit.glb`를 기존 플레이어의 얼굴·손·긴 부츠와 합성합니다. 앞·뒤 옷자락은 원본 UV 경계가 찢어지지 않도록 각각 하나의 연속된 스프링 변형 메시로 움직입니다. 허리의 윗줄은 고정하고 아래쪽은 실제 플레이어 이동·방향 전환의 관성으로 최대 7cm 흔들리며, 정지하면 감쇠합니다. 기본 `SoftBody3D`는 원본의 UV 분할 정점을 서로 다른 입자로 취급하여 표면이 갈라졌기에 사용하지 않습니다. 시험은 게임 테스트룸 `F2 → 기본 → 플레이어 의상 · 이동 물리`에서 합니다. 360도 웹 뷰어는 정적 외형·봉합 상태를 보기 위한 것입니다.

`qa/`에는 창 없는 실제 Godot/Vulkan 렌더에서 촬영한 정지 정면, 걷는 측면, 멈춘 후면과 소스 해시가 들어 있습니다. 피부·상의·바지·부츠 결합 및 옷자락 봉합을 검토한 기록입니다. 동영상이나 수동 조작 검증으로 해석하지 않습니다.

The five supplied originals are preserved under `source/`. The generated GLB combines the supplied outfit with the existing head, hands, and tall boots. Two low-density hem panels use bounded spring deformation driven by the player's actual movement; the 360° web viewer shows the static shape only. The opaque upper shirt fixes transparent shoulder and armpit gaps while the original frayed hem appearance remains.
