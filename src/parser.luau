local parser = {}

export type Token = {
    kind: string,
    value: string,
    line: number,
    column: number,
    index: number,
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
    ["continue"] = true,
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

local STATEMENT_KEYWORDS = {
    ["break"] = true,
    ["continue"] = true,
    ["do"] = true,
    ["for"] = true,
    ["local"] = true,
    ["repeat"] = true,
    ["return"] = true,
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

    local column = 0
    local function push(kind: string, value: string, startCol: number)
        table.insert(tokens, { 
            kind = kind, 
            value = value, 
            line = line, 
            column = startCol,
            index = #tokens + 1
        })
    end

    while i <= len do
        local ch = string.sub(src, i, i)
        local startCol = column

        if ch == " " or ch == "\t" then
            i += 1
            column += 1
        elseif ch == "\n" then
            line += 1
            column = 0
            i += 1
        elseif ch == "-" and string.sub(src, i + 1, i + 1) == "-" then
            local startI = i
            -- Comment: line or block
            if string.sub(src, i + 2, i + 2) == "[" then
                local nextIndex, nl = parser.tryScanLong(src, i + 2)
                if nextIndex then
                    local commentVal = string.sub(src, i, nextIndex - 1)
                    if nl > 0 then
                        line += nl
                        -- Find column of last line of comment
                        local lastNl = commentVal:find("\n[^\n]*$")
                        if lastNl then
                            column = #commentVal - lastNl
                        else
                            column += #commentVal
                        end
                    else
                        column += #commentVal
                    end
                    i = nextIndex
                else
                    i = i + 2
                    column += 2
                end
            else
                while i <= len and string.sub(src, i, i) ~= "\n" do
                    i += 1
                end
                -- We don't advance column here because it will stop at \n or EOF
                -- If it stops at \n, the \n case will handle it.
                -- However, we need to advance i and column for the text we skipped
                column += (i - startI)
            end
        elseif ch == "'" or ch == '"' then
            local startI = i
            local quote = ch
            i += 1
            column += 1
            while i <= len do
                local c = string.sub(src, i, i)
                if c == "\\" then
                    i += 2
                    column += 2
                elseif c == quote then
                    i += 1
                    column += 1
                    break
                else
                    if c == "\n" then
                        line += 1
                        column = 0
                    else
                        column += 1
                    end
                    i += 1
                end
            end
            push("string", string.sub(src, startI, i - 1), startCol)
        elseif ch == "[" then
            local startI = i
            local nextIndex, nl = parser.tryScanLong(src, i)
            if nextIndex then
                local strVal = string.sub(src, startI, nextIndex - 1)
                if nl > 0 then
                    line += nl
                    local lastNl = strVal:find("\n[^\n]*$")
                    if lastNl then
                        column = #strVal - lastNl
                    else
                        column += #strVal
                    end
                else
                    column += #strVal
                end
                i = nextIndex
                push("string", strVal, startCol)
            else
                push("symbol", ch, startCol)
                i += 1
                column += 1
            end
        elseif string.match(ch, "%d") then
            local start = i
            i += 1
            while i <= len and string.match(string.sub(src, i, i), "[%d%.eE+-]") do
                i += 1
            end
            local val = string.sub(src, start, i - 1)
            push("number", val, startCol)
            column += #val
        elseif string.match(ch, "[A-Za-z_]") then
            local start = i
            i += 1
            while i <= len and string.match(string.sub(src, i, i), "[A-Za-z0-9_]") do
                i += 1
            end
            local word = string.sub(src, start, i - 1)
            if KEYWORDS[word] then
                push("keyword", word, startCol)
            else
                push("identifier", word, startCol)
            end
            column += #word
        else
            -- Prefer the longest match to stay close to Luau's lexer rules.
            if string.sub(src, i, i + 2) == "..." then
                push("symbol", "...", startCol)
                i += 3
                column += 3
            else
                local two = string.sub(src, i, i + 1)
                if two == "==" or two == "~=" or two == "<=" or two == ">=" or two == "//" or two == ".." or two == "::" then
                    push("symbol", two, startCol)
                    i += 2
                    column += 2
                else
                    push("symbol", ch, startCol)
                    i += 1
                    column += 1
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
    if token.kind == "identifier" then
        return true
    end
    if token.kind == "keyword" then
        return STATEMENT_KEYWORDS[token.value] == true
    end
    if token.kind == "symbol" then
        return token.value == "(" or token.value == "{"
    end
    return false
end

--- Replace ternary expression with instrumented version
local function replaceTernaryExpression(lines: {string}, startLine: number, endLine: number, branchId: number, filePath: string, coverage, functionDeclarationLines, functionInstrumentedLines, linesInCondition, firstTokens, tokensByLine, tokens, branchData, lineHitIds): (string, number, number)
    local text = ""
    for i = startLine, math.min(endLine, #lines) do
        if i > startLine then text = text .. "\n" end
        text = text .. lines[i]
    end

    -- Helper to get offset within 'text' for a token
    local function getTokenOffset(tokenIdx)
        if not tokenIdx then return nil end
        local t = tokens[tokenIdx]
        local offset = 0
        for i = startLine, t.line - 1 do
            offset = offset + #lines[i] + 1 -- +1 for newline
        end
        return offset + t.column
    end

    local ifPos = getTokenOffset(branchData.ifTokenIdx)
    if not ifPos then return lines[startLine], 1, 0 end
    
    local thenPos = getTokenOffset(branchData.thenTokenIdx)
    if not thenPos then return lines[startLine], 1, 0 end
    local thenMatchEnd = thenPos + #tokens[branchData.thenTokenIdx].value
    local thenKeyword = text:sub(thenPos + 1, thenMatchEnd)
    
    local elsePos = getTokenOffset(branchData.elseIdx)
    if not elsePos then return lines[startLine], 1, 0 end
    local elseMatchEnd = elsePos + #tokens[branchData.elseIdx].value
    local elseKeyword = text:sub(elsePos + 1, elseMatchEnd)
    
    local endPos = getTokenOffset(branchData.endTokenIdx)
    if not endPos then return lines[startLine], 1, 0 end
    local elseExprEnd = endPos + #tokens[branchData.endTokenIdx].value
    
    -- Extract parts preserving EVERYTHING except where we inject
    local beforeThen = text:sub(1, thenPos)
    local thenToElse = text:sub(thenMatchEnd + 1, elsePos)
    local elseToEnd = text:sub(elseMatchEnd + 1, elseExprEnd)
    local afterTernary = text:sub(elseExprEnd + 1)
    
    -- Function to instrument internal expressions without recursion
    local function instrumentInternal(partText: string, partStartLine: number)
        local partLines = {}
        local current = partText
        local startIdx = 1
        while true do
            local nl = current:find("\n", startIdx, true)
            if not nl then table.insert(partLines, current:sub(startIdx)) break end
            table.insert(partLines, current:sub(startIdx, nl-1))
            startIdx = nl + 1
        end
        
        local addedCount = 0
        local result = {}
        for i, lineText in ipairs(partLines) do
            local currentLineNo = partStartLine + i - 1
            local modifications = {}
            local token = firstTokens[currentLineNo]
            local trimmed = lineText:match("^%s*(.-)%s*$") or ""
            local indent = lineText:match("^(%s*)") or ""
            
            if (currentLineNo ~= startLine) then
                if functionDeclarationLines[currentLineNo] then
                    local decls = functionDeclarationLines[currentLineNo]
                    local lineInsertions = {}
                    for _, decl in ipairs(decls) do
                        local t = tokens[decl.tokenIdx]
                        -- We need the column relative to the start of this partText line
                        -- Actually, for instrumentInternal, lineText is already one line.
                        -- We can find the token on this line.
                        local targetToken = nil
                        local tokensOnLine = tokensByLine[currentLineNo]
                        if tokensOnLine then
                            for _, ti in ipairs(tokensOnLine) do
                                if ti.index == decl.tokenIdx then
                                    targetToken = ti.token
                                    break
                                end
                            end
                        end

                        if targetToken then
                            local modStr = "_G.__covfn(" .. tostring(decl.id) .. ");"
                            table.insert(lineInsertions, { col = targetToken.column, text = modStr })
                            addedCount += 1
                        end
                    end

                    if #lineInsertions > 0 then
                        table.sort(lineInsertions, function(a, b) return a.col > b.col end)
                        local originalLine = lines[currentLineNo]
                        local newLine = originalLine
                        for _, ins in ipairs(lineInsertions) do
                            local tokenOnLine = nil
                            for _, ti in ipairs(tokensByLine[currentLineNo]) do
                                if ti.token.column == ins.col then
                                    tokenOnLine = ti.token
                                    break
                                end
                            end
                            if tokenOnLine then
                                local pos = tokenOnLine.column + #tokenOnLine.value
                                -- Adjust for indentation if we are using originalLine which has it
                                newLine = newLine:sub(1, pos) .. " " .. ins.text .. newLine:sub(pos + 1)
                            end
                        end
                        lineText = newLine
                    end
                    trimmed = lineText:match("^%s*(.-)%s*$") or ""
                    indent = lineText:match("^(%s*)") or ""
                end
                
                local markers = functionInstrumentedLines[currentLineNo]
                if markers then
                    local lineInsertions = {}
                    for _, marker in ipairs(markers) do
                        if marker.allocatedId then
                            local hitStr = "_G.__covhit(" .. tostring(marker.allocatedId) .. ");"
                            if marker.tokenIdx then
                                table.insert(lineInsertions, { col = tokens[marker.tokenIdx].column, tokenIdx = marker.tokenIdx, text = hitStr, priority = 2 })
                            else
                                table.insert(modifications, hitStr)
                            end
                            addedCount += 1
                        end
                    end
                    if #lineInsertions > 0 then
                        table.sort(lineInsertions, function(a, b) 
                            if a.col ~= b.col then return a.col > b.col end
                            return (a.priority or 0) > (b.priority or 0)
                        end)
                        local originalLine = lines[currentLineNo]
                        local newLine = originalLine
                        for _, ins in ipairs(lineInsertions) do
                            local tokenOnLine = nil
                            local tokensOnLine = tokensByLine[currentLineNo]
                            if tokensOnLine then
                                for _, ti in ipairs(tokensOnLine) do
                                    if ti.token.column == ins.col then
                                        tokenOnLine = ti.token
                                        break
                                    end
                                end
                            end
                            if tokenOnLine then
                                local pos = tokenOnLine.column + #tokenOnLine.value
                                newLine = newLine:sub(1, pos) .. " " .. ins.text .. newLine:sub(pos + 1)
                            end
                        end
                        lineText = newLine
                    end
                end

                local lineHitId = lineHitIds[currentLineNo]
                if lineHitId then
                    table.insert(modifications, "_G.__covhit(" .. tostring(lineHitId) .. ");")
                    addedCount += 1
                end
            end
            
            if #modifications > 0 then
                result[i] = indent .. table.concat(modifications, " ") .. " " .. trimmed
            else
                result[i] = lineText
            end
        end
        return table.concat(result, "\n"), addedCount
    end

    -- Helper to trim but keep track of shared coverage
    local function instrumentPart(part: string, partStartLine: number)
        local trimmed = part:match("^%s*(.-)%s*$") or ""
        local prefix = part:match("^(%s*)") or ""
        local suffix = part:match("(%s*)$") or ""
        local instrumented, added = instrumentInternal(trimmed, partStartLine)
        return instrumented, prefix, suffix, added
    end

    local _, thenLinesOffset = text:sub(1, thenMatchEnd):gsub("\n", "\n")
    local _, elseLinesOffset = text:sub(1, elseMatchEnd):gsub("\n", "\n")
    
    local instrumentedThen, prefixThen, suffixThen, thenAdded = instrumentPart(thenToElse, startLine + thenLinesOffset)
    local instrumentedElse, prefixElse, suffixElse, elseAdded = instrumentPart(elseToEnd, startLine + elseLinesOffset)
    
    -- Build the instrumented version by wrapping the results
    local instrumented = string.format("%s%s%s_G.__covbranch(%d, 0)(%s)%s%s%s_G.__covbranch(%d, 1)(%s)%s",
        beforeThen, thenKeyword, prefixThen, branchId, instrumentedThen, suffixThen, elseKeyword, prefixElse, branchId, instrumentedElse, suffixElse .. afterTernary)
    
    local _, linesConsumed = text:gsub("\n", "\n")
    linesConsumed = linesConsumed + 1
    
    return instrumented, linesConsumed, thenAdded + elseAdded
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
            local signatureEndLine = token.line
            local parenDepth = 0
            local foundParen = false
            local signatureEndTokenIdx = idx
            local j = nil
            
            for i = idx + 1, #tokens do
                local t = tokens[i]
                if t.kind == "symbol" and t.value == "(" then
                    foundParen = true
                    parenDepth += 1
                elseif t.kind == "symbol" and t.value == ")" then
                    parenDepth -= 1
                    if parenDepth == 0 and foundParen then
                        -- Found end of parameter list, now skip past return type annotation if present
                        j = i + 1
                        
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
                                elseif rt.kind == "symbol" and (rt.value == "." or rt.value == ":" or rt.value == "?" or rt.value == "|" or rt.value == "&" or rt.value == "{" or rt.value == "}" or rt.value == "[" or rt.value == "]" or rt.value == ",") then
                                    j += 1
                                elseif rt.kind == "identifier" then
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
                        
                        signatureEndTokenIdx = j - 1
                        signatureEndLine = tokens[signatureEndTokenIdx].line
                        
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
            if not functionDeclarationLines[signatureEndLine] then
                functionDeclarationLines[signatureEndLine] = {}
            end
            local lineTokens = tokensByLine[token.line]
            local isDefinition = false
            if funcName ~= "<anonymous>" then
                if firstTokens[token.line] == token then
                    isDefinition = true
                elseif lineTokens and lineTokens[1] and lineTokens[1].token.kind == "keyword" and lineTokens[1].token.value == "local" and lineTokens[2] and lineTokens[2].token == token then
                    isDefinition = true
                end
            end

            table.insert(functionDeclarationLines[signatureEndLine], { id = fnId, tokenIdx = signatureEndTokenIdx, isDefinition = isDefinition })
            
            -- Detect empty body
            local isEmpty = true
            local k = j or (signatureEndTokenIdx + 1)
            while k <= #tokens do
                local kt = tokens[k]
                if kt.kind == "keyword" and kt.value == "end" then
                    break
                end
                if kt.kind ~= "comment" then -- Lexer doesn't produce whitespace tokens, but check just in case
                    isEmpty = false
                    break
                end
                k += 1
            end

            -- Mark function body start line
            if not functionInstrumentedLines[bodyLineNo] then
                functionInstrumentedLines[bodyLineNo] = {}
            end
            
            if bodyLineNo == signatureEndLine then
                table.insert(functionInstrumentedLines[bodyLineNo], { tokenIdx = signatureEndTokenIdx, isEmpty = isEmpty, isDefinition = isDefinition })
            else
                table.insert(functionInstrumentedLines[bodyLineNo], { id = nil, isEmpty = isEmpty, isDefinition = isDefinition })
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
                
                -- Detect if this is an if expression based on context
                local firstOnLine = firstTokens[token.line]
                local isTernary = (firstOnLine ~= token)
                if not isTernary and i > 1 then
                    local prev = tokens[i - 1]
                    if prev.kind == "symbol" and (prev.value == "(" or prev.value == "{" or prev.value == "[" or prev.value == ",") then
                        isTernary = true
                    end
                end
                
                local elseIdx = nil
                local endTokenIdx = nil
                while j <= #tokens and depth > 0 do
                    local t = tokens[j]
                    
                    if isTernary and depth == 1 and foundElse then
                        -- For ternary expressions, we can stop when we find a token that indicates
                        -- the end of the expression (after finding else)
                        if t.kind == "symbol" and (t.value == ")" or t.value == "," or t.value == ";" or t.value == "]") then
                            endTokenIdx = j - 1
                            depth = 0
                            break
                        elseif t.kind == "keyword" and (t.value == "local" or t.value == "return" or t.value == "end" or t.value == "function") then
                            endTokenIdx = j - 1
                            depth = 0
                            break
                        end
                    end

                    if t.kind == "keyword" then
                        if t.value == "if" or t.value == "do" or t.value == "for" or t.value == "function" or t.value == "while" or t.value == "repeat" then
                            depth += 1
                        elseif t.value == "end" or t.value == "until" then
                            depth -= 1
                            if depth == 0 then
                                isTernary = false  -- Found end matching our 'if', so it's a statement
                                endTokenIdx = j
                                -- If we never found an else, add implicit else branch
                                if not foundElse then
                                    table.insert(branchLocations, {start = {line = t.line, column = 0}, ["end"] = {line = t.line, column = 0}})
                                end
                            end
                        elseif depth == 1 and t.value == "elseif" then
                            isTernary = false  -- current ternary replacement doesn't handle multiple branches
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
                            elseIdx = j
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
                    elseif t.kind == "symbol" then
                        if t.value == "(" or t.value == "{" or t.value == "[" then
                            depth += 1
                        elseif t.value == ")" or t.value == "}" or t.value == "]" then
                            depth -= 1
                        end
                    end
                    if depth > 0 then
                        j += 1
                    end
                end
                
                if not endTokenIdx then
                    endTokenIdx = math.min(j, #tokens)
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
                        isTernary = isTernary,
                        endLine = tokens[j-1].line,
                        ifTokenIdx = i,
                        thenTokenIdx = thenIdx,
                        elseIdx = elseIdx,
                        endTokenIdx = j - 1
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

    -- Pass 2.8: Allocate Hit IDs in order
    local lineHitIds = {}
    for lNo = 1, #lines do
        local token = firstTokens[lNo]
        local trimmed = lines[lNo]:match("^%s*(.-)$") or ""
        
        -- Identify if this is a function definition
        local isFunctionDefinition = false
        if functionDeclarationLines[lNo] then
            for _, decl in ipairs(functionDeclarationLines[lNo]) do
                if decl.isDefinition then
                    isFunctionDefinition = true
                    break
                end
            end
        end

        local isContinuation = false
        if token then
            local tokenInfoList = tokensByLine[lNo]
            local firstTokenInfo = tokenInfoList and tokenInfoList[1]
            if firstTokenInfo and firstTokenInfo.index > 1 then
                local prev = tokens[firstTokenInfo.index - 1]
                if prev.kind == "symbol" then
                    local v = prev.value
                    if v == "(" or v == "[" or v == "{" or v == "," or v == "=" or v == "+" or v == "-" or v == "*" or v == "/" or v == "//" or v == "%" or v == "^" or v == ".." or v == "==" or v == "~=" or v == "<" or v == ">" or v == "<=" or v == ">=" or v == "." or v == ":" or v == "::" or v == "->" then
                        isContinuation = true
                    end
                elseif prev.kind == "keyword" then
                    local v = prev.value
                    if v == "and" or v == "or" or v == "not" or v == "in" then
                        isContinuation = true
                    end
                end
            end
        end

        -- Check body hits first (they get higher priority for IDs if they are at the start of the line)
        if functionInstrumentedLines[lNo] then
            for _, marker in ipairs(functionInstrumentedLines[lNo]) do
                if not marker.isEmpty or marker.isDefinition then
                    local id = coverage.nextId
                    coverage.nextId += 1
                    coverage.map[id] = { file = filePath, line = lNo }
                    marker.allocatedId = id
                end
            end
        end

        -- Check statement hit
        if (parser.shouldInstrument(token) and trimmed ~= "" and not linesInCondition[lNo] and not isFunctionDefinition and not isContinuation and not functionInstrumentedLines[lNo] and not functionDeclarationLines[lNo]) then
            local id = coverage.nextId
            coverage.nextId += 1
            coverage.map[id] = { file = filePath, line = lNo }
            lineHitIds[lNo] = id
        end
    end

    -- Third pass: generate instrumented source
    local lineNo = 1
    while lineNo <= #lines do
        local text = lines[lineNo]
        local token = firstTokens[lineNo]
        local modifications = {}
        local linesToSkip = 0
        local lineHitId = lineHitIds[lineNo]
        local bodyHitMarkers = functionInstrumentedLines[lineNo]
        local isTernaryLine = false
        if branchInstrumentedLines[lineNo] and #branchInstrumentedLines[lineNo] >= 2 then
            local branchId1 = branchInstrumentedLines[lineNo][1].branchId
            local branchId2 = branchInstrumentedLines[lineNo][2].branchId
            if branchId1 == branchId2 then
                isTernaryLine = true
            end
        end

        -- Add function declaration instrumentation if needed handled in assembly logic below

        if isTernaryLine then
            -- Parse and replace ternary expression
            local branchInfo = branchInstrumentedLines[lineNo][1]
            local branchId = branchInfo.branchId
            local branchData = coverage.branchMap[branchId]
            
            local newText, consumed, internalAdded = replaceTernaryExpression(lines, lineNo, branchData.endLine, branchId, filePath, coverage, functionDeclarationLines, functionInstrumentedLines, linesInCondition, firstTokens, tokensByLine, tokens, branchData, lineHitIds)
            
            if newText ~= lines[lineNo] then
                text = newText
                linesToSkip = consumed - 1  -- Skip the consumed lines
                branchAdded += 2 + (internalAdded or 0)
            else
                -- Fallback to line-level instrumentation if parsing fails
                for _, bInfo in ipairs(branchInstrumentedLines[lineNo]) do
                    table.insert(modifications, "_G.__covbranch(" .. tostring(bInfo.branchId) .. ", " .. tostring(bInfo.pathIndex) .. ");")
                    branchAdded += 1
                end
            end
        else
            -- Normal branch instrumentation
            if branchInstrumentedLines[lineNo] then
                for _, bInfo in ipairs(branchInstrumentedLines[lineNo]) do
                    table.insert(modifications, "_G.__covbranch(" .. tostring(bInfo.branchId) .. ", " .. tostring(bInfo.pathIndex) .. ");")
                    branchAdded += 1
                end
            end
        end

        if lineHitId then
            table.insert(modifications, "_G.__covhit(" .. tostring(lineHitId) .. ");")
            stmtAdded += 1
        end

        local lineInsertions = {}
        if functionDeclarationLines[lineNo] then
            for _, decl in ipairs(functionDeclarationLines[lineNo]) do
                table.insert(lineInsertions, { col = tokens[decl.tokenIdx].column, tokenIdx = decl.tokenIdx, text = "_G.__covfn(" .. tostring(decl.id) .. ");", priority = 1 })
                fnAdded += 1
            end
        end
        if bodyHitMarkers then
            for _, marker in ipairs(bodyHitMarkers) do
                if marker.allocatedId then
                    local hitStr = "_G.__covhit(" .. tostring(marker.allocatedId) .. ");"
                    if marker.tokenIdx then
                        table.insert(lineInsertions, { col = tokens[marker.tokenIdx].column, tokenIdx = marker.tokenIdx, text = hitStr, priority = 2 })
                    else
                        table.insert(modifications, hitStr)
                    end
                    stmtAdded += 1
                end
            end
        end

        if #lineInsertions > 0 then
            table.sort(lineInsertions, function(a, b) 
                if a.col ~= b.col then return a.col > b.col end
                return (a.priority or 0) > (b.priority or 0)
            end)
            
            for _, ins in ipairs(lineInsertions) do
                local targetToken = tokens[ins.tokenIdx]
                local pos = targetToken.column + #targetToken.value
                text = text:sub(1, pos) .. " " .. ins.text .. text:sub(pos + 1)
            end
        end

        -- Combine modifications with original line
        if #modifications > 0 then
            local modStr = table.concat(modifications, " ")
            local currentIndent = string.match(text, "^(%s*)") or ""
            local currentTrimmed = string.match(text, "^%s*(.-)$") or ""
            if currentTrimmed ~= "" then
                instrumented[#instrumented + 1] = currentIndent .. modStr .. " " .. currentTrimmed
            else
                instrumented[#instrumented + 1] = currentIndent .. modStr
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