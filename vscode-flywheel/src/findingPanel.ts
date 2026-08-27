import * as vscode from 'vscode';
import { Finding } from './sarifLoader';

function escapeHtml(text: string): string {
    return text
        .replace(/&/g, '&amp;')
        .replace(/</g, '&lt;')
        .replace(/>/g, '&gt;')
        .replace(/"/g, '&quot;');
}

/** Detail WebView panel for a single finding. */
export class FindingPanel {
    private static readonly panels = new Map<string, FindingPanel>();

    static show(
        extensionUri: vscode.Uri,
        finding: Finding,
        onLabel: (finding: Finding, label: 'tp' | 'fp') => void,
    ): void {
        const key = finding.findingIndex;
        const existing = FindingPanel.panels.get(key);
        if (existing) {
            existing.panel.reveal();
            return;
        }
        const panel = vscode.window.createWebviewPanel(
            'agentReviewerFindingDetail',
            `${finding.ruleId}: ${finding.findingIndex}`,
            vscode.ViewColumn.Beside,
            { enableScripts: true },
        );
        const instance = new FindingPanel(panel, extensionUri, finding, onLabel);
        FindingPanel.panels.set(key, instance);
        panel.onDidDispose(() => FindingPanel.panels.delete(key));
    }

    private constructor(
        private readonly panel: vscode.WebviewPanel,
        extensionUri: vscode.Uri,
        private readonly finding: Finding,
        onLabel: (finding: Finding, label: 'tp' | 'fp') => void,
    ) {
        void extensionUri;
        panel.webview.html = this.renderHtml();
        panel.webview.onDidReceiveMessage((msg: { type?: string }) => {
            if (msg?.type === 'openLocation') {
                void this.openLocation();
            } else if (msg?.type === 'labelTp') {
                onLabel(this.finding, 'tp');
            } else if (msg?.type === 'labelFp') {
                onLabel(this.finding, 'fp');
            }
        });
    }

    private async openLocation(): Promise<void> {
        const workspaceFolder = vscode.workspace.workspaceFolders?.[0];
        const uri = this.finding.uri.startsWith('/')
            ? vscode.Uri.file(this.finding.uri)
            : workspaceFolder
                ? vscode.Uri.joinPath(workspaceFolder.uri, this.finding.uri)
                : vscode.Uri.file(this.finding.uri);
        try {
            const doc = await vscode.window.showTextDocument(uri, { preview: true });
            const line = Math.max(0, this.finding.line - 1);
            const range = new vscode.Range(line, 0, line, 0);
            doc.revealRange(range, vscode.TextEditorRevealType.InCenter);
            doc.selection = new vscode.Selection(range.start, range.start);
        } catch {
            void vscode.window.showWarningMessage(`无法打开文件: ${this.finding.uri}`);
        }
    }

    private renderHtml(): string {
        const f = this.finding;
        const location = `${escapeHtml(f.uri)}:${f.line}`;
        return `<!DOCTYPE html>
<html lang="zh">
<head>
<meta charset="UTF-8">
<style>
  body { font-family: var(--vscode-font-family); padding: 16px; color: var(--vscode-foreground); }
  h1 { font-size: 1.3em; }
  dl { display: grid; grid-template-columns: 8em 1fr; row-gap: 4px; }
  dt { opacity: 0.7; }
  dd { margin: 0; }
  a { color: var(--vscode-textLink-foreground); cursor: pointer; }
  pre { white-space: pre-wrap; background: var(--vscode-textCodeBlock-background); padding: 12px; border-radius: 4px; }
  button { margin-right: 8px; padding: 6px 14px; cursor: pointer; }
  .tp { background: var(--vscode-button-background); color: var(--vscode-button-foreground); border: none; }
  .fp { background: var(--vscode-button-secondaryBackground); color: var(--vscode-button-secondaryForeground); border: none; }
</style>
</head>
<body>
  <h1>${escapeHtml(f.ruleId)}</h1>
  <dl>
    <dt>Location</dt><dd><a id="loc">${location}</a></dd>
    <dt>Level</dt><dd>${escapeHtml(f.level)}</dd>
    <dt>Severity</dt><dd>${escapeHtml(f.severity ?? '—')}</dd>
    <dt>Confidence</dt><dd>${f.confidence ?? '—'}</dd>
    <dt>Ruling</dt><dd>${escapeHtml(f.ruling ?? '—')}</dd>
    <dt>FindingIndex</dt><dd><code>${escapeHtml(f.findingIndex)}</code></dd>
    <dt>SARIF</dt><dd><code>${escapeHtml(f.sarifPath)}</code></dd>
  </dl>
  <h2>Message</h2>
  <pre>${escapeHtml(f.message)}</pre>
  <div>
    <button class="tp" id="tp">👍 True Positive</button>
    <button class="fp" id="fp">👎 False Positive</button>
  </div>
<script>
  const vscode = acquireVsCodeApi();
  document.getElementById('loc').addEventListener('click', () => vscode.postMessage({ type: 'openLocation' }));
  document.getElementById('tp').addEventListener('click', () => vscode.postMessage({ type: 'labelTp' }));
  document.getElementById('fp').addEventListener('click', () => vscode.postMessage({ type: 'labelFp' }));
</script>
</body>
</html>`;
    }
}
