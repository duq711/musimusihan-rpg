# 강아지 펫 에셋 조사 / Dog companion asset research

확인일 / Checked: 2026-10-05, Asia/Seoul. 가격은 확인 당시 USD 세전이며 판매처·할인에 따라 달라집니다. / Prices are observed USD before tax and vary by store and sale.

## 사용자 요청과 조사 범위 / Request and scope

사용자는 사실적인 강아지 펫을 구상했습니다. 주인공과 함께 공격하고, 숨겨진 아이템을 물어오며, 쓰다듬기와 먹이 주기로 교감합니다. 이번 작업은 모델·애니메이션 조사이며 품종·구매·최종 에셋은 미정입니다.

The requested dog companion fights beside the player, retrieves hidden items, and supports petting and feeding. This work researches models and animation; breed, purchase and final asset selection remain undecided.

현재 로컬 프로젝트는 Unity `6000.3.25f1`, Built-in 렌더링입니다. 확인 경로: `unity-game/ProjectSettings/ProjectVersion.txt`, `GraphicsSettings.asset`의 `m_CustomRenderPipeline: {fileID: 0}`, QualitySettings 및 Packages 설정. 판매자의 호환 표는 해당 표의 버전 기준이며 이 프로젝트에 실제 임포트한 결과가 아닙니다.

The local project uses Unity `6000.3.25f1` and Built-in rendering. Store compatibility tables describe their listed versions; they do not establish a tested import into this project.

## 후보 / Candidates

| 후보 / Asset | 확인 가격 / Price | 확인된 장점 / Verified strengths | 부족하거나 미확인 / Gaps |
| --- | --- | --- | --- |
| [Skye the Border Collie (Dog), MalberS](https://assetstore.unity.com/packages/3d/characters/animals/skye-the-border-collie-dog-378638) | $99.99 | 털 카드, Unity 설명 200+ 모션, 공격·냄새 탐색·줍기·놓기·먹기·귀여운 반응. Unity 6000.0.77f1에서 Built-in/URP/HDRP 표시. / Fur cards, 200+ advertised Unity animations, combat, scent searching, pickup/drop, feeding and expressive reactions. | 전용 Carry 및 직접 쓰다듬기 클립 미확인. / No dedicated carry or direct petting clip confirmed. |
| [Animalia – German Shepherd (male), GiM](https://assetstore.unity.com/packages/3d/characters/animals/animalia-german-shepherd-male-145860) | $99.99 | 4K, LOD, 제작사 설명 98개·60fps·root motion 유/무, 다양한 물기 공격·탐색 보행. Unity 2021.3.30f1 세 렌더링 경로 표시. / 4K, LODs, 98 advertised clips at 60fps, root-motion/in-place variants, bite attacks and seeking locomotion. | 공개 전체 목록에서 먹기·줍기·놓기·쓰다듬기 미확인. / Eating, pickup/drop and petting absent from the published list. |
| [Dog – Border Collie, Red Deer](https://assetstore.unity.com/packages/3d/characters/animals/dog-border-collie-191222) | $25 | 112개 모션, 공격·땅파기·먹기·마시기·줍기, 4 LOD. Unity 2020.3.41f1 세 경로 표시. / 112 animations, attack/dig/eat/drink/pickup and four LODs. | 냄새 탐색·운반·쓰다듬기 미확인. 털과 근접 외형의 비교 검토가 필요. / Sniff, carry and petting unconfirmed; compare close-up coat quality. |
| [Labrador Retriever Dog, Rozy1418](https://www.cgtrader.com/3d-models/animal/mammal/labrador-retriever-dog-rig-ad65bab2-7eca-4cb8-b335-9419d397daff) | 할인 $15 / 정가 $30 | 19개 모션: 쓰다듬기·앉아서 쓰다듬기·탐색·땅파기·이동·마시기. Maya/FBX 애니메이션. / 19 clips include petting, seated petting, search, digging, locomotion and drinking; Maya/FBX animation. | 공격·먹기·줍기·운반 미기재. 판매 이미지의 털은 매끈한 메시/텍스처 표현으로 보임. / No listed attack/eat/pickup/carry; the inspected coat looks smooth and texture based. |

## 우선 추천과 동작 근거 / Recommendation and motion evidence

**Skye를 우선 추천합니다.** 요청한 전투·탐색·돌봄 동작의 범위와 현재 렌더링 지원을 함께 고려한 조사 판단입니다. 품종 확정 또는 구매 결정이 아닙니다. 사실적인 털 표현과 귀여운 체형을 섞은 외형이며, 사진과 구분되지 않는 실사로 단정하지 않습니다.

**Skye is the first recommendation** based on motion coverage and advertised rendering support. This is a research recommendation, not an approved breed or purchase. Its detailed coat accompanies somewhat cute proportions; photographic equivalence is not established.

공식 [Package Content](https://assetstore.unity.com/packages/3d/characters/animals/skye-the-border-collie-dog-378638#content) 트리를 실제 브라우저로 펼쳐 다음 파일을 확인했습니다. / The live official package tree was expanded to verify these files:

| 용도 / Use | 확인한 클립 / Confirmed clips |
| --- | --- |
| 함께 공격 / Combat | `Dog_Attack_Bite_Forward v2`, 좌우 물기·발 공격 / side bite and paw attacks |
| 탐색 / Search | `Dog_Smell`, 냄새 맡으며 걷기·속보·방향 전환 / smelling walk, trot and turns |
| 아이템 회수 / Retrieval | `Dog_PickUp`, `Dog_Drop` |
| 먹이·물 / Feeding | `Dog_Eat`, `Dog_Drink1` |
| 교감 반응 / Affection | `Dog_Happy`, `Dog_Head_Tilt`, `Dog_Rolling`, 핥기·앉기·잠 / licking, sitting and sleeping |

줍기·놓기 클립이 완성된 물어오기 시스템을 뜻하지는 않습니다. 입의 아이템 부착, 운반 중 이동, 주인공 앞에 내려놓기, 숨은 아이템 판정·탐색 AI를 연결해야 합니다. 쓰다듬기는 위 반응을 활용할 수 있지만 주인공의 손동작·손 위치·타이밍을 추가해야 합니다. 이는 구현 방향이며 이번에 구현·검증한 기능이 아닙니다.

Pickup/drop clips are a basis for retrieval. Mouth attachment, carrying locomotion, returning/dropping, hidden-item detection and search AI still require implementation. Affection reactions can support petting, but the player's hand animation, contact position and timing need authoring. These are proposed implementation steps, not implemented or tested features.

Skye의 Unity 설명은 200+ 모션, [제작사 Fab 설명](https://www.fab.com/listings/fa25a2b9-0178-4805-97d9-5caeb5e2e82f)은 298+로 다릅니다. Unity판의 정확한 총수는 확정하지 않습니다. [공식 실사 버전 영상](https://www.youtube.com/watch?v=eKo0JS-2owo), [Unity 영상](https://www.youtube.com/watch?v=633FxKpc7rs)에서 외형·움직임을 검토할 수 있습니다.

Unity and Fab advertise different animation counts (200+ and 298+); the exact Unity total remains unconfirmed. The linked publisher videos provide visual previews.

Skye 판매 페이지에는 Animal Controller 종속 표시가 있지만 제작사 설명은 자체 컨트롤러가 있으면 필요 없다고 안내합니다. AC 연동 prefab/demo를 사용할 때 의존성을 확인합니다. 모델·클립만 사용하려는 경우 별도 구매를 무조건 필수로 계산하지 않습니다.

The store marks an Animal Controller dependency, while the publisher says an existing custom controller can be used. Check that dependency for AC-integrated prefabs/demos rather than assuming a second purchase is mandatory for the model and clips.

GiM 동작 근거: [German Shepherd 공식 전체 목록](https://gim.studio/animalia/german-shepherd/). Unity판의 제작 리그 포함 범위와 PRO 상업용 FBX/PNG 구성은 구분해야 하며, Unreal의 gFur 화면을 Unity에서 같은 털 표현이 보장되는 근거로 쓰지 않습니다.

GiM evidence: the linked full publisher motion list. Package-specific authoring-rig/FBX contents and Unreal gFur presentation must be distinguished from the Unity product.

## 보류한 후보 / Other reviewed candidates

- [RetroStyle Realistic 3D Dog Pack](https://assetstore.unity.com/packages/3d/characters/animals/realistic-3d-dog-pack-367480): $129.99, Unity 표는 HDRP만 호환. [Fab 제작사 설명](https://www.fab.com/listings/a1910b03-c432-4992-ad1e-22f6b0ea0c97)은 12종·기본 이동/대기/회전 중심이며 요청한 전투·돌봄 전체 동작은 미확인. / HDRP-only compatibility table and documented locomotion/idles; full requested interaction coverage unconfirmed.
- [Nyilonelycompany Golden Retriever adult](https://www.cgtrader.com/3d-models/animal/mammal/golden-retriever-dog-06f200cd-6a1f-4d22-9899-02a96e8c28f4): $50, 먹기·공격·이동 명시. 쓰다듬기·탐색·운반은 미기재. / Lists eating, attacks and locomotion; petting/search/carrying not listed.
- [Bicode DOG Full Animations – Brittany Spaniel](https://www.artstation.com/marketplace/p/Wmn07/dog-full-animations-brittany-spaniel): 323개, 쓰다듬기·먹기·냄새·공 놀이가 풍부하지만 2,422 triangles/1K 텍스처로 이번의 높은 사실감 우선 후보에 들지 않음. / Rich interaction clips, but its 2,422-triangle/1K model does not lead this realism shortlist.

## 확인·산출물 / Verification and output

주요 후보 4개와 보류 후보 3개의 공식 판매자 자료를 검토했습니다. Skye의 실제 패키지 파일 목록과 외형, Labrador의 판매 이미지·현재 가격을 브라우저에서 확인했습니다. 구매·에셋 다운로드·Unity 임포트·게임 실행은 0회이며 성능 또는 실제 접촉 품질은 검증하지 않았습니다. 저장한 캡처·영상·빌드·복제 프로젝트는 0개로 별도 정리 대상이 없습니다. 최종 산출물은 이 문서입니다. 현재 게임 소스·에셋·플레이용 앱은 보존했습니다.

Reviewed official seller material for four shortlisted and three secondary candidates. Live browser checks covered Skye's actual file list and appearance, and Labrador's image/current price. Purchases, asset downloads, Unity imports and game runs: zero. Runtime performance/contact quality remain untested. No captures, videos, builds or copied projects were saved; this note is the final artifact. Existing source, assets and playable app were preserved.
