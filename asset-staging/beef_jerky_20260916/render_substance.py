"""Bake the supplied SBSAR using Adobe's local Integration Tools protocol."""
import json, os, socket, threading, time
from http.server import HTTPServer, BaseHTTPRequestHandler
from pathlib import Path

ROOT = Path(__file__).resolve().parent
OUT = ROOT / 'output' / 'textures'
OUT.mkdir(parents=True, exist_ok=True)
done = threading.Event()
class Handler(BaseHTTPRequestHandler):
    def do_POST(self):
        raw = self.rfile.read(int(self.headers['Content-Length']))
        (ROOT/'source/render_response.json').write_bytes(raw)
        self.send_response(200); self.end_headers()
        print('CALLBACK',raw.decode()[:1500],flush=True)
        done.set()
    def log_message(self,*args): pass
callback = HTTPServer(('127.0.0.1',0),Handler)
threading.Thread(target=callback.serve_forever,daemon=True).start()
app = dict(pid=os.getpid(), host='127.0.0.1', port=callback.server_port, key='BLD', name='Blender')

def request(op, data, endpoint='m7ef-7gYN-zTGu-4D3w', mode=1):
    msg = dict(type=mode, endpoint=endpoint, operation=op, data=data, timer=time.time())
    with socket.create_connection(('127.0.0.1', 42657)) as s:
        s.settimeout(240)
        s.sendall(json.dumps(msg).encode())
        raw = b''
        while True:
            part = s.recv(65536)
            if not part: break
            raw += part
            try: return json.loads(raw)
            except json.JSONDecodeError: pass
    return json.loads(raw)

print('REGISTER', request(10, {'app':app}, 'Lwnd-CHcT-uJlw-YSw3'), flush=True)
r = request(20, {'app':app, 'substance':dict(name='BeefJerky', file='/Users/duq711gmail.com/Downloads/beef-jerky.sbsar', **{'$outputsize':[11,11], 'normal_format':1})})
(ROOT/'source/load_response.json').write_text(json.dumps(r,indent=2))
print('LOAD', r['message'], flush=True)
assert r['code']==0,r
outputs = [dict(identifier=o['identifier'],enabled=True,format='PNG',bitdepth='16' if o['identifier']=='height' else '8') for o in r['data']['graphs'][0]['outputs'] if o['type']=='image']
print('RENDER',request(25,dict(app=app,substance=dict(uuid=r['data']['uuid'],graph_idx=0),render=dict(path=str(OUT),outputs=outputs)),mode=2),flush=True)
assert done.wait(240),'render callback timed out'
print('OUTPUTS',[p.name for p in OUT.rglob('*')],flush=True)
print('DISCONNECT',request(11,{'app':app},'Lwnd-CHcT-uJlw-YSw3'),flush=True)
callback.shutdown()
