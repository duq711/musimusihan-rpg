// Background Chrome/Metal acceptance. Disposable output stays outside production.
// NODE_PATH=<bundled packages> node validate.cjs [output directory] [frames=600]
const fs = require('node:fs'),
  path = require('node:path'),
  os = require('node:os');
const {
  chromium
} = require('playwright');
const OUT = process.argv[2] || '/tmp/gothic-rebuild-qa-20261020',
  N = Number(process.argv[3] || 600);
const skipPerformance = process.argv.includes('--skip-performance');
fs.mkdirSync(OUT, {
  recursive: true
});
const report = {
  date: '2026-10-20',
  checks: [],
  errors: [],
  externalRequests: [],
  performance: [],
  conditions: {
    viewport: [1280, 900],
    dpr: 1,
    frames: N,
    warmupFrames: 90,
    browser: 'Installed Google Chrome, headless, ANGLE Metal, muted',
    scope: 'Actual new game, nonempty representative views and a real keyboard movement route. Compare room identities, not pixel-equivalent geometry, with the preserved explorer.'
  }
};

function check(ok, name, detail) {
  if (!ok) throw Error(name + ' ' + JSON.stringify(detail || ''));
  report.checks.push({
    name,
    ...(detail === undefined ? {} : {
      detail
    })
  });
}
const snap = p => p.evaluate(() => gothicGame.snapshot());
const wait = p => p.waitForTimeout(140);
async function near(p, type, id, distance = 1.5) {
  return p.evaluate(({
    type,
    id,
    distance
  }) => {
    const api = gothicGame.qa,
      obj = type === 'enemy' ? api.world.enemies.find(e => e.id === id) : api.world.objects.find(o => o.id === id);
    for (let i = 0; i < 24; i++) {
      const a = i * Math.PI / 12,
        x = obj.x + Math.sin(a) * distance,
        z = obj.z + Math.cos(a) * distance;
      if (api.canMove(x, z) && api.sight(x, z, obj.x, obj.z)) {
        api.setPose(x, z, Math.atan2(-(obj.x - x), -(obj.z - z)));
        return {
          x,
          z
        };
      }
    }
    throw Error('No interaction approach ' + id);
  }, {
    type,
    id,
    distance
  });
}
async function roomPose(p, id) {
  return p.evaluate(id => {
    const a = gothicGame.qa,
      r = a.world.rooms[id - 1];
    for (const [dx, dz] of [
        [0, 1.5],
        [1.5, 1.5],
        [-1.5, 1.5],
        [0, -1.5],
        [2, 0],
        [-2, 0]
      ]) {
      if (a.canMove(r.x + dx, r.z + dz)) {
        a.setPose(r.x + dx, r.z + dz, 0);
        return;
      }
    }
    throw Error('No floor in room ' + id);
  }, id);
}
async function sample(p, name, moving = false) {
    if (skipPerformance) return;
    await p.evaluate(() => new Promise(resolve => {
      let n = 0;

      function tick() {
        if (++n >= 90) resolve();
        else requestAnimationFrame(tick);
      }
      requestAnimationFrame(tick);
    }));
    const before = await snap(p);
    if (moving) await p.keyboard.down('KeyW');
    const data = await p.evaluate(({
      N,
      moving
    }) => new Promise(resolve => {
      let last, n = 0,
        direction = 'KeyW';
      const times = [],
        draws = [],
        triangles = [],
        cpu = [];

      function tick(now) {
        if (last !== undefined) times.push(now - last);
        last = now;
        const s = gothicGame.snapshot();
        draws.push(s.renderer.calls);
        triangles.push(s.renderer.triangles);
        cpu.push(s.renderer.cpuSubmitMs);
        if (moving) {
          const r = gothicGame.qa.world.rooms[32],
            next = s.pose.z < r.z - .5 ? 'KeyS' : s.pose.z > r.z + 1 ? 'KeyW' : direction;
          if (next !== direction) {
            dispatchEvent(new KeyboardEvent('keyup', {
              code: direction
            }));
            dispatchEvent(new KeyboardEvent('keydown', {
              code: next
            }));
            direction = next;
          }
        }
        if (++n <= N) requestAnimationFrame(tick);
        else {
          if (moving) dispatchEvent(new KeyboardEvent('keyup', {
            code: direction
          }));
          resolve({
            times,
            draws,
            triangles,
            cpu
          });
        }
      }
      requestAnimationFrame(tick);
    }), {
      N,
      moving
    });
    if (moving) {
      await p.keyboard.up('KeyW');
      await p.keyboard.up('KeyS');
    }
    const sorted = [...data.times].sort((a, b) => a - b),
      mean = data.times.reduce((s, n) => s + n, 0) / data.times.length;
    const result = {
      name,
      samples: data.times.length,
      mean_ms: mean,
      p50_ms: sorted[Math.floor(sorted.length * .5)],
      p95_ms: sorted[Math.floor(sorted.length * .95)],
      p99_ms: sorted[Math.floor(sorted.length * .99)],
      over_16_67_ratio: data.times.filter(t => t > 16.67).length / data.times.length,
      over_18_ratio: data.times.filter(t => t > 18).length / data.times.length,
      over_33_34_ratio: data.times.filter(t => t > 33.34).length / data.times.length,
      mean_fps: 1000 / mean,
      max_draw_calls: Math.max(...data.draws),
      max_submitted_triangles: Math.max(...data.triangles),
      max_cpu_submit_ms: Math.max(...data.cpu),
      before: before.pose,
      after: (await snap(p)).pose,
      raw_intervals_ms: data.times
    };
    result.target_met = result.mean_fps >= 59 && result.p95_ms <= 18;
    report.performance.push(result);
    console.log(JSON.stringify({
      ...result,
      raw_intervals_ms: undefined
    }));
  }
  (async () => {
    let browser;
    try {
      browser = await chromium.launch({
        executablePath: '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',
        headless: true,
        args: ['--use-gl=angle', '--use-angle=metal', '--mute-audio']
      });
      report.browserVersion = browser.version();
      report.hardware = {
        cpu: os.cpus()[0].model,
        arch: os.arch(),
        os: os.release()
      };
      const p = await browser.newPage({
        viewport: {
          width: 1280,
          height: 900
        },
        deviceScaleFactor: 1
      });
      p.on('pageerror', e => report.errors.push(e.message));
      p.on('console', m => {
        if (m.type() === 'error') report.errors.push(m.text());
      });
      p.on('request', r => {
        if (/^https?:/.test(r.url()) && new URL(r.url()).origin !== 'http://127.0.0.1:8790') report.externalRequests.push(r.url());
      });
      await p.goto('http://127.0.0.1:8790/?qa=1');
      await p.waitForFunction(() => window.gothicGame?.snapshot().ready, undefined, {
        timeout: 60000
      });
      report.gpu = await p.evaluate(() => {
        const gl = document.querySelector('#stage canvas').getContext('webgl2'),
          e = gl.getExtension('WEBGL_debug_renderer_info');
        return {
          renderer: e ? gl.getParameter(e.UNMASKED_RENDERER_WEBGL) : null,
          framebuffer: [gl.drawingBufferWidth, gl.drawingBufferHeight]
        };
      });
      check(!/SwiftShader|llvmpipe/i.test(report.gpu.renderer), 'Hardware Metal renderer', report.gpu);
      check((await snap(p)).world.rooms === 35, 'All 35 newly authored rooms load');
      await p.screenshot({
        path: path.join(OUT, 'title.png')
      });
      await p.click('#new-game');
      await wait(p);
      check((await snap(p)).mode === 'playing', 'New game opens the real expedition');
      const start = await snap(p);
      await p.keyboard.down('KeyW');
      await p.waitForTimeout(450);
      await p.keyboard.up('KeyW');
      const walked = await snap(p);
      check(Math.hypot(walked.pose.x - start.pose.x, walked.pose.z - start.pose.z) > .8, 'Actual WASD walking moves on floor');
      await p.keyboard.down('ShiftLeft');
      await p.keyboard.down('KeyS');
      await p.waitForTimeout(400);
      await p.keyboard.up('KeyS');
      await p.keyboard.up('ShiftLeft');
      check((await snap(p)).state.stamina < 98, 'Sprinting spends stamina');
      await p.keyboard.press('Escape');
      await wait(p);
      const frozen = await snap(p);
      await p.waitForTimeout(350);
      check((await snap(p)).state.seconds === frozen.state.seconds, 'Pause freezes simulation and expedition clock');
      await p.click('#resume');
      await p.keyboard.press('KeyM');
      check(await p.isVisible('#map-screen'), 'M opens exploration map');
      await p.screenshot({
        path: path.join(OUT, 'map.png')
      });
      await p.click('#map-screen [data-close]');
      await p.keyboard.press('KeyI');
      check((await p.locator('#inventory .item').count()) === 5, 'Inventory shows equipment and actual item counts');
      await p.click('#bag-screen [data-close]');
      await p.keyboard.press('KeyJ');
      check((await p.locator('#journal-list li').count()) === 3, 'Journal shows three live relic objectives');
      await p.click('#journal-screen [data-close]');
      const connectivity = await p.evaluate(() => {
        const {
          world,
          canMove
        } = gothicGame.qa, step = .54, key = (x, z) => `${x},${z}`, valid = new Set();
        for (const t of world.tiles) {
          const [ix, iz] = t.split(',').map(Number);
          for (let dx = -1; dx <= 1; dx++)
            for (let dz = -1; dz <= 1; dz++) {
              const x = ix * 2 + dx,
                z = iz * 2 + dz,
                k = key(x, z);
              if (!valid.has(k) && canMove(x * step, z * step)) valid.add(k);
            }
        }
        const start = [Math.round(world.start[0] / step), Math.round(world.start[2] / step)],
          queue = [start],
          seen = new Set([key(...start)]);
        for (let i = 0; i < queue.length; i++) {
          const [x, z] = queue[i];
          for (const [dx, dz] of [
              [1, 0],
              [-1, 0],
              [0, 1],
              [0, -1]
            ]) {
            const k = key(x + dx, z + dz);
            if (valid.has(k) && !seen.has(k) && [.25, .5, .75].every(t => canMove((x + dx * t) * step, (z + dz * t) * step))) {
              seen.add(k);
              queue.push([x + dx, z + dz]);
            }
          }
        }
        return {
          testedNodes: valid.size,
          reachableNodes: seen.size,
          unreachableRooms: world.rooms.filter(r => !queue.some(([x, z]) => Math.abs(x * step - r.x) < r.w * .3 && Math.abs(z * step - r.z) < r.h * .3)).map(r => r.id),
          unreachableObjects: world.objects.filter(o => !queue.some(([x, z]) => Math.hypot(x * step - o.x, z * step - o.z) < 1.8 && gothicGame.qa.sight(x * step, z * step, o.x, o.z))).map(o => o.id)
        };
      });
      check(!connectivity.unreachableRooms.length && !connectivity.unreachableObjects.length, 'Physical capsule path reaches all 35 rooms and every loot/relic/exit', connectivity);
      await p.evaluate(() => {
        const r = gothicGame.qa.world.rooms[34];
        gothicGame.qa.setPose(r.x, r.z, 0);
      });
      await p.keyboard.down('KeyA');
      await p.waitForTimeout(2000);
      await p.keyboard.up('KeyA');
      const atWall = await snap(p);
      check(atWall.blockedMoves > 0, 'Actual movement rejects wall penetration');
      check(await p.evaluate(() => gothicGame.qa.canMove(gothicGame.snapshot().pose.x, gothicGame.snapshot().pose.z)), 'Player remains on unoccupied supported floor');
      await near(p, 'object', 'chest-35');
      await p.keyboard.press('KeyE');
      await wait(p);
      let loot = await snap(p);
      check(loot.state.opened.includes('chest-35') && loot.state.potions === 4, 'E opens the actual chest and grants one potion');
      const money = loot.state.crowns;
      await p.keyboard.press('KeyE');
      check((await snap(p)).state.crowns === money, 'Opened chest cannot grant duplicate loot');
      await near(p, 'object', 'return-seal', 1);
      await p.keyboard.press('KeyE');
      check((await snap(p)).mode === 'playing', 'Exit remains sealed before all relics');
      await roomPose(p, 33);
      await wait(p);
      await p.screenshot({
        path: path.join(OUT, 'room33.png')
      });
      check((await snap(p)).room === 33, 'Living quarters have their own room title');
      await sample(p, 'room33-interior');
      // Actual movement handler through the living-quarters aisle, reversing W/S
      // at its ends. No pose changes or teleports during the recorded sample.
      await p.evaluate(() => {
        const r = gothicGame.qa.world.rooms[32];
        gothicGame.qa.setPose(r.x, r.z + 1.4, 0);
      });
      await sample(p, 'room33-walking-aisle', true);
      await roomPose(p, 34);
      await sample(p, 'room34-interior');
      await roomPose(p, 35);
      await sample(p, 'room35-interior');
      await roomPose(p, 1);
      await p.keyboard.down('KeyQ');
      await sample(p, 'chapel-combat-view');
      await p.keyboard.up('KeyQ');
      await p.screenshot({
        path: path.join(OUT, 'chapel.png')
      });
      await p.keyboard.press('Digit1');
      for (const room of [30, 23, 1]) {
        const enemyId = 'guardian-' + room,
          relicId = 'relic-' + room;
        await near(p, 'object', relicId);
        await p.keyboard.press('KeyE');
        check(!(await snap(p)).state.relics.includes(room), 'Guardian seals relic ' + room);
        await near(p, 'enemy', enemyId, 1.5);
        if (room === 30) {
          await p.keyboard.down('KeyQ');
          const hp = (await snap(p)).state.hp;
          await p.waitForTimeout(1250);
          check((await snap(p)).state.hp === hp, 'Facing shield blocks the real enemy strike');
          await p.keyboard.up('KeyQ');
          await p.waitForTimeout(2200);
          check((await snap(p)).state.hp < hp, 'Unguarded enemy strike damages health');
          const before = (await snap(p)).state;
          await p.keyboard.press('Digit1');
          const after = (await snap(p)).state;
          check(after.hp > before.hp && after.potions === before.potions - 1, 'Healing consumes a potion and restores health');
        }
        for (let n = 0; n < 8; n++) {
          const current = await snap(p),
            e = current.enemies.find(e => e.id === enemyId);
          if (e.dead) break;
          await near(p, 'enemy', enemyId, 1.5);
          await p.keyboard.press('Space');
          await p.waitForTimeout(560);
        }
        check((await snap(p)).state.dead.includes(enemyId), 'Actual sword defeats guardian ' + room);
        await near(p, 'object', relicId);
        await p.keyboard.press('KeyE');
        check((await snap(p)).state.relics.includes(room), 'Actual E interaction recovers relic ' + room);
      }
      await p.keyboard.press('Escape');
      await wait(p);
      await p.click('#save-title');
      check(await p.isVisible('#continue-game'), 'New game uses its own saved expedition');
      await p.reload();
      await p.waitForFunction(() => window.gothicGame?.snapshot().ready);
      await p.click('#continue-game');
      const restored = await snap(p);
      check(restored.state.relics.length === 3 && restored.state.opened.includes('chest-35') && restored.state.kills === 3, 'Reload preserves relics, loot and defeated guardians');
      await near(p, 'object', 'return-seal', 1);
      await p.keyboard.press('KeyE');
      check((await snap(p)).mode === 'end' && (await p.textContent('#end-title')).includes('성소는'), 'All three relics unlock the actual victory return');
      await p.screenshot({
        path: path.join(OUT, 'ending.png')
      });
      await p.click('#retry');
      check((await snap(p)).state.relics.length === 0 && (await snap(p)).state.hp === 100, 'Retry resets a complete new expedition');
      await p.keyboard.press('Escape');
      await p.selectOption('#quality', '0.75');
      check((await snap(p)).renderer.framebuffer[0] === 960, 'Quality setting changes actual framebuffer');
      await p.check('#motion');
      check(await p.isChecked('#motion'), 'Reduced motion preference works');
      await p.selectOption('#quality', '1');
      await p.click('#resume');
      // Corrupt an inactive save. Reloading during active play deliberately runs
      // pagehide autosave, replacing the injected corruption with a valid snapshot.
      await p.keyboard.press('Escape');
      await p.click('#save-title');
      await p.evaluate(() => localStorage.setItem('musimusihan.gothic-origin.v1', '{broken'));
      await p.reload();
      await p.waitForFunction(() => window.gothicGame?.snapshot().ready);
      check(await p.isHidden('#continue-game'), 'Corrupt save safely returns to a fresh title');
      await p.setViewportSize({
        width: 390,
        height: 844
      });
      await p.screenshot({
        path: path.join(OUT, 'mobile-title.png')
      });
      check(await p.evaluate(() => document.documentElement.scrollWidth === innerWidth), '390px title has no horizontal overflow');
      await p.click('#new-game');
      await p.keyboard.press('KeyM');
      check(await p.isVisible('#map-screen [data-close]'), '390px map close remains accessible');
      await p.screenshot({
        path: path.join(OUT, 'mobile-map.png')
      });
      await p.click('#map-screen [data-close]');
      check(!report.errors.length, 'Zero runtime or shader errors', report.errors);
      check(!report.externalRequests.length, 'All runtime assets load offline', report.externalRequests);
      if (!skipPerformance) check(report.performance.length === 5 && report.performance.every(p => p.target_met), 'Representative frame-time targets', report.performance.map(({
        name,
        target_met
      }) => ({
        name,
        target_met
      })));
      else report.performanceNotRepeated = 'Only the inactive-corruption fixture changed after the completed five-scenario measurements. Keep the earlier measured receipt.';
      report.status = 'passed';
    } catch (e) {
      report.status = 'failed';
      report.failure = e.stack;
      console.error(e.stack);
      process.exitCode = 1;
    } finally {
      if (browser) await browser.close();
      fs.writeFileSync(path.join(OUT, 'validation.json'), JSON.stringify(report, null, 2) + '\n');
      console.log(JSON.stringify({
        status: report.status,
        checks: report.checks.length,
        errors: report.errors,
        output: OUT
      }));
    }
  })();
