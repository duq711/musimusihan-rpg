"""Temporary authenticated LAN transfer for this one Windows authoring delivery.

Serves only the explicit input ZIP; accepts a new, hash-checked delivery ZIP.
No directory browsing, arbitrary paths, shell execution or archive extraction.
"""
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
import hashlib
import hmac
import json
import os
import secrets
import threading
import time
import zipfile

ROOT = Path(__file__).resolve().parent
TOKEN = secrets.token_urlsafe(32)
INCOMING = ROOT / "transfer_incoming"
INCOMING.mkdir(exist_ok=True)
INPUT = ROOT / "transfer_input.zip"
with zipfile.ZipFile(INPUT, "w", zipfile.ZIP_DEFLATED) as bundle:
    for name in ("INTEGRATION_PLAN.md", "AUTHORING_BRIEF.md", "delivery_requirements.json", "motion_manifest.schema.json", "validate_delivery.py"):
        bundle.write(ROOT / name, name)
    for name in ("reference_notes.md", "sU7jk2OQlgc.mp4", "overhead_dense_01.jpg", "left_right_dense_01.jpg", "right_left_dense_01.jpg", "jump_14_17_01.jpg", "jump_14_17_02.jpg"):
        bundle.write(ROOT / "reference" / name, name)


class Transfer(BaseHTTPRequestHandler):
    def log_message(self, format, *args):
        pass  # Avoid recording authentication headers or request contents.

    def authorized(self):
        return hmac.compare_digest(self.headers.get("Authorization", ""), "Bearer " + TOKEN)

    def reply(self, code, payload):
        data = json.dumps(payload).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def do_GET(self):
        if not self.authorized():
            return self.reply(403, {"error": "forbidden"})
        if self.path == "/status":
            return self.reply(200, {"task": ROOT.name, "input_sha256": hashlib.file_digest(INPUT.open("rb"), "sha256").hexdigest(), "received": [p.name for p in INCOMING.glob("delivery_*.zip")]})
        if self.path != "/input.zip":
            return self.reply(404, {"error": "unknown resource"})
        self.send_response(200)
        self.send_header("Content-Type", "application/zip")
        self.send_header("Content-Length", str(INPUT.stat().st_size))
        self.end_headers()
        with INPUT.open("rb") as source:
            while chunk := source.read(1024 * 1024):
                self.wfile.write(chunk)
        print(json.dumps({"event": "input_delivered", "peer": self.client_address[0]}), flush=True)

    def do_POST(self):
        if not self.authorized():
            return self.reply(403, {"error": "forbidden"})
        if self.path != "/delivery.zip":
            return self.reply(404, {"error": "unknown resource"})
        try:
            length = int(self.headers.get("Content-Length", "0"))
        except ValueError:
            length = 0
        expected = self.headers.get("X-Content-SHA256", "").lower()
        if not 0 < length <= 512 * 1024 * 1024 or len(expected) != 64 or any(c not in "0123456789abcdef" for c in expected):
            return self.reply(400, {"error": "size and SHA256 required"})
        self.connection.settimeout(120)
        target = INCOMING / ("delivery_" + time.strftime("%Y%m%d_%H%M%S") + "_" + secrets.token_hex(3) + ".zip")
        partial = target.with_suffix(".partial")
        digest = hashlib.sha256()
        try:
            with partial.open("xb") as output:
                remaining = length
                while remaining:
                    chunk = self.rfile.read(min(1024 * 1024, remaining))
                    if not chunk:
                        raise ValueError("incomplete upload")
                    output.write(chunk)
                    digest.update(chunk)
                    remaining -= len(chunk)
            if not hmac.compare_digest(digest.hexdigest(), expected):
                raise ValueError("SHA256 mismatch")
            if not zipfile.is_zipfile(partial):
                raise ValueError("ZIP required")
            partial.rename(target)
        except (OSError, ValueError) as error:
            partial.unlink(missing_ok=True)
            return self.reply(400, {"error": str(error)})
        result = {"received": target.name, "sha256": digest.hexdigest(), "bytes": length}
        print(json.dumps({"event": "delivery_received", **result}), flush=True)
        self.reply(201, result)


if __name__ == "__main__":
    server = ThreadingHTTPServer(("192.168.45.224", 0), Transfer)
    server.daemon_threads = True
    info = {"url": "http://%s:%s" % server.server_address, "bearer_token": TOKEN, "ttl_seconds": 1800, "input_sha256": hashlib.file_digest(INPUT.open("rb"), "sha256").hexdigest()}
    info_path = ROOT / "transfer_connection.json"
    descriptor = os.open(info_path, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(descriptor, "w") as output:
        json.dump(info, output, indent=2)
    print(json.dumps(info), flush=True)
    expiry = threading.Timer(1800, server.shutdown)
    expiry.daemon = True
    expiry.start()
    try:
        server.serve_forever()
    finally:
        expiry.cancel()
        server.server_close()
        info_path.unlink(missing_ok=True)
