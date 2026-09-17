const fs = require('node:fs');
const path = require('node:path');
const { pathToFileURL } = require('node:url');
const { createHash } = require('node:crypto');
const assert = require('node:assert/strict');
const { chromium } = require('/Users/duq711gmail.com/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/playwright');

(async () => {
  const browser = await chromium.launch({
    executablePath: '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',
    headless: true,
    args: ['--disable-background-networking', '--disable-component-update'],
  });
  const checks = [];
  const errors = [];
  let dataAudit;
  const page = await browser.newPage({ viewport: { width: 1440, height: 1000 } });
  page.on('pageerror', error => errors.push(error.message));
  async function checkImages() {
    await page.waitForFunction(() => [...document.querySelectorAll('#panels img')].every(img => img.complete && img.naturalWidth > 0));
  }
  try {
    await page.goto(pathToFileURL(path.join(__dirname, 'index.html')).href);
    const catalog = await page.locator('#data').evaluate(el => JSON.parse(el.textContent));
    const links = [];
    for (const entry of [...catalog.objects, ...catalog.scenes]) {
      if (entry.concept) links.push(entry.concept);
      for (const key of ['baseline', 'current']) {
        const record = entry[key];
        if (record) links.push(record.sheet, record.manifest, ...Object.values(record.views || {}));
      }
    }
    for (const url of links) assert(fs.existsSync(path.resolve(__dirname, decodeURIComponent(url))), `Missing referenced file: ${url}`);
    for (const scene of catalog.scenes) {
      if (scene.baseline && scene.current) {
        for (const key of ['position', 'target', 'fov']) assert.deepEqual(scene.baseline[key], scene.current[key]);
      }
    }
    if (process.argv.includes('--require-complete')) {
      for (const key of ['total', 'concept', 'baseline', 'current']) assert.equal(catalog.counts[key], 126);
      assert.equal(catalog.scenes.length, 10);
      assert(catalog.scenes.every(scene => scene.baseline && scene.current));
      assert.equal(new Set(catalog.objects.map(entry => entry.current.iteration)).size, 1, 'Final objects must use one completed aggregate capture');
      const currentManifests = new Set([...catalog.objects, ...catalog.scenes].map(entry => entry.current.manifest));
      for (const manifestUrl of new Set(links.filter(url => url.endsWith('capture_manifest.json')))) {
        const manifest = JSON.parse(fs.readFileSync(path.resolve(__dirname, decodeURIComponent(manifestUrl))));
        assert.notEqual(manifest.source_files_unchanged, false, 'Capture sources changed during rendering');
        if (currentManifests.has(manifestUrl)) assert.equal(manifest.source_files_unchanged, true, 'Final current captures require verified unchanged sources');
        assert.equal(manifest.actual_renderer, 'vulkan');
        assert.equal(manifest.display_driver, 'embedded');
        assert.equal(manifest.expedition_and_cursor_preserved, true);
      }
    }
    dataAudit = {
      coverage: catalog.counts,
      referenced_file_checks: links.length,
      same_camera_scene_checks: catalog.scenes.filter(scene => scene.baseline && scene.current).length,
      current_object_iterations: [...new Set(catalog.objects.map(entry => entry.current?.iteration).filter(Boolean))],
      current_scene_iterations: [...new Set(catalog.scenes.map(entry => entry.current?.iteration).filter(Boolean))],
      html_sha256: createHash('sha256').update(fs.readFileSync(path.join(__dirname, 'index.html'))).digest('hex'),
    };
    await checkImages();
    assert.equal(await page.locator('#list button').count(), 126);
    assert.equal(await page.locator('#panels .panel').count(), 3);
    checks.push('126 object entries and initial three loaded image panels');
    await page.locator('#search').fill('reliquary_chest');
    assert.equal(await page.locator('#list button').count(), 1);
    await page.locator('#list button').click();
    assert.match(await page.locator('#meta').innerText(), /reliquary_chest/);
    await checkImages();
    const keys = ['sheet', 'front', 'back', 'left', 'right', 'top', 'bottom'];
    for (let i = 0; i < keys.length; i++) {
      await page.locator('#directions button').nth(i).click();
      assert.equal(await page.locator('#directions button[aria-pressed=true]').count(), 1);
      const sources = await page.locator('#panels .panel').nth(1).locator('img').getAttribute('src');
      assert(sources.endsWith(keys[i] === 'sheet' ? '_six_views.png' : `_${keys[i]}.png`));
      await checkImages();
    }
    checks.push('Search by object ID and all seven direction controls');
    await page.locator('#directions button').first().click();
    await checkImages();
    await page.screenshot({ path: path.join(__dirname, 'viewer_objects_1440.png'), fullPage: true });
    await page.locator('#panels .visual').first().focus();
    await page.keyboard.press('Enter');
    assert.equal(await page.locator('#lightbox').evaluate(el => el.open), true);
    await page.waitForFunction(() => document.querySelector('#largeImage').complete && document.querySelector('#largeImage').naturalWidth > 0);
    await page.screenshot({ path: path.join(__dirname, 'viewer_modal_1440.png'), fullPage: true });
    await page.keyboard.press('Escape');
    assert.equal(await page.locator('#lightbox').evaluate(el => el.open), false);
    await page.locator('#panels .visual').last().click();
    await page.locator('#close').click();
    assert.equal(await page.locator('#lightbox').evaluate(el => el.open), false);
    checks.push('Keyboard Enter opens image; Escape and close button dismiss modal');
    await page.locator('#search').fill('zzzz-no-object');
    assert.equal(await page.locator('#list button').count(), 0);
    assert.match(await page.locator('#list').innerText(), /일치하는 항목이 없습니다/);
    await page.locator('#next').click();
    await page.locator('#search').fill('방패');
    assert.equal(await page.locator('#list button').count(), 1);
    await page.locator('#list button').click();
    await page.locator('#search').fill('');
    const current = await page.locator('#title').innerText();
    await page.locator('#next').focus();
    await page.keyboard.press('Enter');
    assert.notEqual(await page.locator('#title').innerText(), current);
    await page.locator('#previous').click();
    assert.equal(await page.locator('#title').innerText(), current);
    checks.push('Empty search, Korean search, and keyboard item navigation');
    await page.locator('#search').fill('mine_stone_pillar_');
    const lastFilteredTitle = await page.locator('#list button span').last().innerText();
    await page.locator('#previous').click();
    assert.equal(await page.locator('#title').innerText(), lastFilteredTitle);
    await page.locator('#search').fill('flame_and_sparks');
    await page.locator('#list button').click();
    assert.match(await page.locator('#meta').innerText(), /^시각 효과/);
    checks.push('Previous selects last filtered result when selection is outside results; category is localized');
    await page.locator('#scenesTab').click();
    assert.equal(await page.locator('#list button').count(), 10);
    assert.equal(await page.locator('#directions button').count(), 0);
    assert.equal(await page.locator('#panels .panel').count(), 2);
    for (let i = 0; i < 10; i++) {
      await page.locator('#list button').nth(i).click();
      await checkImages();
    }
    await page.locator('#list button').nth(1).click();
    await checkImages();
    await page.screenshot({ path: path.join(__dirname, 'viewer_scenes_1440.png'), fullPage: true });
    checks.push('All ten scene comparisons and both image panels load');
    await page.locator('#objectsTab').click();
    assert.equal(await page.locator('#list button').count(), 126);
    await page.setViewportSize({ width: 390, height: 844 });
    await checkImages();
    assert(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth));
    await page.screenshot({ path: path.join(__dirname, 'viewer_mobile_390.png'), fullPage: true });
    checks.push('Objects tab restores and narrow layout has no horizontal overflow');
    assert.deepEqual(errors, []);
    fs.writeFileSync(path.join(__dirname, 'viewer_qa.json'), JSON.stringify({ passed: true, headless: true, viewport: [1440, 1000], data_audit: dataAudit, checks, page_errors: errors }, null, 2) + '\n');
    console.log(JSON.stringify({ passed: true, data_audit: dataAudit, checks, page_errors: errors }));
  } finally {
    await browser.close();
  }
})().catch(error => {
  fs.writeFileSync(path.join(__dirname, 'viewer_qa.json'), JSON.stringify({ passed: false, error: error.message }, null, 2) + '\n');
  console.error(error);
  process.exitCode = 1;
});
