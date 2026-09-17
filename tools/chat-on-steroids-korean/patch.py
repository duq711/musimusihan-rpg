#!/usr/bin/env python3
"""Version-locked, reversible Korean UI patch for Chat On Steroids 2.1.13.

Uses only the Python standard library and macOS ditto/codesign. Does not read or
modify application user data, credentials, conversations, or project files.
"""
import argparse
import copy
import hashlib
import json
from pathlib import Path
import plistlib
import re
import shutil
import struct
import subprocess

ROOT = Path(__file__).resolve().parent
APP = Path.home() / 'Applications/Chat On Steroids.app'
EXPECTED = '4e737cc41af837a978472f4b1db17f22b19873615f87c8b559948e046028234a'
JS = 'out/renderer/assets/index-Bk8Dq4Pu.js'
HTML = 'out/renderer/index.html'
MAIN = 'out/main/index.js'
BACKUP = Path.home() / 'Library/Application Support/Chat On Steroids Korean Patch/original-2.1.13.bundle'

def digest(data):
    return hashlib.sha256(data).hexdigest()

def unpack(data):
    _, size, _, length = struct.unpack('<IIII', data[:16])
    raw = data[16:16 + length]
    return json.loads(raw), 8 + size, digest(raw)

def leaves(tree, prefix=''):
    for name, entry in tree.get('files', {}).items():
        path = prefix + name
        if 'files' in entry:
            yield from leaves(entry, path + '/')
        else:
            yield path, entry

def contents(data):
    tree, start, _ = unpack(data)
    return {p: data[start + int(e['offset']):start + int(e['offset']) + e['size']]
            for p, e in leaves(tree) if 'offset' in e}

def replace_once(text, old, new):
    assert text.count(old) == 1, f'Unexpected patch site: {old[:100]}'
    return text.replace(old, new, 1)

def patch_renderer(js, html, ko):
    js = replace_once(js, 'const STORAGE_KEY$1 = "cos.ui.language";',
        'const koKR = ' + json.dumps(ko, ensure_ascii=False, separators=(',', ':')) + ';\n'
        'const STORAGE_KEY$1 = "cos.ui.language";')
    js = replace_once(js,
        'if (window.localStorage.getItem(STORAGE_KEY$1) === "zh-CN") language = "zh-CN";',
        'const savedLanguage = window.localStorage.getItem(STORAGE_KEY$1);\n'
        '  if (savedLanguage === "zh-CN" || savedLanguage === "ko") language = savedLanguage;')
    js = replace_once(js,
        'const translated = language === "zh-CN" && Object.hasOwn(catalog$1, key) ? catalog$1[key] : source;',
        'const activeCatalog = language === "ko" ? koKR : catalog$1;\n'
        '  const translated = language !== "en" && Object.hasOwn(activeCatalog, key) ? activeCatalog[key] : source;')
    for value in ['select.value', 'button2.dataset.language']:
        js = replace_once(js, f'{value} === "zh-CN" ? "zh-CN" : "en"',
            f'{value} === "ko" ? "ko" : {value} === "zh-CN" ? "zh-CN" : "en"')
    html = replace_once(html, '<div class="language-tabs" role="group" aria-label="Language">',
        '<div class="language-tabs" role="group" aria-label="Language">\n'
        '                <button type="button" data-language="ko" lang="ko" translate="no" aria-pressed="false">한국어</button>')
    html = replace_once(html, '<select id="uiLanguage" class="language-select" translate="no">',
        '<select id="uiLanguage" class="language-select" translate="no"><option value="ko" lang="ko">한국어</option>')
    return js, html

def patch_native(js):
    # Limit changes to known display strings. Internal roles, IPC and tools remain identical.
    a = js.index('function refreshTray() {')
    b = js.index('electron.app.on("second-instance"', a)
    tray = js[a:b]
    for en, ko in {'Connected':'연결됨', 'No internet':'인터넷 연결 없음', 'Not connected':'연결 안 됨',
                   'Open':'열기', 'Disconnect':'연결 해제', 'Connect':'연결', 'Quit':'종료'}.items():
        tray = replace_once(tray, json.dumps(en), json.dumps(ko, ensure_ascii=False))
    js = js[:a] + tray + js[b:]
    for en, ko in {'Import MCP bundle':'MCP 번들 가져오기', 'Approve a folder for ChatGPT':'ChatGPT에서 사용할 폴더 승인',
                   'Import skill':'스킬 가져오기', 'Choose a project folder for ChatGPT':'ChatGPT 프로젝트 폴더 선택',
                   'Select the tunnel executable':'터널 실행 파일 선택', 'Attach files':'파일 첨부'}.items():
        js = replace_once(js, 'title: ' + json.dumps(en), 'title: ' + json.dumps(ko, ensure_ascii=False))
    # Use Electron's native menu roles so accelerators and native editing behavior are retained.
    menu = '''
  electron.Menu.setApplicationMenu(electron.Menu.buildFromTemplate([
    {label: "Chat On Steroids", submenu: [
      {role:"about", label:"Chat On Steroids 정보"}, {type:"separator"},
      {role:"services", label:"서비스"}, {type:"separator"},
      {role:"hide", label:"Chat On Steroids 가리기"}, {role:"hideOthers", label:"기타 가리기"},
      {role:"unhide", label:"모두 보기"}, {type:"separator"}, {role:"quit", label:"Chat On Steroids 종료"}]},
    {label:"파일", submenu:[{role:"close", label:"창 닫기"}]},
    {label:"편집", submenu:[{role:"undo", label:"실행 취소"}, {role:"redo", label:"다시 실행"},
      {type:"separator"}, {role:"cut", label:"잘라내기"}, {role:"copy", label:"복사"},
      {role:"paste", label:"붙여넣기"}, {role:"pasteAndMatchStyle", label:"스타일 맞춰 붙여넣기"},
      {role:"delete", label:"삭제"}, {role:"selectAll", label:"모두 선택"}, {type:"separator"},
      {label:"말하기", submenu:[{role:"startSpeaking", label:"말하기 시작"}, {role:"stopSpeaking", label:"말하기 중단"}]}]},
    {label:"보기", submenu:[{role:"reload", label:"새로고침"}, {role:"forceReload", label:"강제로 새로고침"},
      {role:"toggleDevTools", label:"개발자 도구"}, {type:"separator"},
      {role:"resetZoom", label:"실제 크기"}, {role:"zoomIn", label:"확대"}, {role:"zoomOut", label:"축소"},
      {type:"separator"}, {role:"togglefullscreen", label:"전체 화면 전환"}]},
    {label:"윈도우", role:"windowMenu", submenu:[{role:"minimize", label:"최소화"},
      {role:"zoom", label:"확대/축소"}, {type:"separator"}, {role:"front", label:"모두 앞으로 가져오기"}]}
  ]));
'''
    marker = 'void electron.app.whenReady().then(async () => {\n  if (!shouldBeginAppBootstrap(hasSingleInstanceLock, quitting)) return;'
    return replace_once(js, marker, marker + menu)

def repack(data, updates):
    tree, start, _ = unpack(data)
    tree = copy.deepcopy(tree)
    chunks, offset = [], 0
    for path, entry in leaves(tree):
        if 'offset' not in entry:
            continue
        old = data[start + int(entry['offset']):start + int(entry['offset']) + entry['size']]
        content = updates.get(path, old)
        entry['offset'], entry['size'] = str(offset), len(content)
        if path in updates:
            block = entry.get('integrity', {}).get('blockSize', 4194304)
            entry['integrity'] = {'algorithm':'SHA256', 'hash':digest(content), 'blockSize':block,
                                  'blocks':[digest(content[i:i+block]) for i in range(0,len(content),block)]}
        chunks.append(content)
        offset += len(content)
    raw = json.dumps(tree, ensure_ascii=False, separators=(',', ':')).encode()
    payload = struct.pack('<I', len(raw)) + raw
    payload += b'\0' * (-len(payload) % 4)
    header = struct.pack('<I', len(payload)) + payload
    return struct.pack('<II', 4, len(header)) + header + b''.join(chunks)

def build():
    src = APP / 'Contents/Resources/app.asar'
    data = src.read_bytes()
    if digest(data) != EXPECTED:
        original = BACKUP / 'Contents/Resources/app.asar'
        assert original.exists() and digest(original.read_bytes()) == EXPECTED, 'Unsupported version or changed app; refusing to patch.'
        data = original.read_bytes()
    old = contents(data)
    ko = {}
    for i in range(1,4):
        part = json.loads((ROOT / f'ko-part-{i}.json').read_text())
        source = json.loads((ROOT / f'source-part-{i}.json').read_text())
        assert part.keys() == source.keys(), f'Catalog {i} keys differ'
        assert not (ko.keys() & part.keys()), 'Duplicate catalog keys'
        for key, val in part.items():
            assert isinstance(val,str) and val.strip(), key
            assert sorted(re.findall(r'\{\d+\}', key)) == sorted(re.findall(r'\{\d+\}',val)), key
        ko.update(part)
    assert len(ko) == 1134
    (ROOT/'ko.json').write_text(json.dumps(ko,ensure_ascii=False,indent=2)+'\n')
    js, html = patch_renderer(old[JS].decode(), old[HTML].decode(), ko)
    updates = {JS:js.encode(), HTML:html.encode(), MAIN:patch_native(old[MAIN].decode()).encode()}
    out = ROOT/'build';out.mkdir(exist_ok=True)
    for path, val in updates.items():
        target = out/path;target.parent.mkdir(parents=True,exist_ok=True);target.write_bytes(val)
    patched = repack(data,updates)
    new = contents(patched)
    changed = sorted(p for p in old if old[p] != new[p])
    assert old.keys() == new.keys()
    assert changed == sorted(updates), changed
    (out/'app.asar').write_bytes(patched)
    manifest = {'appVersion':'2.1.13','patchVersion':'ko-1','originalSHA256':EXPECTED,
                'patchedSHA256':digest(patched),'asarHeaderSHA256':unpack(patched)[2],
                'changedFiles':changed,'unchangedPackedFiles':len(old)-len(changed),'catalogEntries':len(ko)}
    (out/'manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
    print(json.dumps(manifest,indent=2))

def install():
    assert_not_running()
    manifest = json.loads((ROOT/'build/manifest.json').read_text())
    patched = ROOT/'build/app.asar'
    assert digest(patched.read_bytes()) == manifest['patchedSHA256']
    current = APP/'Contents/Resources/app.asar'
    if digest(current.read_bytes()) == manifest['patchedSHA256']:
        print('Korean patch already installed.');return
    assert digest(current.read_bytes()) == EXPECTED, 'Installed app changed; refusing overwrite.'
    if not BACKUP.exists():
        BACKUP.parent.mkdir(parents=True,exist_ok=True)
        subprocess.run(['/usr/bin/ditto',str(APP),str(BACKUP)],check=True)
    assert digest((BACKUP/'Contents/Resources/app.asar').read_bytes()) == EXPECTED
    try:
        shutil.copy2(patched,current)
        plist = APP/'Contents/Info.plist'
        info = plistlib.loads(plist.read_bytes())
        info['ElectronAsarIntegrity']['Resources/app.asar']['hash'] = manifest['asarHeaderSHA256']
        plist.write_bytes(plistlib.dumps(info))
        subprocess.run(['/usr/bin/codesign','--force','--sign','-',
                        '--preserve-metadata=identifier,entitlements,flags,runtime',str(APP)],check=True)
        subprocess.run(['/usr/bin/codesign','--verify','--deep','--strict',str(APP)],check=True)
    except BaseException:
        restore()
        raise
    print('Installed. Original app backup: '+str(BACKUP))

def restore():
    assert_not_running()
    assert digest((BACKUP/'Contents/Resources/app.asar').read_bytes()) == EXPECTED
    manifest = json.loads((ROOT/'build/manifest.json').read_text())
    current = digest((APP/'Contents/Resources/app.asar').read_bytes())
    assert current in [EXPECTED,manifest['patchedSHA256']], 'App version changed; do not restore over an update.'
    # Only the patch-owned files and signature are restored; no user data is touched.
    for path in ['Contents/Resources/app.asar','Contents/Info.plist','Contents/_CodeSignature/CodeResources']:
        shutil.copy2(BACKUP/path,APP/path)
    shutil.copy2(BACKUP/'Contents/MacOS/Chat On Steroids',APP/'Contents/MacOS/Chat On Steroids')
    subprocess.run(['/usr/bin/codesign','--verify','--deep','--strict',str(APP)],check=True)
    print('Original application restored. User data unchanged.')

def assert_not_running():
    processes=subprocess.run(['/bin/ps','-axo','comm='],check=True,capture_output=True,text=True).stdout
    binary=str(APP/'Contents/MacOS/Chat On Steroids')
    assert not any(line.strip()==binary for line in processes.splitlines()), 'Quit Chat On Steroids before installing or restoring.'

if __name__ == '__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('command',choices=['build','install','restore'])
    args=parser.parse_args()
    {'build':build,'install':install,'restore':restore}[args.command]()
