local framework = require("./framework")
local expect = framework.expect
local describe = framework.describe
local ensureCoverage = require("../src/ensureCoverage")

describe("ensureCoverage", function()
	_G.__COVERAGE__ = nil
	local coverage = ensureCoverage()
	expect(type(coverage)).toBe("table")
	expect(type(coverage.hits)).toBe("table")
	expect(coverage.nextId).toBe(1)
	-- Call again to test existing
	local coverage2 = ensureCoverage()
	expect(coverage).toBe(coverage2)
end)

describe("ensureCoverage multiple calls", function()
	_G.__COVERAGE__ = nil
	local coverage1 = ensureCoverage()
	local coverage2 = ensureCoverage()
	expect(coverage1).toBe(coverage2)
	expect(coverage2.nextId).toBe(coverage1.nextId)
end)

describe("ensureCoverage with existing data", function()
	_G.__COVERAGE__ = {
		hits = { [1] = 5 },
		map = { [1] = { file = "test.lua", line = 1 } },
		nextId = 2,
		f = { [1] = 3 },
		fnMap = { [1] = { name = "test", line = 1, file = "test.lua", loc = {} } },
		nextFnId = 2,
		b = {},
		branchMap = {},
		nextBranchId = 1,
	}
	local coverage = ensureCoverage()
	expect(coverage.nextId).toBe(2)
	expect(coverage.nextFnId).toBe(2)
	expect(coverage.hits[1]).toBe(5)
end)

describe("ensureCoverage coverage functions exist", function()
	ensureCoverage()
	expect(type(_G.__covhit)).toBe("function")
	expect(type(_G.__covfn)).toBe("function")
	expect(type(_G.__covbranch)).toBe("function")
end)