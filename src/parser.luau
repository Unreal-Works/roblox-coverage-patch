local parser = {}

export type Token = {
    kind: string,
    value: string,
    line: number,
}

-- Extract function name from tokens following 'function' keyword
function parser.extractFunctionName(tokens: {Token}, startIndex: number): string
    local i = startIndex
    if i > #tokens then
        return "<anonymous>"
    end
    
    local nameParts = {}
    local token = tokens[i]
    
    -- Handle: function name(...) or function obj.name(...) or function obj:name(...)
    if token.kind == "identifier" then
        table.insert(nameParts, token.value)
        i += 1
        
        -- Check for . or : for method/nested names
        while i <= #tokens do
            local sep = tokens[i]
            if sep.kind == "symbol" and (sep.value == "." or sep.value == ":") then
                table.insert(nameParts, sep.value)
                i += 1
                if i <= #tokens and tokens[i].kind == "identifier" then
                    table.insert(nameParts, tokens[i].value)
                    i += 1
                else
                    break
                end
            else
                break
            end
        end
        
        return table.concat(nameParts, "")
    end
    
    return "<anonymous>"
end

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
    local stmtAdded = 0
    local fnAdded = 0
    
    -- Build token index lookup
    local tokensByLine = {}
    for idx, token in ipairs(tokens) do
        if not tokensByLine[token.line] then
            tokensByLine[token.line] = {}
        end
        table.insert(tokensByLine[token.line], {index = idx, token = token})
    end

    -- Track which lines have function instrumentation
    local functionInstrumentedLines = {}
    
    -- Track which lines have branch instrumentation
    local branchInstrumentedLines = {}
    local branchAdded = 0
    
    -- First pass: detect and instrument functions
    for idx, token in ipairs(tokens) do
        if token.kind == "keyword" and token.value == "function" then
            -- Extract function name
            local funcName = parser.extractFunctionName(tokens, idx + 1)
            
            -- Find the line after the function declaration (after opening paren or first line of body)
            -- We need to find the line right after 'function name(params)' which would be the first body line
            local bodyLineNo = nil
            local parenDepth = 0
            local foundParen = false
            
            for i = idx + 1, #tokens do
                local t = tokens[i]
                if t.kind == "symbol" and t.value == "(" then
                    foundParen = true
                    parenDepth += 1
                elseif t.kind == "symbol" and t.value == ")" then
                    parenDepth -= 1
                    if parenDepth == 0 and foundParen then
                        -- Found end of parameter list, next line is body start
                        -- Look for the next token that's on a different line
                        if i + 1 <= #tokens then
                            local nextToken = tokens[i + 1]
                            -- If next token is on same line, we need to inject on that line
                            -- Otherwise inject on the next line
                            bodyLineNo = nextToken.line
                            break
                        end
                    end
                end
            end
            
            -- If we couldn't find params, just use next line after function keyword
            if not bodyLineNo then
                bodyLineNo = token.line + 1
            end
            
            -- Register function
            local fnId = coverage.nextFnId
            coverage.nextFnId += 1
            coverage.fnMap[fnId] = {
                name = funcName,
                line = token.line,                file = filePath,                loc = { start = { line = token.line, column = 0 }, ["end"] = { line = token.line, column = 0 } }
            }
            
            -- Mark this line for function instrumentation
            if not functionInstrumentedLines[bodyLineNo] then
                functionInstrumentedLines[bodyLineNo] = {}
            end
            table.insert(functionInstrumentedLines[bodyLineNo], fnId)
        end
    end
    
    -- Second pass: detect if/elseif/else branches
    local i = 1
    while i <= #tokens do
        local token = tokens[i]
        if token.kind == "keyword" and token.value == "if" then
            -- Found an if statement, track all branches
            local branchId = coverage.nextBranchId
            coverage.nextBranchId += 1
            
            local branchLocations = {}
            local branchLines = {}
            
            -- Find the 'then' for the if branch
            local thenIdx = nil
            for j = i + 1, #tokens do
                if tokens[j].kind == "keyword" and tokens[j].value == "then" then
                    thenIdx = j
                    break
                end
            end
            
            if thenIdx then
                -- First branch starts after 'then'
                local firstBranchLine = nil
                if thenIdx + 1 <= #tokens then
                    firstBranchLine = tokens[thenIdx + 1].line
                end
                
                if firstBranchLine then
                    table.insert(branchLines, {line = firstBranchLine, pathIndex = 0})
                    table.insert(branchLocations, {start = {line = firstBranchLine, column = 0}, ["end"] = {line = firstBranchLine, column = 0}})
                end
                
                -- Look for elseif/else/end to find other branches
                local depth = 1
                local j = thenIdx + 1
                local foundElse = false
                
                while j <= #tokens and depth > 0 do
                    local t = tokens[j]
                    if t.kind == "keyword" then
                        if t.value == "if" then
                            depth += 1
                        elseif t.value == "end" then
                            depth -= 1
                            if depth == 0 then
                                -- Reached the end of this if statement
                                -- If we never found an else, add implicit else branch
                                if not foundElse then
                                    table.insert(branchLocations, {start = {line = t.line, column = 0}, ["end"] = {line = t.line, column = 0}})
                                end
                            end
                        elseif depth == 1 and t.value == "elseif" then
                            -- Find the 'then' after elseif
                            local elseifThenIdx = nil
                            for k = j + 1, #tokens do
                                if tokens[k].kind == "keyword" and tokens[k].value == "then" then
                                    elseifThenIdx = k
                                    break
                                end
                            end
                            if elseifThenIdx and elseifThenIdx + 1 <= #tokens then
                                local elseifBranchLine = tokens[elseifThenIdx + 1].line
                                table.insert(branchLines, {line = elseifBranchLine, pathIndex = #branchLocations})
                                table.insert(branchLocations, {start = {line = elseifBranchLine, column = 0}, ["end"] = {line = elseifBranchLine, column = 0}})
                            end
                        elseif depth == 1 and t.value == "else" then
                            foundElse = true
                            -- Else branch starts on next line
                            if j + 1 <= #tokens then
                                local elseBranchLine = tokens[j + 1].line
                                table.insert(branchLines, {line = elseBranchLine, pathIndex = #branchLocations})
                                table.insert(branchLocations, {start = {line = elseBranchLine, column = 0}, ["end"] = {line = elseBranchLine, column = 0}})
                            end
                        end
                    end
                    j += 1
                end
                
                -- Register branch if we found at least 2 paths
                if #branchLocations >= 2 then
                    coverage.branchMap[branchId] = {
                        type = "if",
                        line = token.line,
                        file = filePath,
                        locations = branchLocations
                    }
                    
                    -- Mark lines for branch instrumentation
                    for _, branchInfo in ipairs(branchLines) do
                        if not branchInstrumentedLines[branchInfo.line] then
                            branchInstrumentedLines[branchInfo.line] = {}
                        end
                        table.insert(branchInstrumentedLines[branchInfo.line], {branchId = branchId, pathIndex = branchInfo.pathIndex})
                    end
                end
            end
        end
        i += 1
    end

    -- Third pass: generate instrumented source
    for lineNo, text in ipairs(lines) do
        local token = firstTokens[lineNo]
        local indent = string.match(text, "^(%s*)") or ""
        local trimmed = string.match(text, "^%s*(.-)$") or ""
        local modifications = {}
        
        -- Add branch instrumentation if needed
        if branchInstrumentedLines[lineNo] then
            for _, branchInfo in ipairs(branchInstrumentedLines[lineNo]) do
                table.insert(modifications, "_G.__covbranch(" .. tostring(branchInfo.branchId) .. ", " .. tostring(branchInfo.pathIndex) .. ");")
                branchAdded += 1
            end
        end
        
        -- Add function instrumentation if needed
        if functionInstrumentedLines[lineNo] then
            for _, fnId in ipairs(functionInstrumentedLines[lineNo]) do
                table.insert(modifications, "_G.__covfn(" .. tostring(fnId) .. ");")
                fnAdded += 1
            end
        end
        
        -- Add statement instrumentation if needed
        if parser.shouldInstrument(token) and trimmed ~= "" then
            local id = coverage.nextId
            coverage.nextId += 1
            coverage.map[id] = { file = filePath, line = lineNo }
            table.insert(modifications, "_G.__covhit(" .. tostring(id) .. ");")
            stmtAdded += 1
        end
        
        -- Combine modifications with original line
        if #modifications > 0 then
            local prefix = indent .. table.concat(modifications, " ")
            if trimmed ~= "" then
                instrumented[#instrumented + 1] = prefix .. " " .. trimmed
            else
                instrumented[#instrumented + 1] = prefix
            end
        else
            instrumented[#instrumented + 1] = text
        end
    end

    local result = table.concat(instrumented, "\n")
    return result, stmtAdded + fnAdded + branchAdded
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
        coverage = { 
            hits = {}, 
            map = {}, 
            nextId = 1,
            f = {},
            fnMap = {},
            nextFnId = 1,
            b = {},
            branchMap = {},
            nextBranchId = 1
        }
        _G.__COVERAGE__ = coverage
    else
        -- Initialize missing fields
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