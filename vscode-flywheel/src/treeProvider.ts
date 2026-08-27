import * as vscode from 'vscode';
import { Finding, SarifLevel, SarifStore } from './sarifLoader';

type NodeKind = 'file' | 'rule' | 'finding';

export class FindingNode extends vscode.TreeItem {
    constructor(
        public readonly kind: NodeKind,
        label: string,
        collapsibleState: vscode.TreeItemCollapsibleState,
        public readonly finding?: Finding,
    ) {
        super(label, collapsibleState);
    }
}

function severityIcon(level: SarifLevel): vscode.ThemeIcon {
    switch (level) {
        case 'error':
            return new vscode.ThemeIcon('error');
        case 'warning':
            return new vscode.ThemeIcon('warning');
        default:
            return new vscode.ThemeIcon('info');
    }
}

/** Tree: source file → ruleId → finding. */
export class FindingsTreeProvider implements vscode.TreeDataProvider<FindingNode> {
    private readonly _onDidChangeTreeData = new vscode.EventEmitter<FindingNode | undefined>();
    readonly onDidChangeTreeData = this._onDidChangeTreeData.event;

    constructor(private readonly store: SarifStore) {}

    refresh(): void {
        this._onDidChangeTreeData.fire(undefined);
    }

    getTreeItem(element: FindingNode): vscode.TreeItem {
        return element;
    }

    getChildren(element?: FindingNode): FindingNode[] {
        const showLabeled = vscode.workspace
            .getConfiguration('agentReviewer')
            .get<boolean>('showLabeled', false);

        const visible = this.store
            .all()
            .filter((f) => showLabeled || !this.store.isLabeled(f.findingIndex));

        if (!element) {
            // Level 1: group by source file
            const byFile = new Map<string, Finding[]>();
            for (const f of visible) {
                const key = SarifStore.fileLabel(f);
                const list = byFile.get(key) ?? [];
                list.push(f);
                byFile.set(key, list);
            }
            return [...byFile.entries()]
                .sort(([a], [b]) => a.localeCompare(b))
                .map(([fileLabel, findings]) => {
                    const node = new FindingNode(
                        'file',
                        `${fileLabel} (${findings.length})`,
                        vscode.TreeItemCollapsibleState.Collapsed,
                        findings[0],
                    );
                    node.iconPath = vscode.ThemeIcon.File;
                    node.contextValue = 'file';
                    node.tooltip = findings[0]?.uri ?? fileLabel;
                    return node;
                });
        }

        if (element.kind === 'file' && element.finding) {
            // Level 2: group this file's findings by ruleId
            const fileLabel = SarifStore.fileLabel(element.finding);
            const fileFindings = visible.filter(
                (f) => SarifStore.fileLabel(f) === fileLabel,
            );
            const byRule = new Map<string, Finding[]>();
            for (const f of fileFindings) {
                const list = byRule.get(f.ruleId) ?? [];
                list.push(f);
                byRule.set(f.ruleId, list);
            }
            return [...byRule.entries()]
                .sort(([a], [b]) => a.localeCompare(b))
                .map(([ruleId, findings]) => {
                    const node = new FindingNode(
                        'rule',
                        `${ruleId} (${findings.length})`,
                        vscode.TreeItemCollapsibleState.Collapsed,
                        findings[0],
                    );
                    node.iconPath = new vscode.ThemeIcon('symbol-class');
                    node.contextValue = 'rule';
                    return node;
                });
        }

        if (element.kind === 'rule' && element.finding) {
            // Level 3: individual findings under this (file, ruleId)
            const fileLabel = SarifStore.fileLabel(element.finding);
            const ruleId = element.finding.ruleId;
            return visible
                .filter((f) => SarifStore.fileLabel(f) === fileLabel && f.ruleId === ruleId)
                .sort((a, b) => a.line - b.line)
                .map((f) => {
                    const labeled = this.store.isLabeled(f.findingIndex);
                    const firstLine = f.message.split('\n')[0];
                    const label =
                        firstLine.length > 80 ? firstLine.slice(0, 77) + '…' : firstLine;
                    const node = new FindingNode(
                        'finding',
                        label || f.findingIndex,
                        vscode.TreeItemCollapsibleState.None,
                        f,
                    );
                    node.description = `:${f.line}`;
                    node.tooltip = `${f.uri}:${f.line}\n${f.ruleId}: ${f.message}`;
                    node.iconPath = severityIcon(f.level);
                    node.contextValue = labeled ? 'findingLabeled' : 'finding';
                    node.command = {
                        command: 'agentReviewer.openFindingDetail',
                        title: 'Open Finding Detail',
                        arguments: [f],
                    };
                    return node;
                });
        }

        return [];
    }
}
