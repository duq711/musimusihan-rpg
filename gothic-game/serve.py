#!/usr/bin/env python3
"""Offline, loopback-only game server. Never exposes the surrounding repository."""
import argparse
import http.server
from pathlib import Path
from urllib.parse import unquote, urlsplit

ROOT = Path(__file__).resolve().parent

class Handler(http.server.SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=str(ROOT), **kwargs)

    def allowed(self):
        try:
            path = (ROOT / unquote(urlsplit(self.path).path).lstrip('/')).resolve()
            return path.is_relative_to(ROOT) if hasattr(path, 'is_relative_to') else ROOT == path or ROOT in path.parents
        except (ValueError, OSError):
            return False

    def do_GET(self):
        if not self.allowed():
            self.send_error(404)
            return
        super().do_GET()

    def do_HEAD(self):
        if not self.allowed():
            self.send_error(404)
            return
        super().do_HEAD()

    def end_headers(self):
        self.send_header('Cache-Control', 'no-cache')
        super().end_headers()

    def log_request(self, code='-', size='-'):
        if str(code).startswith(('4', '5')):
            super().log_request(code, size)

if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--port', type=int, default=8790)
    args = parser.parse_args()
    http.server.ThreadingHTTPServer.request_queue_size = 64
    print(f'잔향의 성소 / Sanctuary of Echoes: http://127.0.0.1:{args.port}/', flush=True)
    with http.server.ThreadingHTTPServer(('127.0.0.1', args.port), Handler) as server:
        try:
            server.serve_forever()
        except KeyboardInterrupt:
            pass
