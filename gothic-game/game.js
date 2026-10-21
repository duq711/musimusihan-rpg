import * as T from 'three';
import {
  buildWorld,
  makeEnemy,
  makeHands,
  material,
  CELL,
  noise
} from './world.js';

const $ = id => document.getElementById(id),
  stage = $('stage'),
  SAVE = 'musimusihan.gothic-origin.v1',
  PREF = 'musimusihan.gothic-origin.preferences.v1';
const qa = new URLSearchParams(location.search).has('qa');
const scene = new T.Scene();
scene.background = new T.Color(0x17242e);
const renderer = new T.WebGLRenderer({
  antialias: true,
  alpha: false,
  powerPreference: 'high-performance'
});
renderer.setPixelRatio(1);
renderer.outputColorSpace = T.SRGBColorSpace;
renderer.info.autoReset = false;
stage.append(renderer.domElement);
renderer.domElement.tabIndex = 0;
renderer.domElement.setAttribute('aria-label', '게임 화면. WASD 이동, 드래그 시선, Space 공격, E 조사.');
const camera = new T.PerspectiveCamera(66, 1, .06, 42);
camera.rotation.order = 'YXZ';
scene.add(camera);
const mat = material(),
  hands = makeHands(mat);
camera.add(hands.root);
hands.root.visible = false;
hands.root.scale.setScalar(.55);
hands.root.position.set(0, -.3, -.5);
let world, mode = 'loading',
  ready = false,
  clock = 0,
  last = 0,
  pose = {
    x: 0,
    z: 0,
    yaw: 0,
    pitch: 0
  },
  state, activeRoom = null,
  target = null,
  attackTime = 0,
  hurtTime = 0,
  block = false,
  toastUntil = 0,
  attackLanded = false,
  saveTime = 0,
  roomTime = 0,
  frameCost = 0,
  blockedMoves = 0;
const keys = new Set(),
  screens = ['title-screen', 'pause-screen', 'map-screen', 'bag-screen', 'journal-screen', 'end-screen'];
const prefs = {
  sensitivity: 1,
  quality: 1,
  reduced: matchMedia('(prefers-reduced-motion: reduce)').matches
};
try {
  const p = JSON.parse(localStorage.getItem(PREF));
  if (p) {
    if (Number.isFinite(p.sensitivity)) prefs.sensitivity = Math.max(.5, Math.min(2, p.sensitivity));
    if ([1, .75].includes(p.quality)) prefs.quality = p.quality;
    if (typeof p.reduced === 'boolean') prefs.reduced = p.reduced;
  }
} catch {}
$('sensitivity').value = prefs.sensitivity;
$('quality').value = prefs.quality;
$('motion').checked = prefs.reduced;

function resize() {
  renderer.setSize(Math.round(innerWidth * prefs.quality), Math.round(innerHeight * prefs.quality), false);
  camera.aspect = innerWidth / innerHeight;
  camera.updateProjectionMatrix();
}
addEventListener('resize', resize);
resize();
const meta = [{
  room: 30,
  name: '잊힌 이름의 서책',
  hint: '남쪽 하단 책장실 · XXX'
}, {
  room: 23,
  name: '종지기의 검은 뼈',
  hint: '동쪽 큰 묘실 · XXIII'
}, {
  room: 1,
  name: '꺼지지 않는 성화',
  hint: '북서쪽 대예배당 · I'
}];

function fresh() {
  return {
    version: 1,
    hp: 100,
    stamina: 100,
    potions: 3,
    crowns: 0,
    relics: [],
    opened: [],
    dead: [],
    visited: [35],
    seconds: 0,
    kills: 0
  };
}

function readSave() {
  try {
    const v = JSON.parse(localStorage.getItem(SAVE));
    if (!v || v.version !== 1 || !Number.isFinite(v.hp) || v.hp <= 0 || v.hp > 100 || !Number.isFinite(v.x) || !Number.isFinite(v.z) || !Number.isFinite(v.yaw) || !world.walkable(v.x, v.z)) return null;
    for (const k of ['relics', 'opened', 'dead', 'visited'])
      if (!Array.isArray(v[k])) return null;
    return {
      ...fresh(),
      hp: v.hp,
      stamina: 100,
      potions: Math.max(0, Math.min(99, Math.floor(Number(v.potions) || 0))),
      crowns: Math.max(0, Math.min(99999, Math.floor(Number(v.crowns) || 0))),
      relics: v.relics.filter(id => meta.some(m => m.room === id)),
      opened: v.opened.filter(id => world.objects.some(o => o.id === id && o.kind === 'chest')),
      dead: v.dead.filter(id => world.enemies.some(e => e.id === id)),
      visited: v.visited.filter(id => Number.isInteger(id) && id >= 1 && id <= 35),
      seconds: Math.max(0, Number(v.seconds) || 0),
      kills: Math.max(0, Number(v.kills) || 0),
      x: v.x,
      z: v.z,
      yaw: v.yaw,
      pitch: Math.max(-1, Math.min(1, Number(v.pitch) || 0))
    };
  } catch {
    return null;
  }
}

function save() {
  if (!state || state.hp <= 0 || mode === 'end' || mode === 'title') return false;
  try {
    localStorage.setItem(SAVE, JSON.stringify({
      ...state,
      ...pose
    }));
    $('save-status').textContent = '이 브라우저에 서약을 기록했습니다.';
    return true;
  } catch {
    $('save-status').textContent = '기록 공간을 사용할 수 없습니다. 현재 플레이는 계속됩니다.';
    return false;
  }
}

function prefSave() {
  try {
    localStorage.setItem(PREF, JSON.stringify(prefs));
  } catch {}
}

function roman(n) {
  return [
    ['L', 50],
    ['XL', 40],
    ['X', 10],
    ['IX', 9],
    ['V', 5],
    ['IV', 4],
    ['I', 1]
  ].map(([r, k]) => {
    const count = Math.floor(n / k);
    n %= k;
    return r.repeat(count);
  }).join('');
}

function toast(message) {
  $('toast').textContent = message;
  $('toast').hidden = false;
  toastUntil = clock + 4;
}

function unlock() {
  if (document.pointerLockElement) document.exitPointerLock();
  keys.clear();
  block = false;
  drag = null;
}
let focusBefore = null;

function screen(id) {
  for (const s of screens) $(s).hidden = s !== id;
  $('hud').hidden = !state || id === 'title-screen' || id === 'end-screen';
  $('touch-controls').hidden = !(coarse && id === null && mode === 'playing');
  if (id) {
    $('toast').hidden = true;
    toastUntil = 0;
    focusBefore = document.activeElement;
    unlock();
    requestAnimationFrame(() => $(id).querySelector('button:not([hidden])')?.focus());
  } else if (focusBefore?.isConnected) renderer.domElement.focus({
    preventScroll: true
  });
}

function play() {
  mode = 'playing';
  screen(null);
  hands.root.visible = true;
}

function pause(id = 'pause-screen') {
  if (mode !== 'playing') return;
  mode = 'paused';
  screen(id);
  if (id === 'map-screen') drawMap();
  if (id === 'bag-screen') inventory();
  if (id === 'journal-screen') journal();
  save();
}

function close() {
  if (mode === 'paused') play();
}

function title() {
  unlock();
  mode = 'title';
  state = null;
  hands.root.visible = false;
  screen('title-screen');
  $('continue-game').hidden = !readSave();
  const r = world.rooms[0];
  camera.position.set(r.x - 2, 2, r.z - r.h * .37);
  camera.rotation.set(-.06, Math.PI + .16, 0);
}

function begin(continuing = false) {
  const loaded = continuing && readSave();
  state = loaded || fresh();
  pose = {
    x: loaded ? loaded.x : world.start[0],
    z: loaded ? loaded.z : world.start[2],
    yaw: loaded ? loaded.yaw : 0,
    pitch: loaded ? loaded.pitch : 0
  };
  for (const r of world.rooms) r.visited = state.visited.includes(r.id);
  for (const o of world.objects) {
    if (o.kind === 'relic') {
      o.collected = state.relics.includes(o.room);
      o.group.visible = !o.collected;
    }
    if (o.kind === 'chest') {
      o.opened = state.opened.includes(o.id);
      o.lid.rotation.x = o.opened ? -1.35 : 0;
    }
  }
  for (const e of world.enemies) {
    e.x = e.home[0];
    e.z = e.home[1];
    e.hp = e.maxHp;
    e.dead = state.dead.includes(e.id);
    e.group.visible = !e.dead;
    e.group.scale.setScalar(1);
    e.group.rotation.set(0, 0, 0);
    e.group.position.set(e.x, 0, e.z);
    e.state = 'idle';
    e.timer = 0;
  }
  attackTime = 0;
  hurtTime = 0;
  roomTime = 0;
  activeRoom = null;
  play();
  updateHUD();
  save();
  toast(loaded ? ' 서약을 이어갑니다.' : '세 성물을 찾아 이곳의 귀환 인장으로 돌아오십시오.');
}
const coarse = matchMedia('(pointer: coarse)').matches;
$('new-game').onclick = () => begin();
$('continue-game').onclick = () => begin(true);
$('resume').onclick = close;
$('pause-button').onclick = () => pause();
$('map-button').onclick = () => pause('map-screen');
$('bag-button').onclick = () => pause('bag-screen');
$('journal-button').onclick = () => pause('journal-screen');
$('potion-button').onclick = heal;
$('bag-heal').onclick = () => {
  heal();
  inventory();
};
$('save-title').onclick = () => {
  save();
  title();
};
$('retry').onclick = () => begin();
$('end-title-button').onclick = title;
document.querySelectorAll('[data-close]').forEach(b => b.onclick = close);
$('sensitivity').oninput = e => {
  prefs.sensitivity = Number(e.target.value);
  prefSave();
};
$('quality').onchange = e => {
  prefs.quality = Number(e.target.value);
  resize();
  prefSave();
};
$('motion').onchange = e => {
  prefs.reduced = e.target.checked;
  prefSave();
};

function inventory() {
  $('inventory').replaceChildren();
  const items = [
    ['떠돌이의 검', '갈라진 은빛, 날은 아직 살아 있다.', '장착'],
    ['오래된 원형 방패', 'Q / 우클릭으로 방어. 기력을 소모한다.', '장착'],
    ['회복약', '생명 40 회복', `${state.potions} 병`],
    ['크라운', '버려진 성소의 화폐', `${state.crowns}`],
    ['검은 성물', '서약을 완수할 세 개의 흔적', `${state.relics.length} / 3`]
  ];
  for (const [name, hint, count] of items) {
    const row = document.createElement('div');
    row.className = 'item';
    const text = document.createElement('span');
    text.textContent = name;
    const small = document.createElement('small');
    small.textContent = hint;
    text.append(small);
    const amount = document.createElement('span');
    amount.textContent = count;
    row.append(text, amount);
    $('inventory').append(row);
  }
  $('bag-heal').disabled = state.potions <= 0 || state.hp >= 100;
}

function journal() {
  $('journal-list').replaceChildren();
  for (const m of meta) {
    const li = document.createElement('li');
    li.textContent = (state.relics.includes(m.room) ? '◆ ' : '◇ ') + m.name;
    const small = document.createElement('small');
    small.textContent = state.relics.includes(m.room) ? '수복했습니다.' : m.hint;
    li.append(small);
    $('journal-list').append(li);
  }
}

function heal() {
  if (!state || !['playing', 'paused'].includes(mode)) return;
  if (state.hp >= 100) {
    toast('아직 회복약이 필요하지 않습니다.');
    return;
  }
  if (state.potions <= 0) {
    toast('회복약이 없습니다. 상자를 수색하십시오.');
    return;
  }
  state.potions--;
  state.hp = Math.min(100, state.hp + 40);
  toast('회복약 · 생명 +40');
  updateHUD();
  save();
}

function end(won) {
  mode = 'end';
  unlock();
  screen('end-screen');
  hands.root.visible = false;
  $('end-kicker').textContent = won ? 'THE VOW IS KEPT' : 'THE INK REMEMBERS';
  $('end-title').textContent = won ? '성소는 당신을 기억한다' : '그림자 속에 서약을 남기다';
  $('end-copy').textContent = won ? '세 성물을 되찾았습니다. 닫혀 있던 귀환의 길이 열립니다.' : '먹빛이 당신을 삼켰습니다. 다시 불빛을 따라 걸으십시오.';
  $('end-stats').textContent = `탐험 ${state.visited.length} / 35 · 수호자 ${state.kills} · ${Math.floor(state.seconds/60)}분 ${Math.floor(state.seconds%60)}초`;
  try {
    localStorage.removeItem(SAVE);
  } catch {}
}

function hit(damage) {
  if (mode !== 'playing') return;
  state.hp = Math.max(0, state.hp - damage);
  hurtTime = .45;
  $('damage').style.opacity = .7;
  updateHUD();
  if (!state.hp) end(false);
}

function sight(ax, az, bx, bz) {
  const distance = Math.hypot(bx - ax, bz - az),
    n = Math.ceil(distance / .28);
  for (let i = 1; i < n; i++)
    if (!world.walkable(ax + (bx - ax) * i / n, az + (bz - az) * i / n, .06)) return false;
  return true;
}

function canMove(x, z, r = .25) {
  return world.walkable(x, z, r) && !world.propsAt(x, z).some(o => {
    const nx = Math.max(o.x - o.w / 2, Math.min(x, o.x + o.w / 2)),
      nz = Math.max(o.z - o.d / 2, Math.min(z, o.z + o.d / 2));
    return (x - nx) ** 2 + (z - nz) ** 2 < r * r;
  });
}

function movement(dt) {
  let forward = (keys.has('KeyW') ? 1 : 0) - (keys.has('KeyS') ? 1 : 0),
    side = (keys.has('KeyD') ? 1 : 0) - (keys.has('KeyA') ? 1 : 0);
  const len = Math.hypot(forward, side);
  const sprint = keys.has('ShiftLeft') && len > 0 && state.stamina > 1 && !block;
  const speed = block ? 1.5 : sprint ? 4.4 : 2.8;
  if (keys.has('ArrowLeft')) pose.yaw += dt * 1.7;
  if (keys.has('ArrowRight')) pose.yaw -= dt * 1.7;
  if (len) {
    forward /= len;
    side /= len;
    const dx = (side * Math.cos(pose.yaw) - forward * Math.sin(pose.yaw)) * speed * dt,
      dz = (-forward * Math.cos(pose.yaw) - side * Math.sin(pose.yaw)) * speed * dt;
    const steps = Math.ceil(Math.hypot(dx, dz) / .12);
    for (let i = 0; i < steps; i++) {
      if (canMove(pose.x + dx / steps, pose.z)) pose.x += dx / steps;
      else blockedMoves++;
      if (canMove(pose.x, pose.z + dz / steps)) pose.z += dz / steps;
      else blockedMoves++;
    }
  }
  state.stamina = Math.max(0, Math.min(100, state.stamina + (sprint ? -22 : block ? -3 : 18) * dt));
  if (state.stamina < 1) block = false;
  return len > 0;
}

function attack() {
  if (mode !== 'playing' || attackTime > 0 || state.stamina < 16) return;
  state.stamina -= 16;
  attackTime = .48;
  attackLanded = false;
  block = false;
}

function attackImpact() {
  let best = null,
    dist = Infinity;
  for (const e of world.enemies) {
    if (e.dead) continue;
    const dx = e.x - pose.x,
      dz = e.z - pose.z,
      d = Math.hypot(dx, dz);
    const facing = (-Math.sin(pose.yaw) * dx - Math.cos(pose.yaw) * dz) / Math.max(.001, d);
    if (d < 2.35 && facing > .67 && d < dist && sight(pose.x, pose.z, e.x, e.z)) {
      best = e;
      dist = d;
    }
  }
  if (best) {
    best.hp -= 27;
    best.flash = .17;
    best.state = 'stagger';
    best.timer = .34;
    if (best.hp <= 0) {
      best.dead = true;
      best.state = 'falling';
      best.timer = .75;
      state.dead.push(best.id);
      state.kills++;
      state.crowns += 15;
      toast(`${best.name} · 침묵하다`);
      save();
    }
  }
}

function updateEnemies(dt) {
  for (const e of world.enemies) {
    if (e.dead) {
      if (e.timer > 0) {
        e.timer -= dt;
        e.group.rotation.z = -Math.min(1, .75 - e.timer) * 1.8;
        e.group.position.y = -Math.min(.7, .75 - e.timer);
        if (e.timer <= 0) e.group.visible = false;
      }
      continue;
    }
    const dx = pose.x - e.x,
      dz = pose.z - e.z,
      d = Math.hypot(dx, dz);
    if (d > 15) continue;
    const seen = d < 9 && sight(e.x, e.z, pose.x, pose.z);
    e.group.position.set(e.x, Math.sin(clock * 2 + e.room) * .015, e.z);
    e.group.rotation.y = Math.atan2(-dx, -dz);
    e.group.rotation.z = 0;
    if (e.flash > 0) {
      e.flash -= dt;
      e.group.scale.setScalar(1 + Math.sin(e.flash * 35) * .035);
    } else e.group.scale.setScalar(1);
    e.timer = Math.max(0, e.timer - dt);
    if (e.state === 'stagger' && e.timer === 0) e.state = 'idle';
    if (e.state === 'windup') {
      e.group.rotation.z = Math.sin(clock * 15) * .06;
      e.group.scale.y = 1.05;
      if (e.timer === 0) {
        if (d < 2.1 && seen) {
          const facing = (-Math.sin(pose.yaw) * (e.x - pose.x) - Math.cos(pose.yaw) * (e.z - pose.z)) / Math.max(.01, d);
          if (block && state.stamina >= 15 && facing > .1) {
            state.stamina -= 15;
            toast('막았다. 지금 반격하십시오.');
            e.state = 'stagger';
            e.timer = .65;
          } else {
            hit(e.kind === 'warden' ? 24 : 14);
            e.state = 'recover';
            e.timer = .75;
          }
        } else {
          e.state = 'recover';
          e.timer = .75;
        }
      }
    } else if (['recover', 'stagger'].includes(e.state)) {
      if (e.timer === 0) e.state = 'idle';
    } else if (seen) {
      if (d < 1.65) {
        e.state = 'windup';
        e.timer = e.kind === 'warden' ? 1 : .8;
      } else {
        e.state = 'pursue';
        const speed = e.kind === 'warden' ? .85 : 1.15,
          nx = e.x + dx / d * dt * speed,
          nz = e.z + dz / d * dt * speed;
        if (canMove(nx, e.z, .24)) e.x = nx;
        if (canMove(e.x, nz, .24)) e.z = nz;
      }
    } else e.state = 'idle';
  }
}

function findTarget() {
  let nearest = null,
    dist = 2.5;
  for (const o of world.objects) {
    if (o.collected || o.opened) continue;
    const dx = o.x - pose.x,
      dz = o.z - pose.z,
      d = Math.hypot(dx, dz),
      facing = (-Math.sin(pose.yaw) * dx - Math.cos(pose.yaw) * dz) / Math.max(d, .001);
    if (d < dist && (facing > .48 || d < .85) && sight(pose.x, pose.z, o.x, o.z)) {
      dist = d;
      nearest = o;
    }
  }
  return nearest;
}

function interact() {
  if (mode !== 'playing') return;
  target = findTarget();
  if (!target) return;
  if (target.kind === 'chest') {
    target.opened = true;
    state.opened.push(target.id);
    state.crowns += 8 + target.room % 8;
    if (target.room % 2 === 1) {
      state.potions++;
      toast('상자를 수색했다 · 회복약 +1 · 크라운');
    } else toast('상자를 수색했다 · 크라운');
  }
  if (target.kind === 'relic') {
    if (world.enemies.some(e => e.room === target.room && !e.dead)) {
      toast('수호자가 성물의 서약을 붙들고 있습니다.');
      return;
    }
    target.collected = true;
    target.group.visible = false;
    state.relics.push(target.room);
    toast(`${target.name} · 수복 ${state.relics.length} / 3`);
    if (state.relics.length === 3) toast('세 성물의 서약이 모였다. 35번 보급 창고로 돌아가십시오.');
  }
  if (target.kind === 'exit') {
    if (state.relics.length === 3) {
      end(true);
      return;
    }
    toast(`아직 ${3-state.relics.length}개의 성물이 성소에 남아 있습니다.`);
  }
  updateHUD();
  save();
}

function updateHUD() {
  if (!state) return;
  $('health').style.width = `${state.hp}%`;
  $('health-value').textContent = Math.ceil(state.hp);
  $('stamina').style.width = `${state.stamina}%`;
  $('potion-count').textContent = state.potions;
  $('relic-count').textContent = `성물 ${state.relics.length} / 3`;
  $('quest').textContent = state.relics.length === 3 ? '귀환 인장으로 돌아가라' : '세 개의 검은 성물을 찾아라';
}

function updateRoom() {
  const r = world.rooms.find(r => Math.abs(pose.x - r.x) < r.w / 2 + .5 && Math.abs(pose.z - r.z) < r.h / 2 + .5);
  if (r && r !== activeRoom) {
    activeRoom = r;
    if (!r.visited) {
      r.visited = true;
      state.visited.push(r.id);
      save();
    }
    $('room-name').textContent = r.name_ko;
    $('room-number').textContent = `지하 1층 · ${roman(r.id)}`;
  }
}

function drawMap() {
  const c = $('map'),
    ctx = c.getContext('2d'),
    [xmin, zmin, xmax, zmax] = world.extent,
    pad = 35,
    factor = Math.min((c.width - pad * 2) / (xmax - xmin), (c.height - pad * 2) / (zmax - zmin)),
    ox = (c.width - (xmax - xmin) * factor) / 2,
    oz = (c.height - (zmax - zmin) * factor) / 2;
  const point = (x, z) => [ox + (x - xmin) * factor, oz + (z - zmin) * factor];
  ctx.fillStyle = '#121c22';
  ctx.fillRect(0, 0, c.width, c.height);
  for (const t of world.tiles) {
    const [x, z] = t.split(',').map(n => Number(n) * CELL);
    if (Math.hypot(x - pose.x, z - pose.z) < 9 || world.rooms.some(r => r.visited && Math.abs(x - r.x) < r.w / 2 + 3 && Math.abs(z - r.z) < r.h / 2 + 3)) {
      ctx.fillStyle = '#485650';
      const [a, b] = point(x, z);
      ctx.fillRect(a - CELL * factor / 2, b - CELL * factor / 2, CELL * factor + .5, CELL * factor + .5);
    }
  }
  ctx.textAlign = 'center';
  ctx.textBaseline = 'middle';
  for (const r of world.rooms) {
    if (!r.visited) continue;
    const [x, z] = point(r.x, r.z);
    ctx.fillStyle = '#cbb88b';
    ctx.font = '11px Georgia';
    ctx.fillText(roman(r.id), x, z);
  }
  for (const m of meta) {
    if (state.relics.includes(m.room)) continue;
    const r = world.rooms[m.room - 1],
      [x, z] = point(r.x, r.z);
    ctx.fillStyle = '#cbad68';
    ctx.beginPath();
    ctx.arc(x, z - 12, 4, 0, Math.PI * 2);
    ctx.fill();
  }
  const start = world.rooms[34],
    [sx, sz] = point(start.x, start.z);
  ctx.fillStyle = '#ddca92';
  ctx.font = '20px Georgia';
  ctx.fillText('◇', sx, sz + 12);
  const [px, pz] = point(pose.x, pose.z);
  ctx.save();
  ctx.translate(px, pz);
  ctx.rotate(-pose.yaw);
  ctx.fillStyle = '#eee0b4';
  ctx.strokeStyle = '#121a20';
  ctx.lineWidth = 2;
  ctx.beginPath();
  ctx.moveTo(0, -9);
  ctx.lineTo(6, 7);
  ctx.lineTo(0, 4);
  ctx.lineTo(-6, 7);
  ctx.closePath();
  ctx.fill();
  ctx.stroke();
  ctx.restore();
  $('map-progress').textContent = `기록한 방 ${state.visited.length} / 35 · 지하 공간의 성물은 ●로 표시됩니다.`;
}
let drag = null,
  suppressClick = false;
renderer.domElement.addEventListener('pointerdown', e => {
  if (mode !== 'playing') return;
  if (e.button === 2) {
    block = state.stamina > 0;
    return;
  }
  if (e.button === 0 && !document.pointerLockElement) {
    drag = {
      x: e.clientX,
      y: e.clientY,
      total: 0,
      id: e.pointerId
    };
    suppressClick = false;
    renderer.domElement.setPointerCapture(e.pointerId);
  }
});
renderer.domElement.addEventListener('pointermove', e => {
  if (mode !== 'playing') return;
  if (document.pointerLockElement) {
    pose.yaw -= e.movementX * .0025 * prefs.sensitivity;
    pose.pitch = Math.max(-1.1, Math.min(1.1, pose.pitch - e.movementY * .0025 * prefs.sensitivity));
  } else if (drag) {
    const dx = e.clientX - drag.x,
      dy = e.clientY - drag.y;
    drag.total += Math.hypot(dx, dy);
    drag.x = e.clientX;
    drag.y = e.clientY;
    pose.yaw -= dx * .004 * prefs.sensitivity;
    pose.pitch = Math.max(-1.1, Math.min(1.1, pose.pitch - dy * .004 * prefs.sensitivity));
    suppressClick = drag.total > 5;
  }
});
renderer.domElement.addEventListener('pointerup', e => {
  if (e.button === 2) block = false;
  if (e.button === 0) {
    if (!suppressClick && mode === 'playing') attack();
    drag = null;
  }
});
renderer.domElement.addEventListener('pointercancel', () => {
  drag = null;
  block = false;
});
renderer.domElement.addEventListener('contextmenu', e => e.preventDefault());
addEventListener('keydown', e => {
  if (e.target instanceof HTMLInputElement || e.target instanceof HTMLSelectElement) return;
  if (['Space', 'ArrowLeft', 'ArrowRight', 'ArrowUp', 'ArrowDown'].includes(e.code)) e.preventDefault();
  if (e.repeat) {
    if (mode === 'playing') keys.add(e.code);
    return;
  }
  if (e.code === 'Escape') {
    if (mode === 'playing') pause();
    else close();
    return;
  }
  if (mode !== 'playing') {
    if (mode === 'paused' && ['KeyM', 'KeyI', 'KeyJ'].includes(e.code)) close();
    return;
  }
  keys.add(e.code);
  if (e.code === 'KeyE') interact();
  if (e.code === 'Space') attack();
  if (e.code === 'KeyQ') block = state.stamina > 0;
  if (e.code === 'Digit1') heal();
  if (e.code === 'KeyM') pause('map-screen');
  if (e.code === 'KeyI') pause('bag-screen');
  if (e.code === 'KeyJ') pause('journal-screen');
  if (e.code === 'KeyF') renderer.domElement.requestPointerLock()?.catch(() => toast('마우스 잠금을 사용할 수 없습니다. 화면을 드래그하십시오.'));
});
addEventListener('keyup', e => {
  keys.delete(e.code);
  if (e.code === 'KeyQ') block = false;
});
addEventListener('blur', () => {
  keys.clear();
  block = false;
  if (mode === 'playing') pause();
});
document.addEventListener('visibilitychange', () => {
  if (document.hidden && mode === 'playing') pause();
});
document.addEventListener('pointerlockchange', () => {
  if (!document.pointerLockElement && mode === 'playing') pause();
});
document.querySelectorAll('[data-move]').forEach(b => {
  b.onpointerdown = e => {
    e.preventDefault();
    b.setPointerCapture(e.pointerId);
    if (mode === 'playing') keys.add(b.dataset.move);
  };
  b.onpointerup = b.onpointercancel = () => keys.delete(b.dataset.move);
});
$('touch-attack').onclick = attack;
$('touch-use').onclick = interact;
$('touch-block').onpointerdown = e => {
  e.currentTarget.setPointerCapture(e.pointerId);
  if (mode === 'playing') block = true;
};
$('touch-block').onpointerup = $('touch-block').onpointercancel = () => block = false;
addEventListener('pagehide', save);

// One low cost draw for drifting dust. Uses no texture or animated CPU colliders.
const dustGeometry = new T.BufferGeometry(),
  dustPositions = [];
for (let i = 0; i < 100; i++) dustPositions.push((noise(i, 1) - .5) * 24, noise(i, 2) * 5, (noise(i, 3) - .5) * 24);
dustGeometry.setAttribute('position', new T.Float32BufferAttribute(dustPositions, 3));
const dust = new T.Points(dustGeometry, new T.PointsMaterial({
  color: 0xb8b7a0,
  size: .025,
  transparent: true,
  opacity: .26,
  depthWrite: false
}));
scene.add(dust);

function frame(now) {
  requestAnimationFrame(frame);
  const started = performance.now(),
    dt = Math.min(.04, (now - last) / 1000 || .016);
  last = now;
  clock += dt;
  if (!ready) return;
  if (mode === 'playing') {
    state.seconds += dt;
    const moving = movement(dt);
    updateEnemies(dt);
    if (attackTime > 0) {
      attackTime = Math.max(0, attackTime - dt);
      if (attackTime < .29 && !attackLanded) {
        attackImpact();
        attackLanded = true;
      }
    }
    if (hurtTime > 0) {
      hurtTime -= dt;
      if (hurtTime <= 0) $('damage').style.opacity = 0;
    }
    camera.position.set(pose.x, 1.7 + (moving && !prefs.reduced ? Math.sin(clock * 10) * .025 : 0), pose.z);
    camera.rotation.set(pose.pitch, pose.yaw, 0);
    const swing = attackTime > 0 ? Math.sin((.48 - attackTime) / .48 * Math.PI) : 0;
    hands.right.rotation.set(-swing * .35, swing * .7, -.15 + swing * 1.5);
    hands.right.position.x = .6 - swing * .23;
    hands.left.position.set(block ? -.15 : -.6, block ? -.17 : -.4, block ? -.5 : -.64);
    hands.left.rotation.y = block ? -.2 : 0;
    hands.root.position.y = -.3 + (moving && !prefs.reduced ? Math.sin(clock * 10) * .012 : 0);
    roomTime += dt;
    if (roomTime > .1) {
      roomTime = 0;
      updateRoom();
      target = findTarget();
      $('prompt').hidden = !target;
      $('prompt-text').textContent = target ? target.kind === 'relic' ? target.name : target.kind === 'exit' ? '귀환 인장 · 서약 확인' : '상자 수색' : '';
      updateHUD();
      const nearest = world.enemies.filter(e => !e.dead && Math.hypot(e.x - pose.x, e.z - pose.z) < 7 && sight(pose.x, pose.z, e.x, e.z)).sort((a, b) => Math.hypot(a.x - pose.x, a.z - pose.z) - Math.hypot(b.x - pose.x, b.z - pose.z))[0];
      $('boss').hidden = !nearest;
      if (nearest) {
        $('enemy-name').textContent = nearest.name + (nearest.state === 'windup' ? ' · 공격 예고' : '');
        $('enemy-health').style.width = `${nearest.hp/nearest.maxHp*100}%`;
        $('enemy-health').style.background = nearest.state === 'windup' ? '#dd865d' : '#93413c';
      }
    }
    saveTime += dt;
    if (saveTime > 10) {
      saveTime = 0;
      save();
    }
  }
  if (toastUntil && clock > toastUntil) {
    $('toast').hidden = true;
    toastUntil = 0;
  }
  if (mode === 'playing' || mode === 'title')
    for (const o of world.objects) {
      if (o.kind === 'relic' && !o.collected) {
        o.group.rotation.y = clock * .4;
        o.group.position.y = 1.75 + (prefs.reduced ? 0 : Math.sin(clock * 1.5) * .07);
      }
      if (o.kind === 'chest' && o.opened) o.lid.rotation.x += (-1.35 - o.lid.rotation.x) * Math.min(1, dt * 5);
    }
  if (mode === 'title') {
    const r = world.rooms[0];
    camera.position.x = r.x - 2 + (prefs.reduced ? 0 : Math.sin(clock * .08) * .4);
    camera.rotation.y = Math.PI + .16 + (prefs.reduced ? 0 : Math.sin(clock * .08) * .025);
  }
  mat.uniforms.eye.value.copy(camera.position);
  mat.uniforms.torch.value.copy(camera.position).add(new T.Vector3(-.6, .3, -.4));
  mat.uniforms.clock.value = clock;
  const nearby = world.flames.map(f => ({
    f,
    d: (f.x - camera.position.x) ** 2 + (f.z - camera.position.z) ** 2
  })).sort((a, b) => a.d - b.d);
  for (let i = 0; i < 4; i++) {
    const f = nearby[i].f;
    mat.uniforms.lamps.value[i].set(f.x, f.y, f.z);
  }
  dust.position.set(Math.round(camera.position.x / 12) * 12, 0, Math.round(camera.position.z / 12) * 12);
  dust.rotation.y = prefs.reduced ? 0 : Math.sin(clock * .03) * .1;
  renderer.info.reset();
  renderer.render(scene, camera);
  frameCost = performance.now() - started;
}

function snapshot() {
  return {
    ready,
    mode,
    pose: {
      ...pose
    },
    room: activeRoom?.id,
    state: state ? JSON.parse(JSON.stringify(state)) : null,
    target: target?.id,
    attackTime,
    blocking: block,
    blockedMoves,
    renderer: {
      calls: renderer.info.render.calls,
      triangles: renderer.info.render.triangles,
      lines: renderer.info.render.lines,
      framebuffer: renderer.getSize(new T.Vector2()).toArray(),
      cpuSubmitMs: frameCost
    },
    world: {
      rooms: world?.rooms.length,
      tiles: world?.tiles.size,
      parts: world?.parts,
      obstacles: world?.obstacles.length
    },
    enemies: world?.enemies.map(({
      id,
      hp,
      x,
      z,
      dead,
      state,
      timer
    }) => ({
      id,
      hp,
      x,
      z,
      dead,
      state,
      timer
    }))
  };
}
try {
  const response = await fetch('./layout.json');
  if (!response.ok) throw Error(`지도 HTTP ${response.status}`);
  world = buildWorld(await response.json(), mat);
  scene.add(world.root);
  for (const e of world.enemies) {
    if (!canMove(e.x, e.z)) {
      let found = false;
      for (let radius = .5; radius < 3 && !found; radius += .5)
        for (let k = 0; k < 8 && !found; k++) {
          const x = e.x + Math.cos(k * Math.PI / 4) * radius,
            z = e.z + Math.sin(k * Math.PI / 4) * radius;
          if (canMove(x, z)) {
            e.x = x;
            e.z = z;
            e.home = [x, z];
            found = true;
          }
        }
      if (!found) throw Error(`수호자 ${e.id}의 이동 공간이 없습니다.`);
    }
    world.root.add(makeEnemy(e, mat));
  }
  window.gothicGame = {
    snapshot
  };
  if (qa) window.gothicGame.qa = {
    world,
    canMove,
    sight,
    setPose(x, z, yaw = 0) {
      if (!canMove(x, z)) throw Error('QA pose must be on an unoccupied playable floor.');
      Object.assign(pose, {
        x,
        z,
        yaw,
        pitch: 0
      });
      keys.clear();
      block = false;
    },
    step(dt) {
      if (mode !== 'playing') throw Error('Play before stepping');
      movement(Math.min(dt, .04));
    },
    damage: hit,
    attack,
    interact,
    pause,
    close,
    drawMap
  };
  ready = true;
  $('load-status').textContent = '준비되었습니다 · 화면을 누르고 성소에 들어가십시오.';
  $('new-game').disabled = false;
  title();
} catch (error) {
  console.error(error);
  $('load-status').textContent = `성소를 열지 못했습니다. ${error.message} · 로컬 실행 안내를 확인하십시오.`;
  $('new-game').disabled = true;
}
requestAnimationFrame(frame);
