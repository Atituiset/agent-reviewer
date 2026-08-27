#!/usr/bin/env bash
# 人工标注回传（飞轮）：memory-label.sh <sarif-path> <findingIndex> <tp|fp> [reason]
# TP → incident_pattern 提案进 quarantine；FP → scenario_trust 累加，30 天 ≥3 次触发场景改进提案。
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PY="$ROOT/.venv/bin/python"; [ -x "$PY" ] || PY="${PYTHON:-python3}"
exec "$PY" "$ROOT/scripts/_lib.py" memory-label "$@"
