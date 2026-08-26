#!/usr/bin/env python3
"""MVP 确定性内核（仅 stdlib）。

被 scripts/*.sh 与 hooks/*.sh 调用（解释器由壳层解析：优先 .venv/bin/python）。
退出码约定：
  0 = 通过/放行          2 = 门禁拒绝（业务结果）
  3 = 内部异常（壳层据此 fail-open）
"""
from __future__ import annotations

import hashlib
import json
import os
import re
import sqlite3
import subprocess
import sys
from datetime import datetime, timedelta, timezone
from pathlib import Path

# 测试隔离：selftest 在沙箱仓库中设 MVP_ROOT；生产路径 = 本文件上两级目录
ROOT = Path(os.environ.get("MVP_ROOT") or Path(__file__).resolve().parent.parent)
ARTIFACT_DIR = ROOT / ".git" / "review-gate"
FALLBACK_ARTIFACT = ROOT / ".review" / "last-review.json"
METRICS = ROOT / ".review" / "metrics.jsonl"
DB_PATH = ROOT / "memory" / "team.db"

REQUIRED_FIELDS = ("diff_hash", "verdict", "reviewed_at", "findings", "spec_ref")
VALID_VERDICTS = ("CLEAN", "ISSUES_FOUND", "ESCALATED")


def die_internal(msg: str):
    print(f"[gate] internal error: {msg}", file=sys.stderr)
    sys.exit(3)


# ---------------------------------------------------------------- git helpers

def git(args: list[str], binary: bool = False):
    r = subprocess.run(["git", *args], cwd=ROOT, capture_output=True, check=False)
    if r.returncode != 0:
        return None
    return r.stdout if binary else r.stdout.decode("utf-8", "replace")


def diff_canonical() -> bytes | None:
    """git diff HEAD 的原始字节输出——hash 绑定的规范对象。"""
    return git(["diff", "HEAD"], binary=True)


# ---------------------------------------------------------------- registry

def _expand_braces(g: str) -> list[str]:
    m = re.search(r"\{([^{}]*)\}", g)
    if not m:
        return [g]
    out: list[str] = []
    for alt in m.group(1).split(","):
        out += _expand_braces(g[: m.start()] + alt + g[m.end():])
    return out


def glob_to_regex(g: str) -> re.Pattern:
    """glob 方言：'**/' 匹配零或多层目录，'**' 匹配任意串，'*' 单段，'?' 单字符。"""
    out, i = "", 0
    while i < len(g):
        if g.startswith("**/", i):
            out += "(?:.*/)?"
            i += 3
        elif g.startswith("**", i):
            out += ".*"
            i += 2
        elif g[i] == "*":
            out += "[^/]*"
            i += 1
        elif g[i] == "?":
            out += "."
            i += 1
        else:
            out += re.escape(g[i])
            i += 1
    return re.compile("^" + out + "$")


def load_registry() -> list[tuple[re.Pattern, list[str]]]:
    data = json.loads((ROOT / "rules" / "registry.json").read_text(encoding="utf-8"))
    rules = []
    for r in data["rules"]:
        for g in _expand_braces(r["path"]):
            rules.append((glob_to_regex(g), r["scenarios"]))
    return rules


def scenarios_for(path: str) -> set[str]:
    hits: set[str] = set()
    for rx, scen in load_registry():
        if rx.match(path):
            hits.update(scen)
    return hits


def known_scenarios() -> set[str]:
    base = ROOT / "rules" / "scenarios"
    if not base.is_dir():
        return set()
    return {p.name for p in base.iterdir() if (p / "meta.yaml").exists()}


# ---------------------------------------------------------------- metrics (§4)

def append_metrics(event: dict) -> None:
    try:
        METRICS.parent.mkdir(parents=True, exist_ok=True)
        event = {"ts": datetime.now(timezone.utc).isoformat(timespec="seconds"), **event}
        with METRICS.open("a", encoding="utf-8") as f:
            f.write(json.dumps(event, ensure_ascii=False) + "\n")
    except OSError as e:  # 埋点失败不阻塞主流程
        print(f"[metrics] append failed: {e}", file=sys.stderr)


# ---------------------------------------------------------------- artifact 校验（MVP §2.1）

def _fail(code: str, message: str, hint: str) -> dict:
    return {"code": code, "message": message, "hint": hint}


def _verdict_failures(a: dict) -> list[dict]:
    v = a.get("verdict")
    findings = a.get("findings") or []
    if v not in VALID_VERDICTS:
        return [_fail("E_VERDICT", f"非法 verdict: {v!r}", "取值 CLEAN | ISSUES_FOUND | ESCALATED")]
    if v == "CLEAN":
        return []
    unresolved = [f for f in findings if not f.get("resolved")]
    if v == "ISSUES_FOUND":
        return [] if not unresolved else [
            _fail("E_VERDICT", f"ISSUES_FOUND 且存在 {len(unresolved)} 条未解决 finding",
                  "修复后重评至 CLEAN，或改判 ESCALATED 并逐条给人工 ruling")]
    if v == "ESCALATED":
        if not a.get("escalated"):
            return [_fail("E_VERDICT", "ESCALATED 但 escalated 字段非 true",
                          "熔断放行必须 escalated:true 留痕")]
        missing_ruling = [f for f in unresolved if not f.get("ruling")]
        if missing_ruling:
            return [_fail("E_VERDICT", f"{len(missing_ruling)} 条未解决 finding 缺人工 ruling",
                          "每条残留 finding 补 ruling 后方可熔断放行")]
    return []


def has_unstaged() -> bool | None:
    """True=存在 unstaged 改动；False=干净；None=git 异常。(--quiet 用退出码表达结果)"""
    r = subprocess.run(["git", "diff", "--quiet"], cwd=ROOT, capture_output=True, check=False)
    if r.returncode == 0:
        return False
    if r.returncode == 1:
        return True
    return None


def validate_artifact(path: Path) -> tuple[bool, list[dict]]:
    fails: list[dict] = []

    # 规则 1 前置：完整暂存（评审树 == 提交树的前提）
    unstaged = has_unstaged()
    if unstaged is None:
        fails.append(_fail("E_GIT", "git diff --quiet 执行失败", "检查仓库状态"))
    elif unstaged:
        fails.append(_fail(
            "E_PARTIAL_STAGE",
            "存在 unstaged 改动：部分 stage 时「评审过的树 ≠ 提交的树」",
            "先 git add 完整暂存本次变更，再重新校验"))

    if not path.is_file():
        fails.append(_fail(
            "E_NO_ARTIFACT",
            f"评审工件不存在: {path}",
            "运行 /sdd-review 生成评审工件后再提交"))
        return False, fails

    # 结构与字段
    try:
        a = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as e:
        fails.append(_fail("E_MALFORMED", f"工件不可读/非法 JSON: {e}", "重跑 /sdd-review"))
        return False, fails
    missing = [k for k in REQUIRED_FIELDS if k not in a]
    if missing:
        fails.append(_fail("E_MALFORMED", f"工件缺字段: {missing}", "按 §2.1 schema 重写工件"))

    # 规则 2 hash 绑定
    d = diff_canonical()
    if d is None:
        fails.append(_fail("E_GIT", "git diff HEAD 失败（空仓库？）", "初始化提交后再试"))
    else:
        actual = hashlib.sha256(d).hexdigest()
        if a.get("diff_hash") != actual:
            fails.append(_fail(
                "E_HASH_MISMATCH",
                "diff_hash 与当前工作区不符：评审后代码已变动",
                "重新运行 /sdd-review 再提交"))

    # 规则 3 verdict 三态
    fails += _verdict_failures(a)

    # 规则 4 时效 24h
    try:
        ts = datetime.fromisoformat(str(a.get("reviewed_at")).replace("Z", "+00:00"))
        if datetime.now(timezone.utc) - ts > timedelta(hours=24):
            fails.append(_fail("E_STALE", "工件超过 24 小时", "重新评审"))
    except ValueError:
        fails.append(_fail("E_MALFORMED", "reviewed_at 非法 ISO8601", "重跑 /sdd-review"))

    # 规则 5 场景名存在性（防幻觉场景名）
    known = known_scenarios() | {"none"}
    bad = sorted({f.get("scenario") for f in (a.get("findings") or [])
                  if f.get("scenario") and f["scenario"] not in known})
    if bad:
        fails.append(_fail("E_UNKNOWN_SCENARIO", f"finding 引用了不存在的场景: {bad}",
                           f"可用场景见 rules/scenarios/：{sorted(known)}"))
    return not fails, fails


def artifact_path_for(session_id: str | None) -> Path:
    if session_id:
        return ARTIFACT_DIR / f"{session_id}.json"
    return FALLBACK_ARTIFACT


# ---------------------------------------------------------------- hook-gate（MVP §2.2）

DOCS_ONLY = re.compile(r"^(docs/.*)|[^ ]*\.md$")


def _exemptions(paths: list[str], added: int, deleted: int) -> str | None:
    if added + deleted < 20:
        return f"trivial: diff 仅 {added}+{deleted} 行（<20 豁免）"
    if paths and all(DOCS_ONLY.match(p) or p.endswith(".md") for p in paths):
        return "docs-only: 变更仅触及文档"
    return None


def cmd_hook_gate() -> int:
    try:
        payload = json.load(sys.stdin)
    except json.JSONDecodeError:
        return 0  # 非 hook 调用（无合法 stdin），放行
    command = str(payload.get("tool_input", {}).get("command", ""))
    session_id = payload.get("session_id")
    if "git commit" not in command:
        return 0
    if (ROOT / ".review" / "DISABLED").exists():
        append_metrics({"event": "gate_allow", "reason": "kill-switch"})
        return 0

    numstat = git(["diff", "HEAD", "--numstat"])
    if numstat is None:  # 无 HEAD（首仓）等异常 → fail-open 留痕
        append_metrics({"event": "gate_allow", "reason": "no-head"})
        return 0
    added = deleted = 0
    paths: list[str] = []
    for line in numstat.splitlines():
        parts = line.split("\t")
        if len(parts) == 3:
            added += int(parts[0]) if parts[0].isdigit() else 0
            deleted += int(parts[1]) if parts[1].isdigit() else 0
            paths.append(parts[2])

    exempt = _exemptions(paths, added, deleted)
    if exempt:
        append_metrics({"event": "gate_allow", "reason": exempt})
        return 0

    ok, fails = validate_artifact(artifact_path_for(session_id))
    if ok:
        append_metrics({"event": "gate_allow", "reason": "artifact-ok", "session": session_id})
        return 0
    append_metrics({"event": "gate_deny", "codes": [f["code"] for f in fails],
                    "session": session_id})
    print("[review-gate] 本次提交被门禁拦截：")
    for f in fails:
        print(f"  {f['code']}: {f['message']}\n    ↳ 修正: {f['hint']}")
    print("  请运行 /sdd-review 完成任务级评审后重试（豁免/关闭见 hooks/README.md）")
    return 2


# ---------------------------------------------------------------- memoryd（MVP §2.5）

SCHEMA = """
CREATE TABLE IF NOT EXISTS memories (
  id TEXT PRIMARY KEY,
  kind TEXT NOT NULL,
  status TEXT NOT NULL DEFAULT 'quarantine',
  content TEXT NOT NULL,
  modules TEXT NOT NULL,
  bound_paths TEXT NOT NULL,
  evidence TEXT NOT NULL,
  created_at TEXT NOT NULL,
  reviewed_by TEXT,
  reviewed_at TEXT
);
"""


def db() -> sqlite3.Connection:
    DB_PATH.parent.mkdir(parents=True, exist_ok=True)
    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row
    conn.executescript(SCHEMA)
    return conn


def memory_propose(payload: dict) -> int:
    content = str(payload.get("content", ""))
    ev = payload.get("evidence") or {}
    # 治理红线：无 file:line 证据拒收
    if not re.search(r"[^`\s]+:\d+", content):
        print(json.dumps({"ok": False, "code": "E_NO_EVIDENCE",
                          "message": "content 必须含 file:line 证据"}, ensure_ascii=False))
        return 2
    conn = db()
    mid = payload.get("id") or f"mem-{datetime.now(timezone.utc).strftime('%Y%m%d%H%M%S%f')}"
    conn.execute(
        "INSERT INTO memories (id,kind,status,content,modules,bound_paths,evidence,created_at)"
        " VALUES (?,'review_finding','quarantine',?,?,?,?,?)",
        (mid, content, json.dumps(payload.get("modules") or [], ensure_ascii=False),
         json.dumps(payload.get("bound_paths") or [], ensure_ascii=False),
         json.dumps(ev, ensure_ascii=False),
         datetime.now(timezone.utc).isoformat(timespec="seconds")))
    conn.commit()
    print(json.dumps({"ok": True, "id": mid, "status": "quarantine"}, ensure_ascii=False))
    return 0


def memory_approve(mem_id: str, reject_reason: str | None) -> int:
    conn = db()
    new_status = "archived" if reject_reason else "active"
    cur = conn.execute(
        "UPDATE memories SET status=?, reviewed_by=?, reviewed_at=? WHERE id=? AND status='quarantine'",
        (new_status, "human-mde", datetime.now(timezone.utc).isoformat(timespec="seconds"), mem_id))
    conn.commit()
    if cur.rowcount == 0:
        print(json.dumps({"ok": False, "code": "E_NOT_IN_QUARANTINE",
                          "message": f"id={mem_id} 不在待审核状态"}, ensure_ascii=False))
        return 2
    print(json.dumps({"ok": True, "id": mem_id, "status": new_status}, ensure_ascii=False))
    return 0


def memory_recall(paths: list[str]) -> int:
    conn = db()
    rows = conn.execute("SELECT id,content,modules FROM memories WHERE status='active'").fetchall()
    matched = []
    for row in rows:
        mods = json.loads(row["modules"])
        for m in mods:
            rx = glob_to_regex(m)
            if any(rx.match(p) for p in paths):
                matched.append(row["id"])
                break
    for row in rows:
        if row["id"] in matched:
            print(f"- [{row['id']}] {row['content']}")
    return 0


# ---------------------------------------------------------------- 输入包打包（MVP §2.3）

def cmd_package(rest: list[str]) -> int:
    """review-package：diff + 场景路由 checklist 索引 + 记忆召回 + spec 段落 → 输入包目录。"""
    import tempfile

    def opt(name: str, default=None):
        return rest[rest.index(name) + 1] if name in rest else default

    spec_dir = Path(opt("--spec", "")) if opt("--spec") else None
    ts = datetime.now(timezone.utc).strftime("%Y%m%d-%H%M%S")
    out = Path(opt("--out", str(Path(tempfile.gettempdir()) / f"review-{ts}")))
    out.mkdir(parents=True, exist_ok=True)

    (out / "diff.patch").write_bytes(diff_canonical() or b"")
    numstat = git(["diff", "HEAD", "--numstat"]) or ""
    paths = [ln.split("\t")[2] for ln in numstat.splitlines() if len(ln.split("\t")) == 3]

    known = known_scenarios()
    scen = sorted(set().union(*[scenarios_for(p) for p in paths], set()) & (known | {"default"})) \
        if paths else ["default"]

    file_lines = [f"- {p}" for p in paths] or ["- （无）"]
    ctx = ["# 变更文件", *file_lines, "", "# 命中场景索引（按需读对应 checklist）"]
    for s in scen:
        ctx.append(f"- {s} → rules/scenarios/{s}/checklist.md")
    ctx.append("")
    recalled = []
    try:
        conn = db()
        rows = conn.execute("SELECT id,content,modules FROM memories WHERE status='active'").fetchall()
        for row in rows:
            mods = json.loads(row["modules"])
            if any(glob_to_regex(m).match(p) for m in mods for p in paths):
                recalled.append(f"- [{row['id']}] {row['content']}")
    except sqlite3.Error as e:
        ctx.append(f"(记忆库不可用，跳过召回: {e})")
    ctx.append("# 团队记忆召回（active 且模块命中；空 = 无）")
    ctx += recalled or ["- （无）"]

    if spec_dir and spec_dir.is_dir():
        ctx.append(f"\n# spec 相关段落（{spec_dir}）")
        budget = 8192
        for md in sorted(spec_dir.glob("*.md")):
            text = md.read_text(encoding="utf-8", errors="replace")
            chunk = text[:budget]
            ctx += [f"\n## {md.name}", chunk]
            budget -= len(chunk)
            if budget <= 0:
                ctx.append("\n(后续 spec 内容因长度预算截断)")
                break
    else:
        ctx.append("\n# spec 段落：未提供 --spec（openspec change 目录），conformance 通道按无锚评审并在 finding 中标注 AMBIGUOUS 风险")

    (out / "context.md").write_text("\n".join(ctx), encoding="utf-8")
    (out / "scenarios.json").write_text(json.dumps(scen, ensure_ascii=False), encoding="utf-8")
    print(str(out))
    return 0


# ---------------------------------------------------------------- CLI dispatch

def main() -> int:
    argv = sys.argv[1:]
    if not argv:
        die_internal("missing subcommand")
    cmd, rest = argv[0], argv[1:]
    if cmd == "hook-gate":
        return cmd_hook_gate()
    if cmd == "verify-artifact":
        sid = rest[rest.index("--session") + 1] if "--session" in rest else None
        path = artifact_path_for(sid)
        ok, fails = validate_artifact(path)
        if ok:
            print(f"[verify-artifact] OK ({path})")
            return 0
        for f in fails:
            print(f"DENY {f['code']}: {f['message']} | 修正: {f['hint']}")
        return 2
    if cmd == "scenarios-for":
        for p in rest:
            print(p, "->", ",".join(sorted(scenarios_for(p))) or "(none)")
        return 0
    if cmd == "memory-propose":
        return memory_propose(json.load(sys.stdin))
    if cmd == "memory-approve":
        reason = rest[rest.index("--reject") + 1] if "--reject" in rest else None
        return memory_approve(rest[0], reason)
    if cmd == "memory-recall":
        return memory_recall(rest)
    if cmd == "package":
        return cmd_package(rest)
    if cmd == "replay-info":
        n_cases = sum(1 for p in (ROOT / "rules" / "scenarios").rglob("golden.json"))
        print(f"回放样本 golden.json 共 {n_cases} 个；为 0 时回放基线不可用（等待团队 cases 迁移）")
        return 0
    die_internal(f"unknown subcommand {cmd}")


if __name__ == "__main__":
    try:
        sys.exit(main())
    except SystemExit:
        raise
    except Exception as e:  # noqa: BLE001 —— 统一 fail-open 语义出口
        die_internal(repr(e))
