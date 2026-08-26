#!/usr/bin/env bash
# 打包评审输入（MVP §2.3）：diff.patch + context.md（变更清单/场景索引/记忆召回/spec 段落）+ scenarios.json
# 用法: review-package.sh [--spec <openspec/changes/<name>>] [--out <dir>]   输出: 包目录路径
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PY="$ROOT/.venv/bin/python"; [ -x "$PY" ] || PY="${PYTHON:-python3}"
exec "$PY" "$ROOT/scripts/_lib.py" package "$@"
