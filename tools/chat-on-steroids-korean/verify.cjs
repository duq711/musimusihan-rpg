const fs = require('node:fs');
const assert = require('node:assert/strict');
const { JSDOM } = require('jsdom');
const path = require('node:path');
const root = __dirname;
const html = fs.readFileSync(path.join(root, 'build/out/renderer/index.html'), 'utf8');
const renderer = fs.readFileSync(path.join(root, 'build/out/renderer/assets/index-Bk8Dq4Pu.js'), 'utf8');
const prefix = renderer.slice(0, renderer.indexOf('const DISMISSED_VERSION_KEY ='));
assert(prefix.includes('function initLanguage()'));
const ko = JSON.parse(fs.readFileSync(path.join(root,'ko.json'),'utf8'));
const source = Object.assign({}, ...[1,2,3].map(n => JSON.parse(fs.readFileSync(path.join(root,`source-part-${n}.json`),'utf8'))));
assert.deepEqual(Object.keys(ko),Object.keys(source));
for(const [key,value] of Object.entries(ko)) {
  assert(value.trim(),key);
  assert.deepEqual([...value.matchAll(/\{\d+\}/g)].map(m=>m[0]).sort(), [...key.matchAll(/\{\d+\}/g)].map(m=>m[0]).sort(),key);
}
function fixture(saved) {
  const dom = new JSDOM(html, {url:'https://cos-patch.test',runScripts:'outside-only'});
  if(saved)dom.window.localStorage.setItem('cos.ui.language',saved);
  dom.window.eval(prefix+'\nwindow.testI18n = {t,ui,uiText,initLanguage,setLanguage};');
  return dom;
}
const dom = fixture('ko');
const d = dom.window.document;
const api = dom.window.testI18n;
const missing = [];
const walker = d.createTreeWalker(d.body,4);
while(walker.nextNode()){
  const n=walker.currentNode;
  if(n.parentElement?.closest('script,style,svg,code,kbd,textarea,[translate="no"]'))continue;
  const s=n.textContent.replace(/\s+/g,' ').trim();
  if(/[a-zA-Z]{2}/.test(s)&&!Object.hasOwn(ko,s))missing.push(s);
}
for(const n of d.querySelectorAll('[title],[placeholder],[aria-label]')){
  for(const attr of ['title','placeholder','aria-label']){
    const s=n.getAttribute(attr);
    if(s&&/[a-zA-Z]{2}/.test(s)&&!Object.hasOwn(ko,s))missing.push(s);
  }
}
assert.deepEqual(missing,[],'Static UI strings missing from Korean catalog');
api.initLanguage();
const input=d.getElementById('chatInput');
input.value='Save\n사용자 초안 <script>not markup</script> 🙂';
input.setSelectionRange(2,7);
const automation=d.getElementById('chatAutomation');
automation.value='loop';
const authored=d.createElement('div');authored.textContent='Save';d.body.append(authored);
const newer=api.ui(d.createElement('div'),'textContent',()=>api.t('New chat'));d.body.append(newer);
newer.textContent='New chat — 사용자 대화 제목';
const label=api.ui(d.createElement('button'),'textContent',()=>api.t('Remove {0}',['Save <img src=x>']));
api.ui(label,'aria-label',()=>api.t('Remove {0}',['Save <img src=x>']));d.body.append(label);
const iconNodes=[...d.querySelectorAll('svg')];
const select=d.getElementById('uiLanguage');
for(const language of ['ko','en','zh-CN','ko','en','ko']){
  select.value=language;select.dispatchEvent(new dom.window.Event('change'));
  assert.equal(d.documentElement.lang,language);
  assert.equal(select.value,language);
  assert.equal(d.querySelector(`[data-language="${language}"]`).getAttribute('aria-pressed'),'true');
  assert.equal(d.getElementById('chatInput'),input);
  assert.equal(input.value,'Save\n사용자 초안 <script>not markup</script> 🙂');
  assert.deepEqual([input.selectionStart,input.selectionEnd],[2,7]);
  assert.equal(automation.value,'loop');
  assert.equal(authored.textContent,'Save');
  assert.equal(newer.textContent,'New chat — 사용자 대화 제목');
  assert.equal(label.querySelector('img'),null);
  assert.equal(label.textContent,label.getAttribute('aria-label'));
  assert.deepEqual([...d.querySelectorAll('svg')],iconNodes);
  assert.equal(d.getElementById('newChat').textContent.trim(),language==='ko'?ko['New chat']:language==='en'?'New chat':source['New chat']);
}
d.querySelector('[data-language="en"]').click();assert.equal(select.value,'en');
d.querySelector('[data-language="ko"]').click();assert.equal(select.value,'ko');
assert.equal(dom.window.localStorage.getItem('cos.ui.language'),'ko');
for(const literal of ['gpt-6-astra','gpt-6-pro','high','__proto__','toString','/rpg/AGENTS.md'])assert.equal(api.t(literal),literal);
const reloaded=fixture(dom.window.localStorage.getItem('cos.ui.language'));
reloaded.window.testI18n.initLanguage();
assert.equal(reloaded.window.document.documentElement.lang,'ko');
assert.equal(reloaded.window.testI18n.t('Settings'),'설정');
const detachedReads=[];
const host=d.createElement('div');d.body.append(host);
for(let i=0;i<100;i++)host.replaceChildren(api.ui(d.createElement('span'),'textContent',()=>{detachedReads.push(i);return api.t('Settings')}));
host.replaceChildren();detachedReads.length=0;
api.setLanguage('en');assert.equal(detachedReads.length,0);
dom.window.close();reloaded.window.close();
console.log('PASS: 1,134 keys and placeholders; all static labels; Korean/English/Chinese switching; saved language reload; draft text/selection, authored titles/messages, SVGs, internal values preserved; no detached-node repaint.');
