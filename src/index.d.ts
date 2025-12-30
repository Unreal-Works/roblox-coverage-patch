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

interface FileCoverageData {
    path: string;
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

interface CovPatch {
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
     * const covpatch = require(ReplicatedStorage.covpatch);
     *
     * // Instrument everything with defaults
     * covpatch.instrument();
     *
     * // Instrument only specific folders
     * covpatch.instrument([ServerScriptService.MyProject], []);
     *
     * // Exclude test files
     * covpatch.instrument(
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
     * const covpatch = require(ReplicatedStorage.covpatch);
     *
     * // After generating coverage report
     * local report = covpatch.istanbul();
     *
     * // Cleanup instrumentation data
     * covpatch.cleanup();
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
     * const covpatch = require(ReplicatedStorage.covpatch);
     *
     * // Run your tests...
     *
     * // Generate and export coverage report
     * const report = covpatch.istanbul();
     * const json = HttpService.JSONEncode(report);
     * // Write json to file or send to external service
     * ```
     */
    istanbul(): IstanbulReport;
}

declare const covpatch: CovPatch;
export = covpatch;
