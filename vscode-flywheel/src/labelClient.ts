import * as child_process from 'child_process';
import * as fs from 'fs';
import * as path from 'path';
import * as vscode from 'vscode';
import { Finding, SarifStore } from './sarifLoader';

export type LabelKind = 'tp' | 'fp';

function resolveScriptPath(): string | undefined {
    const configured = vscode.workspace
        .getConfiguration('agentReviewer')
        .get<string>('reviewerRoot', '');
    const candidates: string[] = [];
    if (configured) {
        candidates.push(path.join(configured, 'scripts', 'memory-label.sh'));
    }
    for (const folder of vscode.workspace.workspaceFolders ?? []) {
        candidates.push(path.join(folder.uri.fsPath, 'scripts', 'memory-label.sh'));
    }
    return candidates.find((p) => fs.existsSync(p));
}

interface LabelResult {
    ok: boolean;
    code?: string;
    message?: string;
    fp_count?: number;
}

/**
 * Label a finding via the local memory-label.sh script (no HTTP server).
 * Fail-open: never throws; reports problems via warning messages.
 */
export async function labelFinding(
    finding: Finding,
    label: LabelKind,
    store: SarifStore,
    onLabeled: () => void,
    reason?: string,
): Promise<void> {
    const script = resolveScriptPath();
    if (!script) {
        void vscode.window.showWarningMessage(
            '找不到 memory-label.sh，请设置 agentReviewer.reviewerRoot 指向 agent-reviewer 仓库。',
        );
        return;
    }

    const args = [script, finding.sarifPath, finding.findingIndex, label, reason ?? ''];

    let stdout: string;
    let failed = false;
    try {
        stdout = await new Promise<string>((resolve, reject) => {
            child_process.execFile(
                'bash',
                args,
                { timeout: 30_000 },
                (error, out) => {
                    if (error) {
                        reject(new Error(`${error.message}\n${out}`));
                    } else {
                        resolve(out);
                    }
                },
            );
        });
    } catch (err) {
        failed = true;
        stdout = err instanceof Error ? err.message : String(err);
    }

    let result: LabelResult | undefined;
    try {
        // The script prints a single JSON object on stdout.
        const line = stdout.trim().split('\n').find((l) => l.trim().startsWith('{'));
        if (line) {
            result = JSON.parse(line) as LabelResult;
        }
    } catch {
        // fall through — handled below
    }

    if (failed || !result || result.ok !== true) {
        const detail = result?.message ?? stdout.trim().slice(0, 300);
        void vscode.window.showWarningMessage(`标注失败: ${detail || 'unknown error'}`);
        return;
    }

    store.markLabeled(finding.findingIndex);
    onLabeled();
    if (label === 'tp') {
        void vscode.window.showInformationMessage('TP → 已生成 quarantine 提案');
    } else {
        void vscode.window.showInformationMessage(
            `FP → violations+1${result.fp_count !== undefined ? ` (30 天内共 ${result.fp_count} 次)` : ''}`,
        );
    }
}
