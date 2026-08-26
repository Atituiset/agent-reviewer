#!/usr/bin/env bash
# 评审结论 → quarantine（MVP §2.5）。stdin: {"content":"…file:line…","modules":["glob"],"bound_paths":[],"evidence":{...}}
# 无 file:line 证据拒收（E_NO_EVIDENCE）。用法: cat finding.json | memory-propose.sh
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PY="$ROOT/.venv/bin/python"; [ -x "$PY" ] || PY="${PYTHON:-python3}"
exec "$PY" "$ROOT/scripts/_lib.py" memory-propose
