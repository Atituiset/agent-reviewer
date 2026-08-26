#!/usr/bin/env bash
# PreToolUse 门禁 hook（matcher: Bash），只拦截含 "git commit" 的命令（MVP §2.2）。
# stdin JSON: {"session_id": "...", "tool_input": {"command": "..."}}
# 放行条件（任一）: diff<20 行 | 纯文档 | .review/DISABLED 存在 | 工件校验通过
# fail-open: 本脚本内部任何异常 → exit 0 放行并留痕 stderr
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PY="$ROOT/.venv/bin/python"; [ -x "$PY" ] || PY="${PYTHON:-python3}"

OUT="$("$PY" "$ROOT/scripts/_lib.py" hook-gate 2>&1)"
RC=$?
case $RC in
  0) exit 0 ;;
  2) echo "$OUT" >&2; exit 2 ;;          # 拒绝：stderr 回带给模型
  *) echo "[review-gate] 内部异常，按 fail-open 放行: $OUT" >&2; exit 0 ;;
esac
