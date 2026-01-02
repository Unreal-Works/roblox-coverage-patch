--- Ensure global coverage table and hit function exist.
--- Creates `_G.__COVERAGE__`, `_G.__covhit`, `_G.__covfn`, and `_G.__covbranch`
function ensureCoverage()
	local coverage = _G.__COVERAGE__
	if not coverage then
		coverage = {
			hits = {},
			map = {},
			nextId = 1,
			f = {},
			fnMap = {},
			nextFnId = 1,
			b = {},
			branchMap = {},
			nextBranchId = 1,
			originals = {},
		}
		_G.__COVERAGE__ = coverage
	else
		-- Initialize missing fields
		if not coverage.originals then
			coverage.originals = {}
		end
		if not coverage.nextId then
			local maxId = 0
			for id in pairs(coverage.map) do
				if id > maxId then
					maxId = id
				end
			end
			coverage.nextId = maxId + 1
		end
		if not coverage.f then
			coverage.f = {}
		end
		if not coverage.fnMap then
			coverage.fnMap = {}
		end
		if not coverage.nextFnId then
			local maxFnId = 0
			for id in pairs(coverage.fnMap) do
				if id > maxFnId then
					maxFnId = id
				end
			end
			coverage.nextFnId = maxFnId + 1
		end
		if not coverage.b then
			coverage.b = {}
		end
		if not coverage.branchMap then
			coverage.branchMap = {}
		end
		if not coverage.nextBranchId then
			local maxBranchId = 0
			for id in pairs(coverage.branchMap) do
				if id > maxBranchId then
					maxBranchId = id
				end
			end
			coverage.nextBranchId = maxBranchId + 1
		end
	end

	function _G.__covhit(id: number)
		local hits = coverage.hits
		hits[id] = (hits[id] or 0) + 1
	end

	function _G.__covfn(fnId: number)
		local f = coverage.f
		f[fnId] = (f[fnId] or 0) + 1
	end

	function _G.__covbranch(branchId: number, pathIndex: number)
		local b = coverage.b
		if not b[branchId] then
			b[branchId] = {}
		end
		local path = b[branchId]
		path[pathIndex] = (path[pathIndex] or 0) + 1

		-- Return a function that returns the value (for ternary expressions)
		return function(value: any)
			return value
		end
	end

	return coverage
end

return ensureCoverage