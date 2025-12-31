local parser = {}

export type Token = {
    kind: string,
    value: string,
    line: number,
}

--- Extract function name from tokens following 'function' keyword
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

--- Normalize all newlines (CRLF and CR) to LF
function parser.normalizeNewlines(src: string): string
    src = string.gsub(src, "\r\n", "\n")
    src = string.gsub(src, "\r", "\n")
    return src
end

--- Count newlines in a string chunk
function parser.countNewlines(chunk: string): number
    local _, n = string.gsub(chunk, "\n", "\n")
    return n
end

--- Split source into lines
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

--- Long strings and block comments share the same delimiter pattern.
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
    local closeStart, closeEnd = string.find(src, closing, startContent, true)
    if not closeStart then
        return #src + 1, 0
    end

    local content = string.sub(src, startContent, closeStart - 1)
    local newlines = parser.countNewlines(content)
    return closeEnd + 1, newlines
end

--- Tokenize source code into a list of tokens
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
    -- Don't instrument function definitions/literals
    if token.kind == "keyword" and token.value == "function" then
        return false
    end
    -- Don't instrument if statements
    if token.kind == "keyword" and token.value == "if" then
        return false
    end
    -- Don't instrument bare literal values (true, false, nil)
    if token.value == "true" or token.value == "false" or token.value == "nil" then
        return false
    end
    if KEYWORDS[token.value] then
        return true
    end
    return false
end

--- Replace ternary expression with instrumented version
local function replaceTernaryExpression(lines: {string}, startLine: number, branchId: number): (string, number)
    -- For multi-line ternaries, collect the full expression
    local text = lines[startLine]
    local lineNum = startLine + 1
    local linesConsumed = 1
    
    -- Simple heuristic: collect lines until we find a line that doesn't look like continuation
    -- This is a simplified approach - in a real parser, we'd use proper expression parsing
    while lineNum <= #lines do
        local nextLine = lines[lineNum]
        local trimmed = nextLine:match("^%s*(.-)%s*$") or ""
        
        -- Stop if we find a keyword that indicates end of expression
        if trimmed:match("^local%s+") or trimmed:match("^return%s+") or trimmed:match("^end$") or 
           trimmed:match("^function%s+") or trimmed:match("^if%s+") or trimmed:match("^for%s+") or
           trimmed:match("^while%s+") or trimmed:match("^repeat%s+") or trimmed:match("^_G%.") then
            break
        end
        
        -- Stop if we find a symbol that typically ends expressions
        if trimmed:match("^[%)%]};]$") or trimmed:match("^,%s*$") then
            break
        end
        
        text = text .. "\n" .. nextLine
        lineNum = lineNum + 1
        linesConsumed = linesConsumed + 1
    end
    
    -- Now parse the collected text
    -- Find the positions more accurately
    local ifStart = text:find("if%s+")
    if not ifStart then return lines[startLine], 1 end
    local ifEnd = ifStart + 2  -- after "if"
    local conditionStart = ifEnd + 1
    
    local thenStart = text:find("then%s+", ifEnd)
    if not thenStart then return lines[startLine], 1 end
    local thenEnd = thenStart + 3  -- after "then"
    local thenExprStart = thenEnd + 1
    
    local elseStart = text:find("else%s+", thenEnd)
    if not elseStart then return lines[startLine], 1 end
    local elseEnd = elseStart + 3  -- after "else"
    local elseExprStart = elseEnd + 1
    
    -- Extract parts
    local beforeIf = text:sub(1, ifStart - 1)
    local condition = text:sub(conditionStart, thenStart - 1):match("^%s*(.-)%s*$") or ""
    local thenExpr = text:sub(thenExprStart, elseStart - 1):match("^%s*(.-)%s*$") or ""
    local elseExpr = text:sub(elseExprStart):match("^%s*(.-)%s*$") or ""
    
    -- Build the instrumented version
    local instrumented = string.format("%sif %s then _G.__covbranch(%d, 0)(%s) else _G.__covbranch(%d, 1)(%s)",
        beforeIf, condition, branchId, thenExpr, branchId, elseExpr)
    
    return instrumented, linesConsumed
end

--- Instrument source code by injecting coverage hit calls
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
    
    -- Track which lines have function declaration instrumentation
    local functionDeclarationLines = {}
    local branchInstrumentedLines = {}
    local branchAdded = 0
    
    -- Track which lines are inside if/elseif conditions (between if/elseif keyword and then keyword)
    local linesInCondition = {}
    
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
                        -- Found end of parameter list, now skip past return type annotation if present
                        local j = i + 1
                        
                        -- Skip past return type annotation (: returnType)
                        if j <= #tokens and tokens[j].kind == "symbol" and tokens[j].value == ":" then
                            j += 1
                            -- Skip the return type tokens until we find something that's not part of the type
                            local returnParenDepth = 0
                            while j <= #tokens do
                                local rt = tokens[j]
                                if rt.kind == "symbol" and rt.value == "(" then
                                    returnParenDepth += 1
                                    j += 1
                                elseif rt.kind == "symbol" and rt.value == ")" then
                                    if returnParenDepth == 0 then
                                        j += 1
                                        break
                                    else
                                        returnParenDepth -= 1
                                        j += 1
                                    end
                                elseif rt.kind == "symbol" and rt.value == "->" then
                                    j += 1
                                else
                                    -- Stop skipping type if we're not in parens
                                    if returnParenDepth == 0 then
                                        break
                                    end
                                    j += 1
                                end
                            end
                        end
                        
                        -- Now find the first actual statement in the function body
                        -- Skip to the first meaningful token that's not part of signature
                        while j <= #tokens do
                            local bt = tokens[j]
                            -- Find the first token that indicates actual code
                            if bt.kind == "keyword" then
                                if bt.value == "end" then
                                    bodyLineNo = bt.line
                                    break
                                elseif bt.value ~= "nil" and bt.value ~= "true" and bt.value ~= "false" then
                                    -- Found a statement keyword (local, if, return, etc)
                                    bodyLineNo = bt.line
                                    break
                                end
                            elseif bt.kind == "identifier" then
                                -- Function call or assignment
                                bodyLineNo = bt.line
                                break
                            end
                            j += 1
                        end
                        break
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
                line = token.line,
                file = filePath,
                loc = { start = { line = token.line, column = 0 }, ["end"] = { line = token.line, column = 0 } }
            }
            
            -- Mark this line for function instrumentation
            functionDeclarationLines[token.line] = fnId
            
            -- Instrument function body unless it's an anonymous function on the same line as its declaration
            if funcName ~= "<anonymous>" or bodyLineNo ~= token.line then
                functionInstrumentedLines[bodyLineNo] = true
            end
        end
    end
    
    -- Second pass: detect if/elseif/else branches and mark condition lines
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
                -- Mark all lines between 'if' and 'then' as being in a condition
                local ifLine = token.line
                local thenLine = tokens[thenIdx].line
                if ifLine ~= thenLine then
                    for lineNum = ifLine, thenLine do
                        linesInCondition[lineNum] = true
                    end
                end
                
                -- First branch starts after 'then', but skip lines containing 'then'
                local firstBranchLine = nil
                if thenIdx + 1 <= #tokens then
                    local candidateLine = tokens[thenIdx + 1].line
                    -- If the candidate line contains 'then', find the next line
                    if candidateLine == tokens[thenIdx].line then
                        -- For ternary expressions on the same line, use the line containing 'if'
                        -- since we can't inject within the expression, we'll instrument the line
                        firstBranchLine = token.line  -- token is the 'if' keyword
                    else
                        firstBranchLine = candidateLine
                    end
                end
                
                if firstBranchLine then
                    table.insert(branchLines, {line = firstBranchLine, pathIndex = 0})
                    table.insert(branchLocations, {start = {line = firstBranchLine, column = 0}, ["end"] = {line = firstBranchLine, column = 0}})
                end
                
                -- Look for elseif/else/end to find other branches
                local depth = 1
                local j = thenIdx + 1
                local foundElse = false
                local isTernary = true  -- Assume ternary until we find 'end'
                
                while j <= #tokens and depth > 0 do
                    local t = tokens[j]
                    if t.kind == "keyword" then
                        if t.value == "if" then
                            depth += 1
                            isTernary = false  -- Nested if means this is not a simple ternary
                        elseif t.value == "end" then
                            depth -= 1
                            isTernary = false  -- Found end, so this is a statement if, not ternary
                            if depth == 0 then
                                -- Reached the end of this if statement
                                -- If we never found an else, add implicit else branch
                                if not foundElse then
                                    table.insert(branchLocations, {start = {line = t.line, column = 0}, ["end"] = {line = t.line, column = 0}})
                                end
                            end
                        elseif depth == 1 and t.value == "elseif" then
                            isTernary = false  -- elseif means this is a complex if statement
                            -- Find the 'then' after elseif
                            local elseifThenIdx = nil
                            for k = j + 1, #tokens do
                                if tokens[k].kind == "keyword" and tokens[k].value == "then" then
                                    elseifThenIdx = k
                                    break
                                end
                            end
                            
                            -- Mark all lines between 'elseif' and 'then' as being in a condition
                            local elseifLine = t.line
                            local elseifThenLine = elseifThenIdx and tokens[elseifThenIdx].line or t.line
                            if elseifLine ~= elseifThenLine then
                                for lineNum = elseifLine, elseifThenLine do
                                    linesInCondition[lineNum] = true
                                end
                            end
                            
                            if elseifThenIdx and elseifThenIdx + 1 <= #tokens then
                                local candidateLine = tokens[elseifThenIdx + 1].line
                                local elseifBranchLine
                                -- If the candidate line contains 'then', find the next line
                                if candidateLine == tokens[elseifThenIdx].line then
                                    -- Find the next token that's not on the same line as 'then'
                                    local k = elseifThenIdx + 1
                                    while k <= #tokens and tokens[k].line == tokens[elseifThenIdx].line do
                                        k += 1
                                    end
                                    if k <= #tokens then
                                        elseifBranchLine = tokens[k].line
                                    end
                                else
                                    elseifBranchLine = candidateLine
                                end
                                if elseifBranchLine then
                                    table.insert(branchLines, {line = elseifBranchLine, pathIndex = #branchLocations})
                                    table.insert(branchLocations, {start = {line = elseifBranchLine, column = 0}, ["end"] = {line = elseifBranchLine, column = 0}})
                                end
                            end
                        elseif depth == 1 and t.value == "else" then
                            foundElse = true
                            -- Else branch starts on next line, but skip lines containing 'else'
                            if j + 1 <= #tokens then
                                local candidateLine = tokens[j + 1].line
                                local elseBranchLine
                                -- If the candidate line contains 'else', find the next line
                                if candidateLine == t.line then
                                    -- For ternary expressions on the same line, use the line containing 'if'
                                    -- since we can't inject within the expression, we'll instrument the line
                                    elseBranchLine = token.line  -- token is the original 'if' keyword
                                else
                                    elseBranchLine = candidateLine
                                end
                                if elseBranchLine then
                                    table.insert(branchLines, {line = elseBranchLine, pathIndex = #branchLocations})
                                    table.insert(branchLocations, {start = {line = elseBranchLine, column = 0}, ["end"] = {line = elseBranchLine, column = 0}})
                                end
                            end
                        end
                    elseif isTernary and depth == 1 and foundElse then
                        -- For ternary expressions, we can stop when we find a token that indicates
                        -- the end of the expression (after finding else)
                        if t.kind == "symbol" and (t.value == ")" or t.value == "," or t.value == ";" or t.value == "]") then
                            -- End of ternary expression
                            depth = 0
                        elseif t.kind == "keyword" and (t.value == "local" or t.value == "return" or t.value == "end" or t.value == "function") then
                            -- End of ternary expression
                            depth = 0
                        end
                    end
                    j += 1
                end
                
                -- For ternary expressions, if we reached the end of tokens and found else, we're done
                if isTernary and foundElse and j > #tokens then
                    depth = 0
                end
                
                -- Register branch if we found at least 2 paths
                if #branchLocations >= 2 then
                    coverage.branchMap[branchId] = {
                        type = "if",
                        line = token.line,
                        file = filePath,
                        locations = branchLocations,
                        isTernary = isTernary
                    }
                    
                    -- For ternary expressions, mark the 'if' line for both branches
                    if isTernary then
                        branchLines = {{line = token.line, pathIndex = 0}, {line = token.line, pathIndex = 1}}
                    end
                    
                    -- Mark lines for branch instrumentation
                    for _, branchInfo in ipairs(branchLines) do
                        if not branchInstrumentedLines[branchInfo.line] then
                            branchInstrumentedLines[branchInfo.line] = {}
                        end
                        table.insert(branchInstrumentedLines[branchInfo.line], {branchId = branchId, pathIndex = branchInfo.pathIndex, isTernary = isTernary})
                    end
                end
            end
        end
        i += 1
    end

    -- Third pass: generate instrumented source
    local lineNo = 1
    while lineNo <= #lines do
        local text = lines[lineNo]
        local token = firstTokens[lineNo]
        local indent = string.match(text, "^(%s*)") or ""
        local trimmed = string.match(text, "^%s*(.-)$") or ""
        local modifications = {}
        local linesToSkip = 0
        local isTernaryLine = false
        
        -- Add function declaration instrumentation if needed
        if functionDeclarationLines[lineNo] then
            local fnId = functionDeclarationLines[lineNo]
            table.insert(modifications, "_G.__covfn(" .. tostring(fnId) .. ");")
            fnAdded += 1
        end
        
        -- Add branch instrumentation if needed
        if branchInstrumentedLines[lineNo] then
            -- Check if this is a ternary expression line
            if #branchInstrumentedLines[lineNo] == 2 then
                local branchId1 = branchInstrumentedLines[lineNo][1].branchId
                local branchId2 = branchInstrumentedLines[lineNo][2].branchId
                if branchId1 == branchId2 then
                    isTernaryLine = true
                end
            end
            
            if isTernaryLine then
                -- For ternary expressions, inject branch calls within the expression
                local branchId = branchInstrumentedLines[lineNo][1].branchId
                
                -- Parse and replace ternary expression
                local newText, consumed = replaceTernaryExpression(lines, lineNo, branchId)
                
                if newText ~= lines[lineNo] then
                    text = newText
                    linesToSkip = consumed - 1  -- Skip the consumed lines
                    branchAdded += 2
                else
                    -- Fallback to line-level instrumentation if parsing fails
                    for _, branchInfo in ipairs(branchInstrumentedLines[lineNo]) do
                        table.insert(modifications, "_G.__covbranch(" .. tostring(branchInfo.branchId) .. ", " .. tostring(branchInfo.pathIndex) .. ");")
                        branchAdded += 1
                    end
                end
            else
                -- Normal branch instrumentation
                for _, branchInfo in ipairs(branchInstrumentedLines[lineNo]) do
                    table.insert(modifications, "_G.__covbranch(" .. tostring(branchInfo.branchId) .. ", " .. tostring(branchInfo.pathIndex) .. ");")
                    branchAdded += 1
                end
            end
        end
        
        -- Add function body instrumentation if needed
        if functionInstrumentedLines[lineNo] then
            local id = coverage.nextId
            coverage.nextId += 1
            coverage.map[id] = { file = filePath, line = lineNo }
            table.insert(modifications, "_G.__covhit(" .. tostring(id) .. ");")
            stmtAdded += 1
        end
        
        -- Add statement instrumentation if needed
        if (parser.shouldInstrument(token) and trimmed ~= "" and not linesInCondition[lineNo] and not functionInstrumentedLines[lineNo]) and not isTernaryLine then
            local id = coverage.nextId
            coverage.nextId += 1
            coverage.map[id] = { file = filePath, line = lineNo }
            table.insert(modifications, "_G.__covhit(" .. tostring(id) .. ");")
            stmtAdded += 1
        end
        
        -- Combine modifications with original line
        if #modifications > 0 then
            if functionDeclarationLines[lineNo] then
                -- For function declarations, append the modification, but insert before 'end' if present
                local modStr = table.concat(modifications, " ")
                if trimmed:find("end") then
                    local beforeEnd = trimmed:gsub("(%s*end%s*)$", "")
                    local endPart = trimmed:match("(%s*end%s*)$") or "end"
                    instrumented[#instrumented + 1] = indent .. beforeEnd .. " " .. modStr .. " " .. endPart:gsub("^%s*", "")
                else
                    instrumented[#instrumented + 1] = text .. " " .. modStr
                end
            else
                local prefix = indent .. table.concat(modifications, " ")
                if trimmed ~= "" then
                    instrumented[#instrumented + 1] = prefix .. " " .. trimmed
                else
                    instrumented[#instrumented + 1] = prefix
                end
            end
        else
            instrumented[#instrumented + 1] = text
        end
        
        lineNo = lineNo + 1 + linesToSkip
    end

    local result = table.concat(instrumented, "\n")
    return result, stmtAdded + fnAdded + branchAdded
end

--- Compute module path relative to a stopAt ancestor
function parser.computeModulePath(module: Instance, stopAt: Instance?): string
    local parts = {}
    local current: Instance? = module
    while current and current ~= stopAt do
        table.insert(parts, 1, current.Name)
        current = current.Parent
    end
    return table.concat(parts, "/")
end

--- Ensure global coverage table and hit function exist
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
            nextBranchId = 1,
            originals = {}
        }
        _G.__COVERAGE__ = coverage
    else
        -- Initialize missing fields
        if not coverage.originals then
            coverage.originals = {}
        end
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
        
        -- Return a function that returns the value (for ternary expressions)
        return function(value: any)
            return value
        end
    end

    return coverage
end

--- Instrument a ModuleScript's source code
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

    -- Save original state before instrumenting
    local moduleInfo = {
        module = module,
        originalSource = source,
        wasReplaced = false,
        patchedModule = nil
    }

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
        
        moduleInfo.wasReplaced = true
        moduleInfo.patchedModule = patched
    end
    
    -- Track this module for cleanup
    table.insert(coverage.originals, moduleInfo)
end

return parser