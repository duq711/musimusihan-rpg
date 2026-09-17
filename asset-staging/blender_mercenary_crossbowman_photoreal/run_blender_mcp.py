#!/usr/bin/env python3
"""Run a Blender Python file through the connected official Blender MCP server."""

from __future__ import annotations

import argparse
import json
import os
import sys
from pathlib import Path


MCP_PACKAGE = Path("/Users/duq711gmail.com/.local/share/blender-mcp-official")
sys.path.insert(0, str(MCP_PACKAGE / "tests"))


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("script", type=Path)
    parser.add_argument("--timeout-scale", type=float, default=30.0)
    args = parser.parse_args()

    script = args.script.expanduser().resolve()
    if not script.is_file():
        parser.error(f"script not found: {script}")

    command = [
        "/Users/duq711gmail.com/.local/bin/uv",
        "--directory",
        str(MCP_PACKAGE / "mcp"),
        "run",
        "--python",
        "3.11",
        "--with",
        "mcp[cli]==1.29.1",
        "blender-mcp",
    ]
    env = os.environ.copy()
    env["GLOBAL_TIMEOUT_SCALE"] = str(args.timeout_scale)
    os.environ["GLOBAL_TIMEOUT_SCALE"] = str(args.timeout_scale)
    from mcp_client import MCPClient
    code = (
        "_p = " + repr(str(script)) + "\n"
        "exec(compile(open(_p, encoding='utf-8').read(), _p, 'exec'), globals())\n"
        "print('MCP_SCRIPT_COMPLETED:' + _p)"
    )

    with MCPClient(command, env=env) as client:
        client.initialize()
        result = client.call_tool("execute_blender_code", {"code": code})

    print(json.dumps(result, ensure_ascii=False, indent=2))
    structured = result.get("structuredContent", {})
    if result.get("isError") or structured.get("status") == "error":
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
