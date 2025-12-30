local parser = {}

export type Token = {
    kind: string,
    value: string,
    line: number,
}

local KEYWORDS = {
    ["and"] = true,
    ["break"] = true,
    ["do"] = true,
    ["else"] = true,
    ["elseif"] = true,
    ["end"] = true,
    ["false"] = true,
    ["for"] = true,
    ["function"] = true,
    ["if"] = true,
    ["in"] = true,
    ["local"] = true,
    ["nil"] = true,
    ["not"] = true,
    ["or"] = true,
    ["repeat"] = true,
    ["return"] = true,
    ["then"] = true,
    ["true"] = true,
    ["until"] = true,
    ["while"] = true,
}

local CLOSING_KEYWORDS = {
    ["end"] = true,
    ["else"] = true,
    ["elseif"] = true,
    ["until"] = true,
}

-- Normalize all newlines (CRLF and CR) to LF
function parser.normalizeNewlines(src: string): string
    src = string.gsub(src, "\r\n", "\n")
    src = string.gsub(src, "\r", "\n")
    return src
end

-- Count newlines in a string chunk
function parser.countNewlines(chunk: string): number
    local _, n = string.gsub(chunk, "\n", "\n")
    return n
end

-- Split source into lines
function parser.splitLines(src: string): {string}
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

-- Long strings and block comments share the same delimiter pattern.
function parser.tryScanLong(src: string, i: number)
    local equalsCount = 0
    while string.sub(src, i + 1 + equalsCount, i + 1 + equalsCount) == "=" do
        equalsCount += 1
    end

    if string.sub(src, i + 1 + equalsCount, i + 1 + equalsCount) ~= "[" then
        return nil
    end

    local closing = "]" .. string.rep("=", equalsCount) .. "]"
    local startContent = i + 2 + equalsCount
    local closePos = string.find(src, closing, startContent, true)
    if not closePos then
        return #src + 1, 0
    end

    local content = string.sub(src, startContent, closePos - 1)
    local newlines = parser.countNewlines(content)
    return closePos + #closing, newlines
end

function parser.tokenize(src: string): {Token}
    local tokens = {}
    local i = 1
    local line = 1
    local len = #src

    local function push(kind: string, value: string)
        tokens[#tokens + 1] = { kind = kind, value = value, line = line }
    end

    while i <= len do
        local ch = string.sub(src, i, i)

        if ch == " " or ch == "\t" then
            i += 1
        elseif ch == "\n" then
            line += 1
            i += 1
        elseif ch == "-" and string.sub(src, i + 1, i + 1) == "-" then
            -- Comment: line or block
            if string.sub(src, i + 2, i + 2) == "[" then
                local nextIndex, nl = parser.tryScanLong(src, i + 2)
                if nextIndex then
                    line += nl
                    i = nextIndex
                else
                    i = i + 2
                end
            else
                while i <= len and string.sub(src, i, i) ~= "\n" do
                    i += 1
                end
            end
        elseif ch == "'" or ch == '"' then
            local quote = ch
            i += 1
            while i <= len do
                local c = string.sub(src, i, i)
                if c == "\\" then
                    i += 2
                elseif c == quote then
                    i += 1
                    break
                else
                    if c == "\n" then
                        line += 1
                    end
                    i += 1
                end
            end
            push("string", "")
        elseif ch == "[" then
            local nextIndex, nl = parser.tryScanLong(src, i)
            if nextIndex then
                line += nl
                i = nextIndex
                push("string", "")
            else
                push("symbol", ch)
                i += 1
            end
        elseif string.match(ch, "%d") then
            local start = i
            i += 1
            while i <= len and string.match(string.sub(src, i, i), "[%d%.eE+-]") do
                i += 1
            end
            push("number", string.sub(src, start, i - 1))
        elseif string.match(ch, "[A-Za-z_]") then
            local start = i
            i += 1
            while i <= len and string.match(string.sub(src, i, i), "[A-Za-z0-9_]") do
                i += 1
            end
            local word = string.sub(src, start, i - 1)
            if KEYWORDS[word] then
                push("keyword", word)
            else
                push("identifier", word)
            end
        else
            -- Prefer the longest match to stay close to Luau's lexer rules.
            if string.sub(src, i, i + 2) == "..." then
                push("symbol", "...")
                i += 3
            else
                local two = string.sub(src, i, i + 1)
                if two == "==" or two == "~=" or two == "<=" or two == ">=" or two == "//" or two == ".." or two == "::" then
                    push("symbol", two)
                    i += 2
                else
                    push("symbol", ch)
                    i += 1
                end
            end
        end
    end

    return tokens
end

-- Calculate the first token on each line
function parser.firstTokenPerLine(tokens: {Token}): {[number]: Token}
    local lookup = {}
    for _, token in ipairs(tokens) do
        if not lookup[token.line] then
            lookup[token.line] = token
        end
    end
    return lookup
end

-- Determine if a line should be instrumented
function parser.shouldInstrument(token: Token?): boolean
    if not token then
        return false
    end
    if CLOSING_KEYWORDS[token.value] then
        return false
    end
    if KEYWORDS[token.value] then
        return true
    end
    return false
end

-- Instrument source code by injecting coverage hit calls
function parser.instrumentSource(source: string, filePath: string, coverage)
    source = parser.normalizeNewlines(source)
    local tokens = parser.tokenize(source)
    local firstTokens = parser.firstTokenPerLine(tokens)
    local lines = parser.splitLines(source)
    local instrumented = {}
    local added = 0

    for lineNo, text in ipairs(lines) do
        local token = firstTokens[lineNo]
        if parser.shouldInstrument(token) then
            local trimmed = string.match(text, "^%s*(.-)$") or ""
            if trimmed ~= "" then
                local indent = string.match(text, "^(%s*)") or ""
                local id = coverage.nextId
                coverage.nextId += 1
                coverage.map[id] = { file = filePath, line = lineNo }
                instrumented[#instrumented + 1] = indent .. "_G.__covhit(" .. tostring(id) .. "); " .. trimmed
                added += 1
            else
                instrumented[#instrumented + 1] = text
            end
        else
            instrumented[#instrumented + 1] = text
        end
    end

    local result = table.concat(instrumented, "\n")
    return result, added
end

-- Compute module path relative to a stopAt ancestor
function parser.computeModulePath(module: Instance, stopAt: Instance?): string
    local parts = {}
    local current: Instance? = module
    while current and current ~= stopAt do
        table.insert(parts, 1, current.Name)
        current = current.Parent
    end
    return table.concat(parts, "/")
end

-- Ensure global coverage table and hit function exist
function parser.ensureCoverage()
    local coverage = _G.__COVERAGE__
    if not coverage then
        coverage = { hits = {}, map = {}, nextId = 1 }
        _G.__COVERAGE__ = coverage
    elseif not coverage.nextId then
        local maxId = 0
        for id in pairs(coverage.map) do
            if id > maxId then
                maxId = id
            end
        end
        coverage.nextId = maxId + 1
    end

    function _G.__covhit(id: number)
        local hits = coverage.hits
        hits[id] = (hits[id] or 0) + 1
    end

    return coverage
end

-- Instrument a ModuleScript's source code
function parser.instrumentModule(module: ModuleScript, root: Instance, coverage)
    local ok, source = pcall(function()
        return module.Source
    end)
    if not ok or type(source) ~= "string" then
        return
    end

    local path = parser.computeModulePath(module, root)
    local instrumented, added = parser.instrumentSource(source, path, coverage)
    if added == 0 then
        return
    end

    local setOk = pcall(function()
        module.Source = instrumented
    end)

    if not setOk then
        local parent = module.Parent
        local originalName = module.Name
        module.Name = originalName .. "__cov_orig"

        local patched = Instance.new("ModuleScript")
        patched.Name = originalName
        patched.Source = instrumented
        patched.Parent = parent
    end
end

return parser