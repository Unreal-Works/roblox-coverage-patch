local parser = require(script.parser)
local covpatch = {}

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
function covpatch.instrument(include, exclude)
	local coverage = parser.ensureCoverage()

	exclude = exclude or {
        game:GetService("ReplicatedStorage"):FindFirstChild("Packages")
    }
	
	-- Always exclude the coverage patch folder itself
	local covpatchFolder = game:GetService("ReplicatedStorage"):FindFirstChild("covpatch")
	if covpatchFolder then
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
		parser.instrumentModule(module, game, coverage)
	end
end

-- Generate Istanbul-compatible coverage report
function covpatch.istanbul()
	local coverage = parser.ensureCoverage()
	local report = {}
	
	-- Process statements
	for id, location in pairs(coverage.map) do
		local file = location.file
		if not report[file] then
			report[file] = {
				path = file,
				statementMap = {},
				fnMap = {},
				branchMap = {},
				s = {},
				f = {},
				b = {}
			}
		end
		local hits = coverage.hits[id] or 0
		report[file].statementMap[tostring(id)] = {
			start = { line = location.line, column = 0 },
			["end"] = { line = location.line, column = 0 }
		}
		report[file].s[tostring(id)] = hits
	end
	
	-- Process functions
	for fnId, fnData in pairs(coverage.fnMap) do
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
					b = {}
				}
			end
			
			local hits = coverage.f[fnId] or 0
			report[file].fnMap[tostring(fnId)] = {
				name = fnData.name,
				decl = {
					start = { line = fnData.line, column = 0 },
					["end"] = { line = fnData.line, column = 0 }
				},
				loc = fnData.loc,
				line = fnData.line
			}
			report[file].f[tostring(fnId)] = hits
		end
	end
	
	-- Process branches
	for branchId, branchData in pairs(coverage.branchMap) do
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
					b = {}
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
					loc = locations[1],  -- lcov expects a loc instead of locations
					locations = locations
				}
				
				-- Get hit counts for each path
				local branchHits = coverage.b[branchId] or {}
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

return covpatch
