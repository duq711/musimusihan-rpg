#!/bin/sh
# Run Git for this project with its local tools, when available.
# 프로젝트 전용 도구가 있으면 사용하여 이 저장소에서 Git을 실행합니다.
set -eu

project_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
if [ -d "$project_root/.local-tools/bin" ]; then
  PATH="$project_root/.local-tools/bin:$PATH"
  export PATH
fi
if [ -d "$project_root/.local-tools/gh-config" ]; then
  GH_CONFIG_DIR="$project_root/.local-tools/gh-config"
  export GH_CONFIG_DIR
fi
exec git -C "$project_root" "$@"
