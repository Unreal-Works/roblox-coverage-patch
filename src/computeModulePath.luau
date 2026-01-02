--- Compute module path relative to a stopAt ancestor
--- For example, given a module structure like:
--- - Workspace
---   - Scripts
---     - MyModule
---
--- Calling computeModulePath(MyModule, Workspace) would return "Scripts/MyModule"
function computeModulePath(module: Instance, stopAt: Instance?): string
	local parts = {}
	local current: Instance? = module
	while current and current ~= stopAt do
		table.insert(parts, 1, current.Name)
		current = current.Parent
	end
	return table.concat(parts, "/")
end

return computeModulePath
