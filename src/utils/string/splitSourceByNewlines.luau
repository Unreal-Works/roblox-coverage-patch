--- Split source into lines by newline characters
function splitSourceByNewlines(src: string): { string }
	local lines = {}
	local start = 1
	while true do
		local nl = string.find(src, "\n", start, true)
		if not nl then
			table.insert(lines, string.sub(src, start))
			break
		end
		table.insert(lines, string.sub(src, start, nl - 1))
		start = nl + 1
	end
	if #lines == 0 then
		table.insert(lines, "")
	end
	return lines
end

return splitSourceByNewlines