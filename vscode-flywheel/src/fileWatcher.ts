import * as vscode from 'vscode';

/**
 * Watches the workspace for *.sarif files and invokes the callback
 * whenever one is created, changed, or deleted.
 */
export class SarifFileWatcher implements vscode.Disposable {
    private watcher: vscode.FileSystemWatcher | undefined;
    private readonly disposables: vscode.Disposable[] = [];

    constructor(private readonly onDidChange: () => void) {}

    start(): void {
        this.watcher = vscode.workspace.createFileSystemWatcher(
            '**/*.sarif',
            false,
            false,
            false,
        );
        const refresh = (uri: vscode.Uri) => {
            if (uri.fsPath.includes('node_modules')) {
                return;
            }
            this.onDidChange();
        };
        this.disposables.push(
            this.watcher.onDidCreate(refresh),
            this.watcher.onDidChange(refresh),
            this.watcher.onDidDelete(refresh),
            this.watcher,
        );
    }

    dispose(): void {
        for (const d of this.disposables) {
            d.dispose();
        }
        this.disposables.length = 0;
    }
}
