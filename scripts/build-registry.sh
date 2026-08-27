#!/usr/bin/env bash
# build-registry.sh — 扫描 rules/scenarios/*/SKILL.md 的 frontmatter，生成 rules/registry.json
# 单一数据源是各 SKILL.md 的 paths 字段；本文件为派生物。
set -euo pipefail

cd "$(dirname "$0")/.."
SCEN_DIR="rules/scenarios"
OUT="rules/registry.json"

command -v python3 >/dev/null || { echo "need python3" >&2; exit 1; }

python3 - "$SCEN_DIR" "$OUT" <<'PY'
import json, re, sys, pathlib

scen_dir, out = pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2])
path_to_scenarios = {}

for skill in sorted(scen_dir.glob("*/SKILL.md")):
    text = skill.read_text(encoding="utf-8")
    m = re.match(r"^---\n(.*?)\n---\n", text, re.S)
    if not m:
        raise SystemExit(f"{skill}: missing frontmatter")
    fm = m.group(1)
    name = re.search(r"^name:\s*(.+)$", fm, re.M).group(1).strip()
    pm = re.search(r"^paths:\s*\[(.*?)\]", fm, re.M | re.S)
    if not pm:
        raise SystemExit(f"{skill}: missing paths")
    # 按逗号切分，但忽略 {} 内的逗号（brace glob，如 **/*.{c,cc,cpp}）
    raw, depth, parts = pm.group(1), 0, []
    for tok in re.split(r"(,)", raw):
        if tok == "," and depth == 0:
            parts.append("|")
        else:
            depth += tok.count("{") - tok.count("}")
            parts.append(tok)
    globs = [g.strip().strip('"').strip("'") for g in "".join(parts).split("|") if g.strip()]
    for g in globs:
        path_to_scenarios.setdefault(g, []).append(name)

rules = [{"path": p, "scenarios": s} for p, s in path_to_scenarios.items()]
out.write_text(json.dumps({"rules": rules}, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
print(f"wrote {out}: {len(rules)} path rules, {len(list(scen_dir.glob('*/SKILL.md')))} scenarios")
PY
