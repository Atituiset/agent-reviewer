#!/usr/bin/env bash
# 按变更文件路径召回 active 记忆（MVP §2.5）。纯 GLOB 匹配、无向量无语义（D7 宁可漏召）。
# 用法: memory-recall.sh <path...>   输出 "- [id] content" 行
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PY="$ROOT/.venv/bin/python"; [ -x "$PY" ] || PY="${PYTHON:-python3}"
exec "$PY" "$ROOT/scripts/_lib.py" memory-recall "$@"
