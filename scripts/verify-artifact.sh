#!/usr/bin/env bash
# 校验评审工件（MVP §2.1 五规则）。用法: verify-artifact.sh [--session <id>]
# 退出码: 0=通过 2=拒绝(输出 DENY 行) 3=内部错误
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PY="$ROOT/.venv/bin/python"; [ -x "$PY" ] || PY="${PYTHON:-python3}"
exec "$PY" "$ROOT/scripts/_lib.py" verify-artifact "$@"
