#!/bin/bash
set -euo pipefail
task_dir="$(cd "$(dirname "$0")" && pwd)"
/usr/bin/python3 "$task_dir/tests/launch_test.py" editor
