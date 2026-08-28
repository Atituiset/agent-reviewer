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
import json, os, re, sys, pathlib

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

# region.snippet：从被审源码提取代码行（SARIF_SRC_ROOT = 被审仓根目录；读不到则空串）
SRC_ROOT = pathlib.Path(os.environ.get("SARIF_SRC_ROOT") or
                        (os.environ.get("GITHUB_WORKSPACE") or "."))
_src_cache: dict = {}

def code_snippet(uri: str, line: int, span: int = 1) -> str:
    if not uri or not line:
        return ""
    try:
        if uri not in _src_cache:
            p = SRC_ROOT / uri
            _src_cache[uri] = p.read_text(encoding="utf-8", errors="replace").splitlines() if p.is_file() else None
        lines = _src_cache[uri]
        if not lines:
            return ""
        start = max(0, line - 1)
        return "\n".join(l.strip() for l in lines[start:start + span])[:400]
    except OSError:
        return ""

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
    msg_text = f'{f.get("summary", "")}\n\n{f.get("detail", "")}'.strip()
    if f.get("reasoning"):
        msg_text += f'\n\n**判断理由**：{f["reasoning"]}'
    if f.get("flow"):
        steps = " → ".join(f'{s.get("file","")}:{s.get("line","")} {s.get("message","")}' for s in f["flow"])
        msg_text += f'\n\n**证据链**：{steps}'
    result = {
        "ruleId": rid,
        "level": LEVEL.get(f.get("severity", "minor"), "warning"),
        "message": {"text": msg_text, "markdown": msg_text},
        "locations": [{
            "physicalLocation": {
                "artifactLocation": {"uri": f.get("file", "")},
                "region": {"startLine": max(1, f.get("line") or 1), "snippet": {"text": code_snippet(f.get("file", ""), max(1, f.get("line") or 1))}},
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
    }
    # 证据链 → codeFlows（SARIF 原生数据流路径，GitHub「Show paths」/SARIF Viewer 可逐步跳转）
    flow = f.get("flow") or []
    if flow:
        result["codeFlows"] = [{
            "threadFlows": [{
                "locations": [
                    {
                        "location": {
                            "physicalLocation": {
                                "artifactLocation": {"uri": step.get("file", "")},
                                "region": {"startLine": max(1, step.get("line") or 1),
                                           "snippet": {"text": code_snippet(step.get("file", ""), max(1, step.get("line") or 1))}},
                            },
                            "message": {"text": step.get("message", "")},
                        }
                    }
                    for step in flow
                ]
            }]
        }]
    # 提炼后的判断理由 → properties；完整轨迹走 hostedViewerUri（渐进式披露）
    if f.get("reasoning"):
        result["properties"]["reasoning"] = f["reasoning"]
    viewer_uri = os.environ.get("SARIF_VIEWER_URI")
    if viewer_uri:
        result["hostedViewerUri"] = viewer_uri
    results.append(result)

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
