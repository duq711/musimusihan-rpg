#!/usr/bin/env python3
"""Local-only Roger/Medival review viewer with explicit asset routes."""
from http.server import ThreadingHTTPServer, SimpleHTTPRequestHandler
from pathlib import Path
from urllib.parse import unquote, urlsplit
import argparse, hashlib, json, shutil
ROOT = Path(__file__).resolve().parents[2]
VIEWER = Path(__file__).resolve().parent
ROGER = ROOT / 'godot-game/assets/licensed/roger/roger_medival.glb'
OUTFIT = ROOT / 'godot-game/assets/3d/player/medival_outfit.glb'
COMPARISON = ROOT / 'asset-staging/player_multiview_proportions_20260922'
CAPTURES = ROOT / 'godot-game/artifacts/visual_qa/player_appearance/multiview_proportions_20260922'
REVIEW_FILES = {'/proportions/compare.html': COMPARISON / 'compare.html', '/proportions/comparison_report.json': COMPARISON / 'comparison_report.json'}
for view in ('front', 'back', 'right', 'left'):
    REVIEW_FILES[f'/proportions/reference_images/{view}.png'] = COMPARISON / f'reference_images/{view}.png'
    for suffix in ('', '_clay'):
        name = f'calibrated_{view}{suffix}.png'
        REVIEW_FILES[f'/godot-game/artifacts/visual_qa/player_appearance/multiview_proportions_20260922/{name}'] = CAPTURES / name
AXILLA = ROOT / 'asset-staging/player_axilla_refinement_20260922'
REVIEW_FILES['/axilla/compare.html'] = AXILLA / 'compare.html'
for revision, folder in [('before', 'axilla_baseline_20260922'), ('after', 'axilla_refinement_final_20260922')]:
    for view in ('front', 'oblique', 'rear'):
        for suffix in ('', '_clay'):
            name = f'axilla_{view}{suffix}.png'
            REVIEW_FILES[f'/axilla/{revision}/{name}'] = ROOT / 'godot-game/artifacts/visual_qa/player_appearance' / folder / name

def asset_info(file, name, kind, route, origin):
    info = {'available': file.is_file(), 'name': name, 'kind': kind,
            'url': route, 'origin': origin}
    if info['available']:
        info.update(sha256=hashlib.sha256(file.read_bytes()).hexdigest(),
                    bytes=file.stat().st_size, modified=file.stat().st_mtime_ns)
    return info

def outfit_info():
    return asset_info(OUTFIT, 'Medival outfit', 'outfit-only', '/outfit.glb',
                      'godot-game/assets/3d/player/medival_outfit.glb')

def model_info():
    roger = asset_info(ROGER, 'Roger · Medival', 'roger-medival', '/roger-medival.glb',
                       'godot-game/assets/licensed/roger/roger_medival.glb')
    outfit = outfit_info()
    selected = roger if roger['available'] else outfit
    return {**selected, 'sources': {'roger': roger, 'outfit': outfit},
            'preview': 'fitted-static' if roger['available'] else 'source-static'}

class Handler(SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs): super().__init__(*args, directory=str(VIEWER), **kwargs)
    def send_json(self, info):
        data = json.dumps(info, ensure_ascii=False).encode()
        self.send_response(200)
        self.send_header('Content-Type', 'application/json; charset=utf-8')
        self.send_header('Content-Length', str(len(data)))
        self.send_header('Cache-Control', 'no-store')
        self.end_headers()
        self.wfile.write(data)
    def send_model(self, file):
        if not file.is_file(): self.send_error(404); return
        self.send_response(200)
        self.send_header('Content-Type', 'model/gltf-binary')
        self.send_header('Content-Length', str(file.stat().st_size))
        self.send_header('Cache-Control', 'no-store')
        self.end_headers()
        with file.open('rb') as stream: shutil.copyfileobj(stream, self.wfile)
    def do_GET(self):
        route = urlsplit(self.path).path
        if route in REVIEW_FILES:
            file = REVIEW_FILES[route]
            if not file.is_file(): self.send_error(404); return
            self.send_response(200)
            self.send_header('Content-Type', {'.html': 'text/html; charset=utf-8', '.json': 'application/json', '.png': 'image/png'}[file.suffix])
            self.send_header('Content-Length', str(file.stat().st_size))
            self.send_header('Cache-Control', 'no-store'); self.end_headers()
            with file.open('rb') as stream: shutil.copyfileobj(stream, self.wfile)
        elif route == '/outfit-info.json':
            self.send_json(outfit_info())
        elif route == '/model-info.json':
            self.send_json(model_info())
        elif route == '/roger-medival.glb':
            self.send_model(ROGER)
        elif route == '/model.glb':
            self.send_model(ROGER if ROGER.is_file() else OUTFIT)
        elif route == '/outfit.glb':
            self.send_model(OUTFIT)
        else:
            # Only viewer assets are exposed. Repository files stay outside root.
            requested=(VIEWER / unquote(route).lstrip('/')).resolve()
            if not requested.is_relative_to(VIEWER): self.send_error(403); return
            super().do_GET()
    def end_headers(self):
        self.send_header('X-Content-Type-Options','nosniff'); super().end_headers()
if __name__ == '__main__':
    parser=argparse.ArgumentParser(); parser.add_argument('--port',type=int,default=8768); args=parser.parse_args()
    server=ThreadingHTTPServer(('127.0.0.1',args.port),Handler)
    print(f'Player 3D viewer: http://127.0.0.1:{server.server_port}',flush=True)
    try: server.serve_forever()
    except KeyboardInterrupt: pass
    finally: server.server_close()
