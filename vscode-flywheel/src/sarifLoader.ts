import * as fs from 'fs';
import * as path from 'path';

export type SarifLevel = 'error' | 'warning' | 'note' | 'none';

export interface Finding {
    /**
     * partialFingerprints.findingIndex — stable identity used by memory-label.sh.
     * Falls back to `ruleId/uri:startLine` when the producer did not emit one;
     * scripts/_lib.py computes the same fallback, so labeling still round-trips.
     */
    findingIndex: string;
    ruleId: string;
    level: SarifLevel;
    uri: string;
    line: number;
    message: string;
    confidence?: number;
    severity?: string;
    ruling?: string;
    /** Absolute path of the .sarif/.jsonl file this finding came from */
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

/**
 * Fallback identity for results without partialFingerprints.findingIndex.
 * Must stay in sync with _fallback_finding_index() in scripts/_lib.py.
 */
function fallbackFindingIndex(result: SarifResult): string {
    const loc = result.locations?.[0]?.physicalLocation;
    return `${result.ruleId ?? 'unknown'}/${loc?.artifactLocation?.uri ?? ''}:${loc?.region?.startLine ?? 0}`;
}

/**
 * Collect results from one parsed JSON value: either a full SARIF document
 * (an object with `runs`) or a single bare result object (jsonl lines may be either).
 */
function resultsOf(value: unknown): SarifResult[] {
    const doc = value as SarifDocument;
    if (doc && Array.isArray(doc.runs)) {
        return doc.runs.flatMap((run) => run.results ?? []);
    }
    return [value as SarifResult];
}

/**
 * Parse a findings file into findings. Throws on unreadable/invalid JSON.
 * - `.sarif`: a single SARIF 2.1.0 document.
 * - `.jsonl`: one JSON value per line — either a full SARIF document or a single result.
 */
export function loadSarifFile(sarifPath: string): Finding[] {
    const raw = fs.readFileSync(sarifPath, 'utf8');
    const values: unknown[] = sarifPath.endsWith('.jsonl')
        ? raw.split('\n').filter((l) => l.trim() !== '').map((l) => JSON.parse(l))
        : [JSON.parse(raw)];
    const findings: Finding[] = [];
    for (const value of values) {
        for (const result of resultsOf(value)) {
            const loc = result.locations?.[0]?.physicalLocation;
            findings.push({
                findingIndex: result.partialFingerprints?.findingIndex ?? fallbackFindingIndex(result),
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
