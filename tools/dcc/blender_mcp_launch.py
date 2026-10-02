#!/usr/bin/env python3
"""Reuse a live Blender bridge, or start a quiet one, then serve official MCP."""

import argparse
import fcntl
import json
import os
from pathlib import Path
import socket
import subprocess
import sys
import time


PROJECT = Path(__file__).resolve().parents[2]
STATE = PROJECT / ".local-tools" / "dcc"
BLENDER = Path("/Applications/Blender.app/Contents/MacOS/Blender")
SERVER = Path.home() / ".local/share/blender-mcp-official/runtime-v1/bin/blender-mcp"
HOST = "127.0.0.1"
PORT = 9876
STARTUP_TIMEOUT = 25


def bridge_info():
    request = {
        "type": "execute",
        "strict_json": True,
        "code": (
            "import bpy\n"
            "result = {'version': bpy.app.version_string, "
            "'background': bpy.app.background, 'file': bpy.data.filepath}\n"
        ),
    }
    with socket.create_connection((HOST, PORT), timeout=3) as connection:
        connection.sendall(json.dumps(request).encode() + b"\0")
        response = bytearray()
        while b"\0" not in response:
            chunk = connection.recv(4096)
            if not chunk or len(response) + len(chunk) > 65536:
                raise RuntimeError("Blender bridge returned an incomplete response")
            response.extend(chunk)
    parsed = json.loads(response.split(b"\0", 1)[0])
    if parsed.get("status") != "ok":
        raise RuntimeError("Blender bridge did not return a successful status")
    return parsed["result"]


def ensure_bridge():
    STATE.mkdir(parents=True, exist_ok=True)
    with (STATE / "blender-launch.lock").open("a") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        try:
            return bridge_info()
        except ConnectionRefusedError:
            pass
        log_path = STATE / "blender-bridge.log"
        with log_path.open("a") as log:
            process = subprocess.Popen(
                [str(BLENDER), "--background", "--disable-autoexec", "--online-mode",
                 "--command", "blender_mcp", "--host", HOST, "--port", str(PORT)],
                stdin=subprocess.DEVNULL, stdout=log, stderr=subprocess.STDOUT,
                start_new_session=True,
            )
        pid_path = STATE / "blender-bridge.pid"
        try:
            pid_path.write_text(str(process.pid) + "\n")
            deadline = time.monotonic() + STARTUP_TIMEOUT
            while time.monotonic() < deadline:
                if process.poll() is not None:
                    raise RuntimeError("Blender bridge exited; inspect " + str(log_path))
                try:
                    return bridge_info()
                except ConnectionRefusedError:
                    time.sleep(0.25)
            raise RuntimeError("Blender bridge startup timed out; inspect " + str(log_path))
        except BaseException:
            if process.poll() is None:
                process.terminate()
                try:
                    process.wait(timeout=3)
                except subprocess.TimeoutExpired:
                    process.kill()
                    process.wait(timeout=3)
            pid_path.unlink(missing_ok=True)
            raise


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--ensure-only", action="store_true", help="Start/check the bridge and print its status")
    args = parser.parse_args()
    if not BLENDER.is_file() or not SERVER.is_file():
        raise RuntimeError("Install Blender and the official MCP environment before launching")
    info = ensure_bridge()
    if args.ensure_only:
        print(json.dumps(info, ensure_ascii=False))
        return
    os.environ["BLENDER_MCP_HOST"] = HOST
    os.environ["BLENDER_MCP_PORT"] = str(PORT)
    os.environ["BLENDER_PATH"] = str(BLENDER)
    os.execv(str(SERVER), [str(SERVER)])


if __name__ == "__main__":
    try:
        main()
    except (OSError, RuntimeError, ValueError) as error:
        print("Blender MCP: " + str(error), file=sys.stderr)
        sys.exit(1)
