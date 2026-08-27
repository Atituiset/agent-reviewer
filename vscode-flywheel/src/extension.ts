import * as vscode from 'vscode';
import { SarifFileWatcher } from './fileWatcher';
import { FindingPanel } from './findingPanel';
import { labelFinding, LabelKind } from './labelClient';
import { Finding, SarifStore } from './sarifLoader';
import { FindingNode, FindingsTreeProvider } from './treeProvider';

async function loadWorkspaceSarif(store: SarifStore): Promise<void> {
    store.clear();
    const uris = await vscode.workspace.findFiles('**/*.sarif', '**/node_modules/**');
    for (const uri of uris) {
        store.loadFile(uri.fsPath);
    }
}

export async function activate(context: vscode.ExtensionContext): Promise<void> {
    const store = new SarifStore();
    const treeProvider = new FindingsTreeProvider(store);

    const treeView = vscode.window.createTreeView('agentReviewerFindings', {
        treeDataProvider: treeProvider,
        showCollapseAll: true,
    });

    const refresh = async (): Promise<void> => {
        await loadWorkspaceSarif(store);
        treeProvider.refresh();
    };

    const doLabel = (finding: Finding, label: LabelKind): Promise<void> =>
        labelFinding(finding, label, store, () => treeProvider.refresh());

    /** Accept either a Finding (webview / palette) or a FindingNode (tree inline button). */
    const asFinding = (arg: unknown): Finding | undefined => {
        if (arg instanceof FindingNode) {
            return arg.finding;
        }
        if (
            typeof arg === 'object' &&
            arg !== null &&
            'findingIndex' in arg &&
            'sarifPath' in arg
        ) {
            return arg as Finding;
        }
        return undefined;
    };

    const requireFinding = (arg: unknown): Finding | undefined => {
        const finding = asFinding(arg);
        if (!finding) {
            void vscode.window.showWarningMessage('请先在 Findings 视图中选择一个 finding。');
        }
        return finding;
    };

    context.subscriptions.push(
        treeView,
        vscode.commands.registerCommand('agentReviewer.refresh', refresh),
        vscode.commands.registerCommand('agentReviewer.openFindingDetail', (arg: unknown) => {
            const finding = requireFinding(arg);
            if (finding) {
                FindingPanel.show(context.extensionUri, finding, (f, label) => {
                    void doLabel(f, label);
                });
            }
        }),
        vscode.commands.registerCommand('agentReviewer.labelTruePositive', (arg: unknown) => {
            const finding = requireFinding(arg);
            if (finding) {
                void doLabel(finding, 'tp');
            }
        }),
        vscode.commands.registerCommand('agentReviewer.labelFalsePositive', (arg: unknown) => {
            const finding = requireFinding(arg);
            if (finding) {
                void doLabel(finding, 'fp');
            }
        }),
    );

    const watcher = new SarifFileWatcher(() => {
        void refresh();
    });
    watcher.start();
    context.subscriptions.push(watcher);

    const autoLoad = vscode.workspace
        .getConfiguration('agentReviewer')
        .get<boolean>('autoLoad', true);
    if (autoLoad) {
        await refresh();
    }
}

export function deactivate(): void {
    // Cleanup is handled via context.subscriptions.
}
