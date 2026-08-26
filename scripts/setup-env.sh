#!/usr/bin/env bash
# 一次性环境初始化：创建 python 虚拟环境（仅 stdlib，无第三方依赖）
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if [ -x "$ROOT/.venv/bin/python" ]; then
  echo "[setup-env] .venv 已存在，跳过"
else
  python3 -m venv "$ROOT/.venv"
  echo "[setup-env] 已创建 $ROOT/.venv"
fi
"$ROOT/.venv/bin/python" -c 'import json, sqlite3, sys; print("[setup-env] stdlib ok:", sys.version.split()[0])'
