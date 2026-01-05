local framework = require("./framework")
local expect = framework.expect
local describe = framework.describe
local coverage = require("../src")

local function dummyLoc()
	return { start = { line = 1, column = 0 }, ["end"] = { line = 1, column = 0 } }
end

describe("runtimeStats aggregates hotspots", function()
	_G.__COVERAGE__ = {
		hits = {
			[1] = 5,
			[2] = 10,
		},
		map = {
			[1] = { file = "src/A.luau", line = 3 },
			[2] = { file = "src/B.luau", line = 2 },
		},
		f = {
			[1] = 7,
			[2] = 1,
		},
		fnMap = {
			[1] = { name = "foo", file = "src/A.luau", line = 5, loc = dummyLoc() },
			[2] = { name = "bar", file = "src/C.luau", line = 1, loc = dummyLoc() },
		},
		b = {
			[1] = {
				[0] = 1,
				[1] = 3,
			},
		},
		branchMap = {
			[1] = {
				type = "if",
				file = "src/B.luau",
				line = 4,
				locations = { dummyLoc(), dummyLoc() },
			},
		},
		originals = {},
	}

	local stats = coverage.runtimeStats({ limit = 5 })

	expect(stats.totals.statements.points).toBe(2)
	expect(stats.totals.functions.points).toBe(2)
	expect(stats.totals.branches.points).toBe(1)
	expect(stats.totals.statements.hits).toBe(15)
	expect(stats.totals.functions.hits).toBe(8)
	expect(stats.totals.branches.hits).toBe(4)

	expect(stats.topStatements[1].id).toBe(2) -- highest hits first
	expect(stats.topFunctions[1].hits).toBe(7)
	expect(stats.topBranches[1].hits).toBe(4)

	expect(stats.hotFiles[1].file).toBe("src/B.luau") -- 10 (stmt) + 4 (branch)
	expect(stats.hotFiles[1].hits).toBe(14)
	expect(stats.hotFiles[2].file).toBe("src/A.luau")
	expect(stats.hotFiles[2].hits).toBe(12)
end)

describe("runtimeStats respects filters", function()
	_G.__COVERAGE__ = {
		hits = {
			[1] = 1,
		},
		map = {
			[1] = { file = "src/X.luau", line = 1 },
		},
		f = {
			[1] = 2,
		},
		fnMap = {
			[1] = { name = "onlyFn", file = "src/X.luau", line = 1, loc = dummyLoc() },
		},
		b = {
			[1] = {
				[0] = 1,
			},
		},
		branchMap = {
			[1] = { type = "if", file = "src/X.luau", line = 1, locations = { dummyLoc(), dummyLoc() } },
		},
		originals = {},
	}

	local stats = coverage.runtimeStats({ minHits = 2, includeBranches = false })

	expect(stats.topStatements[1]).toBeUndefined()
	expect(stats.topFunctions[1].hits).toBe(2)
	expect(stats.topBranches[1]).toBeUndefined()
	expect(stats.totals.branches.points).toBe(0)
	expect(stats.totals.branches.hits).toBe(0)
	expect(stats.hotFiles[1].file).toBe("src/X.luau")
	expect(stats.hotFiles[1].hits).toBe(2)
end)
