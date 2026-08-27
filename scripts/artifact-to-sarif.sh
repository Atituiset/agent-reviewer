#!/usr/bin/env bash
# artifact-to-sarif.sh — 将 review-artifact.json 投影为 SARIF 2.1.0
# canonical 工件不变，SARIF 仅作展示/交换层（MVP 设计 §2.1 投影约定）
# 用法: scripts/artifact-to-sarif.sh <review-artifact.json> [out.sarif]
set -euo pipefail

IN="${1:?usage: artifact-to-sarif.sh <review-artifact.json> [out.sarif]}"
OUT="${2:-${IN%.json}.sarif}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PY="$ROOT/.venv/bin/python"; [ -x "$PY" ] || PY=python3

"$PY" - "$IN" "$OUT" "$ROOT" <<'PYEOF'
import json, re, sys, pathlib

in_path, out_path, root = pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2]), pathlib.Path(sys.argv[3])
art = json.loads(in_path.read_text(encoding="utf-8"))

# 从 SKILL frontmatter 收集场景元数据 → SARIF rules
def scen_meta():
    rules = {}
    for sk in sorted(root.glob("rules/scenarios/*/SKILL.md")):
        text = sk.read_text(encoding="utf-8")
        m = re.match(r"^---\n(.*?)\n---\n", text, re.S)
        fm = m.group(1) if m else ""
        def field(k, default=""):
            mm = re.search(rf"^{k}:\s*(.+)$", fm, re.M)
            return mm.group(1).strip() if mm else default
        key = sk.parent.name
        rules[key] = {
            "id": key,
            "name": field("name", key),
            "shortDescription": {"text": field("description", key)[:120]},
            "properties": {"cwe": field("cwe", "null"),
                           "severity_default": field("severity_default", "medium"),
                           "origin": field("origin", "builtin")},
        }
    return rules

LEVEL = {"critical": "error", "important": "error", "minor": "note",
         "high": "error", "medium": "warning", "low": "note"}

rules_by_id = scen_meta()
used_rule_ids, results = [], []
for i, f in enumerate(art.get("findings", [])):
    scen = f.get("scenario") or "default"
    # scenario 值可能是 cwe-476（短键）或 cwe-476-null-pointer-dereference（全名）
    rid = scen if scen in rules_by_id else next(
        (k for k in rules_by_id if k == scen or rules_by_id[k]["name"] == scen or k.startswith(scen + "-") or scen.startswith(k + "-")),
        scen)
    if rid in rules_by_id and rid not in used_rule_ids:
        used_rule_ids.append(rid)
    snippet = ""
    results.append({
        "ruleId": rid,
        "level": LEVEL.get(f.get("severity", "minor"), "warning"),
        "message": {"text": f'{f.get("summary", "")}\n\n{f.get("detail", "")}'.strip()},
        "locations": [{
            "physicalLocation": {
                "artifactLocation": {"uri": f.get("file", "")},
                "region": {"startLine": f.get("line", 1)},
            }
        }],
        "partialFingerprints": {
            "diffHash": art.get("diff_hash", ""),
            "findingIndex": f"{rid}/{f.get('file','')}:{f.get('line',0)}",
        },
        "properties": {
            "confidence": f.get("confidence"),
            "severity": f.get("severity"),
            "category": f.get("category"),
            "checklist_item": f.get("checklist_item"),
            "refs": f.get("refs", []),
            "ruling": f.get("ruling"),
            "resolved": f.get("resolved"),
        },
    })

sarif = {
    "$schema": "https://json.schemastore.org/sarif-2.1.0.json",
    "version": "2.1.0",
    "runs": [{
        "tool": {"driver": {
            "name": "agent-reviewer",
            "version": "0.1.0",
            "informationUri": "https://github.com/Atituiset/agent-reviewer",
            "rules": [rules_by_id[r] for r in used_rule_ids],
        }},
        "results": results,
        "properties": {
            "verdict": art.get("verdict"),
            "diff_hash": art.get("diff_hash"),
            "reviewed_at": art.get("reviewed_at"),
            "scenarios_scanned": art.get("scenarios_scanned", []),
        },
    }],
}
out_path.write_text(json.dumps(sarif, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
print(f"wrote {out_path}: {len(results)} results, {len(used_rule_ids)} rules")
PYEOF
