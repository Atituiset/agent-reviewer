#!/usr/bin/env bash
# MVP 验收自测（MVP 设计 §5）：在 mktemp 沙箱仓库中运行，不触碰本仓工作区。
# 通过标准：全部 ✓。第 10 条（回放基线）待团队 cases 迁移后由 scenario-replay 承接，此处不含。
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJ="$(cd "$HERE/.." && pwd)"
PY="$PROJ/.venv/bin/python"; [ -x "$PY" ] || PY="${PYTHON:-python3}"

SUT="$(mktemp -d)/repo"; mkdir -p "$SUT"
cp -r "$PROJ/rules" "$PROJ/scripts" "$PROJ/hooks" "$SUT/"
cd "$SUT" || exit 9
git init -qb main && git config user.email t@t && git config user.name t
echo base > base.txt && git add -A && git commit -qm init
export MVP_ROOT="$SUT"

pass=0; fail=0; OUT=""
ok() { echo "  ✓ $1"; pass=$((pass+1)); }
no() { echo "  ✗ $1"; fail=$((fail+1)); [ -n "${OUT:-}" ] && printf '    ↳ 实际输出: %.300s\n' "$OUT"; }
reset_tree() { git reset -q --hard HEAD; git clean -qfd -e .review -e '.review/*'; }
gate() { OUT=$(printf '%s' "$1" | bash hooks/pre-commit-gate.sh 2>&1); return $?; }

# 写工件: write_artifact <session|-> <python覆盖字段JSON>
write_artifact() {
  local sid=$1 over=$2 path
  local h; h=$(git diff HEAD | sha256sum | cut -d' ' -f1)
  if [ "$sid" = "-" ]; then path=".review/last-review.json"; mkdir -p .review; else
    path=".git/review-gate/$sid.json"; mkdir -p .git/review-gate; fi
  MVP_ROOT=$SUT "$PY" - "$path" "$h" "$over" <<'PYEOF'
import json,sys,pathlib
from datetime import datetime,timezone
path,h,over=sys.argv[1],sys.argv[2],json.loads(sys.argv[3])
a={"diff_hash":h,"verdict":"CLEAN","escalated":False,"reviewer":"selftest",
   "spec_ref":"none","scenarios_scanned":["default"],"findings":[],
   "reviewed_at":datetime.now(timezone.utc).isoformat()}
a.update(over)
p=pathlib.Path(path); p.parent.mkdir(parents=True,exist_ok=True)
p.write_text(json.dumps(a,ensure_ascii=False))
PYEOF
}

stage_big_c() { mkdir -p src; awk 'BEGIN{for(i=0;i<30;i++)print "int pad;"}' > src/x.c; git add src/x.c; }

echo "— 门禁拦截与豁免 —"
reset_tree; stage_big_c
gate '{"session_id":"t1","tool_input":{"command":"git commit -m x"}}'; RC=$?
{ [ "$RC" = 2 ] && grep -q E_NO_ARTIFACT <<<"$OUT"; } && ok "① >20 行无工件被拦截(E_NO_ARTIFACT)" || no "① 拦截失效 rc=$RC"

reset_tree; echo "small" >> small.txt && git add small.txt
gate '{"session_id":"t2","tool_input":{"command":"git commit -m x"}}' >/dev/null; [ $? = 0 ] && ok "② <20 行豁免放行" || no "② <20 行未豁免"

reset_tree; mkdir -p docs; awk 'BEGIN{for(i=0;i<30;i++)print "# doc"}' > docs/a.md; git add docs/a.md
gate '{"session_id":"t3","tool_input":{"command":"git commit -m x"}}' >/dev/null; [ $? = 0 ] && ok "③ 纯文档豁免放行" || no "③ 文档未豁免"

mkdir -p .review
reset_tree && touch .review/DISABLED; stage_big_c
gate '{"session_id":"t4","tool_input":{"command":"git commit -m x"}}' >/dev/null; RC=$?; rm -f .review/DISABLED
[ $RC = 0 ] && ok "④ kill-switch 放行" || no "④ kill-switch 未生效 rc=$RC"

echo "— 工件五规则 —"
reset_tree; stage_big_c; write_artifact s5 '{}'
gate '{"session_id":"s5","tool_input":{"command":"git commit -m x"}}' >/dev/null; [ $? = 0 ] && ok "⑤ CLEAN 工件放行" || no "⑤ 合法 CLEAN 未放行"

echo "// more" >> src/x.c && git add src/x.c
gate '{"session_id":"s5","tool_input":{"command":"git commit -m x"}}'; RC=$?
{ [ "$RC" = 2 ] && grep -q E_HASH_MISMATCH <<<"$OUT"; } && ok "⑥ hash 绑定：评审后再改动即拦截" || no "⑥ hash 绑定失效 rc=$RC"

reset_tree; stage_big_c; echo extra >> base.txt   # 已跟踪文件改动未 stage = 真部分暂存
gate '{"session_id":"t7","tool_input":{"command":"git commit -m x"}}'
grep -q E_PARTIAL_STAGE <<<"$OUT" && ok "⑦ 部分 stage 被拒并提示完整暂存" || no "⑦ E_PARTIAL_STAGE 缺失"

reset_tree; stage_big_c
write_artifact s8 '{"verdict":"ESCALATED","escalated":true,"findings":[{"file":"src/x.c","line":1,"severity":"important","scenario":"none","type":"none","summary":"残留","resolved":false,"ruling":null}]}'
gate '{"session_id":"s8","tool_input":{"command":"git commit -m x"}}' >/dev/null; [ $? = 2 ] && ok "⑧a ESCALATED 缺 ruling 被拒" || no "⑧a 缺 ruling 未拒"
write_artifact s8 '{"verdict":"ESCALATED","escalated":true,"findings":[{"file":"src/x.c","line":1,"severity":"important","scenario":"none","type":"none","summary":"残留","resolved":false,"ruling":"MDE 接受"}]}'
gate '{"session_id":"s8","tool_input":{"command":"git commit -m x"}}' >/dev/null; [ $? = 0 ] && ok "⑧b ESCALATED 带 ruling 放行留痕" || no "⑧b 合法 ESCALATED 未放行"

reset_tree; stage_big_c
write_artifact s9 '{"verdict":"ISSUES_FOUND","findings":[{"file":"src/x.c","line":1,"severity":"minor","scenario":"cwe-999999","type":"none","summary":"幻觉场景","resolved":true,"ruling":null}]}'
gate '{"session_id":"s9","tool_input":{"command":"git commit -m x"}}'
grep -q E_UNKNOWN_SCENARIO <<<"$OUT" && ok "⑨ 幻觉场景名被拒(E_UNKNOWN_SCENARIO)" || no "⑨ 场景存在性校验缺失"

echo "— 会话隔离与直接校验 —"
reset_tree; stage_big_c; write_artifact isoA '{}'; write_artifact isoB '{"diff_hash":"deadbeef"}'
write_artifact '-' '{"diff_hash":"fallback-bad"}'
gate '{"session_id":"isoA","tool_input":{"command":"git commit -m x"}}' >/dev/null; RA=$?
gate '{"session_id":"isoB","tool_input":{"command":"git commit -m x"}}' >/dev/null; RB=$?
gate '{"session_id":"","tool_input":{"command":"git commit -m x"}}' >/dev/null; RF=$?
{ [ $RA = 0 ] && [ $RB = 2 ] && [ $RF = 2 ]; } && ok "⑩ 双会话互不覆盖；无会话走 fallback" || no "⑩ 隔离失效 A=$RA B=$RB F=$RF"
bash scripts/verify-artifact.sh --session isoA >/dev/null 2>&1; [ $? = 0 ] && ok "⑪ verify-artifact 直调通过" || no "⑪ 直调失败"

echo "— memoryd 与打包路由 —"
reset_tree
echo '{"content":"模式：src/m.c:10 free 后未置空","modules":["src/**"],"bound_paths":["src/m.c"],"evidence":{"commit_sha":"abc"}}' | bash scripts/memory-propose.sh >/dev/null
./scripts/memory-recall.sh src/m.c 2>/dev/null | grep -q . && no "⑫ quarantine 未经审核即可召回" || ok "⑫ quarantine 不出现在召回"
ID=$(MVP_ROOT=$SUT "$PY" -c "import os,sys;sys.path.insert(0,'scripts');import _lib as l;print(l.db().execute('select id from memories limit 1').fetchone()[0])")
bash scripts/memory-approve.sh "$ID" >/dev/null && ./scripts/memory-recall.sh src/m.c | grep -q "free 后未置空" && ok "⑬ approve 后按模块 GLOB 召回" || no "⑬ 召回链路断裂"
echo '{"content":"无证据"}' | bash scripts/memory-propose.sh >/dev/null 2>&1; [ $? = 2 ] && ok "⑭ 无 file:line 提案被拒收" || no "⑭ 证据红线失效"

reset_tree; stage_big_c
bash scripts/review-package.sh --out "$PWD/pkg" >/dev/null
grep -q cwe-476 pkg/scenarios.json && grep -q "rules/scenarios/cwe-476/checklist.md" pkg/context.md && ok "⑮ C++ 变更注入命中场景索引" || no "⑮ 场景路由未进输入包"
[ -s .review/metrics.jsonl ] && ok "⑯ metrics 埋点落盘(.review/metrics.jsonl)" || no "⑯ metrics 为空"

echo "— fail-open（破坏内核后必须放行）—"
reset_tree; stage_big_c
echo 'def broken(:' >> scripts/_lib.py   # 在 reset 之后破坏，否则被 --hard 还原
gate '{"session_id":"ff","tool_input":{"command":"git commit -m x"}}'; RC=$?
[ $RC = 0 ] && ok "⑰ 内核异常时 fail-open 放行" || no "⑰ fail-open 失效（误拦） rc=$RC"

echo
echo "结果: PASS=$pass FAIL=$fail  (沙箱: $SUT)"
[ $fail = 0 ]
