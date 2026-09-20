#!/usr/bin/env python3
"""Local-only review viewer; serves the current game GLB without copying it."""
from http.server import ThreadingHTTPServer, SimpleHTTPRequestHandler
from pathlib import Path
from urllib.parse import urlsplit
import argparse, hashlib, json, shutil
ROOT = Path(__file__).resolve().parents[2]
VIEWER = Path(__file__).resolve().parent
MODEL = ROOT / 'godot-game/assets/3d/player/gravebound_player.glb'
class Handler(SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs): super().__init__(*args, directory=str(VIEWER), **kwargs)
    def do_GET(self):
        route = urlsplit(self.path).path
        if route == '/model-info.json':
            data=json.dumps({'name':'Gravebound Player', 'sha256':hashlib.sha256(MODEL.read_bytes()).hexdigest(), 'bytes':MODEL.stat().st_size, 'modified':MODEL.stat().st_mtime_ns}).encode()
            self.send_response(200); self.send_header('Content-Type','application/json'); self.send_header('Content-Length',str(len(data))); self.send_header('Cache-Control','no-store'); self.end_headers(); self.wfile.write(data)
        elif route == '/model.glb':
            self.send_response(200); self.send_header('Content-Type','model/gltf-binary'); self.send_header('Content-Length',str(MODEL.stat().st_size)); self.send_header('Cache-Control','no-store'); self.end_headers()
            with MODEL.open('rb') as stream: shutil.copyfileobj(stream,self.wfile)
        else:
            # Only viewer assets are exposed. Repository files stay outside root.
            requested=(VIEWER / route.lstrip('/')).resolve()
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
