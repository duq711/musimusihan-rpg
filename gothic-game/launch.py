#!/usr/bin/env python3
"""Launch the independent game, reusing its server without replacing other apps."""
import errno
import http.server
import json
import threading
import urllib.error
import urllib.request
import webbrowser
from serve import Handler

GAME_ID = 'musimusihan-gothic-origin-20261020'

def find_server():
    for port in range(8790, 8800):
        url = f'http://127.0.0.1:{port}/'
        try:
            server = http.server.ThreadingHTTPServer(('127.0.0.1', port), Handler)
            return url, server
        except OSError as error:
            if error.errno != errno.EADDRINUSE:
                raise
            try:
                with urllib.request.urlopen(url + 'identity.json', timeout=1) as response:
                    if json.load(response).get('id') == GAME_ID:
                        return url, None
            except (OSError, ValueError, urllib.error.URLError):
                continue
    raise RuntimeError('8790–8799 포트가 사용 중입니다. / Ports 8790–8799 are busy.')

if __name__ == '__main__':
    url, server = find_server()
    print(f'잔향의 성소 / Sanctuary of Echoes: {url}', flush=True)
    if server:
        threading.Timer(.4, lambda: webbrowser.open(url)).start()
        print('이 창을 닫으면 게임 서버가 종료됩니다. / Keep this window open while playing.')
        try:
            server.serve_forever()
        except KeyboardInterrupt:
            pass
        finally:
            server.server_close()
    else:
        webbrowser.open(url)
