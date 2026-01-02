local countNewlines = require("./countNewlines")

--- Long strings and block comments share the same delimiter pattern.
function tryScanLong(src: string, i: number)
	local equalsCount = 0
	while string.sub(src, i + 1 + equalsCount, i + 1 + equalsCount) == "=" do
		equalsCount += 1
	end

	if string.sub(src, i + 1 + equalsCount, i + 1 + equalsCount) ~= "[" then
		return nil
	end

	local closing = "]" .. string.rep("=", equalsCount) .. "]"
	local startContent = i + 2 + equalsCount
	local closeStart, closeEnd = string.find(src, closing, startContent, true)
	if not closeStart then
		return #src + 1, 0
	end

	local content = string.sub(src, startContent, closeStart - 1)
	local newlines = countNewlines(content)
	return closeEnd + 1, newlines
end

return tryScanLong