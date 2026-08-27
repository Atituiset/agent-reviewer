# Agent Reviewer Flywheel

VS Code extension for reviewing SARIF findings produced by the
[agent-reviewer](../README.md) pipeline and labeling them as true/false positives to feed
the memory flywheel — no HTTP server, everything runs through local shell scripts.

## What it does

- Scans the workspace for `*.sarif` files (SARIF 2.1.0, `runs[].results[]` with
  `partialFingerprints.findingIndex`) and reloads automatically on file changes.
- Shows findings in the **AI Reviewer** activity-bar view, grouped
  **file → rule → finding**, with severity icons (`error`/`warning`/`note`).
- Clicking a finding opens a detail WebView: rule, location (click to jump to the source
  line), full message, confidence, ruling — plus 👍 / 👎 buttons.
- Labeling runs `scripts/memory-label.sh <sarif> <findingIndex> <tp|fp> [reason]` from the
  agent-reviewer repo: TP generates a quarantine proposal, FP accumulates violation
  counts. Fail-open: script errors show a warning, never break the UI.
- Inline 👍/👎 buttons appear on finding tree items; the same commands are available from
  the command palette.

## Settings

| Setting | Type | Default | Description |
|---|---|---|---|
| `agentReviewer.reviewerRoot` | string | `""` | Path to the agent-reviewer repo containing `scripts/memory-label.sh`. Empty = try workspace root. |
| `agentReviewer.autoLoad` | boolean | `true` | Load all workspace `*.sarif` files on startup. |
| `agentReviewer.showLabeled` | boolean | `false` | Show findings already labeled in this session. |

## Dev loop

```bash
cd vscode-flywheel
npm install
npm run compile
```

Then press **F5** in VS Code to launch an Extension Development Host with the extension
loaded. Use `npm run watch` for incremental recompilation.

## Packaging

```bash
npx @vscode/vsce package
```

produces `agent-reviewer-flywheel-0.1.0.vsix`, installable via
**Extensions: Install from VSIX…**.
