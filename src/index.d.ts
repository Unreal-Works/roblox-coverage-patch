interface CoverageLocation {
    start: {
        line: number;
        column: number;
    };
    end: {
        line: number;
        column: number;
    };
}

interface StatementMap {
    [id: string]: CoverageLocation;
}

interface FunctionMap {
    [id: string]: {
        name: string;
        decl: CoverageLocation;
        loc: CoverageLocation;
        line: number;
    };
}

interface BranchMap {
    [id: string]: {
        type: string;
        line: number;
        loc: CoverageLocation;
        locations: CoverageLocation[];
    };
}

interface HitCounts {
    [id: string]: number;
}

interface BranchHitCounts {
    [id: string]: number[];
}

interface RuntimeStatsOptions {
    /** Max entries per category to return (default 10). */
    limit?: number;
    /** Ignore entries with hit counts below this (default 1). */
    minHits?: number;
    includeStatements?: boolean;
    includeFunctions?: boolean;
    includeBranches?: boolean;
}

interface RuntimeTotalsCategory {
    points: number;
    hits: number;
}

interface RuntimeStatsResult {
    totals: {
        statements: RuntimeTotalsCategory;
        functions: RuntimeTotalsCategory;
        branches: RuntimeTotalsCategory;
    };
    topStatements: Array<{ id: number; hits: number; file?: string; line?: number }>;
    topFunctions: Array<{ id: number; name?: string; hits: number; file?: string; line?: number }>;
    topBranches: Array<{ id: number; type?: string; hits: number; file?: string; line?: number; paths?: number[] }>;
    hotFiles: Array<{ file?: string; hits: number }>;
}

interface FileCoverageData {
    path: string;

    /**
     * Summarize the most frequently hit statements/functions/branches to help diagnose runtime slowness.
     */
    runtimeStats(options?: RuntimeStatsOptions): RuntimeStatsResult;
    statementMap: StatementMap;
    fnMap: FunctionMap;
    branchMap: BranchMap;
    s: HitCounts;
    f: HitCounts;
    b: BranchHitCounts;
}

interface IstanbulReport {
    [filePath: string]: FileCoverageData;
}

interface Coverage {
    /**
     * Instrument all modules in the specified include/exclude sets with coverage tracking.
     *
     * @param include - Array of Instance roots to include for instrumentation.
     *                  Defaults to common Roblox services (ServerScriptService, ReplicatedStorage, etc.)
     * @param exclude - Array of Instance roots to exclude from instrumentation.
     *                  Defaults to ReplicatedStorage.Packages
     *
     * @example
     * ```ts
     * const coverage = require(ReplicatedStorage.coverage);
     *
     * // Instrument everything with defaults
     * coverage.instrument();
     *
     * // Instrument only specific folders
     * coverage.instrument([ServerScriptService.MyProject], []);
     *
     * // Exclude test files
     * coverage.instrument(
     *   [ServerScriptService],
     *   [ServerScriptService.Tests]
     * );
     * ```
     */
    instrument(include?: Instance[], exclude?: Instance[]): void;

    /**
     * Cleanup and remove all instrumentation hooks and data.
     * Call this when coverage data is no longer needed.
     *
     * @example
     * ```ts
     * const coverage = require(ReplicatedStorage.coverage);
     *
     * // After generating coverage report
     * local report = coverage.istanbul();
     *
     * // Cleanup instrumentation data
     * coverage.cleanup();
     * ```
     */
    cleanup(): void;

    /**
     * Generate an Istanbul-compatible coverage report from the collected coverage data.
     *
     * @returns An Istanbul coverage report object mapping file paths to coverage data.
     *          This can be serialized to JSON and used with standard coverage tools like nyc, jest, etc.
     *
     * @example
     * ```ts
     * const HttpService = game.GetService("HttpService");
     * const coverage = require(ReplicatedStorage.coverage);
     *
     * // Run your tests...
     *
     * // Generate and export coverage report
     * const report = coverage.istanbul();
     * const json = HttpService.JSONEncode(report);
     * // Write json to file or send to external service
     * ```
     */
    istanbul(): IstanbulReport;
}

declare const coverage: Coverage;
export = coverage;
