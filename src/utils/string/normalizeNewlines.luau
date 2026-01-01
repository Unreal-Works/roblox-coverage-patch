--- Normalize all newlines (CRLF and CR) to LF
function normalizeNewlines(src: string): string
    src = string.gsub(src, "\r\n", "\n")
    src = string.gsub(src, "\r", "\n")
    return src
end

return normalizeNewlines