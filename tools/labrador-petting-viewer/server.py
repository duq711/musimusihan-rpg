#!/usr/bin/env python3
"""Serve only the local Labrador preview and its licensed model, on loopback."""
from http.server import ThreadingHTTPServer, SimpleHTTPRequestHandler
from pathlib import Path
from urllib.parse import urlsplit, unquote
import argparse
import shutil
import json

ROOT = Path(__file__).resolve().parents[2]
VIEWER = Path(__file__).resolve().parent
EXPORT = ROOT / 'asset-staging/labrador-pet-20261005/export'
VENDOR = VIEWER / 'vendor'
CONFIG = VIEWER / 'locomotion-source.json'
LOCOMOTION_EXPORT = EXPORT
LOCOMOTION_MODEL = 'LabradorPet_Locomotion.glb'
LOCOMOTION_MANIFEST = 'locomotion-manifest.json'
if CONFIG.is_file():
    settings = json.loads(CONFIG.read_text())
    LOCOMOTION_EXPORT = (ROOT / settings['export_directory']).resolve()
    if not LOCOMOTION_EXPORT.is_relative_to(ROOT):
        raise ValueError('Locomotion assets must remain inside this project.')
    LOCOMOTION_MODEL = settings['model']
    LOCOMOTION_MANIFEST = settings['manifest']
    if any(Path(name).name != name for name in (LOCOMOTION_MODEL, LOCOMOTION_MANIFEST)):
        raise ValueError('Use asset filenames in the configured export directory.')

class Handler(SimpleHTTPRequestHandler):
    def do_GET(self):
        route = unquote(urlsplit(self.path).path)
        if route == '/model.glb':
            file = EXPORT / 'LabradorPet_Petting.glb'
        elif route == '/locomotion.glb':
            file = LOCOMOTION_EXPORT / LOCOMOTION_MODEL
        elif route == '/locomotion-manifest.json':
            file = LOCOMOTION_EXPORT / LOCOMOTION_MANIFEST
        elif route.startswith('/vendor/'):
            file = (VENDOR / route.removeprefix('/vendor/')).resolve()
            if not file.is_relative_to(VENDOR):
                self.send_error(403); return
        elif route in ('/', '/index.html', '/petting.js'):
            file = VIEWER / ('index.html' if route == '/' else route[1:])
        elif route in ('/locomotion', '/locomotion/', '/locomotion.html', '/locomotion.js'):
            file = VIEWER / ('locomotion.js' if route == '/locomotion.js' else 'locomotion.html')
        else:
            self.send_error(404); return
        if not file.is_file():
            self.send_error(404); return
        self.send_response(200)
        self.send_header('Content-Type', {'.js': 'text/javascript', '.html': 'text/html; charset=utf-8', '.glb': 'model/gltf-binary', '.json': 'application/json; charset=utf-8'}.get(file.suffix, 'application/octet-stream'))
        self.send_header('Content-Length', str(file.stat().st_size))
        self.send_header('Cache-Control', 'no-store')
        self.send_header('X-Content-Type-Options', 'nosniff')
        self.end_headers()
        with file.open('rb') as stream:
            shutil.copyfileobj(stream, self.wfile)

if __name__ == '__main__':
    parser = argparse.ArgumentParser(); parser.add_argument('--port', type=int, default=8773)
    args = parser.parse_args()
    ThreadingHTTPServer(('127.0.0.1', args.port), Handler).serve_forever()
