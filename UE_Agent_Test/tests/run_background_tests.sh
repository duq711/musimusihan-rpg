#!/bin/bash
set -euo pipefail
task_dir="$(cd "$(dirname "$0")/.." && pwd)"
nice -n 10 /usr/bin/python3 "$task_dir/tests/launch_test.py" headless
