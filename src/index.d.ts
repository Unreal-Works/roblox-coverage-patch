export type CoverageLocation = {
	file: string;
	line: number;
};

export type CoverageSummary = {
	executed: number;
	total: number;
	lines: Record<number, number>;
};

export type CoverageResult = {
	hits: Record<number, number>;
	map: Record<number, CoverageLocation>;
	nextId: number;
	summary?: Record<string, CoverageSummary>;
};

declare const covpatch: {
	run(): void;
	finalize(): CoverageResult;
};

export = covpatch;
