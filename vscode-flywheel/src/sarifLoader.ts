import * as fs from 'fs';
import * as path from 'path';

export type SarifLevel = 'error' | 'warning' | 'note' | 'none';

export interface Finding {
    /** partialFingerprints.findingIndex — stable identity used by memory-label.sh */
    findingIndex: string;
    ruleId: string;
    level: SarifLevel;
    uri: string;
    line: number;
    message: string;
    confidence?: number;
    severity?: string;
    ruling?: string;
    /** Absolute path of the .sarif file this finding came from */
    sarifPath: string;
}

interface SarifResult {
    ruleId?: string;
    level?: string;
    message?: { text?: string };
    locations?: Array<{
        physicalLocation?: {
            artifactLocation?: { uri?: string };
            region?: { startLine?: number };
        };
    }>;
    partialFingerprints?: { findingIndex?: string };
    properties?: {
        confidence?: number;
        severity?: string;
        ruling?: string;
    };
}

interface SarifDocument {
    runs?: Array<{ results?: SarifResult[] }>;
}

/** Parse a single SARIF 2.1.0 file into findings. Throws on unreadable/invalid JSON. */
export function loadSarifFile(sarifPath: string): Finding[] {
    const raw = fs.readFileSync(sarifPath, 'utf8');
    const doc = JSON.parse(raw) as SarifDocument;
    const findings: Finding[] = [];
    for (const run of doc.runs ?? []) {
        for (const result of run.results ?? []) {
            const loc = result.locations?.[0]?.physicalLocation;
            const findingIndex =
                result.partialFingerprints?.findingIndex ??
                `${result.ruleId ?? 'unknown'}/${loc?.artifactLocation?.uri ?? ''}:${loc?.region?.startLine ?? 0}`;
            findings.push({
                findingIndex,
                ruleId: result.ruleId ?? 'unknown',
                level: (result.level as SarifLevel) ?? 'warning',
                uri: loc?.artifactLocation?.uri ?? '',
                line: loc?.region?.startLine ?? 0,
                message: result.message?.text ?? '',
                confidence: result.properties?.confidence,
                severity: result.properties?.severity,
                ruling: result.properties?.ruling,
                sarifPath,
            });
        }
    }
    return findings;
}

/**
 * Aggregates findings from multiple SARIF files and tracks which
 * findingIndexes have been labeled in this session (in-memory only).
 */
export class SarifStore {
    private readonly byFile = new Map<string, Finding[]>();
    private readonly labeled = new Set<string>();

    /** (Re)load one SARIF file into the store. Returns false if it could not be parsed. */
    loadFile(sarifPath: string): boolean {
        try {
            this.byFile.set(sarifPath, loadSarifFile(sarifPath));
            return true;
        } catch {
            this.byFile.delete(sarifPath);
            return false;
        }
    }

    removeFile(sarifPath: string): void {
        this.byFile.delete(sarifPath);
    }

    clear(): void {
        this.byFile.clear();
    }

    /** All findings, grouped by source file path (basename of artifactLocation.uri). */
    all(): Finding[] {
        return [...this.byFile.values()].flat();
    }

    files(): string[] {
        return [...this.byFile.keys()];
    }

    markLabeled(findingIndex: string): void {
        this.labeled.add(findingIndex);
    }

    isLabeled(findingIndex: string): boolean {
        return this.labeled.has(findingIndex);
    }

    /** Display name for grouping: the finding's source-file basename. */
    static fileLabel(finding: Finding): string {
        return finding.uri ? path.basename(finding.uri) : '(unknown file)';
    }
}
