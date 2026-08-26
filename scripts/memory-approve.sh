#!/usr/bin/env bash
# MDE 人工审核（MVP §2.5）。用法: memory-approve.sh <id> [--reject <reason>]
# 通过 → active；驳回 → archived 并留 reason 于审核记录。
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PY="$ROOT/.venv/bin/python"; [ -x "$PY" ] || PY="${PYTHON:-python3}"
[ $# -lt 1 ] && { echo "usage: $0 <id> [--reject <reason>]" >&2; exit 2; }
exec "$PY" "$ROOT/scripts/_lib.py" memory-approve "$@"
