--- Count newlines in a string chunk
function countNewlines(chunk: string): number
    local _, n = string.gsub(chunk, "\n", "\n")
    return n
end

return countNewlines