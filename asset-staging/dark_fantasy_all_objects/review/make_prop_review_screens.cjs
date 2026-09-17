const fs = require('node:fs');
const path = require('node:path');
const { pathToFileURL } = require('node:url');
const { chromium } = require('/Users/duq711gmail.com/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/playwright');

(async () => {
  const root = path.resolve(__dirname, '../../..');
  const record = JSON.parse(fs.readFileSync(path.join(root, 'concept-art/dark_fantasy_all_objects/props_final_review.json')));
  const iteration = process.argv[2] || 'final_iteration_01';
  if (!/^[a-z0-9_]+$/.test(iteration)) throw new Error('Invalid capture iteration');
  const capture = path.join(root, 'godot-game/artifacts/visual_qa/dark_fantasy_objects', iteration);
  const output = path.join(__dirname, iteration === 'final_iteration_01' ? 'props_final_pairs' : `props_${iteration}_pairs`);
  fs.mkdirSync(output, { recursive: true });
  const html = path.join(output, 'pair.html');
  fs.writeFileSync(html, '<!doctype html><meta charset="utf-8"><style>body{margin:0;background:#171d1a;color:#dce5d6;font:18px system-ui}header{padding:20px 30px;border-bottom:1px solid #495145}main{display:grid;grid-template-columns:1fr 1fr;gap:16px;padding:10px 20px}h2{font-size:18px;font-weight:500;margin:8px 0 12px}img{width:100%;height:830px;object-fit:contain;background:#1b211e}footer{font-size:13px;color:#a4b29b;padding:8px 25px}</style><header id="title"></header><main><section><h2>생성 컨셉 원본</h2><img id="concept"></section><section><h2>실제 게임 모델 · 최종 6방향</h2><img id="actual"></section></main><footer>원본 파일을 그대로 표시한 검토 화면. 이미지의 색·명암·형태를 편집하지 않았습니다.</footer>');
  const browser = await chromium.launch({ executablePath: '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome', headless: true });
  try {
    const page = await browser.newPage({ viewport: { width: 1920, height: 1000 } });
    await page.goto(pathToFileURL(html).href);
    for (const entry of record.entries) {
      const actual = path.join(capture, `${entry.id}_six_views.png`);
      const target = path.join(output, `${entry.id}.png`);
      if (fs.existsSync(target)) continue;
      if (!fs.existsSync(actual)) continue;
      await page.evaluate(({ title, concept, actual }) => {
        document.querySelector('#title').textContent = title;
        document.querySelector('#concept').src = concept;
        document.querySelector('#actual').src = actual;
      }, { title: `${entry.title} · ${entry.id}`, concept: pathToFileURL(path.join(root, 'concept-art/dark_fantasy_all_objects', entry.concept_file)).href, actual: pathToFileURL(actual).href });
      await page.waitForFunction(() => [...document.images].every(img => img.complete && img.naturalWidth > 0));
      await page.screenshot({ path: target });
      console.log(entry.id);
    }
  } finally { await browser.close(); }
})().catch(error => { console.error(error); process.exitCode = 1; });
