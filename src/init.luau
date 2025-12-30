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
		for _, module in ipairs(excludeRoot:GetDescendants()) do
			if module:IsA("ModuleScript") then
				includedModules[module] = nil
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

	local modules = getModulesInIntersection(include or {
		game:GetService("ServerScriptService"),
		game:GetService("ReplicatedStorage"),
		game:GetService("ServerStorage"),
		game:GetService("StarterPlayer"),
		game:GetService("StarterGui"),
	}, exclude or {
		game:GetService("ReplicatedStorage"):FindFirstChild("Packages"),
	})

	for _, module in ipairs(modules) do
		parser.instrumentModule(module, game, coverage)
	end
end

-- Generate Istanbul-compatible coverage report
function covpatch.istanbul()
	local coverage = parser.ensureCoverage()
	local report = {}
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
	return report
end

return covpatch
