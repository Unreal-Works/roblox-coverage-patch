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
        elseif ch == "'" or ch == '"' or ch == "`" then
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
                if two == "==" or two == "~=" or two == "<=" or two == ">=" or two == "//" or two == ".." or two == "::" or two == "->" then
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
        return token.value == "(" or token.value == "{" or token.value == "["
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

    -- Detect ternary expressions with elseif branches (3+ paths)
    local elseifTokens = {}
    do
        local i = branchData.thenTokenIdx + 1
        while i < branchData.elseIdx do
            local tk = tokens[i]
            if tk.kind == "keyword" and tk.value == "elseif" then
                -- find the matching 'then' after this elseif
                local thenIdx = nil
                for j = i + 1, #tokens do
                    if tokens[j].kind == "keyword" and tokens[j].value == "then" then
                        thenIdx = j
                        break
                    end
                end
                if thenIdx then
                    table.insert(elseifTokens, { elseifIdx = i, thenIdx = thenIdx })
                end
            end
            i += 1
        end
    end
    
    if #elseifTokens > 0 then
        -- Build branch segments: then branch, each elseif branch, else branch
        local function tokenOffset(idx)
            local o = getTokenOffset(idx)
            if not o then return nil end
            return o
        end

        local segments = {}

        -- Helper to find first token after a given index
        local function nextTokenIdx(idx)
            if idx >= #tokens then return nil end
            return idx + 1
        end

        -- First branch (after initial then)
        local startTokIdx = nextTokenIdx(branchData.thenTokenIdx)
        local startOffset = startTokIdx and tokenOffset(startTokIdx)
        local firstSeparatorOffset = tokenOffset(elseifTokens[1].elseifIdx)
        if startOffset and firstSeparatorOffset then
            table.insert(segments, { path = 0, startOffset = startOffset, endOffset = firstSeparatorOffset })
        else
            return lines[startLine], 1, 0
        end

        -- Middle branches for each elseif
        for idx, info in ipairs(elseifTokens) do
            local branchStartTokIdx = nextTokenIdx(info.thenIdx)
            local branchStartOffset = branchStartTokIdx and tokenOffset(branchStartTokIdx)
            local branchEndOffset
            if idx < #elseifTokens then
                branchEndOffset = tokenOffset(elseifTokens[idx + 1].elseifIdx)
            else
                branchEndOffset = tokenOffset(branchData.elseIdx)
            end

            if branchStartOffset and branchEndOffset then
                table.insert(segments, { path = idx, startOffset = branchStartOffset, endOffset = branchEndOffset })
            else
                return lines[startLine], 1, 0
            end
        end

        -- Else branch
        local elseStartTokIdx = nextTokenIdx(branchData.elseIdx)
        local elseStartOffset = elseStartTokIdx and tokenOffset(elseStartTokIdx)
        local elseEndOffset = tokenOffset(branchData.endTokenIdx)
        if elseStartOffset and elseEndOffset then
            elseEndOffset = elseEndOffset + #tokens[branchData.endTokenIdx].value
            table.insert(segments, { path = #segments, startOffset = elseStartOffset, endOffset = elseEndOffset })
        else
            return lines[startLine], 1, 0
        end

        -- Assemble instrumented text by wrapping each branch expression
        local parts = {}
        local cursor = 0
        for _, seg in ipairs(segments) do
            -- keep everything up to expression start
            parts[#parts + 1] = text:sub(cursor + 1, seg.startOffset)

            -- Separate trailing whitespace before the next separator so it stays outside the wrapper
            local exprEnd = seg.endOffset
            while exprEnd > seg.startOffset and text:sub(exprEnd, exprEnd):match("%s") do
                exprEnd -= 1
            end
            local trailing = text:sub(exprEnd + 1, seg.endOffset)

            -- wrap expression
            parts[#parts + 1] = string.format("%s(%d, %d)(%s)", "_G.__covbranch", branchId, seg.path, text:sub(seg.startOffset + 1, exprEnd))
            -- restore trailing whitespace
            parts[#parts + 1] = trailing

            cursor = seg.endOffset
        end
        parts[#parts + 1] = text:sub(cursor + 1)

        local instrumented = table.concat(parts)
        local _, linesConsumed = text:gsub("\n", "\n")
        linesConsumed = linesConsumed + 1
        return instrumented, linesConsumed, 0
    end
    
    -- Extract parts preserving EVERYTHING except where we inject
    local beforeThen = text:sub(1, thenPos)
    local thenToElse = text:sub(thenMatchEnd + 1, elsePos)
    local elseToEnd = text:sub(elseMatchEnd + 1, elseExprEnd)
    local afterTernary = text:sub(elseExprEnd + 1)
    
    -- Function to instrument internal expressions without recursion
    local function instrumentInternal(partText: string, partStartLine: number, colOffset: number?)
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
            local currentColOffset = (i == 1 and colOffset or 0)
            
            local combinedLineInsertions = {}
            if functionDeclarationLines[currentLineNo] then
                local decls = functionDeclarationLines[currentLineNo]
                for _, decl in ipairs(decls) do
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
                        local relCol = targetToken.column - currentColOffset
                        if relCol >= 0 and relCol < #lineText then
                            local modStr = "_G.__covfn(" .. tostring(decl.id) .. ");"
                            table.insert(combinedLineInsertions, { col = targetToken.column, text = modStr, priority = 1 })
                            addedCount += 1
                        end
                    end
                end
            end
            
            local markers = functionInstrumentedLines[currentLineNo]
            if markers then
                for _, marker in ipairs(markers) do
                    if marker.allocatedId then
                        local hitStr = "_G.__covhit(" .. tostring(marker.allocatedId) .. ");"
                        if marker.tokenIdx then
                            local t = tokens[marker.tokenIdx]
                            local relCol = t.column - currentColOffset
                            if relCol >= 0 and relCol < #lineText then
                                table.insert(combinedLineInsertions, { col = t.column, text = hitStr, priority = 2 })
                                addedCount += 1
                            end
                        elseif currentLineNo ~= startLine then
                            table.insert(modifications, hitStr)
                            addedCount += 1
                        end
                    end
                end
            end

            if #combinedLineInsertions > 0 then
                table.sort(combinedLineInsertions, function(a, b) 
                    if a.col ~= b.col then return a.col > b.col end
                    return (a.priority or 0) > (b.priority or 0)
                end)
                local newLine = lineText
                for _, ins in ipairs(combinedLineInsertions) do
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
                        local pos = tokenOnLine.column - currentColOffset + #tokenOnLine.value
                        newLine = newLine:sub(1, pos) .. " " .. ins.text .. newLine:sub(pos + 1)
                    end
                end
                lineText = newLine
                trimmed = lineText:match("^%s*(.-)%s*$") or ""
                indent = lineText:match("^(%s*)") or ""
            end

            local lineHitId = lineHitIds[currentLineNo]
            if lineHitId and (currentLineNo ~= startLine) then
                table.insert(modifications, "_G.__covhit(" .. tostring(lineHitId) .. ");")
                addedCount += 1
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
    local function instrumentPart(part: string, partStartLine: number, partStartCol: number)
        local prefix = part:match("^(%s*)") or ""
        local suffix = part:match("(%s*)$") or ""
        local trimmed = part:sub(#prefix + 1, #part - #suffix)
        local instrumented, added = instrumentInternal(trimmed, partStartLine, partStartCol + #prefix)
        return instrumented, prefix, suffix, added
    end

    local _, thenLinesOffset = text:sub(1, thenMatchEnd):gsub("\n", "\n")
    local _, elseLinesOffset = text:sub(1, elseMatchEnd):gsub("\n", "\n")
    
    local instrumentedThen, prefixThen, suffixThen, thenAdded = instrumentPart(thenToElse, startLine + thenLinesOffset, tokens[branchData.thenTokenIdx].column + #tokens[branchData.thenTokenIdx].value)
    local instrumentedElse, prefixElse, suffixElse, elseAdded = instrumentPart(elseToEnd, startLine + elseLinesOffset, tokens[branchData.elseIdx].column + #tokens[branchData.elseIdx].value)
    
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

    -- Track loop headers whose 'do' is on a separate line so we can avoid double-instrumenting the block start
    local loopDoLines = {}

    do
        for idx, token in ipairs(tokens) do
            if token.kind == "keyword" and (token.value == "for" or token.value == "while") then
                local nestedFunctionDepth = 0
                local j = idx + 1
                while j <= #tokens do
                    local t = tokens[j]
                    if t.kind == "keyword" then
                        if t.value == "function" then
                            nestedFunctionDepth += 1
                        elseif t.value == "end" then
                            if nestedFunctionDepth > 0 then
                                nestedFunctionDepth -= 1
                            end
                        elseif t.value == "do" and nestedFunctionDepth == 0 then
                            if t.line ~= token.line then
                                loopDoLines[t.line] = true
                            end
                            break
                        end
                    end
                    j += 1
                end
            end
        end
    end
    
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
            local bodyStartTokenIdx = nil
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
                            local returnAngleDepth = 0
                            local returnBraceDepth = 0
                            local returnBracketDepth = 0

                            while j <= #tokens do
                                local rt = tokens[j]
                                local prev = tokens[j-1]

                                -- If we hit a new line at depth 0, check if we should stop.
                                -- We only continue across newlines if either the previous token
                                -- or current token is a symbol that typically continues a type.
                                if returnParenDepth == 0 and returnAngleDepth == 0 and returnBraceDepth == 0 and returnBracketDepth == 0 and rt.line > prev.line then
                                    local rtIsCont = (rt.kind == "symbol" and (rt.value == "|" or rt.value == "&" or rt.value == "," or rt.value == "." or rt.value == ":" or rt.value == "->" or rt.value == "?" or rt.value == "<"))
                                    local prevIsCont = (prev.kind == "symbol" and (prev.value == "|" or prev.value == "&" or prev.value == "," or prev.value == "." or prev.value == ":" or prev.value == "->" or prev.value == "<"))
                                    if not rtIsCont and not prevIsCont then
                                        break
                                    end
                                end

                                if rt.kind == "symbol" and rt.value == "(" then
                                    returnParenDepth += 1
                                    j += 1
                                elseif rt.kind == "symbol" and rt.value == ")" then
                                    if returnParenDepth == 0 then
                                        break
                                    else
                                        returnParenDepth -= 1
                                        j += 1
                                    end
                                elseif rt.kind == "symbol" and rt.value == "{" then
                                    returnBraceDepth += 1
                                    j += 1
                                elseif rt.kind == "symbol" and rt.value == "}" then
                                    if returnBraceDepth == 0 then
                                        break
                                    else
                                        returnBraceDepth -= 1
                                        j += 1
                                    end
                                elseif rt.kind == "symbol" and rt.value == "[" then
                                    returnBracketDepth += 1
                                    j += 1
                                elseif rt.kind == "symbol" and rt.value == "]" then
                                    if returnBracketDepth == 0 then
                                        break
                                    else
                                        returnBracketDepth -= 1
                                        j += 1
                                    end
                                elseif rt.kind == "symbol" and rt.value == "<" then
                                    returnAngleDepth += 1
                                    j += 1
                                elseif rt.kind == "symbol" and rt.value == ">" then
                                    if returnAngleDepth > 0 then
                                        returnAngleDepth -= 1
                                    end
                                    j += 1
                                elseif rt.kind == "symbol" and rt.value == "->" then
                                    j += 1
                                elseif rt.kind == "symbol" and (rt.value == "." or rt.value == ":" or rt.value == "?" or rt.value == "|" or rt.value == "&" or rt.value == "," or rt.value == "...") then
                                    j += 1
                                elseif rt.kind == "identifier" then
                                    j += 1
                                elseif rt.kind == "keyword" and (rt.value == "nil" or rt.value == "true" or rt.value == "false") then
                                    j += 1
                                else
                                    -- Stop skipping type if we're not in parens or angle brackets
                                    if returnParenDepth == 0 and returnAngleDepth == 0 and returnBraceDepth == 0 and returnBracketDepth == 0 then
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
                            if parser.shouldInstrument(bt) or (bt.kind == "keyword" and bt.value == "end") then
                                bodyLineNo = bt.line
                                bodyStartTokenIdx = j
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

            -- Ensure the function declaration marker stays before the body start
            if bodyStartTokenIdx and signatureEndTokenIdx >= bodyStartTokenIdx and bodyStartTokenIdx > idx then
                signatureEndTokenIdx = bodyStartTokenIdx - 1
                signatureEndLine = tokens[signatureEndTokenIdx].line
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

            -- Skip body hit if the function starts with a multi-line if/elseif condition
            local skipBodyHit = false
            if bodyStartTokenIdx and bodyStartTokenIdx > 1 then
                local prevTok = tokens[bodyStartTokenIdx - 1]
                if prevTok and prevTok.kind == "keyword" and (prevTok.value == "if" or prevTok.value == "elseif") then
                    if prevTok.line < tokens[bodyStartTokenIdx].line and firstTokens[prevTok.line] == prevTok then
                        skipBodyHit = true
                    end
                end
            end

            if not skipBodyHit then
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
    end
    for l, decls in pairs(functionDeclarationLines) do end
    
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
            
                -- Detect if this is an if expression based on context
                local firstOnLine = firstTokens[token.line]
                local isTernary = (firstOnLine ~= token)
                if not isTernary and i > 1 then
                    local prev = tokens[i - 1]
                    if prev.kind == "symbol" and (prev.value == "(" or prev.value == "{" or prev.value == "[" or prev.value == ",") then
                        isTernary = true
                    end
                end

                if thenIdx then
                    -- Mark all lines between 'if' and 'then' as being in a condition
                    local ifLine = token.line
                    local thenLine = tokens[thenIdx].line
                    if ifLine ~= thenLine then
                        local startMarkLine = ifLine
                        if isTernary then
                            startMarkLine = ifLine + 1
                        end
                        for lineNum = startMarkLine, thenLine do
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
                local inlineIfDepth = 0
                local j = thenIdx + 1
                local foundElse = false
                
                local elseIdx = nil
                local endTokenIdx = nil
                while j <= #tokens and depth > 0 do
                    local t = tokens[j]
                    
                    if isTernary and depth == 1 and foundElse then
                        -- For ternary expressions, stop when we hit a token that clearly ends the branch
                        if t.kind == "symbol" and (t.value == ")" or t.value == "," or t.value == ";" or t.value == "]" or t.value == "}") then
                            endTokenIdx = j - 1
                            depth = 0
                            break
                        elseif t.kind == "keyword" and (t.value == "local" or t.value == "return" or t.value == "end" or t.value == "if" or t.value == "do" or t.value == "for" or t.value == "while" or t.value == "repeat" or t.value == "until" or t.value == "break" or t.value == "continue" or t.value == "elseif" or t.value == "else") then
                            endTokenIdx = j - 1
                            depth = 0
                            break
                        elseif t.kind == "comment" and elseIdx and t.line > tokens[elseIdx].line then
                            -- Comment on a new line after else signals we've left the expression
                            endTokenIdx = j - 1
                            depth = 0
                            break
                        elseif firstTokens[t.line] == t and elseIdx and t.line > tokens[elseIdx].line then
                            -- New line after else: stop unless previous token forces continuation
                            local prev = tokens[j - 1]
                            local continue = false
                            if prev then
                                if prev.kind == "symbol" then
                                    local v = prev.value
                                    if v == "(" or v == "[" or v == "{" or v == "," or v == "=" or v == "+" or v == "-" or v == "*" or v == "/" or v == "//" or v == "%" or v == "^" or v == ".." or v == "==" or v == "~=" or v == "<" or v == ">" or v == "<=" or v == ">=" or v == "." or v == ":" or v == "::" or v == "->" then
                                        continue = true
                                    end
                                elseif prev.kind == "keyword" then
                                    local v = prev.value
                                    if v == "and" or v == "or" or v == "not" or v == "in" or v == "else" then
                                        continue = true
                                    end
                                end
                            end
                            if not continue then
                                endTokenIdx = j - 1
                                depth = 0
                                break
                            end
                        else
                            -- If we hit the first token of a new line after the else
                            -- and the previous token closed an expression, treat that as the end.
                            local prev = tokens[j - 1]
                            if prev and prev.kind == "symbol" and (prev.value == ")" or prev.value == "}" or prev.value == "]") and firstTokens[t.line] == t and t.line > prev.line and (not elseIdx or t.line > tokens[elseIdx].line) then
                                endTokenIdx = j - 1
                                depth = 0
                                break
                            end
                        end
                    end

                    if t.kind == "keyword" then
                        if t.value == "if" or t.value == "do" or t.value == "for" or t.value == "function" or t.value == "while" or t.value == "repeat" then
                            -- Treat inline/ternary-style if-expressions specially so they don't steal the outer else
                            local isExpressionIf = false
                            if t.value == "if" then
                                local prevTok = tokens[j - 1]
                                if prevTok then
                                    if prevTok.kind == "symbol" and (prevTok.value == "(" or prevTok.value == "{" or prevTok.value == "[" or prevTok.value == "," or prevTok.value == "=") then
                                        isExpressionIf = true
                                    elseif prevTok.kind == "keyword" and (prevTok.value == "return" or prevTok.value == "local") then
                                        isExpressionIf = true
                                    elseif firstTokens[t.line] ~= t then
                                        isExpressionIf = true
                                    end
                                end
                            end

                            if isExpressionIf then
                                depth += 1
                                inlineIfDepth += 1
                            else
                                depth += 1
                            end
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
                        elseif inlineIfDepth > 0 and t.value == "else" then
                            -- Close an inline if-expression without affecting the outer branch tracking
                            depth -= 1
                            inlineIfDepth -= 1
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
                    elseif (v == "if" or v == "elseif") and prev.line < token.line then
                        isContinuation = true
                    end
                end
            end
        end

        if loopDoLines[lNo] then
            isContinuation = true
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
        local isTypeDeclaration = false
        if token and (token.value == "type" or token.value == "export") then
            local lineTokens = tokensByLine[lNo]
            if lineTokens then
                if token.value == "type" then
                    -- Check for type NAME
                    if #lineTokens >= 2 and lineTokens[2].token.kind == "identifier" then
                        isTypeDeclaration = true
                    end
                elseif token.value == "export" then
                    -- Check for export type
                    if #lineTokens >= 2 and lineTokens[2].token.value == "type" then
                        isTypeDeclaration = true
                    end
                end
            end
        end

        if (not isTypeDeclaration and parser.shouldInstrument(token) and trimmed ~= "" and not linesInCondition[lNo] and not isFunctionDefinition and not isContinuation and not functionInstrumentedLines[lNo] and not functionDeclarationLines[lNo]) then
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
        local ternaryInfo = nil
        if branchInstrumentedLines[lineNo] then
            for _, info in ipairs(branchInstrumentedLines[lineNo]) do
                if info.isTernary then
                    ternaryInfo = info
                    break
                end
            end
        end

        -- Add function declaration instrumentation if needed handled in assembly logic below

        local modifications = {}
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

        if ternaryInfo then
            -- Parse and replace ternary expression on this line
            local branchId = ternaryInfo.branchId
            local branchData = coverage.branchMap[branchId]
            local newText, consumed, internalAdded = replaceTernaryExpression(lines, lineNo, branchData.endLine, branchId, filePath, coverage, functionDeclarationLines, functionInstrumentedLines, linesInCondition, firstTokens, tokensByLine, tokens, branchData, lineHitIds)

            if newText ~= lines[lineNo] then
                text = newText
                linesToSkip = consumed - 1  -- Skip the consumed lines
                local branchCount = #branchData.locations
                branchAdded += branchCount + (internalAdded or 0)
                -- Clear lineInsertions as they are now invalid for this modified line
                lineInsertions = {}

                -- Remove ternary branch entries so they are not also emitted as plain branches
                if branchInstrumentedLines[lineNo] then
                    local filtered = {}
                    for _, info in ipairs(branchInstrumentedLines[lineNo]) do
                        if info.branchId ~= branchId or not info.isTernary then
                            table.insert(filtered, info)
                        end
                    end
                    branchInstrumentedLines[lineNo] = filtered
                end

                -- Emit any remaining non-ternary branch instrumentation on this line (e.g., outer branches)
                if branchInstrumentedLines[lineNo] then
                    for _, bInfo in ipairs(branchInstrumentedLines[lineNo]) do
                        table.insert(modifications, "_G.__covbranch(" .. tostring(bInfo.branchId) .. ", " .. tostring(bInfo.pathIndex) .. ");")
                        branchAdded += 1
                    end
                end
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