local ensureCoverage = require("@self/ensureCoverage")
local parser = require("@self/parser")
local coverage = {}

function getModulesInIntersection(include: { Instance }, exclude: { Instance }): { ModuleScript }
	local includedModules = {}
	for _, includeRoot in ipairs(include) do
		for _, module in ipairs(includeRoot:GetDescendants()) do
			if module:IsA("ModuleScript") then
				includedModules[module] = true
			end
		end
	end

	for _, excludeRoot in ipairs(exclude) do
		if excludeRoot then
			for _, module in ipairs(excludeRoot:GetDescendants()) do
				if module:IsA("ModuleScript") then
					includedModules[module] = nil
				end
			end
			-- Also exclude the root itself if it's a ModuleScript
			if excludeRoot:IsA("ModuleScript") then
				includedModules[excludeRoot] = nil
			end
		end
	end

	local result = {}
	for module, _ in pairs(includedModules) do
		table.insert(result, module)
	end
	return result
end

-- Instrument all modules in the specified include/exclude sets
function coverage.instrument(include, exclude)
	local coverageData = ensureCoverage()

	exclude = exclude or {
		game:GetService("ReplicatedStorage"):FindFirstChild("Packages"),
	}

	-- Always exclude the coverage patch folder itself
	local coverageFolder = game:GetService("ReplicatedStorage"):FindFirstChild("coverage")
	if coverageFolder then
		table.insert(exclude, script)
	end

	local modules = getModulesInIntersection(include or {
		game:GetService("ServerScriptService"),
		game:GetService("ReplicatedStorage"),
		game:GetService("ServerStorage"),
		game:GetService("StarterPlayer"),
		game:GetService("StarterGui"),
	}, exclude)

	for _, module in ipairs(modules) do
		parser.instrumentModule(module, game, coverageData)
	end
end

-- Generate Istanbul-compatible coverage report
function coverage.istanbul()
	local coverageData = ensureCoverage()
	local report = {}

	-- Process statements
	for id, location in pairs(coverageData.map) do
		local file = location.file
		if not report[file] then
			report[file] = {
				path = file,
				statementMap = {},
				fnMap = {},
				branchMap = {},
				s = {},
				f = {},
				b = {},
			}
		end
		local hits = coverageData.hits[id] or 0
		report[file].statementMap[tostring(id)] = {
			start = { line = location.line, column = 0 },
			["end"] = { line = location.line, column = 0 },
		}
		report[file].s[tostring(id)] = hits
	end

	-- Process functions
	for fnId, fnData in pairs(coverageData.fnMap) do
		local file = fnData.file
		if file then
			if not report[file] then
				report[file] = {
					path = file,
					statementMap = {},
					fnMap = {},
					branchMap = {},
					s = {},
					f = {},
					b = {},
				}
			end

			local hits = coverageData.f[fnId] or 0
			report[file].fnMap[tostring(fnId)] = {
				name = fnData.name,
				decl = {
					start = { line = fnData.line, column = 0 },
					["end"] = { line = fnData.line, column = 0 },
				},
				loc = fnData.loc,
				line = fnData.line,
			}
			report[file].f[tostring(fnId)] = hits
		end
	end

	-- Process branches
	for branchId, branchData in pairs(coverageData.branchMap) do
		local file = branchData.file
		if file and branchData.locations and #branchData.locations > 0 then
			if not report[file] then
				report[file] = {
					path = file,
					statementMap = {},
					fnMap = {},
					branchMap = {},
					s = {},
					f = {},
					b = {},
				}
			end

			-- Build location array for this branch, filtering out invalid entries
			local locations = {}
			for i, loc in ipairs(branchData.locations) do
				if loc and loc.start and loc["end"] then
					table.insert(locations, loc)
				end
			end

			-- Only add branch if it has valid locations
			if #locations >= 2 then
				report[file].branchMap[tostring(branchId)] = {
					type = branchData.type,
					line = branchData.line,
					loc = locations[1], -- lcov expects a loc instead of locations
					locations = locations,
				}

				-- Get hit counts for each path
				local branchHits = coverageData.b[branchId] or {}
				local hitArray = {}
				for i = 1, #locations do
					table.insert(hitArray, branchHits[i - 1] or 0)
				end
				report[file].b[tostring(branchId)] = hitArray
			end
		end
	end

	return report
end

-- Analyze collected hits to surface hotspots and potential runtime bottlenecks
-- Options:
--   limit (number?): max entries per category (default 10)
--   minHits (number?): minimum hit count to include (default 1)
--   includeStatements/includeFunctions/includeBranches (boolean?): category toggles
function coverage.runtimeStats(options)
	local coverageData = ensureCoverage()
	options = options or {}
	local limit = options.limit or 10
	local minHits = options.minHits or 1
	local includeStatements = options.includeStatements ~= false
	local includeFunctions = options.includeFunctions ~= false
	local includeBranches = options.includeBranches ~= false

	local function takeTop(items)
		table.sort(items, function(a, b)
			if a.hits ~= b.hits then
				return a.hits > b.hits
			end
			local af = tostring(a.file or "")
			local bf = tostring(b.file or "")
			if af ~= bf then
				return af < bf
			end
			return (a.line or 0) < (b.line or 0)
		end)
		local result = {}
		for i = 1, math.min(limit, #items) do
			result[i] = items[i]
		end
		return result
	end

	local stats = {
		totals = {
			statements = { points = 0, hits = 0 },
			functions = { points = 0, hits = 0 },
			branches = { points = 0, hits = 0 },
		},
		topStatements = {},
		topFunctions = {},
		topBranches = {},
		hotFiles = {},
	}

	local fileTotals = {}

	if includeStatements and coverageData.hits and coverageData.map then
		for id, hits in pairs(coverageData.hits) do
			local info = coverageData.map[id]
			if info and hits >= minHits then
				stats.totals.statements.points += 1
				stats.totals.statements.hits += hits
				table.insert(stats.topStatements, {
					id = id,
					hits = hits,
					file = info.file,
					line = info.line,
				})

				if info.file then
					fileTotals[info.file] = (fileTotals[info.file] or 0) + hits
				end
			end
		end
		stats.topStatements = takeTop(stats.topStatements)
	end

	if includeFunctions and coverageData.f and coverageData.fnMap then
		for fnId, hits in pairs(coverageData.f) do
			local info = coverageData.fnMap[fnId]
			if info and hits >= minHits then
				stats.totals.functions.points += 1
				stats.totals.functions.hits += hits
				table.insert(stats.topFunctions, {
					id = fnId,
					name = info.name,
					hits = hits,
					file = info.file,
					line = info.line,
				})

				if info.file then
					fileTotals[info.file] = (fileTotals[info.file] or 0) + hits
				end
			end
		end
		stats.topFunctions = takeTop(stats.topFunctions)
	end

	if includeBranches and coverageData.b and coverageData.branchMap then
		for branchId, hitPaths in pairs(coverageData.b) do
			local info = coverageData.branchMap[branchId]
			if info then
				local totalHits = 0
				for _, h in pairs(hitPaths) do
					totalHits += h or 0
				end

				if totalHits >= minHits then
					stats.totals.branches.points += 1
					stats.totals.branches.hits += totalHits
					table.insert(stats.topBranches, {
						id = branchId,
						type = info.type,
						hits = totalHits,
						file = info.file,
						line = info.line,
						paths = hitPaths,
					})

					if info.file then
						fileTotals[info.file] = (fileTotals[info.file] or 0) + totalHits
					end
				end
			end
		end
		stats.topBranches = takeTop(stats.topBranches)
	end

	for file, hits in pairs(fileTotals) do
		table.insert(stats.hotFiles, { file = file, hits = hits })
	end
	stats.hotFiles = takeTop(stats.hotFiles)

	return stats
end

-- Revert all instrumented modules back to their original state
function coverage.cleanup()
	local coverageData = ensureCoverage()

	for _, moduleInfo in ipairs(coverageData.originals) do
		if moduleInfo.wasReplaced then
			-- Module was replaced with a patched version
			-- Destroy the patched module and restore the original name
			if moduleInfo.patchedModule then
				pcall(function()
					moduleInfo.patchedModule:Destroy()
				end)
			end

			if moduleInfo.module then
				pcall(function()
					-- Restore original name (remove __cov_orig suffix)
					local originalName = string.gsub(moduleInfo.module.Name, "__cov_orig$", "")
					moduleInfo.module.Name = originalName
				end)
			end
		else
			-- Module's Source was modified directly, restore it
			if moduleInfo.module and moduleInfo.originalSource then
				pcall(function()
					moduleInfo.module.Source = moduleInfo.originalSource
				end)
			end
		end
	end

	-- Clear the originals tracking
	coverageData.originals = {}
end

return coverage
