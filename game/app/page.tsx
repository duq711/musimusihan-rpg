'use client';

import { useState } from 'react';

type Phase = 'hideout' | 'raid' | 'combat' | 'result';
type HideoutTab = 'shelter' | 'loadout' | 'trader' | 'quest';
type Facing = 0 | 1 | 2 | 3;
type Overlay = null | 'pack' | 'loot' | 'trap' | 'shrine';
type ItemId = 'bandage' | 'oil' | 'salt' | 'chalice' | 'relic';
type EnemyId = 'pilgrim' | 'guard' | 'warden' | 'pursuer';

interface Position {
  x: number;
  y: number;
}

interface ItemDef {
  name: string;
  glyph: string;
  description: string;
  weight: number;
  value: number;
}

interface EnemyTemplate {
  id: EnemyId;
  name: string;
  hp: number;
  armor: number;
  damage: [number, number];
  description: string;
  drops: ItemId[];
  reward: [number, number];
}

interface EnemyState extends EnemyTemplate {
  key: string;
  currentHp: number;
}

interface RaidResult {
  kind: 'success' | 'partial' | 'dead';
  title: string;
  detail: string;
  reward: number;
  loot: ItemId[];
}

const MAP = [
  '#######',
  '#..G.Q#',
  '#.###.#',
  '#C.TS.#',
  '###.#.#',
  '#X.E..#',
  '#######',
];

const START: Position = { x: 1, y: 5 };
const DIRECTIONS: Array<{ x: number; y: number; label: string }> = [
  { x: 0, y: -1, label: '북쪽' },
  { x: 1, y: 0, label: '동쪽' },
  { x: 0, y: 1, label: '남쪽' },
  { x: -1, y: 0, label: '서쪽' },
];

const ITEMS: Record<ItemId, ItemDef> = {
  bandage: { name: '누런 붕대', glyph: '✚', description: '생명력을 6 회복한다.', weight: 1, value: 5 },
  oil: { name: '등불 기름', glyph: '◈', description: '등불을 8 회복한다.', weight: 1, value: 7 },
  salt: { name: '검은 소금', glyph: '✦', description: '상인이 찾는 금지된 재료.', weight: 1, value: 18 },
  chalice: { name: '은잔', glyph: '♜', description: '핏자국이 지워지지 않는 은잔.', weight: 2, value: 25 },
  relic: { name: '검은 성물함', glyph: '◆', description: '이번 계약의 목표. 반드시 탈출해야 한다.', weight: 2, value: 0 },
};

const ENEMIES: Record<EnemyId, EnemyTemplate> = {
  pilgrim: {
    id: 'pilgrim',
    name: '굶주린 순례자',
    hp: 7,
    armor: 0,
    damage: [2, 4],
    description: '젖은 기도문을 씹으며 길을 막고 있다.',
    drops: ['bandage'],
    reward: [6, 10],
  },
  guard: {
    id: 'guard',
    name: '공허한 경비병',
    hp: 12,
    armor: 1,
    damage: [3, 5],
    description: '녹슨 갑옷 안쪽에서 긁는 소리가 들린다.',
    drops: ['salt'],
    reward: [9, 14],
  },
  warden: {
    id: 'warden',
    name: '성물지기',
    hp: 18,
    armor: 1,
    damage: [4, 6],
    description: '성물함을 품은 채 제단에서 몸을 일으킨다.',
    drops: ['relic', 'chalice'],
    reward: [14, 20],
  },
  pursuer: {
    id: 'pursuer',
    name: '되살아난 성물지기',
    hp: 10,
    armor: 1,
    damage: [4, 6],
    description: '발소리가 멈췄다. 그것은 이미 바로 뒤에 있다.',
    drops: [],
    reward: [0, 0],
  },
};

const ENEMY_TILES: Record<string, EnemyId> = {
  '3,5': 'pilgrim',
  '3,1': 'guard',
  '5,1': 'warden',
};

const keyOf = (position: Position) => position.x + ',' + position.y;
const roll = (min: number, max: number) => Math.floor(Math.random() * (max - min + 1)) + min;

function ItemGlyph({ id }: { id: ItemId }) {
  return <span className={'item-glyph item-' + id}>{ITEMS[id].glyph}</span>;
}

export default function Home() {
  const [phase, setPhase] = useState<Phase>('hideout');
  const [tab, setTab] = useState<HideoutTab>('shelter');
  const [questAccepted, setQuestAccepted] = useState(false);
  const [questCompleted, setQuestCompleted] = useState(false);
  const [crowns, setCrowns] = useState(42);
  const [stash, setStash] = useState<ItemId[]>([]);
  const [pack, setPack] = useState<ItemId[]>(['bandage', 'oil']);
  const [weaponName, setWeaponName] = useState('녹슨 장검');
  const [weaponDamage, setWeaponDamage] = useState<[number, number]>([4, 6]);
  const [armor, setArmor] = useState(1);
  const [hp, setHp] = useState(20);
  const [torch, setTorch] = useState(18);
  const [position, setPosition] = useState<Position>(START);
  const [previousPosition, setPreviousPosition] = useState<Position>(START);
  const [facing, setFacing] = useState<Facing>(1);
  const [steps, setSteps] = useState(0);
  const [turn, setTurn] = useState(0);
  const [cleared, setCleared] = useState<string[]>([]);
  const [resolved, setResolved] = useState<string[]>([]);
  const [enemyHealth, setEnemyHealth] = useState<Record<string, number>>({});
  const [enemy, setEnemy] = useState<EnemyState | null>(null);
  const [guardBonus, setGuardBonus] = useState(false);
  const [overlay, setOverlay] = useState<Overlay>(null);
  const [pendingLoot, setPendingLoot] = useState<ItemId[]>([]);
  const [pursuit, setPursuit] = useState<number | null>(null);
  const [result, setResult] = useState<RaidResult | null>(null);
  const [log, setLog] = useState<string[]>([
    '검은 성물함을 회수하고 살아 돌아와라.',
    '장비를 잃으면 되찾을 수 없다.',
  ]);

  const packWeight = pack.reduce((sum, id) => sum + ITEMS[id].weight, 0);
  const direction = DIRECTIONS[facing];
  const frontPosition = { x: position.x + direction.x, y: position.y + direction.y };
  const frontKey = keyOf(frontPosition);
  const currentMarker = MAP[position.y][position.x];
  const frontBlocked = MAP[frontPosition.y]?.[frontPosition.x] === '#';
  const frontThreat = ENEMY_TILES[frontKey] && !cleared.includes(frontKey);
  const canExtract = phase === 'raid' && keyOf(position) === keyOf(START) && steps > 0 && overlay === null;

  const pushLog = (message: string) => {
    setLog((messages) => [message, ...messages].slice(0, 3));
  };

  const canCarry = (id: ItemId) => {
    return pack.length < 6 && packWeight + ITEMS[id].weight <= 8;
  };

  const isWall = (next: Position) => MAP[next.y]?.[next.x] === '#' || MAP[next.y]?.[next.x] === undefined;

  const die = (detail: string) => {
    const lost = [...pack];
    setResult({
      kind: 'dead',
      title: '레이드 사망',
      detail,
      reward: 0,
      loot: lost,
    });
    setPack([]);
    setWeaponName('녹슨 단검');
    setWeaponDamage([3, 5]);
    setArmor(0);
    setEnemy(null);
    setOverlay(null);
    setPhase('result');
  };

  const enemyStrike = (target: EnemyState, guarded: boolean, baseHp = hp) => {
    let rawDamage =
      target.id === 'warden' && target.currentHp <= 8
        ? roll(2, 3) + roll(2, 3)
        : roll(target.damage[0], target.damage[1]);

    if (target.id === 'guard' && target.currentHp < target.hp) rawDamage += 1;

    const armoredDamage = Math.max(1, rawDamage - armor);
    const damage = guarded ? Math.max(1, Math.ceil(armoredDamage / 2)) : armoredDamage;
    const nextHp = Math.max(0, baseHp - damage);
    setHp(nextHp);
    pushLog((guarded ? '방패로 충격을 흘렸다. ' : '') + damage + '의 피해를 입었다.');

    if (nextHp <= 0) {
      die(target.name + '에게 쓰러졌다. 이번 레이드의 장비와 전리품을 모두 잃었다.');
    }
  };

  const startCombat = (id: EnemyId, tileKey: string) => {
    const template = ENEMIES[id];
    const currentHp = enemyHealth[tileKey] ?? template.hp;
    const nextEnemy = { ...template, key: tileKey, currentHp };
    setEnemy(nextEnemy);
    setGuardBonus(false);
    setOverlay(null);
    setPhase('combat');
    pushLog(template.name + '와 조우했다.');

    if (torch <= 0) {
      pushLog('어둠 속에서 적이 먼저 달려든다.');
      enemyStrike(nextEnemy, false);
    }
  };

  const resolveVictory = (defeated: EnemyState) => {
    const earned = roll(defeated.reward[0], defeated.reward[1]);
    setCrowns((value) => value + earned);
    setCleared((tiles) => [...tiles, defeated.key]);
    setEnemyHealth((values) => ({ ...values, [defeated.key]: 0 }));
    setEnemy(null);
    setPhase('raid');
    pushLog(defeated.name + '을 쓰러뜨렸다. ' + earned + ' 크라운을 챙겼다.');

    if (defeated.drops.length > 0) {
      setPendingLoot(defeated.drops);
      setOverlay('loot');
    }
  };

  const attack = () => {
    if (!enemy) return;
    const bonus = guardBonus ? 1 : 0;
    const damage = Math.max(1, roll(weaponDamage[0], weaponDamage[1]) + bonus - enemy.armor);
    const nextEnemy = { ...enemy, currentHp: Math.max(0, enemy.currentHp - damage) };
    setGuardBonus(false);
    setEnemyHealth((values) => ({ ...values, [enemy.key]: nextEnemy.currentHp }));
    pushLog(weaponName + '으로 ' + damage + '의 피해를 입혔다.');

    if (nextEnemy.currentHp <= 0) {
      resolveVictory(nextEnemy);
      return;
    }

    setEnemy(nextEnemy);
    enemyStrike(nextEnemy, false);
  };

  const guard = () => {
    if (!enemy) return;
    setGuardBonus(true);
    pushLog('자세를 낮추고 다음 공격 기회를 노린다.');
    enemyStrike(enemy, true);
  };

  const combatBandage = () => {
    if (!enemy) return;
    const index = pack.indexOf('bandage');
    if (index < 0) {
      pushLog('사용할 붕대가 없다.');
      return;
    }

    const nextPack = [...pack];
    nextPack.splice(index, 1);
    const healedHp = Math.min(20, hp + 6);
    setPack(nextPack);
    setHp(healedHp);
    pushLog('붕대로 상처를 감쌌다. 적은 기다려주지 않는다.');
    enemyStrike(enemy, false, healedHp);
  };

  const flee = () => {
    if (!enemy) return;
    if (Math.random() < 0.55) {
      setEnemyHealth((values) => ({ ...values, [enemy.key]: enemy.currentHp }));
      setPosition(previousPosition);
      setEnemy(null);
      setPhase('raid');
      pushLog('간신히 이전 통로로 물러났다.');
      return;
    }

    pushLog('퇴로가 막혔다.');
    enemyStrike(enemy, false);
  };

  const handleTile = (next: Position) => {
    const tileKey = keyOf(next);
    const enemyId = ENEMY_TILES[tileKey];

    if (enemyId && !cleared.includes(tileKey)) {
      startCombat(enemyId, tileKey);
      return;
    }

    const marker = MAP[next.y][next.x];
    if (marker === 'C' && !resolved.includes(tileKey)) {
      setResolved((tiles) => [...tiles, tileKey]);
      setPendingLoot(['bandage', 'salt']);
      setOverlay('loot');
      pushLog('잠긴 궤짝을 열었다. 금속 긁는 소리가 멀리 퍼진다.');
      return;
    }

    if (marker === 'T' && !resolved.includes(tileKey)) {
      setOverlay('trap');
      pushLog('바닥 틈에서 녹슨 철침이 보인다.');
      return;
    }

    if (marker === 'S' && !resolved.includes(tileKey)) {
      setOverlay('shrine');
      pushLog('말라붙은 제단이 등불을 요구한다.');
      return;
    }

    if (marker === 'X') pushLog('승강기 쇠문이 보인다. 이곳에서 탈출할 수 있다.');
    else pushLog('한 칸 전진했다. 물방울 소리만 따라온다.');
  };

  const move = (kind: 'forward' | 'back') => {
    if (phase !== 'raid' || overlay) return;
    const movementFacing = kind === 'forward' ? facing : (((facing + 2) % 4) as Facing);
    const vector = DIRECTIONS[movementFacing];
    const next = { x: position.x + vector.x, y: position.y + vector.y };

    if (isWall(next)) {
      pushLog('차갑고 젖은 벽이 길을 막는다.');
      return;
    }

    const nextTorch = Math.max(0, torch - 1);
    const nextPursuit = pursuit === null ? null : Math.max(0, pursuit - 1);
    setPreviousPosition(position);
    setPosition(next);
    setTorch(nextTorch);
    setSteps((value) => value + 1);
    setTurn((value) => value + 1);
    setPursuit(nextPursuit);

    if (nextPursuit === 0 && keyOf(next) !== keyOf(START)) {
      setPursuit(null);
      startCombat('pursuer', 'pursuer-' + turn);
      return;
    }

    if (nextPursuit === 10 || nextPursuit === 6 || nextPursuit === 3) {
      pushLog('뒤쪽 통로에서 쇠사슬 끌리는 소리가 가까워진다.');
    }

    handleTile(next);
  };

  const turnPlayer = (delta: number) => {
    if (phase !== 'raid' || overlay) return;
    setFacing((value) => ((value + delta + 4) % 4) as Facing);
    pushLog(delta < 0 ? '왼쪽으로 몸을 돌렸다.' : '오른쪽으로 몸을 돌렸다.');
  };

  const resolveTrap = (careful: boolean) => {
    const tileKey = keyOf(position);
    setResolved((tiles) => [...tiles, tileKey]);
    setOverlay(null);

    if (careful && torch >= 2) {
      setTorch((value) => value - 2);
      pushLog('불빛으로 철침의 간격을 읽고 조심히 통과했다.');
      return;
    }

    const nextHp = Math.max(0, hp - 3);
    setHp(nextHp);
    pushLog('철침이 장화를 뚫었다. 3의 피해를 입었다.');
    if (nextHp <= 0) die('어두운 통로의 철침 함정에 쓰러졌다.');
  };

  const resolveShrine = (offer: boolean) => {
    const tileKey = keyOf(position);
    setResolved((tiles) => [...tiles, tileKey]);
    setOverlay(null);

    if (offer && torch >= 4) {
      setTorch((value) => value - 4);
      setHp((value) => Math.min(20, value + 8));
      pushLog('등불을 바치자 상처가 차갑게 봉합됐다.');
      return;
    }

    pushLog('제단을 건드리지 않고 떠났다.');
  };

  const takeLoot = (index: number) => {
    const id = pendingLoot[index];
    if (!canCarry(id)) {
      pushLog('가방의 칸이나 무게가 부족하다.');
      return;
    }

    setPack((items) => [...items, id]);
    setPendingLoot((items) => items.filter((_, itemIndex) => itemIndex !== index));
    pushLog(ITEMS[id].name + '을 가방에 넣었다.');
    if (id === 'relic') setPursuit(14);
  };

  const usePackItem = (index: number) => {
    const id = pack[index];
    if (id !== 'bandage' && id !== 'oil') return;
    const nextPack = [...pack];
    nextPack.splice(index, 1);
    setPack(nextPack);

    if (id === 'bandage') {
      setHp((value) => Math.min(20, value + 6));
      pushLog('붕대를 사용했다.');
    } else {
      setTorch((value) => Math.min(20, value + 8));
      pushLog('등불에 기름을 채웠다.');
    }
  };

  const dropPackItem = (index: number) => {
    const id = pack[index];
    setPack((items) => items.filter((_, itemIndex) => itemIndex !== index));
    pushLog(ITEMS[id].name + '을 바닥에 버렸다.');
  };

  const startRaid = () => {
    if (!questAccepted) {
      setTab('quest');
      return;
    }

    setPhase('raid');
    setPosition(START);
    setPreviousPosition(START);
    setFacing(1);
    setHp(20);
    setTorch(18);
    setSteps(0);
    setTurn(0);
    setCleared([]);
    setResolved([]);
    setEnemyHealth({});
    setEnemy(null);
    setOverlay(null);
    setPendingLoot([]);
    setPursuit(null);
    setResult(null);
    setLog(['승강기가 멈췄다. 살아서 성물함을 가져와야 한다.', '뒤쪽 쇠문은 아직 열려 있다.']);
  };

  const extract = () => {
    if (!canExtract) return;
    const runLoot = [...pack];
    const hasRelic = runLoot.includes('relic');
    const reward = hasRelic ? 60 : 0;
    setStash((items) => [...items, ...runLoot]);
    setPack([]);
    setCrowns((value) => value + reward);

    if (hasRelic) {
      setQuestCompleted(true);
      setQuestAccepted(false);
    }

    setResult({
      kind: hasRelic ? 'success' : 'partial',
      title: hasRelic ? '계약 완료' : '생환 · 임무 미완료',
      detail: hasRelic
        ? '검은 성물함과 장비를 은신처로 가져왔다.'
        : '살아 돌아왔지만 성물함은 아직 던전에 있다.',
      reward,
      loot: runLoot,
    });
    setPhase('result');
  };

  const returnToHideout = () => {
    setPhase('hideout');
    setTab('shelter');
    setOverlay(null);
    setEnemy(null);
  };

  const buyConsumable = (id: 'bandage' | 'oil', price: number) => {
    if (crowns < price || !canCarry(id)) return;
    setCrowns((value) => value - price);
    setPack((items) => [...items, id]);
  };

  const buyUpgrade = (kind: 'weapon' | 'armor') => {
    const price = kind === 'weapon' ? 30 : 35;
    if (crowns < price) return;
    if (kind === 'weapon' && weaponDamage[0] >= 5) return;
    if (kind === 'armor' && armor >= 2) return;
    setCrowns((value) => value - price);
    if (kind === 'weapon') {
      setWeaponName('낡은 용병검');
      setWeaponDamage([5, 7]);
    } else {
      setArmor(2);
    }
  };

  const sellStash = (index: number) => {
    const id = stash[index];
    if (id === 'relic') return;
    setCrowns((value) => value + ITEMS[id].value);
    setStash((items) => items.filter((_, itemIndex) => itemIndex !== index));
  };

  const moveStashToPack = (index: number) => {
    const id = stash[index];
    if (!canCarry(id)) return;
    setStash((items) => items.filter((_, itemIndex) => itemIndex !== index));
    setPack((items) => [...items, id]);
  };

  const movePackToStash = (index: number) => {
    const id = pack[index];
    setPack((items) => items.filter((_, itemIndex) => itemIndex !== index));
    setStash((items) => [...items, id]);
  };

  const renderItemRow = (
    id: ItemId,
    index: number,
    actionLabel?: string,
    onAction?: () => void,
  ) => (
    <div className="item-row" key={id + '-' + index}>
      <ItemGlyph id={id} />
      <div className="item-copy">
        <strong>{ITEMS[id].name}</strong>
        <small>{ITEMS[id].description}</small>
      </div>
      <span className="item-weight">{ITEMS[id].weight}㎏</span>
      {actionLabel && onAction ? (
        <button type="button" className="small-action" onClick={onAction}>{actionLabel}</button>
      ) : null}
    </div>
  );

  if (phase === 'result' && result) {
    return (
      <main className="game-shell">
        <section className={'game-frame result-screen result-' + result.kind}>
          <div className="result-art">
            <span className="result-mark">{result.kind === 'dead' ? '†' : '◇'}</span>
            <p>{result.kind === 'dead' ? 'THE DUNGEON KEEPS ITS DEAD' : 'EXTRACTION COMPLETE'}</p>
          </div>
          <section className="result-panel">
            <span className="eyebrow">레이드 결과</span>
            <h1>{result.title}</h1>
            <p>{result.detail}</p>
            <div className="result-stats">
              <div><small>계약 보상</small><strong>{result.reward} 크라운</strong></div>
              <div><small>회수 물품</small><strong>{result.kind === 'dead' ? 0 : result.loot.length}개</strong></div>
              <div><small>이동</small><strong>{steps}칸</strong></div>
            </div>
            <div className="result-loot">
              {result.loot.length === 0 ? <p>남은 물품이 없다.</p> : result.loot.map((id, index) => (
                <div key={id + '-' + index} className={result.kind === 'dead' ? 'lost-item' : ''}>
                  <ItemGlyph id={id} />
                  <span>{ITEMS[id].name}</span>
                </div>
              ))}
            </div>
            <button type="button" className="primary-button" onClick={returnToHideout}>
              은신처로 돌아가기
            </button>
          </section>
        </section>
      </main>
    );
  }

  if (phase === 'hideout') {
    return (
      <main className="game-shell">
        <section className="game-frame hideout-frame">
          <header className="shelter-header">
            <div>
              <p className="eyebrow">지하 피난처 · 3일째</p>
              <h1>순례자의 은신처</h1>
            </div>
            <div className="currency"><span>◉</span><strong>{crowns}</strong></div>
          </header>

          <section className="shelter-view" aria-label="은신처">
            <div className="shelter-arch" />
            <div className="shelter-gate"><i /><i /><i /></div>
            <div className="shelter-fire"><i /></div>
            <div className="shelter-bench"><span /><b /></div>
            <div className="shelter-bed" />
            <div className="shelter-hero"><i /></div>
            <div className="shelter-vignette" />
            <div className="hideout-status">
              <span className={questAccepted ? 'ready-dot active' : 'ready-dot'} />
              {questAccepted ? '레이드 준비됨' : '새 계약을 확인하세요'}
            </div>
          </section>

          <section className="hideout-content">
            {tab === 'shelter' ? (
              <div className="shelter-panel">
                <div className="brief-card">
                  <span className="card-icon">⌂</span>
                  <div><small>현재 목표</small><strong>{questAccepted ? '검은 성물함 회수' : '수락한 계약 없음'}</strong></div>
                </div>
                <div className="brief-grid">
                  <div><small>무기</small><strong>{weaponName}</strong><span>{weaponDamage[0]}–{weaponDamage[1]} 피해</span></div>
                  <div><small>방어</small><strong>{armor}</strong><span>피해 경감</span></div>
                  <div><small>가방</small><strong>{pack.length} / 6</strong><span>{packWeight} / 8㎏</span></div>
                </div>
                <button type="button" className="primary-button raid-button" onClick={startRaid}>
                  {questAccepted ? '승강기를 타고 출정' : '퀘스트를 먼저 수락'}
                </button>
              </div>
            ) : null}

            {tab === 'loadout' ? (
              <div className="inventory-panel">
                <div className="equipment-strip">
                  <div><small>주무기</small><strong>{weaponName}</strong><span>{weaponDamage[0]}–{weaponDamage[1]}</span></div>
                  <div><small>방어구</small><strong>{armor === 2 ? '가죽 갑옷' : armor === 1 ? '누빈 조끼' : '없음'}</strong><span>방어 {armor}</span></div>
                  <div><small>적재</small><strong>{packWeight} / 8㎏</strong><span>{pack.length} / 6칸</span></div>
                </div>
                <h2>레이드 가방</h2>
                <div className="item-list">
                  {pack.length === 0 ? <p className="empty-copy">가방이 비어 있다.</p> : pack.map((id, index) =>
                    renderItemRow(id, index, '보관', () => movePackToStash(index)),
                  )}
                </div>
                <h2>보관함</h2>
                <div className="item-list compact-list">
                  {stash.length === 0 ? <p className="empty-copy">회수한 물품이 없다.</p> : stash.map((id, index) =>
                    renderItemRow(id, index, '장착', () => moveStashToPack(index)),
                  )}
                </div>
              </div>
            ) : null}

            {tab === 'trader' ? (
              <div className="trader-panel">
                <div className="trader-intro">
                  <div className="trader-portrait"><span /></div>
                  <div><small>대장장이 · 신뢰 1</small><h2>“살아서 갚을 생각이라면 골라.”</h2></div>
                </div>
                <div className="shop-grid">
                  <button type="button" onClick={() => buyConsumable('bandage', 8)} disabled={crowns < 8 || !canCarry('bandage')}>
                    <ItemGlyph id="bandage" /><strong>누런 붕대</strong><span>◉ 8</span>
                  </button>
                  <button type="button" onClick={() => buyConsumable('oil', 10)} disabled={crowns < 10 || !canCarry('oil')}>
                    <ItemGlyph id="oil" /><strong>등불 기름</strong><span>◉ 10</span>
                  </button>
                  <button type="button" onClick={() => buyUpgrade('weapon')} disabled={crowns < 30 || weaponDamage[0] >= 5}>
                    <span className="shop-glyph">⚔</span><strong>낡은 용병검</strong><span>{weaponDamage[0] >= 5 ? '구매함' : '◉ 30'}</span>
                  </button>
                  <button type="button" onClick={() => buyUpgrade('armor')} disabled={crowns < 35 || armor >= 2}>
                    <span className="shop-glyph">▣</span><strong>가죽 갑옷</strong><span>{armor >= 2 ? '구매함' : '◉ 35'}</span>
                  </button>
                </div>
                <h2>보관함 판매</h2>
                <div className="item-list compact-list">
                  {stash.filter((id) => id !== 'relic').length === 0 ? <p className="empty-copy">판매할 전리품이 없다.</p> :
                    stash.map((id, index) => id === 'relic' ? null :
                      renderItemRow(id, index, ITEMS[id].value + ' 판매', () => sellStash(index)),
                    )}
                </div>
              </div>
            ) : null}

            {tab === 'quest' ? (
              <div className="quest-panel">
                <div className="quest-paper">
                  <div className="quest-seal">†</div>
                  <p className="eyebrow">수도원 계약 · 위험도 4</p>
                  <h2>검은 성물함</h2>
                  <p>버려진 수도원의 가장 깊은 제단에서 성물함을 회수하라. 물건은 소유한 채 승강기로 돌아와야 한다.</p>
                  <div className="quest-meta">
                    <div><small>보상</small><strong>◉ 60</strong></div>
                    <div><small>추정 위협</small><strong>해골 3</strong></div>
                    <div><small>반환 조건</small><strong>생환</strong></div>
                  </div>
                  <button
                    type="button"
                    className="primary-button"
                    onClick={() => { setQuestAccepted(true); setQuestCompleted(false); }}
                    disabled={questAccepted}
                  >
                    {questCompleted ? '계약 다시 수락' : questAccepted ? '계약 수락됨' : '계약 수락'}
                  </button>
                </div>
              </div>
            ) : null}
          </section>

          <nav className="hideout-nav" aria-label="은신처 메뉴">
            {([
              ['shelter', '⌂', '은신처'],
              ['loadout', '▦', '장비'],
              ['trader', '♟', '상인'],
              ['quest', '▤', '퀘스트'],
            ] as Array<[HideoutTab, string, string]>).map(([id, glyph, label]) => (
              <button key={id} type="button" className={tab === id ? 'active' : ''} onClick={() => setTab(id)}>
                <span>{glyph}</span><b>{label}</b>
              </button>
            ))}
          </nav>
        </section>
      </main>
    );
  }

  const sceneLabel = enemy
    ? enemy.name
    : currentMarker === 'X'
      ? '낡은 승강기'
      : currentMarker === 'C'
        ? '약탈된 보급실'
        : currentMarker === 'T'
          ? '철침 통로'
          : currentMarker === 'S'
            ? '피의 성소'
            : '수도원 지하';

  return (
    <main className="game-shell">
      <section className={'game-frame raid-frame ' + (hp <= 7 ? 'critical' : '')}>
        <header className="raid-header">
          <div>
            <p className="eyebrow">RAID · {sceneLabel}</p>
            <h1>잔향의 성소</h1>
          </div>
          <div className="direction-chip" aria-label={'현재 방향 ' + DIRECTIONS[facing].label}>
            <span className="direction-arrow" style={{ transform: 'rotate(' + facing * 90 + 'deg)' }}>↑</span>
            {DIRECTIONS[facing].label}
          </div>
        </header>

        <div className="hud" aria-label="플레이어 상태">
          <div className="stat-block">
            <span className="stat-icon hp-icon">+</span>
            <div><small>생명력</small><strong>{hp} / 20</strong></div>
            <span className="meter"><i style={{ width: (hp / 20) * 100 + '%' }} /></span>
          </div>
          <div className="stat-block">
            <span className="stat-icon torch-icon">◆</span>
            <div><small>등불</small><strong>{torch} / 20</strong></div>
            <span className="meter torch-meter"><i style={{ width: (torch / 20) * 100 + '%' }} /></span>
          </div>
          <div className="stat-block compact">
            <small>가방</small><strong>{packWeight} / 8</strong>
          </div>
        </div>

        <section className={'viewport ' + (frontBlocked ? 'front-blocked ' : '') + (enemy ? 'combat-scene ' : '') + (torch === 0 ? 'unlit' : '')} aria-label="1인칭 던전 시야">
          <div className="ceiling" />
          <div className="wall wall-left" />
          <div className="wall wall-right" />
          <div className="floor-grid" />
          <div className="far-door"><span /></div>
          {frontBlocked ? <div className="front-wall"><i /><i /><i /></div> : null}
          <div className="hanging-chain chain-one" />
          <div className="hanging-chain chain-two" />
          {frontThreat && !enemy ? <div className="distant-figure"><i /><b /></div> : null}
          {enemy ? (
            <div className={'enemy-sprite enemy-' + enemy.id}>
              <span className="enemy-head"><i /><i /></span>
              <span className="enemy-body" />
              <span className="enemy-weapon" />
            </div>
          ) : null}
          {currentMarker === 'C' ? <div className="scene-chest"><i /></div> : null}
          {currentMarker === 'S' ? <div className="scene-shrine"><i>†</i></div> : null}
          {currentMarker === 'X' ? <div className="scene-lift"><i /><i /><i /></div> : null}
          <div className="lantern-glow" style={{ opacity: torch / 20 }} />
          <div className="player-hand hand-left">
            {phase === 'combat' ? <span className="round-shield" /> : <span className="lantern"><i /></span>}
          </div>
          <div className="player-hand hand-right"><span className="blade" /></div>
          <div className="reticle" aria-hidden="true">·</div>
          <div className="scene-grain" />
          {pursuit !== null ? <div className="pursuit-badge"><small>추격</small><strong>{pursuit}</strong></div> : null}
          {enemy ? (
            <div className="enemy-card">
              <div><small>{enemy.description}</small><strong>{enemy.name}</strong></div>
              <span className="enemy-meter"><i style={{ width: (enemy.currentHp / enemy.hp) * 100 + '%' }} /></span>
            </div>
          ) : null}
        </section>

        <section className="encounter-copy" aria-live="polite">
          <div>
            <span className="turn-count">턴 {turn} · 이동 {steps}</span>
            <p>{log[0]}</p>
            <small className="older-log">{log[1]}</small>
          </div>
          {canExtract ? (
            <button type="button" className="extract-button" onClick={extract}>탈출</button>
          ) : (
            <button type="button" className="pack-button" onClick={() => setOverlay('pack')}>가방 <b>{pack.length}</b></button>
          )}
        </section>

        <nav className={'movement-panel ' + (phase === 'combat' ? 'combat-controls' : '')} aria-label={phase === 'combat' ? '전투 조작' : '던전 이동 조작'}>
          {phase === 'combat' ? (
            <>
              <p>행동하면 적도 한 번 행동합니다</p>
              <div className="action-grid">
                <button type="button" onClick={attack}><span>⚔</span><b>공격</b></button>
                <button type="button" onClick={guard}><span>◒</span><b>방어</b></button>
                <button type="button" onClick={combatBandage} disabled={!pack.includes('bandage')}><span>✚</span><b>붕대</b></button>
                <button type="button" onClick={flee}><span>↤</span><b>도주 55%</b></button>
              </div>
            </>
          ) : (
            <>
              <p>버튼을 누를 때 한 칸씩 이동합니다</p>
              <div className="dpad">
                <button className="move-button forward" type="button" onClick={() => move('forward')} disabled={!!overlay}>
                  <span>↑</span><b>전진</b>
                </button>
                <button className="move-button left" type="button" onClick={() => turnPlayer(-1)} disabled={!!overlay}>
                  <span>↶</span><b>좌회전</b>
                </button>
                <div className="dpad-center"><i /></div>
                <button className="move-button right" type="button" onClick={() => turnPlayer(1)} disabled={!!overlay}>
                  <span>↷</span><b>우회전</b>
                </button>
                <button className="move-button back" type="button" onClick={() => move('back')} disabled={!!overlay}>
                  <span>↓</span><b>후진</b>
                </button>
              </div>
            </>
          )}
        </nav>

        {overlay ? (
          <div className="overlay-backdrop" role="dialog" aria-modal="true">
            <section className="event-modal">
              {overlay === 'loot' ? (
                <>
                  <span className="eyebrow">전리품 · 소음 발생</span>
                  <h2>무엇을 가져갈 것인가?</h2>
                  <p>가방 {pack.length}/6칸 · {packWeight}/8㎏</p>
                  <div className="loot-grid">
                    {pendingLoot.length === 0 ? <p className="empty-copy">더 이상 남은 물품이 없다.</p> : pendingLoot.map((id, index) => (
                      <button type="button" key={id + '-' + index} onClick={() => takeLoot(index)} disabled={!canCarry(id)}>
                        <ItemGlyph id={id} /><strong>{ITEMS[id].name}</strong><small>{ITEMS[id].weight}㎏</small>
                      </button>
                    ))}
                  </div>
                  <button type="button" className="secondary-button" onClick={() => { setPendingLoot([]); setOverlay(null); }}>남기고 이동</button>
                </>
              ) : null}

              {overlay === 'trap' ? (
                <>
                  <span className="eyebrow">환경 위험</span>
                  <h2>녹슨 철침 통로</h2>
                  <p>등불로 간격을 읽으면 안전하지만 빛을 더 소모한다.</p>
                  <div className="choice-grid">
                    <button type="button" onClick={() => resolveTrap(true)} disabled={torch < 2}><strong>조심히 통과</strong><small>등불 −2</small></button>
                    <button type="button" onClick={() => resolveTrap(false)}><strong>달려간다</strong><small>생명력 −3</small></button>
                  </div>
                </>
              ) : null}

              {overlay === 'shrine' ? (
                <>
                  <span className="eyebrow">피의 성소</span>
                  <h2>불빛을 바치겠는가?</h2>
                  <p>검게 굳은 제단에서 따뜻한 맥박이 느껴진다.</p>
                  <div className="choice-grid">
                    <button type="button" onClick={() => resolveShrine(true)} disabled={torch < 4}><strong>등불을 바친다</strong><small>등불 −4 · 생명력 +8</small></button>
                    <button type="button" onClick={() => resolveShrine(false)}><strong>떠난다</strong><small>아무 일도 없다</small></button>
                  </div>
                </>
              ) : null}

              {overlay === 'pack' ? (
                <>
                  <span className="eyebrow">레이드 가방</span>
                  <h2>{pack.length}/6칸 · {packWeight}/8㎏</h2>
                  <div className="item-list raid-pack-list">
                    {pack.length === 0 ? <p className="empty-copy">가방이 비어 있다.</p> : pack.map((id, index) => (
                      <div className="item-row" key={id + '-' + index}>
                        <ItemGlyph id={id} />
                        <div className="item-copy"><strong>{ITEMS[id].name}</strong><small>{ITEMS[id].description}</small></div>
                        {(id === 'bandage' || id === 'oil') ? <button type="button" className="small-action" onClick={() => usePackItem(index)}>사용</button> : null}
                        <button type="button" className="small-action danger" onClick={() => dropPackItem(index)}>버림</button>
                      </div>
                    ))}
                  </div>
                  <button type="button" className="secondary-button" onClick={() => setOverlay(null)}>닫기</button>
                </>
              ) : null}
            </section>
          </div>
        ) : null}
      </section>
    </main>
  );
}
