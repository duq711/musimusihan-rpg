# 게임 제작 기준서

기준일: 2026-09-10. 출처: 사용자가 PD 역할을 지정하면서 설명한 게임 컨셉.

이 문서의 **확정**은 사용자에게서 받은 제작 방향이라는 뜻이며, 구현 완료를 뜻하지 않는다. **제안**은 PD 검토안, **미정**은 추가 결정이 필요한 항목이다. 이후 사용자 지시가 우선하며, 변경할 때 관련 항목과 결정 기록을 함께 갱신한다.

## 1. 게임의 중심 경험 — 확정

다크 판타지 세계에서 던전을 탐험하고 전리품을 가지고 살아 돌아오는 싱글플레이 게임을 만든다. 최우선 경험은 **값비싼 물건을 얻은 순간, 그것을 잃지 않고 탈출하고 싶어지는 긴장감**이다.

- 플레이와 원정 진입, 아이템·퀘스트 진행의 참고 방향은 사용자가 설명한 이스케이프 프롬 타르코프 방식이다.
- 전투와 분위기는 다크 앤 다커를 참고하며, 방향 공격과 콤보는 사용자가 설명한 킹덤컴 딜리버런스·시벌리의 느낌을 목표로 한다.
- 보스전은 잠깐의 실수가 죽음으로 이어질 수 있고, 함정을 잘못 밟으면 치명적인 부상을 입을 수 있다.
- 중무장한 상태로 반복해서 죽어도 다시 도전할 경제적 수단이 있어야 한다.
- 초기 제작 대상은 싱글플레이다. 반응에 따라 PvE 협동을 추가할 의향이 있으며, 현재 확정 제작 범위에는 포함하지 않는다.

레퍼런스 이름만으로 해당 게임의 모든 규칙을 도입하지 않는다. 이 문서에 적힌 사용자 요구를 우선하며, 외부 게임의 구체적인 사양 비교가 필요할 때 별도로 조사한다.

## 2. 월드와 원정 — 확정 및 미정

확정된 공간 구조:

`은신처 ↔ 자유롭게 이동하는 마을 광장·상인 → 맵 선택 → 던전 원정 → 탈출·귀환 → 거래·임무·은신처 성장`

- 은신처에서 상인들이 있는 마을 광장까지는 오픈월드 형식으로 연결한다.
- 던전은 맵을 선택하여 입장하는 세미 오픈월드 구조다.
- 은신처는 던전이 아니며 무작위 루팅 상자 생성 대상에서 제외한다. 입장마다 상자의 유무가 달라지는 규칙은 던전에만 적용한다.
- 맵은 최종적으로 최소 10개를 기획한다. 구체적인 맵 이름·순서·해금 조건은 미정이다.
- 한 맵에 머무르는 시간은 평균 30~60분을 목표로 한다. 이 표현이 강제 제한시간인지 목표 플레이 시간인지는 확인이 필요하다.
- 탈출 지점 수·개방 조건·조기 탈출 가능 여부·시간 초과 결과·중도 종료와 저장 규칙은 미정이다.
- 은신처와 광장 사이의 이동 경험은 확정이지만, 광장의 안전 여부와 기술적인 장면 연결 방식은 미정이다.

PD 제안: 고가품을 얻고 탐험을 중단할 수 있는 일반 탈출 경로를 둔다. 보스 처치로만 가능한 탈출은 특별한 경로나 보상으로 검토한다. 현재 구현의 전원 처치 조건을 최종 규칙으로 고정하지 않는다.

## 3. 플레이어의 세 목표와 엔딩 — 확정

플레이어는 세 가지 목표 중 하나를 선택한다. 선택 시점·변경 가능 여부·전투 능력 차이는 미정이며, 서사 목표를 곧바로 전투 직업 제한으로 해석하지 않는다.

| 목표 | 던전에 오는 이유 | 정해진 엔딩 |
|---|---|---|
| 학자 | 미지의 지식을 습득해 인류를 진보시키려는 야망 | 너무 많은 미지의 지식을 습득한 끝에 미쳐 버린다. |
| 성직자 | 종교적 이유로 던전을 없애려 한다. | 던전이 자신이 없앨 수 있는 존재가 아님을 깨닫고 체념한다. |
| 탐험가 | 목돈을 모아 이곳을 탈출하려 한다. | 도망친 곳에서도 던전이 발견되어 영원히 벗어날 수 없음을 깨닫는다. |

세 결말은 인간의 이해와 통제를 넘어서는 공포를 공유한다. 상인으로 등장하는 성직자와 플레이어의 성직자 목표는 별개의 역할이다.

PD 제안: 각 경로에서 실제로 달성하는 중간 성과, 알게 되는 정보, 임무 선택을 다르게 만든다. 비극적인 결말을 유지하면서도 그곳에 이르는 여정과 성취가 의미 있도록 한다. 지식 획득과 현재 스트레스 시스템을 직접 연결할지는 별도로 결정한다.

## 4. 손실과 재기 — 확정 및 미정

확정된 요구:

- 반복 사망과 장비 손실 때문에 파산하더라도 다시 던전에 도전할 수단을 제공한다.
- 던전 입장 직후 가까운 곳에 시체가 있고, 그곳에서 매우 저렴한 무기와 방어구를 얻을 수 있게 한다.
- 사용자는 주운 무기를 상점에서 취급하지 않아 판매할 수 없도록 요구했다. **입구 시체의 무료 무기만인지, 모든 습득 무기인지 범위는 확인 중이다.**
- 이 수단은 자산을 걸지 않고 다시 수익을 노릴 수 있게 하는 장치다. 별도 스캐브 캐릭터나 별도 모드 제작까지 확정된 것은 아니다.

미정 사항:

- 사망할 때 반입 장비·원정 중 습득품·지갑·임무 진행·부상 중 무엇을 잃거나 유지하는가.
- 무료 시체 장비의 회수·보관 가능 여부와 방어구의 판매 규칙.
- 무료 장비를 분해·제작·교환에 사용했을 때 가치가 생기는가.
- 부상·저주가 귀환 또는 사망 후에도 남는다면, 치료 상인 미해금 및 잔고 0 상태에서 어떻게 재도전하는가.
- 보험·보호 보관함·무료 장비 지급 횟수나 대기시간은 결정되지 않았다.

PD 제안: 시작 장비를 얻는 데 다시 고급 장비가 필요하지 않도록 접근성을 보장한다. 무료 출발 이후에는 탐험과 탈출에 실패할 위험을 유지한다. 무료품의 반복 판매나 가공만으로 원정 보상보다 큰 수익이 생기지 않는지 경제 담당이 확인한다.

## 5. 상인·우호도·임무 — 확정

모든 상인에게 우호도 수치가 있다. 일정 우호도 또는 임무 진행으로 추가 임무와 다른 상인의 소개가 열리는 구조를 사용한다. 각 상인의 정확한 수치와 조건 조합은 미정이다.

| 상인 | 역할 |
|---|---|
| 잡상인 | 게임 시작부터 해금. 기초 튜토리얼 임무와 다른 상인 소개의 출발점. |
| 무기 상인 | 무기 취급. 구체적인 매입·판매 품목과 서비스는 후속 설계. |
| 방어구 상인 | 방어구 취급. 구체적인 매입·판매 품목과 서비스는 후속 설계. |
| 연금술사 | 출혈·골절·식중독 등 물리적 부상·질환 치료와 의약품 판매. |
| 성직자 | 저주 해제와 신성한 가호. 던전 안에서도 이를 사용할 수 있게 하는 물건 판매. |
| 음식 상인 | 식재료 판매. |

잡상인 튜토리얼의 확정된 내용은 던전 입장, 몬스터 처치, 던전에서 물건 회수, 은신처 업그레이드 또는 꾸미기다. 일정량의 임무를 끝내면 다른 상인을 소개한다. 정확한 임무 개수·처치 수·회수품·소개 순서는 아직 정하지 않았다.

PD 제안: 튜토리얼 임무는 실제 해당 기능을 수행했을 때 진행한다. 수락·추적·달성·보고·보상·소개 해금이 하나의 흐름으로 연결되어야 한다. 사망 전 처치 기록과 회수품 전달의 인정 방식은 각각 명시한다. 필수 치료를 받기 위한 임무가 그 치료 없이는 수행 불가능한 구조가 되지 않게 한다.

## 6. 전투·마법·원거리 — 확정 및 미정

### 근접 무기

- 기본 마우스 공격은 세 번의 휘두르기가 반복되는 간단한 조작이다.
- Alt를 사용하면 상·하·좌·우·중앙 중 원하는 공격 방향을 선택할 수 있다.
- 특정 커맨드 순서에 맞게 공격하면 무기 콤보가 발동한다.
- 철퇴·도끼·롱소드 등 모든 냉병기에 이 공통 방향을 적용한다.
- Alt를 누르고 있는 방식인지 전환 방식인지, 방향을 마우스로 고르는지, 중앙이 찌르기인지, 입력 허용 시간과 취소 규칙은 미정이다.

PD 제안: 공통 입력 규칙을 공유하되 무기별 사거리·공격 궤적·속도·회복 시간·유효 콤보는 다르게 설계한다. 기본 공격에도 쓰임을 두고, 방향 공격과 콤보는 적의 방어를 공략하는 선택으로 검증한다. 기존 차지 공격·방패·검격 방어·사슬철퇴 특수 공격과의 관계를 먼저 정리한다.

### 방패 — 사용자 확정 (2026-09-12)

- 방패로 가드를 유지하는 동안 적의 공격 피해를 완전히 막는다. 피해를 전부 막기 위해 정확한 타이밍을 맞출 필요는 없다.
- 공격이 닿는 순간에 맞춰 방패를 올리는 저스트 가드는 피해 차단에 더해 공격한 적을 스턴시킨다. 타이밍을 맞춘 보상은 적의 빈틈이다.
- **사용자 후속 확정 — 기력이 0이면 방패를 아예 들 수 없다.** 가드는 기력이 남아 있을 때만 시작·유지한다. 앞서 채택한 기력 0의 가드 허용은 이 지시로 대체됐다.

현재 구현 판단·조정 가능한 값: 기존 정면 좌우 55도 판정과 적 공격 대상 범위를 유지하며 측면·후방 공격 및 환경 피해는 제외한다. 저스트 가드 판정은 방어 시작 후 0.20초, 스턴은 1.15초로 둔다. 일반 방어는 피격량×1.18의 기력을 0까지 소모한다. 막은 결과 기력이 0이 되면 해당 타격은 완전 방어하고 즉시 방패를 내리며, 다음 타격부터 정상적으로 피해를 받는다. 기력이 회복된 뒤 다시 방어를 요청하면 방패를 들 수 있다. 저스트 가드의 기력 8 회복은 유지하지만 기력 0에서는 가드가 성립하지 않으므로 저스트 가드·스턴·회복 보상이 발생하지 않는다. 이 수치와 고갈 시 타격 처리 방식·방어 범위는 전투 담당의 구현 판단이며 사용자 확정 수치가 아니다. 검날끼리 충돌하는 기존 검격 방어의 0.72초 경직과는 구분한다.

구현·검증 상태: **기력 고갈 후속 변경 검증 완료**. 실제 플레이어·적 판정과 기존 방패 시험에 연결했고, 기력 0 거절·막은 직후 고갈에 따른 해제·실제 방패 하강·회복 후 재가드·원정 복원을 포함한 헤드리스 검사 5개가 통과했다. 창 없는 실제 HUD 상태 5개를 촬영하고 기력 부족 안내와 내려간 방패를 확인했다. [이번 검증 기록](../artifacts/validation/shield_stamina_required_20260912/README.md)을 따른다. 이전 완전 방어·스턴 변경에서 확인한 헤드리스 검사 10개와 HUD 촬영은 [당시 검증 기록](../artifacts/validation/shield_guard_20260912/README.md)으로 보존하며, 현재 기력 고갈 규칙의 통과 근거로 대신하지 않는다. 기존 정밀 모션의 파지·소매·복귀 실패는 수정 전 기준본에서도 같은 항목·프레임으로 재현된 별도 이력이다.

### 마법

- 현재 방향은 마법 지팡이가 있어야 마법을 사용할 수 있는 방식이다.
- 주문 습득·시전 자원·시전 시간·중단·지팡이 종류별 차이는 후속 설계 대상이다.

### 활과 플린트락 머스킷

- 활은 사용자가 설명한 킹덤컴식 사용감을 목표로 한다. 조준선·흔들림·숙련·당김 등의 구체적인 기준은 별도로 정한다.
- 플린트락 머스킷은 장전과 연사가 느리고 한 발이 강력하다.
- 탄약·화약·장전 단계·중단 시 처리·불발 등 세부 규칙은 미정이다. 사용자 언급 없이 자동 추가하지 않는다.

## 7. PD가 제안하는 공통 판단 기준

아래는 사용자 목표를 달성하기 위한 제안이며, 개별 수치가 확정된 것은 아니다.

1. 위험을 감수할수록 더 좋은 전리품에 접근하되, 이미 얻은 물건을 지키기 위해 돌아서는 판단이 유효해야 한다.
2. 치명적인 보스·함정은 소리·동작·환경 흔적 등을 통해 배우고 대응할 단서를 제공한다. 반복 사망이 다음 판단을 개선하는지 확인한다.
3. 공포를 위한 어둠과 실제 조작에 필요한 적의 예고 동작·부상·탈출 정보의 식별성을 함께 검토한다.
4. 높은 장비 비용은 부담을 만들지만, 최저 자산 상태에서도 다시 출발할 길을 남긴다.
5. 안전 지역의 거래·제작 수익과 던전 회수 보상을 함께 비교한다. 기존 생활 기능은 보존하면서 긴장감을 약화시키는 경제 구조가 있는지 검토한다.
6. 세 서사 경로가 공유하는 세계 규칙은 일관되게 유지한다. 서로 다른 신념과 정보로 같은 공포를 드러낼 수 있다.

## 8. 현재 프로젝트와의 차이 — 코드 조사 기준

2026-09-10 읽기 전용 조사 결과다. 이번 기획 정리에서 게임을 실행하거나 기능 테스트를 새로 통과시킨 것은 아니다. 구현 상태는 후속 작업 때 다시 확인한다.

| 분야 | 확인한 기반 | 새 방향을 위해 필요한 일 | 근거 |
|---|---|---|---|
| 거점·월드 | 자유 이동 은신처와 지도에서의 장면 선택 | 걸어서 연결되는 상인 광장, 실제 별도 창고·업그레이드 | `scripts/hideout.gd`, `scripts/main_menu.gd` |
| 원정 | 두 던전 기반과 경과 시간 기록 | 원정 시간 규칙, 단계적인 10개 이상 맵 확장 | `scripts/game.gd`, `scripts/cave_dungeon.gd` |
| 탈출 | 적을 모두 처치한 뒤 귀환문으로 생환 | 전리품 회수 후 조기 탈출 선택의 설계 | `scripts/game.gd`의 `enemies_alive` 조건 |
| 사망·재산 | 사망 결과 화면과 재시작 | 지속 재산과 원정 손실 분리, 파산 후 재기 | `scripts/expedition_session.gd`의 `begin_new_journey()`는 기본 장비·돈·상인 재고도 초기화 |
| 거래·임무 | 중개인 실제 구매·판매와 대화 | 상인별 우호도, 실제 임무 상태, 소개 해금, 무료품 매입 정책 | `scripts/merchant.gd`, `scripts/expedition_session.gd` |
| 근접 | 방패 장착 검의 세 공격 패턴 순환 | Alt 방향 선택, 커맨드 콤보, 다른 냉병기 적용 | `scripts/player.gd` |
| 원거리·마법 | 당김·기력·물리 화살, 지팡이 장착 조건의 실제 시전 | 목표 활 사용감 정의, 머스킷 제작 | `scripts/player.gd` |
| 부상·서사 | 출혈·골절·저주와 함정 연결 | 식중독·상인 치료, 세 목표와 엔딩 진행 | `scripts/expedition_session.gd`, `scripts/cave_dungeon.gd` |

## 9. 제작 순서 — PD 제안

완성 목표인 최소 10개 맵을 유지하며, 먼저 하나의 맵에서 게임 전체 순환을 검증한다. 아래 단계는 구현 완료 선언이나 확정 일정이 아니다.

1. **원정 규칙 결정:** 매입 금지 범위·사망 손실/복구·시간의 의미를 결정하고, 기존 탈출·초기화 방식과 맞춘다.
2. **한 맵에서 핵심 순환 완성:** 준비 → 무료 장비 회수 또는 장비 반입 → 탐험 → 값비싼 전리품 획득 → 계속 진행/탈출 판단 → 귀환·거래 또는 사망·재기를 연결한다. 독립 창고와 지속 재산, 실제 튜토리얼과 첫 상인 소개까지 함께 설계한다.
3. **전투·부상 검증:** 대표 근접 무기 하나로 기본 공격·방향 공격·콤보를 완성하고 보스·함정·치료·활·지팡이의 위험과 비용을 조율한다. 준비 단계의 무기 실험은 2단계와 병행할 수 있다.
4. **거점·콘텐츠 확장:** 은신처↔광장 이동, 여섯 상인 역할, 은신처 성장, 추가 무기·머스킷과 세 서사 경로를 확장한다.
5. **맵 확장과 완주 검증:** 지도별 탐험 방식·환경 위험·전리품·임무·탈출 특징을 구분하여 최소 10개로 늘리고, 세 경로를 처음부터 엔딩까지 검증한다.

첫 맵의 평가 항목은 고가품 획득 전후 탈출 판단의 변화, 사망 원인의 이해 가능성, 연속 실패 후 재출발 가능성, 목표 플레이 시간, 튜토리얼과 거래의 연결이다. 수치 목표는 실제 시험 결과를 보고 정한다.

PvE 협동을 위해 소유권·원정 상태·보상 지급 책임을 명확히 나누는 설계를 검토한다. 실제 네트워크 기능과 협동 규칙은 별도 제작 결정이 필요하다.

## 10. 현재 확인할 질문

| ID | 질문 | 상태 |
|---|---|---|
| Q01 | 매입 금지는 입구 시체의 무료 무기에만 적용하는가, 던전에서 주운 모든 무기에 적용하는가? | 사용자 답변 대기 |
| Q02 | 사망 시 장비·습득품을 어떻게 잃고 부상은 어떻게 복구하는가? 잔고 0에서도 정상적으로 재출발 가능한가? | 사용자 답변 대기 |
| Q03 | 30~60분은 맵별 제한시간인가, 목표 플레이 시간인가? | 사용자 답변 대기 |

다음 설계에서 다룰 질문: 일반 탈출의 조건, 임무 진행 보존, 원정 중 저장/종료, Alt 조작, 세 목표의 선택 시점, 상인 소개 순서. 답하지 않은 규칙을 PD 제안만으로 사용자 확정사항으로 바꾸지 않는다.

## 결정 기록

- 2026-09-12 후속 변경: **사용자 확정 — 기력 0이면 방패를 아예 들 수 없다.** 이전의 기력 0 가드 허용 구현 결정을 대체한다. 방어 중 고갈시키는 타격 자체는 완전히 막은 뒤 즉시 방패를 내리고, 이후 공격은 정상 피해를 주며 회복 후 새 방어 요청으로 다시 올리는 방식은 이번 구현 판단이다. 방패 유지 중 완전 방어와 저스트 가드 시 적 스턴은 유지한다. 실제 판정·같은 테스트룸 항목을 연결하고, 관련 자동 검증 5개와 숨김 HUD 촬영·고갈 화면 검토를 완료했다.

- 2026-09-12 초기 변경: 사용자가 전투 기획 담당 작업명 ‘강형욱’을 지정했다. **사용자 확정 — 방패 유지 중에는 적 공격 피해를 완전히 막고, 완벽한 타이밍의 가드는 공격한 적에게 스턴을 준다.** 당시 기력 0에서도 가드를 허용한 구현 결정은 같은 날 후속 지시로 **대체됨(superseded)**. 정면 판정·0.20초 타이밍·1.15초 스턴 등 수치는 조정 가능한 구현값이다. 당시 실제 방패 기능·테스트룸·관련 자동 검증과 HUD 확인 결과는 역사 기록으로 보존한다. 기존 정밀 모션의 실패도 변경 전 비교 결과와 함께 별도 기록한다.

- 2026-09-12: 사용자가 참고 이미지처럼 아이템 상세 설명을 요청했다. 상세창의 기능은 이름표·버리기와 장착 가능한 물건의 장착하기로 한정한다. 원본 카탈로그의 이미지·설명·속성을 표시한다. 24자 별칭, 수량 선택 후 바닥에 놓고 같은 장소에서 회수하는 방식은 이번 구현 판단이며, 시험 세션에서 이름표·개별 강화 정보·물품 수량을 함께 보존한다.

- 2026-09-12 후속 정정: **사용자 확정 — 은신처는 던전이 아니므로 무작위 루팅 상자를 생성하지 않는다.** 앞선 맵 루팅 요청의 범위는 던전으로 한정한다. 실제 `hideout.tscn`은 기존부터 무작위 생성에 연결되지 않았으며 개인 보관함과 생활 소품을 사용한다. `main.tscn`의 검은 성물실은 은신처와 별도의 던전이므로 폐광과 함께 기존 루팅 적용을 유지한다.
- 2026-09-12: **사용자 확정 — 맵의 루팅 상자는 장소의 용도에 맞는 자연스러운 위치에 놓여야 하며, 같은 자리라도 맵 입장에 따라 있거나 없어야 한다.** 고정 후보 위치를 사용하는 방식은 허용됐다. 제공된 나무 상자 2종·나무 통·보물상자를 사용한다. 현재 두 던전에 후보별 점유 추첨을 적용하며 한 번 들어간 맵에서는 결과와 수색 상태를 유지한다. 후보 수, 개별 확률과 맵당 최소·최대 상자 수는 맵 담당의 조정 가능한 구현값이며 사용자 확정 수치가 아니다. 새 맵을 추가할 때도 보관 이유·바닥 접촉·여는 공간·통행 여유를 검증한 후보를 등록한다. 저장 후 재접속의 원정 지속 규칙은 기존 미정 사항으로 유지한다.
- 2026-09-12: 사용자가 UI·UX 담당 작업명 ‘유아인’을 지정하고 첨부 은신처 화면의 UI 제거와 조준선 확대를 요청했다. 해당 화면의 위치·생존·생활 안내 카드, 하단 조작 안내 및 지도 버튼을 숨기며 중앙 점 조준선을 유지한다. 확대 배율 2배는 이번 구현 판단이다. 가방·지도·일시정지와 상호작용 시 표시되는 기능 화면은 유지한다.
- 2026-09-10: 사용자 컨셉을 최초 기준으로 등록. 원정의 긴장감, 최소 10개 맵, 싱글 우선, 세 목표와 비극적 엔딩, 여섯 상인 역할, 무료 시체 장비, 공통 근접 조작, 지팡이·활·머스킷 방향을 기록했다. Q01~Q03은 미정으로 보존한다.

담당자 책임과 작업 인수 기준은 [TEAM_ROLES.md](TEAM_ROLES.md), 실제 개발·검증 규칙은 [AGENTS.md](../AGENTS.md)를 따른다.

## 무장 구성·주무장 입력 — 사용자 후속 확정 (2026-09-12)

- 무장 구성은 주무장 1개, 부무장 2개로 간다. 주무장 기본키는 1이다.
- 의도한 흐름: 비무장 상태에서 검·방패를 주무장으로 갖추고 1을 누르면 둘을 꺼낸다. 검·방패를 들고 다시 1을 누르면 방패를 수납하고 검만 유지한다.
- 이번 우선 구현 범위는 사용자의 “일단 1번을 누르면 방패를 집어넣게” 지시다. 검·방패를 든 상태의 1 입력과 왼쪽으로 빠지는 방패 수납, 수납 후 검 유지 및 방패 방어 해제를 구현한다. 물품 자체를 장착 해제하거나 버리지 않는다.
- 전체 주/부무장 슬롯 개편과 비무장 → 주무장 꺼내기 입력 연결은 아직 미구현이다. 검만 든 뒤 추가 1 입력의 동작은 미정이며 이번에는 변화가 없다. 장비를 다시 장착하거나 테스트룸 시험을 재선택하면 방패 준비 상태로 복원한다.
- 1키는 검을 든 상태에서 주무장 입력이 우선한다. 지팡이의 기존 숫자 주문 선택은 유지하며 전체 입력 개편은 후속 범위다.

- 2026-09-13 사용자 후속 확정: 방패 수납 후 왼손이 검을 잡아 양손 파지로 전환한다. 왼손 복귀·손가락 파지·검 추종을 이번에 확장하며, 공격력 등 전투 수치는 변경하지 않는다.

- 2026-09-13 사용자 후속 확정: 검 양손 파지의 휘두르기 모션은 검·방패와 통일한다. 동일한 세 방향 베기와 재생 시간 및 동작에 맞는 타격 시점을 사용하며, 방패 소지 판정과는 분리한다.
- 2026-09-13 사용자 수정 지시: 우→좌 기본 베기는 날로 베는 궤적과 관성에 맞는 마무리·복귀로 다듬는다. 좌→우 역베기의 검 위치·모양은 보존하고, 오른손 엄지의 과도한 침투와 왼손의 느슨한 파지만 수정한다. 검 원본과 전투 수치는 유지하며 구현·실제 렌더 검증 상태는 테스트룸 문서에 기록한다.
- 2026-09-13 이전 사용자 확정: 기본 우→좌 베기는 현재 파지 위치에서 손목을 돌려 검을 눕힌 후 날부터 벤다. 공격 전에 검을 한 번 더 치켜드는 동작은 없앤다. 이전 직접 공격의 ‘준비 중 검·팔 자세 전체 유지’ 구현 기준은 기본 베기의 손목 회전을 허용하는 이 지시로 대체한다. 방패 착용/수납은 같은 공격 연결과 속도를 사용하며 기존 차지·피해·기력·방패 방어 규칙을 유지한다.
- 당시 구현 판단: `right_diagonal` 준비 0.14초 동안 파지 중심(`GRIP_CENTER`) 위치를 유지하며 손목을 회전하고, 활성 첫 0.10초는 같은 시각의 제작 모션으로 연결한다. Mac 제작 기본 베기는 얕은 우상향 검 길이축과 고정된 날면을 유지한 채 손이 좌하향으로 이어지는 당겨 베기로 조정하며, 끝부분의 180도 반전을 제거한다. 역방향·내려베기 데이터와 원본 손 모델은 보존한다. 최소 준비 0.22초·차지 판정 기준 0.24초, 활성 구간 기준 타격 0.145초·활성 길이 0.30초는 기존 튜닝값을 유지한다.
- 당시 구현·검증 상태: 위 날 정렬 변경의 관련 자동 검사 10종과 실제 Vulkan/embedded 촬영을 완료했다. 기존 자연 검격 교차 시험 1건은 변경 전과 같은 항목에서 실패한다. 원본 손 모델의 엄지·왼손 모양을 추가로 교정했다는 뜻은 아니다.  변경 전 소스는 `../../asset-staging/sword_edge_alignment_20260913/baseline/`에 보존한다. 테스트룸의 기존 `주무장 1번 · 방패 수납`에서 검·방패와 양손 상태를 비교하며 세부 절차·결과는 [TEST_ROOM.md](../TEST_ROOM.md)에 기록한다.

- 2026-09-13 이전 복원 지시: 마지막 좌우 대칭 역베기 결과가 거절되어 해당 변경을 취소한다. 승인된 `right_diagonal`은 유지하고, `left_reverse`와 해당 런타임 연결은 `../../asset-staging/sword_reverse_match_20260913/baseline/`의 변경 직전 상태로 복원한다. 새로운 모션 방향은 추가로 확정하지 않는다.
- 복원 상태: 직전 baseline으로 복원하고 관련 자동 검사 4종을 통과했다. 다시 촬영한 양손 기본·역베기 총 182 PNG가 변경 전 촬영과 모두 일치하며 원정·가방·커서를 보존했다. 복원 근거는 `../../asset-staging/sword_reverse_restore_20260913/validation_summary.json`에 기록한다. 거절된 변경의 검사·촬영과 복원 전 문서는 과거 이력으로 보존하며 새 모션의 사용자 승인을 뜻하지 않는다.

- 2026-09-13 이전 사용자 지시: 복원된 `left_reverse`를 보존하고, `right_diagonal`을 그 역베기와 유사하되 방향만 반대로 바꾼다. 앞선 정베기 승인본 고정과 얕은 우상향·고정 날면 기준은 이 후속 요청으로 대체했다.
- 당시 후보 03 구현 판단: 정베기 제작 시각 0~0.80초는 원본 역베기의 `1.42 - 새 시각`에 해당하는 동일한 `sword`·`right_arm` 포즈를 사용했다. 회수에서는 원본 0.341666667~0.62초의 준비 정지를 생략하고 새 0.803333333~1.42초에 원본 0.341666667→0초의 기존 포즈로 대기 복귀를 이었다. 공간 반전·새 팔 생성 없이 기존 포즈를 재사용했다. 별도 0.14초 손목 준비를 제거하여 WINDUP의 시작 자세·높이를 유지하고, 정베기는 활성 0.145초 타격 시점까지 직접 연결했다. 역베기·내려베기의 연결은 기존 0.10초를 유지했다. 정베기 방패 곡선은 새 시각 격자에서 원래 같은 시각 포즈를 재표본화했으며 바이트 동일성을 뜻하지 않는다. 기존 최소 입력 0.22초·차지 판정 0.24초, 타격 0.145초·활성 0.30초, 피해·기력·방패 규칙은 유지했다.
- 당시 검증 이력: 후보 03을 적용하고 관련 자동 검사 5종과 실제 Vulkan/embedded 촬영을 완료했다. 방패·양손에서 기존 역베기의 총 182 PNG가 변경 전과 같았으며, 수정 정베기의 우→좌 진행·대기 복귀를 직접 확인했다. 정베기 진입의 한 프레임 화면 밖 이동은 남아 있었다. 이 결과는 아래 파지 방향 변경 전 기록이며 검격 교차 시험과 이전 후보 이력을 구분한다. 근거·제한·변경 전 자료는 `../../asset-staging/sword_forehand_from_reverse_20260913/validation_summary.json`, `visual_review.json`, `baseline/`에 보존한다.

- 2026-09-13 이전 사용자 지시: 정베기의 우→좌 이동은 승인했으며, 이동을 유지한 채 검 모델 방향을 반대로 바꾼다.
- 당시 구현·검증 이력: 최종 실제 파지점 중심의 로컬 Z축 회전으로 검과 오른쪽 장갑을 함께 돌려 활성 0.145초 타격까지 점진적으로 180도에 도달하게 했다. 왼손 추종과 소매 IK, manifest·원본 GLB·역베기와 기존 공격 시간·차지·피해·기력·방패 규칙은 보존했다. 관련 검사 8종과 실제 양손·방패 촬영을 완료했으며 기존 역베기 182 PNG와 원본 모션·모델을 보존했다. 회수 중 화면 밖 구간과 기존 자연 검격 교차 시험의 동일한 5개 실패는 당시에도 남아 있었다. 이 결과는 아래 즉시 베기 변경 전 기록이며 영상·변경 전 자료·검사 근거는 [검증 기록](../../asset-staging/sword_forehand_grip_direction_20260913/validation_summary.json)에 보존한다.

- 2026-09-13 이전 지시·구현: 공격 모션을 기존 역베기와 유사하게 만든다. `left_reverse`의 같은 시각 움직임을 기준으로 `right_diagonal`을 좌우 반대 방향으로 제작하며 칼끝 높이·앞뒤 거리·날면과 베기 리듬을 유지한다. 기존 역베기와 나머지 클립, 원본 오른손·검 GLB는 보존한다. 짧은 정베기 입력을 놓으면 바로 공격을 시작하는 규칙과 누르기 차지·피해·기력·방패 규칙은 유지한다.
- 이번 구현 판단: Mac에서 manifest의 `right_diagonal`만 변경한다. 기존 역베기의 같은 시각 검·팔 자세를 화면 좌우 반대로 대응시키고, 모델 형상을 보존한 채 실제 오른쪽 손목에 팔을 맞춘다. 시작과 끝은 원래 오른쪽 대기 자세로 부드럽게 연결한다. 정베기의 별도 180도 회전과 독립적인 타격 자세 진입을 제거하고, 두 베기 모두 활성 첫 0.10초 동안 시작 자세에서 해당 시각의 제작 모션으로 연결한다. 기존 타격 0.145초·활성 0.30초와 전투 수치를 유지한다.
- 현재 구현·검증 상태: 관련 자동 검사 9종을 통과하고 실제 embedded Vulkan에서 양손·방패의 두 베기를 364개 시퀀스 PNG로 촬영했다. 기존 역베기 182개 PNG가 변경 전과 바이트 단위로 같았으며, 정베기를 제외한 9클립과 원본 모델을 보존했다. 보이는 베기의 칼끝 높이·깊이·날 기울기의 좌우 대응과 새 손·소매 분리 없는 대기 복귀를 확인했다. 활성 약 0.183초에는 두 검이 동일하게 화면 밖으로 나가며, 팔 모델의 완전한 좌우 대칭·해부학 전체 검증과 사용자 최종 미감 승인은 이 결과에 포함하지 않는다.
- 검증 기록: 기존 `sword_clash`의 동일한 4개 항목 실패는 이번 9종 통과에서 제외한다. [검증 요약](../../asset-staging/sword_forehand_mirror_reverse_20260913/validation_summary.json), [화면 검토](../../asset-staging/sword_forehand_mirror_reverse_20260913/visual_review.json), [전투 검사 로그](../../asset-staging/sword_forehand_mirror_reverse_20260913/combat_tests.log)에 근거를 기록한다. 기존 `주무장 1번 · 방패 수납`의 실제 표적에서 역베기 기준 양방향 비교를 반복하며 영상·절차는 [TEST_ROOM.md](../TEST_ROOM.md)를 따른다. 직전 `immediate_cut`은 사용자 거절 이력이며 [당시 검사·촬영 기록](../../asset-staging/sword_forehand_immediate_cut_20260913/validation_summary.json)과 원본 자료를 보존한다.

- 2026-09-13 이전 구현 — 정베기를 화면 밖까지 끝까지 휘두르기: 타격 직후 검을 급하게 뒤집던 구간을 수평 베기 연장으로 교체했다. 검·칼끝은 왼쪽으로 계속 진행해 화면 밖으로 빠지며, 화면 아래에서 방향을 정리한 뒤 이미 대기 각도를 갖춘 채 복귀한다. 타격까지의 제작 키, 역베기와 나머지 9클립, 원본 모델·파지, 타격 시간·피해·기력·방패 규칙을 보존했다.
- 이번 검증·사용 위치는 [TEST_ROOM.md](../TEST_ROOM.md)의 최신 항목과 [제작·검증 기록](../../asset-staging/sword_followthrough_20260913/validation_summary.json)을 따른다. 이전 전체 활성 구간의 좌우 반사 기준은 이번 지시로 타격까지의 유지와 화면 밖 후속 베기로 변경되었다.

- 2026-09-14 이전 구현 — 공격 중 방패 유지·역베기 마무리: 검·방패의 정베기·역베기·내려베기 모두 공격 시작 시 들고 있던 방패 위치·각도를 차지부터 회수 끝까지 유지한다. 공격이 끝나면 기존 대기·이동 자세로 연결하며 방어 판정은 기존 RMB·기력 조건을 따른다. 역베기는 타격 이후 칼날의 기울기를 유지하며 오른쪽 화면 밖까지 이어지고, 화면 아래에서 방향을 정리한 뒤 대기 자세로 돌아온다. 정베기·내려베기의 검 궤적과 역베기의 타격까지 제작 키, 원본 모델·파지와 전투 수치는 보존한다.
- 이번 결과와 반복 시험은 [TEST_ROOM.md](../TEST_ROOM.md)와 [검증 기록](../../asset-staging/sword_shield_hold_reverse_finish_20260914/validation_summary.json)을 따른다. 역베기 후속 베기 구간의 변경은 이번 지시가 이전 역베기 전체 보존 조건을 대체한 것이다.

- 2026-09-14 최신 사용자 확정: 공격 중 방패를 고정하던 방식을 대체하고 검을 휘두르기 전에 방패를 왼쪽으로 자연스럽게 빼놓는다. 기존 검 궤적과 화면 밖 마무리는 유지한다.
- 구현 판단: 세 공격 모두 실제 방패 시작 자세에서 0.12초 동안 왼쪽 26cm·위 2cm·뒤 4cm, 옆 회전 10도로 공간을 만든다. 준비→공격 전환의 연속 시계를 사용해 공격 지연 없이 타격 전에 이동을 마친다. 회수 시작 0.06초 뒤부터 대기·이동 자세로 복귀하며 충돌·취소 연결과 기존 방어·기력 규칙을 유지한다. 반복 시험은 [TEST_ROOM.md](../TEST_ROOM.md)의 최신 항목을 따른다.


2026-09-14 최신 사용자 지시 — 방패를 왼쪽 화면 밖으로 완전히 빼기: 앞선 26cm 이동을 95cm 이동으로 늘려 방패 전체가 왼쪽 화면 밖으로 나가도록 한다. 세 공격의 0.12초 선행 이동·회수 복귀 연결과 검 궤적·전투 수치는 유지한다. `F2 → 기본 → 주무장 1번 · 방패 수납`의 **방패 왼쪽 화면 밖으로**와 기존 내려베기 시험에서 짧은/차지 입력을 반복한다. 자동 검사에서는 방패의 모든 메시 경계가 카메라의 왼쪽 시야 밖인지 실제 투영으로 확인한다.


## 2026-09-14 부위별 체력과 상태이상 개편

사용자 확정: 하나의 전체 체력 대신 부위별 체력을 사용한다. 체력이 0인 부위는 일반 회복 수단과 보통의 치유 마법으로 회복하지 못한다. 특수 수술로 0에서 1로 복구한 뒤 다시 치료해야 하며, 높은 단계의 마법도 손상 부위를 복구할 수 있다. 골절·출혈·저주·마비·독을 실제 상태이상으로 추가한다. 첨부 화면은 7부위 상태와 전체 합계를 보여주는 UI 참고다.

이번 구현 판단: 머리35·흉부85·복부70·양팔 각60·양다리 각65, 합440을 사용한다. 머리·흉부가0이면 사망하고 나머지 부위의0은 생존 가능한 손상으로 남긴다. 수술 도구와 3단계 고위 재생은 손상 부위 하나를 정확히1로 복구하며 상태이상은 따로 치료한다. 일반 피해의 잔여량은 살아있는 다른 부위로 분배한다. 현재 적 근접 판정은 기존 사거리·방향 판정을 유지하므로 접근 방향에 따라 전면흉부·측면팔·후면복부·위쪽머리를 선택하며, 바닥 함정은 다리를 다친다. 이는 정밀한 메시 부위 충돌을 구현했다는 뜻이 아니다.

치료 대상은 건강 탭에서 지정하거나 자동 선택한다. 휴식·요리·침상·흡혈은 체력이 남은 부위만 회복한다. 부위 상태는 원정 세션에 보존하고 테스트룸의 전체 회복·총체력 수치 조절은 시험 초기화를 위한 명시적 우회로 구분한다. 골절·출혈은 다친 위치를 표시하며 독·저주·마비는 전신 상태로 표시한다. 새 치료품·마법·상태이상은 원본 카탈로그에서 시험 항목을 자동 등록한다. 수치·피해부위 선택·사망 조건·효과 강도는 조정 가능한 구현 규칙이며 별도의 사용자 확정 수치로 간주하지 않는다.

구현·검증 상태: 실제 플레이·은신처·동굴·테스트룸에 통합하고 부위별 치료, 상태이상, 무기 불이익, 사망·재시험·원정 복원과 기존 관련 회귀를 검증했다. 1280·960의 실제 UI 좌표 입력과 embedded Vulkan 6장을 확인했다. 동굴 사망 후 F2 복귀의 첫 물리 틱 이전 회복 누락도 수정·재검증했다. 결과·검증 범위·실제 화면은 [검증 기록](../artifacts/validation/body_health_20260914/README.md)과 [테스트룸 안내](../TEST_ROOM.md)에 기록한다.

### 2026-09-14 건강 화면 참고 디자인 적용

최신 사용자 지시: 제공한 갑옷 전신 건강 UI와 매우 유사하게 화면을 제작한다. 참고의 어두운 성소·깃발·촛불·갑옷 인물, 황동 장식, 명조체, 붉은 체력 막대, 부위 위치와 상하단 구성을 따르며 가로 게임 화면에 맞춘다. 기본 화면에서는 인물을 중심으로 일곱 체력을 표시하고 부위 선택 시 실제 치료창을 연다. 기존 수술·마법·상태이상·선택 부위·실제 440 체력 규칙은 유지한다. 이번 UI 요청을 새로운 피로·체온 시스템이나 머리 최대 55의 확정으로 취급하지 않는다. 별도 답변이 없는 하단 지표는 기존 포만감·수분·기력·스트레스 데이터에 연결한다. 제작·검증 상태는 [화면 개편 기록](../artifacts/validation/health_reference_20260914/README.md)에 기록한다.


### 2026-09-14 장비·건강 상태 통합

최신 사용자 확정: 별도 장비 탭과 건강 탭을 통합하고, 새 가로 참고처럼 왼쪽 인물·부위 체력·생존 상태와 오른쪽 장비·주머니·허리 파우치·배낭·빠른 사용을 한 화면에 표시한다. 이 지시가 앞선 장비/건강 화면 분리를 대체한다.

구현 판단: 실제 장비 5슬롯과 가방 30칸을 그대로 사용하며, 수납 목록을 8/6/16칸의 표시 구역으로 나눈다. 빠른 사용은 가방에 남은 소비품을 순서대로 최대10개 자동 표시하고 버튼/1~0으로 실제 사용한다. 부위 치료·상태이상·수술·고위 재생·아이템 상세·이름표·장착·폐기는 같은 기존 모델을 사용한다. 참고 그림의 온도·방사능 숫자나 없는 장비 부위를 새 게임 규칙으로 추가하지 않는다. 배경의 기사는 상태 화면용 삽화이며 실시간 장비 모델 미리보기로 간주하지 않는다. 구현과 실제 검증은 [통합 기록](../artifacts/validation/unified_inventory_20260914/README.md)에 남긴다.


2026-09-14 사용자 지시: 상자에 손을 뻗어 잠금을 만지고 뚜껑을 드는 모션을 제거했다. 손 원본 에셋은 보존하며 실제 상자 열기에서는 손 리그를 활성화하거나 진행시키지 않는다. 1.2초 열기·뚜껑 애니메이션·수색·아이템 이동과 장비 숨김/복귀, 취소·F2·재선택·원정 복원은 유지한다. 테스트룸의 `상자 조사 · 열기 · 수색`과 `상자 모션 · 손 동작 없이 열기`에서 반복할 수 있다.


### 2026-09-14 허리 파우치·배낭 장비 교체

사용자 확정: 장착 장비 칸에서 허리 파우치와 배낭을 교체할 수 있어야 한다. 두 장비 슬롯을 추가하여 기존 5슬롯을 7슬롯으로 확장한다. 구현 판단: 기본품과 가벼운 교체품을 각 한 종류씩 두고 기존 상세·장착·해제·이름표·버리기 경로를 사용한다. 소지품은 공용 가방에 유지하고 전체 수납은 기존 30칸이다. 교체 전 장비와 개별 이름표를 보존하며, 기존 5키 장비 데이터도 새 슬롯을 수용한다. 가방 종류별 용량이나 중첩 가방 수납 규칙은 이번 요청에 포함하지 않는다. 테스트룸의 실제 교체 시험과 1280·960 입력/화면 검증을 함께 제공한다.


### 2026-09-15 사용자 지시 — 던전 전투 화면

던전 입장 시 참고 이미지처럼 상단 소지품 단축키, 초록 인체 체력 표시와 인접한 조건부 디버프 아이콘을 노출한다. 앞선 은신처 상시 UI 제거와 적용 장소가 다르다. 물품 사용은 실제 장비·치료·소비로 이어진다.

UI 구현 기준: 1~0의 고정 자동 기본 배치, 실제 일곱 부위 체력과 총 체력/기력, 활성 상태만 보이는 경고. 배고픔·갈증 25 이하, 기력 25% 이하, 스트레스 60 이상을 경고 임계값으로 사용한다. 스트레스의 어지러움 표시와 기력의 피곤함 표시는 기존 수치의 경고이며 독립적인 추가 질환은 아니다. 저주 등 실제 상태이상은 활성 여부를 따른다. 주문 선택은 던전에서 Alt+숫자로 분리하고 기존 시험 항목 조작은 유지한다. 사용자 지정 배치 편집과 별도 피로 질환은 이번 범위에 포함하지 않는다.


### 2026-09-15 사용자 지시 — 아이템 사용 중 남은 시간과 F 취소

중앙 원형 사용 진행 표시와 남은 초, F 취소를 실제 아이템 사용에 연결한다. UI에서 시작하는 소모품 사용은 시간이 끝나야 아이템 한 개 소비와 효과가 적용된다. 취소·중단은 미완료 소비/효과를 남기지 않는다. 붕대·부목은 기존 제작 모션 시간과 맞추고, 일반 약/물 3초·식량 4초·마법서 5초·수술 12초를 이번 구현의 조정 가능한 기본 시간으로 둔다. 참고 영상은 직접 불러오지 못했으므로 첨부 스크린샷의 원형 타이머·소수 초·F 취소를 시각 기준으로 사용한다. 타이머는 원정 저장 필드가 아닌 현재 플레이어의 일시적 행동 상태이며 장면 전환과 시험 복원 때 취소한다.

### 2026-09-17 사용자 지시 — 제작한 육포를 꺼내 먹기 / Eating the authored jerky

[참고 영상 1:45–1:53](https://www.youtube.com/watch?v=kaJqMSBgi00&t=105s)의 오른손으로 꺼내기·입에 가져가 베어 물기·잠깐 내리기·두 번째 한입 흐름을 제작한 불규칙 육포에 적용한다. 해당 구간을 실제 브라우저 화면에서 확인했다. 영상의 소시지를 기존 육포 모델로 바꾸고 엄지·검지로 얇은 끝을 집으며, 손목과 팔은 연결한 채 입을 시점 아래에 둔다. 두 번 베어 문 모양은 원본 재질과 손에 잡힌 부분을 유지하고 노출된 끝만 바꾼다.

구현 시간은 영상 구간에 맞춘 8초이며 조정 가능하다. 음식 효과는 기존 식량의 포만감 32를 재사용한 구현값이다. 완료 시 1개 소비, 중도 취소 시 미소비, F 취소·F2 재시험·원정 격리를 유지한다. 새로운 회복 효과나 식량 밸런스 확정은 아니다.

The referenced 1:45–1:53 sequence was inspected in the browser. Its right-hand draw, bite, brief lowering and second bite are adapted to the existing irregular jerky, using a calibrated thumb/index pinch and connected wrist. The food reaches the lips below the eye camera. Bitten meshes preserve the held end and original material. The adjustable duration is eight seconds; the implementation reuses the existing ration's 32-point hunger effect, commits one item only on completion, and retains cancellation and isolated test-room replay.

### 2026-09-15 사용자 후속 지시 — 나무 막대와 붕대로 부목 제작

사용자는 버클·가죽 스트랩 방식의 부목이 어색하다고 지적하고 [Gray Zone Warfare 영상 31초부터](https://www.youtube.com/watch?v=sjPpfdlupx4&t=31s)처럼 손목 아래에 나무 막대를 받치고 붕대를 감는 방식으로 교체하도록 지시했다. 이전 버클형은 현재 확정 외형이 아니며 제작 이력으로 보존한다. 해당 영상 31~37초의 지지대 배치·팔 회전·붕대 감기·끝 눌러 고정을 실제 브라우저 화면으로 확인했다. 기존 왼팔 치료에 맞춰 좌우 반전하고 현대식 지지대 재질은 단순 나무로 바꾼다. 공통 사용 완료·F 취소 규칙은 유지하며 모션 시간은 7.2초로 조정한다. 제작·실제 검증 상태는 `asset-staging/splint_wrap_20260915/` 기록을 따른다.


### 2026-09-15 사용자 확정 — 제공한 FP arms로 팔·손 교체

제공 파일 `fp_arms.glb`를 1인칭 팔·손 기본 외형으로 사용한다. 검은 소매·갈색 반장갑을 원본대로 유지하고 좌우 실제 뼈대를 기존 무기 동작에 연결했다. 검·방패와 양손 베기의 기존 궤적·장비 위치·전투 규칙은 유지한다. 원본은 `asset-staging/fp_arms_20260915/`에 보존하며 제작·검증은 Mac에서 수행했다. 이번 작업은 1인칭 팔 교체이며 전신 캐릭터 외형 교체를 의미하지 않는다.


### 2026-09-17 사용자 확정 — 제공 모델로 오크 적 추가 / Supplied orc enemy

사용자가 오크의 원본 메시·애니메이션 FBX·텍스처를 제공하고 적 NPC 추가를 요청했다. 기존 캐릭터 그래픽 담당이 원본 도끼·장비·스킨·애니메이션을 통합한다. 구현 판단으로 기존 근접 적 AI와 방패/피격/보상 규칙을 재사용하고 테스트룸 전용 대련 및 폐광 동쪽 창고 적에 적용한다. 던전의 적 수와 기존 창고 적 수치를 유지하며 신규 보스·종족 서사·별도 전투 규칙은 확정하지 않는다.

The user requested an enemy NPC using the supplied orc assets. The implementation reuses existing melee AI, blocking, damage and rewards, with a dedicated test-room duel and the eastern mine store encounter. Existing counts/stats remain unchanged; no new boss, lore or separate combat rules are established.


### 2026-09-17 사용자 후속 확정 — 오크 그래픽 삭제 / Orc graphics removed

사용자가 추가된 몬스터 그래픽을 거부하고 삭제를 요청했다. 위 오크 추가 결정을 철회하여 게임용 오크 모델·행동 코드·테스트룸 대련을 제거하고 동쪽 창고의 기존 검지기를 복원한다. 제작 원본은 보존하며 이 에셋을 재적용하지 않는다. 다른 적과 전투·보상 규칙은 유지한다.

The user rejected the added monster graphics and requested removal, superseding the orc addition above. Remove the runtime asset, controller and trial, restore the original store warden, and preserve the source files without reapplying them. Other enemies and combat/reward rules remain unchanged.

### 2026-09-17 사용자 후속 확정 — CGTrader 크리프 적용 / CGTrader Creep integration

사용자는 오크 삭제 후 지정한 [Creep Creature](https://www.cgtrader.com/free-3d-models/character/fantasy-character/creep-creature)의 모델과 애니메이션을 받아 적용하도록 요청했다. 새 모델의 적용은 확정이며, 이전 오크를 다시 쓰는 결정은 아니다. 제작자는 andriichykrii다. 라이선스에 따른 원본·변환 에셋의 로컬 보관과 공개 저장소 설치 방법은 [크리프 안내](../docs/CREEP_ASSET.md)에 기록한다.

After removing the orc, the user requested the specified Creep Creature model and animations by andriichykrii. This confirms use of the new asset without reinstating the rejected orc. The linked guide documents local asset storage and installation for public-repository users.

구현 판단: 에셋 설치 시 폐광 동쪽 창고 적 한 명과 테스트룸 전용 대련에 연결한다. 기존 적 여섯 명·창고 적 수치·근접 전투·방패·피격·보상·귀환 규칙을 재사용한다. 원본 17개 클립은 보존하고, 게임에서는 대기·추적·물기·양손 연타·피격·사망 6개를 사용한다. 반복이 포함된 공격 클립은 첫 완결 동작 구간만 게임의 한 공격으로 사용한다. 미설치 환경은 기존 검지기를 유지한다. 신규 보스·종족 서사·추가 공격 규칙은 확정하지 않는다.

Implementation choice: integrate one eastern-store encounter and a dedicated test-room duel when installed. Reuse existing encounter count, stats, combat, shield, damage, reward, and extraction rules. Preserve all seventeen clips, connecting six to current behavior and using the first complete cycle of repeating attack clips. Missing-asset environments retain the original warden. No new boss, species lore, or additional combat system is established.

실제 게임 연결과 설치·미설치 자동 검사, GPU 화면 10장 검토를 완료했다. [검증 기록](../artifacts/validation/creep_20260917/README.md)을 따른다. / Integration, installed/missing-asset checks and ten actual GPU renders are verified; see the validation record.

### 2026-09-17 크리프 사망 래그돌 / Creep death ragdoll

사용자 후속 요청에 따라 크리프의 사망을 실제 관절 물리로 연결한다. 구현 범위는 기존 Creep 뼈대의 사망 반응·래그돌 전환·바닥과 벽 접촉이며, 원본 모델과 17개 동작 클립을 보존한다. 살아 있는 적의 공격·방패·피격·처치 보상과 폐광 조우 수는 기존 규칙을 유지한다.

The follow-up request connects Creep death to physical joints. The implementation covers a death reaction, ragdoll transition, and floor/wall contact on the existing skeleton while preserving the source model and all seventeen animation clips. Living attacks, shield interactions, damage, defeat rewards, and mine encounter counts retain their existing rules.

테스트룸에 정면·측면·북쪽 벽 사망 시험을 연결한다. 회복·재생성 후 1초 뒤 실제 피격 함수로 치명타를 주고, F2 일시정지·재선택·초기화·원정 격리를 포함한다. 물리·테스트룸·관련 전투 검사와 실제 GPU 영상 검증을 완료했다. [검증 범위](../artifacts/validation/creep_ragdoll_20260917/README.md)를 따른다.

The test room adds front, side, and north-wall death scenarios. Each heals and respawns, then sends a fatal hit through the real damage function after one second, including F2 pause, replay, reset, and expedition isolation. Physics, test-room, related combat checks and real GPU-video validation passed; see the linked scope and limitations.

## 2026-09-18 크리프 부위 절단 — 사용자 확정 / Creep dismemberment — confirmed

같은 팔·다리·머리를 집중 공격하면 해당 부위를 절단한다. 사용자는 팔다리 절단 후에도 크리프가 살아서 전투를 계속하도록 선택했다. 머리 절단은 즉시 사망이며, 일반 체력 소진에 따른 사망·기존 처치 보상은 유지한다. 초기 구현값(부위당 2회 이상·누적 35, 다리 손실 시 이동 속도 50%/18%)은 조정 가능한 제작 판단이다. 실제 부위 메시·피격 위치·분리 물리·생존 공격·F2 시험을 연결했다. [동작·설치 안내](../docs/CREEP_DISMEMBERMENT.md)와 [검증 근거](../artifacts/validation/creep_dismemberment_20260917/README.md)를 따른다.

Focused hits sever the selected arm, leg or head. The user chose continued combat after limb loss; decapitation kills immediately. Normal health depletion and single death rewards remain. The initial two-hit/35-damage threshold and 50%/18% leg-loss speeds are tunable implementation values. See the linked implementation and validation records.

### 2026-09-18 후속 사용자 확정 — 다리 절단 후 기어가기 / Confirmed follow-up: crawling after leg loss

사용자는 다리가 절단된 크리프가 기어다니도록 요청했다. 한쪽 다리만 잃어도 몸을 지면으로 낮추고 손을 번갈아 뻗어 당기며 이동한다. 기존의 서 있는 추적 자세를 기울여 보이는 방식은 대체한다. 낮은 자세에서는 서서 펀치하지 않고 물기로 공격한다. 팔다리 절단 후 생존, 머리 절단 즉시 사망, 체력 소진과 보상 규칙은 유지한다.

The user requested crawling after leg severance. Losing either leg lowers the body to the ground and alternates reaching and pulling with the supporting hands, replacing the earlier tilted upright pursuit. Attacks use a low bite instead of standing punches. Continued survival after limb loss, immediate death after decapitation, ordinary health depletion and reward rules remain.

구현 판단: 원본 `sleep_loop`의 누운 골격 자세에 코드로 손 IK·몸통 이동을 더하며, 별도 FBX 포복 클립 제작으로 간주하지 않는다. 약 0.48초 자세 전환, 이동 속도 50%/18%, 이동용 캡슐 높이 0.86m, 공격 사거리 1.15m를 조정 가능한 초기값으로 사용한다. `F2 → 기본 → 크리프 절단`의 왼다리·오른다리에 새 동작을 연결하고 양다리 시험을 추가한다. 양다리 시험에만 체력 118을 주고 실제 18 피해 네 번으로 체력 46을 남긴다. 원본 모델·17개 클립과 일반 적 체력은 보존한다.

Implementation choice: use the source prone `sleep_loop` skeletal pose with procedural hand IK and body movement, rather than claiming a separately authored crawl FBX clip. Tunable starting values are a 0.48-second pose transition, 50%/18% movement factors, a 0.86m navigation capsule and 1.15m attack range. Existing left/right-leg F2 trials use the new motion, and a both-legs trial starts at 118 test-only HP before four actual 18-damage hits leave 46 HP. The source model, seventeen clips and normal enemy health are preserved.

관련 자동 검사 7개, 최종 집중 검사와 실제 GPU 영상 36초 검증을 완료했다. 실제 검사·영상과 남은 제약은 [기어가기 검수 기록](../artifacts/validation/creep_crawl_20260918/README.md)에 남기며, 이전 절단 영상의 검증 완료를 새 동작의 완료로 간주하지 않는다. / Seven related suites, a focused final rerun and a 36-second actual GPU video passed. Executed checks, actual video and remaining limits belong in the linked crawl validation record; completion of the earlier dismemberment video does not establish completion of this motion.

### 2026-09-18 후속 사용자 확정 — 랙돌 착지 후 포복 회복 / Confirmed follow-up: prone recovery after a physical fall

다리가 절단되면 바로 포복 자세를 취하지 않고 실제 랙돌로 쓰러진다. 신체가 바닥에 닿고 안정된 뒤 포복 자세를 갖추고 플레이어를 쫓아간다. 이는 앞선 약 0.48초 즉시 포복 전환을 대체한다. 생존 상태의 낙하(`falling`)와 착지 후 자세 전환(`recovering`) 동안 추적과 공격을 중지하며, 실제 쓰러진 뼈 자세에서 포복으로 이어지도록 한다. 사지 절단 후 생존·머리 절단 사망·보상·이동 속도 규칙은 유지한다.

After leg severance, the creature falls with actual ragdoll physics rather than immediately adopting its crawl pose. It begins prone recovery only after its body has landed and stabilized, then pursues the player. This replaces the earlier immediate ~0.48-second crawl transition. Living `falling` and grounded `recovering` phases suspend pursuit and attacks, and recovery starts from the actual physical bone pose. Survival after limb loss, death after decapitation, rewards and movement factors remain unchanged.

착지 판단은 몸통·머리의 지면 접근과 물리 움직임의 안정성을 함께 확인하며 고정 시간만으로 판정하지 않는다. 이 기준과 회복 시간은 구현에서 조정할 수 있는 값이다. 기존 F2 왼다리·오른다리·양다리 항목에 실제 절단 → 랙돌 낙하 → 착지 → 포복 → 전투 재개를 연결하고 각 단계의 일시정지와 중도 취소를 검증했다. 새 `creep_knockdown`을 포함한 **자동 검사 8개와 실제 GPU 영상 60초 검증을 통과**했다. 결과·기록·남은 제약은 [랙돌 착지·회복 검수 기록](../artifacts/validation/creep_living_fall_20260918/README.md), 실제 동작은 [새 시연 영상](../artifacts/validation/creep_living_fall_20260918/creep_living_fall.mp4)에 남긴다. 이전 포복 영상 통과를 이번 물리 전환의 완료 근거로 사용하지 않는다.

Landing uses both torso/head ground proximity and stable physical movement, not a timer alone; thresholds and recovery duration are tunable implementation choices. Existing F2 left-leg, right-leg and both-leg trials exercise real severance, physical fall, landing, prone recovery and resumed combat, with phase pause and cancellation checks. **Eight automated suites and a 60-second actual GPU video review passed**, including the new knockdown suite. Results, evidence and limitations belong in the linked fall/recovery validation record and new demonstration video. The earlier crawl video does not validate this physical transition.

### 2026-09-18 후속 제작 — 포복 중 하체 동작 / Lower-body motion during crawling

포복 중 상체뿐 아니라 골반과 남은 다리도 움직이도록 보완한다. 남은 다리 관절을 원본의 누운 자세에 고정하지 않고 움직이며, 골반은 팔로 몸을 당기는 흐름에 맞춰 무게를 옮긴다. 양다리가 없으면 팔·골반의 움직임으로 진행하고 없어진 다리는 되살리지 않는다. 기존 랙돌 낙하 → 착지·안정 → 포복 회복 → 추적과 낮은 물기 공격, 피해·속도·보상 규칙은 유지한다.

The crawl follow-up moves the pelvis and surviving leg alongside the upper body. Remaining leg joints articulate instead of staying fixed in the source sleeping pose, and pelvic weight shifts follow the arm-pulling rhythm. When both legs are missing, motion uses the arms and pelvis without restoring detached limbs. Existing physical fall, stable landing, prone recovery, pursuit, low bites, damage, speed and reward rules remain intact.

기존 F2 왼다리·오른다리·양다리 시험의 설명과 정지 검사를 확장하고 실제 크리프 추적 경로를 유지한다. 골반·남은 다리 관절을 포함해 F2 정지 시 자세가 고정되는지 확인했다. 관련 자동 검사 **6개와 마지막 조정 후 집중 검사, 실제 GPU 영상 60초 검증을 통과**했다. 새 [검수 기록](../artifacts/validation/creep_lower_body_20260918/README.md)과 [시연 영상](../artifacts/validation/creep_lower_body_20260918/creep_lower_body.mp4)은 이전 랙돌·포복 영상의 검증 완료와 구분한다. 평평한 바닥에서 확인했으며 경사·계단 접지는 미확인이다.

Existing F2 left-leg, right-leg and both-leg descriptions and pause checks are expanded while retaining production Creep pursuit. Pose freezing includes the pelvis and surviving leg joints. **Six related suites, the focused check after the final adjustment, and a 60-second actual GPU video review passed**. The linked new validation record and video are separate from the earlier ragdoll/crawl video results. Validation used a flat floor; slopes and stairs remain unverified.


## 2026-09-18 포복 크리프 검 처형 — 사용자 확정 / Crawling Creep sword execution — confirmed

사용자는 다리가 절단되어 기어다니는 크리프를 처형하는 기능과, 검으로 찔러 넣는 동작 한 가지를 먼저 요청했다. 실제 다리 절단·랙돌 착지·포복 회복을 마친 살아 있는 크리프가 대상이며, 접촉 시 실제 사망·보상·시체 랙돌로 이어진다. 원본 모델과 기존 포복·절단·일반 공격은 보존한다.

The user requested execution of a leg-severed crawling Creep, starting with one sword-stab motion. Eligible living crawlers first complete real severance, physical landing and prone recovery. Contact enters production death, reward and corpse ragdoll. Source models and existing crawl, severance and ordinary attacks are preserved.

초기 제작 판단: 가까운 몸통 조준·LMB 0.4초 이상 누른 뒤 놓기, 검·방패 및 방패 수납 상태 모두 같은 찌르기, 포복 대상에는 추가 저체력·경직 조건 없음. 이는 조정 가능한 조작·밸런스 값이며 다른 적·모든 무기·추가 처형 모션을 확정한 것은 아니다. 같은 변경에서 `F2 → 기본 → 크리프 처형`의 한쪽·양쪽 다리 시험, 실제 플레이 경로와 정지·재시도·원정 복원을 연결한다. 구현·검증 상태는 [처형 안내](../docs/CREEP_EXECUTION.md)를 따른다.

Initial implementation choices: aim at the nearby torso, hold LMB for at least 0.4 seconds and release; one stab with a carried or stowed shield; no extra low-health/stagger gate for crawlers. These are adjustable controls/balance values, not approval of all enemies, weapons or additional execution motions. The same change connects single/both-leg F2 fixtures to actual play, pause/replay and session restoration. The linked guide tracks implementation and verification separately.


검증 완료: 서로 다른 자동 검사 7종과 실제 GPU `final_04`의 18초 시퀀스(540프레임)·정지 화면 39장을 확인했다. 한쪽 다리 1인칭·같은 절단 상태의 별도 측면 반복·양다리 1인칭 세 사례에서 피부 접촉과 단일 사망을 확인했다. 접근을 실제 충돌 이동으로 바꾼 뒤 오른쪽 어깨 이동 보정은 0m이고 기존 팔 길이는 유지한다. 영상 산출물은 `artifacts/validation/creep_execution_20260918/creep_execution.mp4`에 보존한다. 평평한 시험 바닥에서 검증했으며 경사·계단·다른 적 크기는 미확인이다. 파일 인코딩 검증과 GitHub 게시 상태는 최종 검수 기록을 따른다.

Verified: seven distinct automated suites and actual GPU `final_04` output—an 18-second, 540-frame sequence and 39 stills. Single-leg first person, a separate side-view repeat and both-leg first person each confirmed skin contact and one defeat. Collision-aware approach removed right-shoulder correction while preserving arm lengths. The video artifact belongs at `artifacts/validation/creep_execution_20260918/creep_execution.mp4`. Validation used a flat inspection floor; slopes, stairs and differently sized enemies remain unverified. The final verification record separately tracks encoded-file checks and GitHub publication.
