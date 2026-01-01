local process = require("@lune/process")
local parser = require("../src/parser")

local tests = {}

function addTest(name, fn)
	table.insert(tests, { name = name, fn = fn })
end

function expect(actual)
	local expectations
	expectations = {
		toBe = function(expected)
			if actual ~= expected then
				error("\nExpected:\n" .. tostring(expected) .. "\nReceived:\n" .. tostring(actual), 2)
			end
		end,
		toBeGreaterThan = function(expected)
			if actual <= expected then
				error("\nExpected greater than:\n" .. tostring(expected) .. "\nReceived:\n" .. tostring(actual), 2)
			end
		end,
		toBeUndefined = function()
			return expectations.toBe(nil)
		end,
	}
	return expectations
end

function runTests()
	local passed, failed = 0, 0
	for _, test in ipairs(tests) do
		_G.__COVERAGE__ = nil -- Reset coverage between tests

		local ok, err = pcall(test.fn)
		if ok then
			if table.find(process.args, "--verbose") then
				print("[PASS]", test.name)
			end
			passed += 1
		else
			print("[FAIL]", test.name, err)
			failed += 1
		end
	end
	print("Tests finished. Passed:", passed, "Failed:", failed)
	if failed > 0 then
		process.exit(1)
	else
		process.exit(0)
	end
end

-- Tests for parser functions

addTest("normalizeNewlines", function()
	expect(parser.normalizeNewlines("a\r\nb\r\nc")).toBe("a\nb\nc")
	expect(parser.normalizeNewlines("a\rb\rc")).toBe("a\nb\nc")
	expect(parser.normalizeNewlines("a\nb\nc")).toBe("a\nb\nc")
	expect(parser.normalizeNewlines("")).toBe("")
end)

addTest("countNewlines", function()
	expect(parser.countNewlines("a\nb\nc")).toBe(2)
	expect(parser.countNewlines("a\nb")).toBe(1)
	expect(parser.countNewlines("abc")).toBe(0)
	expect(parser.countNewlines("")).toBe(0)
end)

addTest("splitLines", function()
	local lines = parser.splitLines("a\nb\nc")
	expect(#lines).toBe(3)
	expect(lines[1]).toBe("a")
	expect(lines[2]).toBe("b")
	expect(lines[3]).toBe("c")

	lines = parser.splitLines("a\nb")
	expect(#lines).toBe(2)
	expect(lines[1]).toBe("a")
	expect(lines[2]).toBe("b")

	lines = parser.splitLines("")
	expect(#lines).toBe(1)
	expect(lines[1]).toBe("")
end)

addTest("tryScanLong", function()
	local nextIndex, nl = parser.tryScanLong("[[hello]]", 1)
	expect(nextIndex).toBe(10)
	expect(nl).toBe(0)

	nextIndex, nl = parser.tryScanLong("[[hello\nworld]]", 1)
	expect(nextIndex).toBe(16)
	expect(nl).toBe(1)

	nextIndex, nl = parser.tryScanLong("[==[hello]==]", 1)
	expect(nextIndex).toBe(14)
	expect(nl).toBe(0)

	expect(parser.tryScanLong("hello", 1)).toBeUndefined()
end)

addTest("tokenize", function()
	local tokens = parser.tokenize("local x = 1")
	expect(#tokens).toBe(4)
	expect(tokens[1].kind).toBe("keyword")
	expect(tokens[1].value).toBe("local")
	expect(tokens[2].kind).toBe("identifier")
	expect(tokens[2].value).toBe("x")
	expect(tokens[3].kind).toBe("symbol")
	expect(tokens[3].value).toBe("=")
	expect(tokens[4].kind).toBe("number")
	expect(tokens[4].value).toBe("1")

	tokens = parser.tokenize("function test() end")
	expect(#tokens).toBe(5)
	expect(tokens[1].value).toBe("function")
	expect(tokens[2].value).toBe("test")
	expect(tokens[3].value).toBe("(")
	expect(tokens[4].value).toBe(")")
	expect(tokens[5].value).toBe("end")
end)

addTest("firstTokenPerLine", function()
	local tokens = parser.tokenize("local x = 1\nlocal y = 2")
	local firstTokens = parser.firstTokenPerLine(tokens)
	expect(firstTokens[1].value).toBe("local")
	expect(firstTokens[2].value).toBe("local")
end)

addTest("shouldInstrument", function()
	local token = { kind = "keyword", value = "if" }
	expect(parser.shouldInstrument(token :: any)).toBe(false)

	token = { kind = "keyword", value = "local" }
	expect(parser.shouldInstrument(token :: any)).toBe(true)

	token = { kind = "keyword", value = "end" }
	expect(parser.shouldInstrument(token :: any)).toBe(false)

	token = { kind = "identifier", value = "x" }
	expect(parser.shouldInstrument(token :: any)).toBe(true)

	expect(parser.shouldInstrument(nil)).toBe(false)
end)

addTest("extractFunctionName", function()
	local tokens = parser.tokenize("function test() end")
	local name = parser.extractFunctionName(tokens, 2)
	expect(name).toBe("test")

	tokens = parser.tokenize("function obj.method() end")
	name = parser.extractFunctionName(tokens, 2)
	expect(name).toBe("obj.method")

	tokens = parser.tokenize("function obj:method() end")
	name = parser.extractFunctionName(tokens, 2)
	expect(name).toBe("obj:method")

	tokens = parser.tokenize("function() end")
	name = parser.extractFunctionName(tokens, 2)
	expect(name).toBe("<anonymous>")
end)

addTest("instrumentSource basic", function()
	local coverage = parser.ensureCoverage()
	local source = [[local x = 1
if x then
end]]
	local instrumented, added = parser.instrumentSource(source, "test.lua", coverage)
	expect(type(instrumented)).toBe("string")

	-- Add hit for the variable assignment
	-- Add branch in the if statement, don't add hit to prevent double counting
	-- Ensure end does not have a hit, it's purely a syntactic delimiter
	expect(instrumented).toBe([[_G.__covhit(1); local x = 1
if x then
_G.__covbranch(1, 0); end]])
	expect(added).toBe(2)
end)

addTest("ensureCoverage", function()
	_G.__COVERAGE__ = nil
	local coverage = parser.ensureCoverage()
	expect(type(coverage)).toBe("table")
	expect(type(coverage.hits)).toBe("table")
	expect(coverage.nextId).toBe(1)
	-- Call again to test existing
	local coverage2 = parser.ensureCoverage()
	expect(coverage).toBe(coverage2)
end)

-- Edge cases for normalizeNewlines
addTest("normalizeNewlines mixed line endings", function()
	expect(parser.normalizeNewlines("a\r\nb\rc\nd")).toBe("a\nb\nc\nd")
	expect(parser.normalizeNewlines("\r\n\r\n\r\n")).toBe("\n\n\n")
	expect(parser.normalizeNewlines("\n\n\n")).toBe("\n\n\n")
end)

addTest("normalizeNewlines with only CR", function()
	expect(parser.normalizeNewlines("a\rb")).toBe("a\nb")
end)

-- Edge cases for countNewlines
addTest("countNewlines edge cases", function()
	expect(parser.countNewlines("\n")).toBe(1)
	expect(parser.countNewlines("\n\n\n")).toBe(3)
	expect(parser.countNewlines("no newlines here")).toBe(0)
	expect(parser.countNewlines("\n\n\n\n")).toBe(4)
end)

-- Edge cases for splitLines
addTest("splitLines with trailing newline", function()
	local lines = parser.splitLines("a\nb\nc\n")
	expect(#lines).toBe(4)
	expect(lines[4]).toBe("")
end)

addTest("splitLines with only newlines", function()
	local lines = parser.splitLines("\n\n\n")
	expect(#lines).toBe(4)
	expect(lines[1]).toBe("")
	expect(lines[2]).toBe("")
	expect(lines[3]).toBe("")
	expect(lines[4]).toBe("")
end)

addTest("splitLines single character", function()
	local lines = parser.splitLines("x")
	expect(#lines).toBe(1)
	expect(lines[1]).toBe("x")
end)

-- Edge cases for tryScanLong
addTest("tryScanLong with nested equals", function()
	local nextIndex, nl = parser.tryScanLong("[==[hello]==]", 1)
	expect(nextIndex).toBe(14)
	expect(nl).toBe(0)

	nextIndex, nl = parser.tryScanLong("[===[hello]===]", 1)
	expect(nextIndex).toBe(16)
	expect(nl).toBe(0)
end)

addTest("tryScanLong with multiple newlines", function()
	local nextIndex, nl = parser.tryScanLong("[[line1\nline2\nline3]]", 1)
	expect(nextIndex).toBe(22)
	expect(nl).toBe(2)
end)

addTest("tryScanLong unclosed", function()
	local nextIndex, nl = parser.tryScanLong("[[unclosed", 1)
	expect(nextIndex).toBe(11)
	expect(nl).toBe(0)
end)

addTest("tryScanLong not a long string", function()
	expect(parser.tryScanLong("[x]", 1)).toBeUndefined()
	expect(parser.tryScanLong("hello", 1)).toBeUndefined()
end)

-- Edge cases for tokenize
addTest("tokenize with strings", function()
	local tokens = parser.tokenize('"hello world"')
	expect(#tokens).toBe(1)
	expect(tokens[1].kind).toBe("string")

	tokens = parser.tokenize("'single quoted'")
	expect(#tokens).toBe(1)
	expect(tokens[1].kind).toBe("string")
end)

addTest("tokenize with escaped quotes", function()
	local tokens = parser.tokenize('"hello\\"world"')
	expect(#tokens).toBe(1)
	expect(tokens[1].kind).toBe("string")
end)

addTest("tokenize with comments", function()
	local tokens = parser.tokenize("local x = 1 -- comment")
	expect(tokens[4].value).toBe("1")
	expect(#tokens).toBe(4)
end)

addTest("tokenize with block comments", function()
	local tokens = parser.tokenize("local x = 1 --[[comment]] + 2")
	expect(#tokens).toBe(6)
	expect(tokens[1].value).toBe("local")
	expect(tokens[4].value).toBe("1")
	expect(tokens[5].value).toBe("+")
	expect(tokens[6].value).toBe("2")
end)

addTest("tokenize with numbers", function()
	local tokens = parser.tokenize("1 2.5 1e10 1E-5")
	expect(#tokens).toBe(4)
	expect(tokens[1].value).toBe("1")
	expect(tokens[2].value).toBe("2.5")
	expect(tokens[3].value).toBe("1e10")
	expect(tokens[4].value).toBe("1E-5")
end)

addTest("tokenize with operators", function()
	local tokens = parser.tokenize("a == b and c ~= d or e <= f")
	expect(tokens[2].value).toBe("==")
	expect(tokens[4].value).toBe("and")
	expect(tokens[6].value).toBe("~=")
	expect(tokens[8].value).toBe("or")
	expect(tokens[10].value).toBe("<=")
end)

addTest("tokenize with ellipsis", function()
	local tokens = parser.tokenize("function f(...) end")
	expect(#tokens).toBe(6)
	expect(tokens[4].value).toBe("...")
end)

addTest("tokenize with long strings", function()
	local tokens = parser.tokenize("x = [[hello\nworld]]")
	expect(#tokens).toBe(3)
	expect(tokens[1].value).toBe("x")
	expect(tokens[2].value).toBe("=")
	expect(tokens[3].kind).toBe("string")
end)

addTest("tokenize empty string", function()
	local tokens = parser.tokenize("")
	expect(#tokens).toBe(0)
end)

addTest("tokenize only whitespace", function()
	local tokens = parser.tokenize("   \n  \t  ")
	expect(#tokens).toBe(0)
end)

-- Edge cases for extractFunctionName
addTest("extractFunctionName with nested dots", function()
	local tokens = parser.tokenize("function obj.sub.method() end")
	local name = parser.extractFunctionName(tokens, 2)
	expect(name).toBe("obj.sub.method")
end)

addTest("extractFunctionName with colon", function()
	local tokens = parser.tokenize("function a:b:c() end")
	local name = parser.extractFunctionName(tokens, 2)
	expect(name).toBe("a:b:c")
end)

addTest("extractFunctionName with mixed separators", function()
	local tokens = parser.tokenize("function obj.method:other() end")
	local name = parser.extractFunctionName(tokens, 2)
	expect(name).toBe("obj.method:other")
end)

addTest("extractFunctionName out of bounds", function()
	local tokens = parser.tokenize("function")
	local name = parser.extractFunctionName(tokens, 100)
	expect(name).toBe("<anonymous>")
end)

addTest("extractFunctionName no identifier", function()
	local tokens = parser.tokenize("function (x) end")
	local name = parser.extractFunctionName(tokens, 2)
	expect(name).toBe("<anonymous>")
end)

-- Edge cases for ensureCoverage
addTest("ensureCoverage multiple calls", function()
	_G.__COVERAGE__ = nil
	local coverage1 = parser.ensureCoverage()
	local coverage2 = parser.ensureCoverage()
	expect(coverage1).toBe(coverage2)
	expect(coverage2.nextId).toBe(coverage1.nextId)
end)

addTest("ensureCoverage with existing data", function()
	_G.__COVERAGE__ = {
		hits = { [1] = 5 },
		map = { [1] = { file = "test.lua", line = 1 } },
		nextId = 2,
		f = { [1] = 3 },
		fnMap = { [1] = { name = "test", line = 1, file = "test.lua", loc = {} } },
		nextFnId = 2,
		b = {},
		branchMap = {},
		nextBranchId = 1,
	}
	local coverage = parser.ensureCoverage()
	expect(coverage.nextId).toBe(2)
	expect(coverage.nextFnId).toBe(2)
	expect(coverage.hits[1]).toBe(5)
end)

addTest("ensureCoverage coverage functions exist", function()
	parser.ensureCoverage()
	expect(type(_G.__covhit)).toBe("function")
	expect(type(_G.__covfn)).toBe("function")
	expect(type(_G.__covbranch)).toBe("function")
end)

-- Edge cases for instrumentSource
addTest("instrumentSource empty source", function()
	local coverage = parser.ensureCoverage()
	local instrumented, added = parser.instrumentSource("", "test.lua", coverage)
	expect(instrumented).toBe("")
	expect(added).toBe(0)
end)

addTest("instrumentSource only whitespace", function()
	local coverage = parser.ensureCoverage()
	local instrumented, added = parser.instrumentSource("   \n  \n  ", "test.lua", coverage)
	expect(instrumented).toBe("   \n  \n  ")
	expect(added).toBe(0)
end)

addTest("instrumentSource type", function()
	local coverage = parser.ensureCoverage()
	local instrumented, added = parser.instrumentSource("type ABC = string", "test.lua", coverage)
	expect(instrumented).toBe("type ABC = string")
	expect(added).toBe(0)
end)

addTest("instrumentSource export type", function()
	local coverage = parser.ensureCoverage()
	local instrumented, added = parser.instrumentSource("export type ABC = string", "test.lua", coverage)
	expect(instrumented).toBe("export type ABC = string")
	expect(added).toBe(0)
end)

addTest("instrumentSource with function", function()
	local coverage = parser.ensureCoverage()
	local source = [[function test()
  return 1
end]]
	local instrumented, added = parser.instrumentSource(source, "test.lua", coverage)
	expect(added > 0).toBe(true)

	expect(instrumented).toBe([[function test() _G.__covfn(1);
  _G.__covhit(1); return 1
end]])
end)

addTest("instrumentSource with multiple functions", function()
	local coverage = parser.ensureCoverage()
	local source = [[function f1() end
function f2() end]]
	local instrumented, added = parser.instrumentSource(source, "test.lua", coverage)

	expect(instrumented).toBe([[function f1() _G.__covfn(1); _G.__covhit(1); end
function f2() _G.__covfn(2); _G.__covhit(2); end]])
	expect(added > 0).toBe(true)
end)

addTest("instrumentSource with nested if", function()
	local coverage = parser.ensureCoverage()
	local source = [[if x then
  if y then
    z()
  end
end]]
	local instrumented, added = parser.instrumentSource(source, "test.lua", coverage)
	expect(instrumented).toBe([[if x then
  _G.__covbranch(1, 0); if y then
    _G.__covbranch(2, 0); _G.__covhit(1); z()
  end
end]])
	expect(added).toBe(3)
end)

addTest("instrumentSource with if-elseif-else", function()
	local coverage = parser.ensureCoverage()
	local source = [[if x then
elseif y then
  b()
else
  c()
end]]
	local instrumented, added = parser.instrumentSource(source, "test.lua", coverage)
	expect(instrumented).toBe([[if x then
_G.__covbranch(1, 0); elseif y then
  _G.__covbranch(1, 1); _G.__covhit(1); b()
else
  _G.__covbranch(1, 2); _G.__covhit(2); c()
end]])
	expect(added).toBe(5)
end)

addTest("instrumentSource with comments", function()
	local coverage = parser.ensureCoverage()
	local source = [[local x = 1 -- this is a comment
if x then
end]]
	local instrumented, added = parser.instrumentSource(source, "test.lua", coverage)
	expect(instrumented).toBe([[_G.__covhit(1); local x = 1 -- this is a comment
if x then
_G.__covbranch(1, 0); end]])
	expect(added).toBe(2)
end)

addTest("instrumentSource with long strings", function()
	local coverage = parser.ensureCoverage()
	local source = "local x = [[hello\nworld]]\nlocal y = 2"
	local instrumented, added = parser.instrumentSource(source, "test.lua", coverage)
	expect(instrumented).toBe("_G.__covhit(1); local x = [[hello\nworld]]\n_G.__covhit(2); local y = 2")
	expect(added).toBe(2)
end)

addTest("instrumentSource with indentation", function()
	local coverage = parser.ensureCoverage()
	local source = [[function test()
    local x = 1
    if x then
        return x
    end
end]]
	local instrumented, added = parser.instrumentSource(source, "test.lua", coverage)
	expect(instrumented).toBe([[function test() _G.__covfn(1);
    _G.__covhit(1); local x = 1
    if x then
        _G.__covbranch(1, 0); _G.__covhit(2); return x
    end
end]])
	expect(added).toBe(4)
end)

addTest("instrumentSource with multi-line if condition", function()
	local coverage = parser.ensureCoverage()
	local source = "if x == 1\n\tand y == 2 then\n\treturn true\nend"
	local instrumented, added = parser.instrumentSource(source, "test.lua", coverage)
	expect(instrumented).toBe("if x == 1\n\tand y == 2 then\n\t_G.__covbranch(1, 0); _G.__covhit(1); return true\nend")
	expect(added).toBe(2)
end)

addTest("instrumentSource with multi-line elseif condition", function()
	local coverage = parser.ensureCoverage()
	local source = 'if x then\n\ta()\nelseif\n\ttype(x) == "table"\n\tand type(y) == "table"\nthen\n\tb()\nend'
	local instrumented, added = parser.instrumentSource(source, "test.lua", coverage)
	expect(instrumented).toBe(
		"if x then"
			.. "\n\t_G.__covbranch(1, 0); _G.__covhit(1); a()"
			.. "\nelseif"
			.. '\n\ttype(x) == "table"'
			.. '\n\tand type(y) == "table"'
			.. "\nthen"
			.. "\n\t_G.__covbranch(1, 1); _G.__covhit(2); b()"
			.. "\nend"
	)
	expect(added).toBe(4)
end)

addTest("instrumentSource does not instrument on strings", function()
    local coverage = parser.ensureCoverage()
    local source = [[local str = "if x then end"
local str2 = 'elseif y then return 1 end'
local str3 = `else return 2 end`
assert(`function hi`)]]
    local instrumented, added = parser.instrumentSource(source, "test.lua", coverage)
    expect(instrumented).toBe([[_G.__covhit(1); local str = "if x then end"
_G.__covhit(2); local str2 = 'elseif y then return 1 end'
_G.__covhit(3); local str3 = `else return 2 end`
_G.__covhit(4); assert(`function hi`)]])
    expect(added).toBe(4)
end)

addTest("instrumentSource object assignments", function()
    local coverage = parser.ensureCoverage()
    local source = [[function meta:__newindex(key: unknown, value: unknown): ()
    (original :: any)[key] = value
end]]
    local instrumented, added = parser.instrumentSource(source, "test.lua", coverage)
    expect(instrumented).toBe([[function meta:__newindex(key: unknown, value: unknown): () _G.__covfn(1);
    _G.__covhit(1); (original :: any)[key] = value
end]])
    expect(added).toBe(2)
end)

addTest("instrumentSource elseif with body on next line", function()
	local coverage = parser.ensureCoverage()
	local source = [[if x then
    a()
elseif
    y
then
    b()
end]]
	local instrumented, added = parser.instrumentSource(source, "test.lua", coverage)
	expect(instrumented).toBe([[if x then
    _G.__covbranch(1, 0); _G.__covhit(1); a()
elseif
    y
then
    _G.__covbranch(1, 1); _G.__covhit(2); b()
end]])
	expect(added).toBe(4)
end)

addTest("instrumentSource with function literal in method call", function()
	local coverage = parser.ensureCoverage()
	local source = [[self
    :finally(function()
        task.spawn(thread)
    end)
    :catch(
        function() end
    )]]
	local instrumented, added = parser.instrumentSource(source, "test.lua", coverage)
	expect(instrumented).toBe([[_G.__covhit(1); self
    :finally(function() _G.__covfn(1);
        _G.__covhit(2); task.spawn(thread)
    end)
    :catch(
        function() _G.__covfn(2); end
    )]])
	expect(added).toBe(4)
end)

addTest("instrumentSource with literal in function call arguments", function()
	local coverage = parser.ensureCoverage()
	local source = [[bindEach(
        describe :: FIXME_ANALYZE,
        false
    )]]
	local instrumented, added = parser.instrumentSource(source, "test.lua", coverage)
	expect(instrumented).toBe([[_G.__covhit(1); bindEach(
        describe :: FIXME_ANALYZE,
        false
    )]])
	expect(added).toBe(1)
end)

addTest("instrumentSource with multi-line function signature", function()
	local coverage = parser.ensureCoverage()
	local source = [[function _dispatchDescribe(
    blockFn: BlockFn,
    blockName: BlockNameLike,
    mode: any?
): ()
    return nil
end]]
	local instrumented, added = parser.instrumentSource(source, "test.lua", coverage)
	expect(instrumented).toBe([[function _dispatchDescribe(
    blockFn: BlockFn,
    blockName: BlockNameLike,
    mode: any?
): () _G.__covfn(1);
    _G.__covhit(1); return nil
end]])
	expect(added).toBe(2)
end)

addTest("instrumentSource with if statement branch instrumentation", function()
	local coverage = parser.ensureCoverage()
	local source = [[local function test()
    local result = if typeof(value) == "function"
        then setmetatable({}, {
            __call = function(_self, ...)
                return value(...)
            end,
        })
        else value
    end
    return result
end]]
	local instrumented, added = parser.instrumentSource(source, "test.lua", coverage)
	expect(instrumented).toBe([[local function test() _G.__covfn(1);
    _G.__covhit(1); local result = if typeof(value) == "function"
        then _G.__covbranch(1, 0)(setmetatable({}, {
            __call = function(_self, ...) _G.__covfn(2);
                _G.__covhit(2); return value(...)
            end,
        }))
        else _G.__covbranch(1, 1)(value)
    end
    _G.__covhit(3); return result
end]])
	expect(added).toBe(7)
end)

addTest("instrumentSource with ternary expression", function()
	local coverage = parser.ensureCoverage()
	local source = [[local result = if condition then "true" else "false"]]
	local instrumented, added = parser.instrumentSource(source, "test.lua", coverage)
	-- Should have hit instrumentation for the local statement
	-- Should have branch instrumentation for ternary expressions
	expect(instrumented).toBe(
		[[_G.__covhit(1); local result = if condition then _G.__covbranch(1, 0)("true") else _G.__covbranch(1, 1)("false")]]
	)
	expect(added).toBe(3) -- 1 hit + 2 branch instrumentations
end)

addTest("instrumentSource with complex ternary expression", function()
	local coverage = parser.ensureCoverage()
	local source =
		[[local tests = if isArrayTable(taggedTemplateData) then buildArrayTests(title, table_) else buildTemplateTests(title, table_, taggedTemplateData)]]
	local instrumented, added = parser.instrumentSource(source, "test.lua", coverage)
	expect(instrumented).toBe(
		[[_G.__covhit(1); local tests = if isArrayTable(taggedTemplateData) then _G.__covbranch(1, 0)(buildArrayTests(title, table_)) else _G.__covbranch(1, 1)(buildTemplateTests(title, table_, taggedTemplateData))]]
	)
	expect(added).toBe(3) -- 1 hit + 2 branch instrumentations
end)

addTest("instrumentSource with multi-line ternary expression", function()
	local coverage = parser.ensureCoverage()
	local source = [[local result = if someCondition then
    complexFunction(arg1, arg2)
else
    otherFunction(arg3, arg4)]]
	local instrumented, added = parser.instrumentSource(source, "test.lua", coverage)
	expect(instrumented).toBe([[_G.__covhit(1); local result = if someCondition then
    _G.__covbranch(1, 0)(complexFunction(arg1, arg2))
else
    _G.__covbranch(1, 1)(otherFunction(arg3, arg4))]])
	expect(added).toBe(3) -- 1 hit + 2 branch instrumentations
end)

addTest("regression: instrumentSource Promise.is", function()
	local coverage = parser.ensureCoverage()
	local source = [[if objectMetatable == Promise then
    return true
elseif objectMetatable == nil then
    return isCallable(object.andThen)
elseif
    type(objectMetatable) == "table"
    and type(rawget(objectMetatable, "__index")) == "table"
    and isCallable(rawget(rawget(objectMetatable, "__index"), "andThen"))
then
    return true
end]]
	local instrumented, added = parser.instrumentSource(source, "test.lua", coverage)

	expect(instrumented).toBe([[if objectMetatable == Promise then
    _G.__covbranch(1, 0); _G.__covhit(1); return true
elseif objectMetatable == nil then
    _G.__covbranch(1, 1); _G.__covhit(2); return isCallable(object.andThen)
elseif
    type(objectMetatable) == "table"
    and type(rawget(objectMetatable, "__index")) == "table"
    and isCallable(rawget(rawget(objectMetatable, "__index"), "andThen"))
then
    _G.__covbranch(1, 2); _G.__covhit(3); return true
end]])

	expect(added).toBe(6)
end)

addTest("regression: instrumentSource Error.extend", function()
	local coverage = parser.ensureCoverage()
	local source = [[function Error:extend(options)
    options = options or {}

    options.kind = options.kind or self.kind

    return Error.new(options, self)
end]]
	local instrumented, added = parser.instrumentSource(source, "test.lua", coverage)
	expect(instrumented).toBe([[function Error:extend(options) _G.__covfn(1);
    _G.__covhit(1); options = options or {}

    _G.__covhit(2); options.kind = options.kind or self.kind

    _G.__covhit(3); return Error.new(options, self)
end]])
	expect(added).toBe(4)
end)

addTest("regression: instrumentSource circus.test.todo", function()
	local coverage = parser.ensureCoverage()
	local source = [[test.todo = function(testName: Circus_TestName, ...: any): ()
    local rest = { ... }
    if #rest > 0 or typeof(testName) ~= "string" then
        error(ErrorWithStack.new("Todo must be called with only a description.", test.todo))
    end
    return _addTest(testName, "todo", function() end, test.todo)
end]]
	local instrumented, added = parser.instrumentSource(source, "test.lua", coverage)
	expect(instrumented).toBe([[test.todo = function(testName: Circus_TestName, ...: any): () _G.__covfn(1);
    _G.__covhit(1); local rest = { ... }
    if #rest > 0 or typeof(testName) ~= "string" then
        _G.__covbranch(1, 0); _G.__covhit(2); error(ErrorWithStack.new("Todo must be called with only a description.", test.todo))
    end
    return _addTest(testName, "todo", function() _G.__covfn(2); end, test.todo)
end]])
	expect(added).toBe(5)
end)

addTest("regression: instrumentSource JestEnvironmentLuau.new", function()
	local coverage = parser.ensureCoverage()
	local source = [[local JestEnvironmentLuau = {} :: JestEnvironmentLuau;
(JestEnvironmentLuau :: any).__index = JestEnvironmentLuau

function JestEnvironmentLuau.new(config: Config_ProjectConfig): JestEnvironmentLuau
	local self = setmetatable({}, JestEnvironmentLuau)

	self.context = {}
	local global = Object.assign(self.context, config.testEnvironmentOptions)
	self.global = global
	global.global = global

	self.fakeTimers = JestFakeTimers.new()

	return (self :: any) :: JestEnvironmentLuau
end
]]
	local instrumented, added = parser.instrumentSource(source, "test.lua", coverage)
	expect(instrumented).toBe([[_G.__covhit(1); local JestEnvironmentLuau = {} :: JestEnvironmentLuau;
_G.__covhit(2); (JestEnvironmentLuau :: any).__index = JestEnvironmentLuau

function JestEnvironmentLuau.new(config: Config_ProjectConfig): JestEnvironmentLuau _G.__covfn(1);
	_G.__covhit(3); local self = setmetatable({}, JestEnvironmentLuau)

	_G.__covhit(4); self.context = {}
	_G.__covhit(5); local global = Object.assign(self.context, config.testEnvironmentOptions)
	_G.__covhit(6); self.global = global
	_G.__covhit(7); global.global = global

	_G.__covhit(8); self.fakeTimers = JestFakeTimers.new()

	_G.__covhit(9); return (self :: any) :: JestEnvironmentLuau
end
]])
	expect(added).toBe(10)
end)

addTest("regression: instrumentSource JestEach.maybeHandleTemplateString", function()
	local coverage = parser.ensureCoverage()
	local source = [[local next = if i < #templateString then string.sub(templateString, i + 1, i + 1) else nil
if i == #templateString then
    if expressionStarted then
        error("expression not closed")
    end
    table.insert(strings, string.sub(templateString, startIndex))
end]]
	local instrumented, added = parser.instrumentSource(source, "test.lua", coverage)
	expect(instrumented).toBe(
		[[_G.__covhit(1); local next = if i < #templateString then _G.__covbranch(1, 0)(string.sub(templateString, i + 1, i + 1)) else _G.__covbranch(1, 1)(nil)
if i == #templateString then
    _G.__covbranch(2, 0); if expressionStarted then
        _G.__covbranch(3, 0); _G.__covhit(2); error("expression not closed")
    end
    _G.__covhit(3); table.insert(strings, string.sub(templateString, startIndex))
end]]
	)
	expect(added).toBe(7)
end)

addTest("regression: instrumentSource JestEach.each", function()
	local coverage = parser.ensureCoverage()
	local source = [[return setmetatable({
    withGlobal = function(g: Global)
        return function(table_: Global_EachTable, ...)
            return install(g, maybeHandleTemplateString(table_), ...)
        end
    end,
}, {
    __call = function(_self, table_: Global_EachTable, ...): ReturnType<typeof(install)>
        -- ROBLOX deviation: jestMethods, are passed as parameters, not taken from global
        return install(jestMethods :: Global, maybeHandleTemplateString(table_), ...)
    end,
})]]
	local instrumented, added = parser.instrumentSource(source, "test.lua", coverage)
	expect(instrumented).toBe([[_G.__covhit(1); return setmetatable({
    withGlobal = function(g: Global) _G.__covfn(1);
        _G.__covhit(2); return function(table_: Global_EachTable, ...) _G.__covfn(2);
            _G.__covhit(3); return install(g, maybeHandleTemplateString(table_), ...)
        end
    end,
}, {
    __call = function(_self, table_: Global_EachTable, ...): ReturnType<typeof(install)> _G.__covfn(3);
        -- ROBLOX deviation: jestMethods, are passed as parameters, not taken from global
        _G.__covhit(4); return install(jestMethods :: Global, maybeHandleTemplateString(table_), ...)
    end,
})]])
	expect(added).toBe(7)
end)

addTest("regression: instrumentSource JestEach.bind.eachBind", function()
	local coverage = parser.ensureCoverage()
	local source = [[local function eachBind(title: string, test: Global_EachTestFn<EachCallback>, timeout: number?): ()
    title = convertDescriptorToString(title)
end]]
	local instrumented, added = parser.instrumentSource(source, "test.lua", coverage)
	expect(instrumented).toBe(
		[[local function eachBind(title: string, test: Global_EachTestFn<EachCallback>, timeout: number?): () _G.__covfn(1);
    _G.__covhit(1); title = convertDescriptorToString(title)
end]]
	)
	expect(added).toBe(2)
end)

addTest("regression: instrumentSource JestEach.install", function()
	local coverage = parser.ensureCoverage()
	local source = [=[local function install(
	g: Global_Global,
	table_: Global_EachTable,
	...: any --[[ ROBLOX deviation: Upstream array type <Global.TemplateData>. Element type : unknown ]]
)
    local data = if select("#", ...) > 0 then { ... } else {}
end]=]
	local instrumented, added = parser.instrumentSource(source, "test.lua", coverage)
	expect(instrumented).toBe([=[_G.__covhit(1); local function install(
	g: Global_Global,
	table_: Global_EachTable,
	...: any --[[ ROBLOX deviation: Upstream array type <Global.TemplateData>. Element type : unknown ]]
) _G.__covfn(1);
    _G.__covhit(2); local data = if select("#", ...) > 0 then _G.__covbranch(1, 0)({ ... }) else _G.__covbranch(1, 1)({})
end]=])
	expect(added).toBe(5)
end)

addTest("regression: instrumentSource JestEach.bind.applyArguments", function()
	local coverage = parser.ensureCoverage()
	local source = [[return if supportsDone and #params < argumentCount
    then function(done: Global_DoneFn)
        return test(unpackTable(params), done)
    end
    else function()
        return test(unpackTable(params))
    end]]
	local instrumented, added = parser.instrumentSource(source, "test.lua", coverage)
	expect(instrumented).toBe([[_G.__covhit(1); return if supportsDone and #params < argumentCount
    then _G.__covbranch(1, 0)(function(done: Global_DoneFn) _G.__covfn(1);
        _G.__covhit(2); return test(unpackTable(params), done)
    end)
    else _G.__covbranch(1, 1)(function() _G.__covfn(2);
        _G.__covhit(3); return test(unpackTable(params))
    end)]])
	expect(added).toBe(7)
end)

addTest("regression: instrumentSource JestEach.table.interpolation.replaceKeyPathWithValue", function()
	local coverage = parser.ensureCoverage()
	local source = [[function replaceKeyPathWithValue(template: Template): (title: string, match: string) -> string
    return function(title: string, match: string)
        local newMatch = match:gsub("%$", "", 1) -- ROBLOX deviation: escape string
        local keyPath = String.split(newMatch, ".")
        local value = getPath(template, keyPath)
        if isPrimitive(value) then
            return title:gsub(match, tostring(value), 1)
        end
        return title:gsub(match, pretty(value, { maxDepth = 1, min = true }), 1)
    end
end]]
	local instrumented, added = parser.instrumentSource(source, "test.lua", coverage)
	expect(instrumented).toBe(
		[[function replaceKeyPathWithValue(template: Template): (title: string, match: string) -> string _G.__covfn(1);
    _G.__covhit(1); return function(title: string, match: string) _G.__covfn(2);
        _G.__covhit(2); local newMatch = match:gsub("%$", "", 1) -- ROBLOX deviation: escape string
        _G.__covhit(3); local keyPath = String.split(newMatch, ".")
        _G.__covhit(4); local value = getPath(template, keyPath)
        if isPrimitive(value) then
            _G.__covbranch(1, 0); _G.__covhit(5); return title:gsub(match, tostring(value), 1)
        end
        _G.__covhit(6); return title:gsub(match, pretty(value, { maxDepth = 1, min = true }), 1)
    end
end]]
	)
	expect(added).toBe(9)
end)

addTest("regression: instrumentSource circus.combined.dispatch", function()
	local coverage = parser.ensureCoverage()
	local source = [[local function dispatch(event: Circus_AsyncEvent): Promise<nil>
    return Promise.resolve():andThen(function()
        for _, handler in ipairs(eventHandlers) do
            -- ROBLOX deviation START: need to check if value returned is a Promise, otherwise we can't run `:expect()`
            -- ROBLOX FIXME Luau: need to cast handler explicitely as Luau can't infer from type union properly
            local result = (
                handler :: (self: any, event: Circus_AsyncEvent, state: Circus_State) -> nil | Promise<nil>
            )(nil, event, getState())
            if result ~= nil then
                result:expect()
            end
            -- ROBLOX deviation END
        end
    end)
end]]
	local instrumented, added = parser.instrumentSource(source, "test.lua", coverage)
	expect(instrumented).toBe([[local function dispatch(event: Circus_AsyncEvent): Promise<nil> _G.__covfn(1);
    _G.__covhit(1); return Promise.resolve():andThen(function() _G.__covfn(2);
        _G.__covhit(2); for _, handler in ipairs(eventHandlers) do
            -- ROBLOX deviation START: need to check if value returned is a Promise, otherwise we can't run `:expect()`
            -- ROBLOX FIXME Luau: need to cast handler explicitely as Luau can't infer from type union properly
            _G.__covhit(3); local result = (
                handler :: (self: any, event: Circus_AsyncEvent, state: Circus_State) -> nil | Promise<nil>
            )(nil, event, getState())
            if result ~= nil then
                _G.__covbranch(1, 0); _G.__covhit(4); result:expect()
            end
            -- ROBLOX deviation END
        end
    end)
end]])
	expect(added).toBe(7)
end)

addTest("regression: instrumentSource circus.combined.dispatch", function()
	local coverage = parser.ensureCoverage()
	local source = [[local function getTestDuration(test: Circus_TestEntry): number | nil
    local startedAt = test.startedAt
    return if typeof(startedAt) == "number" then DateTime.now().UnixTimestampMillis - startedAt else nil
end]]
	local instrumented, added = parser.instrumentSource(source, "test.lua", coverage)
	expect(instrumented).toBe([[local function getTestDuration(test: Circus_TestEntry): number | nil _G.__covfn(1);
    _G.__covhit(1); local startedAt = test.startedAt
    _G.__covhit(2); return if typeof(startedAt) == "number" then _G.__covbranch(1, 0)(DateTime.now().UnixTimestampMillis - startedAt) else _G.__covbranch(1, 1)(nil)
end]])
	expect(added).toBe(5)
end)

addTest("regression: instrumentSource circus.formatNodeAssertErrors", function()
	local coverage = parser.ensureCoverage()
	local source = [[if originalError == nil then
    error_ = asyncError
    -- ROBLOX deviation START: additional logic to handle Promise library error
elseif originalError.kind == "ExecutionError" then
    error_ = normalizePromiseError(originalError)
    -- ROBLOX deviation END
elseif not Boolean.toJSBoolean(originalError.stack) then
    error_ = asyncError

    error_.message = if Boolean.toJSBoolean(originalError.message)
        then originalError.message
        else ("thrown: %s"):format(prettyFormat(originalError, { maxDepth = 3 }))
    -- ROBLOX deviation START: add __recalculateStacktrace after message has been altered
    Error.__recalculateStacktrace(error_)
    -- ROBLOX deviation END
else
    error_ = originalError
end]]
	local instrumented, added = parser.instrumentSource(source, "test.lua", coverage)
	expect(instrumented).toBe([[if originalError == nil then
    _G.__covbranch(1, 0); _G.__covhit(1); error_ = asyncError
    -- ROBLOX deviation START: additional logic to handle Promise library error
elseif originalError.kind == "ExecutionError" then
    _G.__covbranch(1, 1); _G.__covhit(2); error_ = normalizePromiseError(originalError)
    -- ROBLOX deviation END
elseif not Boolean.toJSBoolean(originalError.stack) then
    _G.__covbranch(1, 2); _G.__covhit(3); error_ = asyncError

    _G.__covhit(4); error_.message = if Boolean.toJSBoolean(originalError.message)
        then _G.__covbranch(2, 0)(originalError.message)
        else _G.__covbranch(2, 1)(("thrown: %s"):format(prettyFormat(originalError, { maxDepth = 3 })))
    -- ROBLOX deviation START: add __recalculateStacktrace after message has been altered
    _G.__covhit(5); Error.__recalculateStacktrace(error_)
    -- ROBLOX deviation END
else
    _G.__covbranch(1, 3); _G.__covhit(6); error_ = originalError
end]])
	expect(added).toBe(12)
end)

addTest("regression: instrumentSource circus.legacy-code-todo-rewrite.jestAdapter._addSnapshotData", function()
	local coverage = parser.ensureCoverage()
	local source = [[results.snapshot.unchecked = if not status.deleted then uncheckedCount else 0
-- Copy the array to prevent memory leaks
results.snapshot.uncheckedKeys = Array.from(uncheckedKeys)]]
	local instrumented, added = parser.instrumentSource(source, "test.lua", coverage)
	expect(instrumented).toBe(
		[[_G.__covhit(1); results.snapshot.unchecked = if not status.deleted then _G.__covbranch(1, 0)(uncheckedCount) else _G.__covbranch(1, 1)(0)
-- Copy the array to prevent memory leaks
_G.__covhit(2); results.snapshot.uncheckedKeys = Array.from(uncheckedKeys)]]
	)
	expect(added).toBe(4)
end)

addTest("regression: instrumentSource JestMockRbx", function()
	local coverage = parser.ensureCoverage()
	local source = [[local CurrentModule = script
local InstanceProxy = require(CurrentModule.InstanceProxy)
local DataModelMocker = require(CurrentModule.DataModelMocker)

export type InstanceProxy<ClassType = Instance> = InstanceProxy.InstanceProxy<ClassType>
export type Spied<ClassType = Instance> = InstanceProxy.Spied<ClassType>
export type ProxyControls<ClassType = Instance> = InstanceProxy.ProxyControls<ClassType>

export type DataModelMocker = DataModelMocker.DataModelMocker

local exports = {}

exports.DataModelMocker = DataModelMocker

return exports]]
	local instrumented, added = parser.instrumentSource(source, "test.lua", coverage)
	expect(instrumented).toBe(
		[[_G.__covhit(1); local CurrentModule = script
_G.__covhit(2); local InstanceProxy = require(CurrentModule.InstanceProxy)
_G.__covhit(3); local DataModelMocker = require(CurrentModule.DataModelMocker)

export type InstanceProxy<ClassType = Instance> = InstanceProxy.InstanceProxy<ClassType>
export type Spied<ClassType = Instance> = InstanceProxy.Spied<ClassType>
export type ProxyControls<ClassType = Instance> = InstanceProxy.ProxyControls<ClassType>

export type DataModelMocker = DataModelMocker.DataModelMocker

_G.__covhit(4); local exports = {}

_G.__covhit(5); exports.DataModelMocker = DataModelMocker

_G.__covhit(6); return exports]]
	)
	expect(added).toBe(6)
end)

addTest("regression: instrumentSource Expect._validateResult", function()
	local coverage = parser.ensureCoverage()
	local source = [[function _validateResult(result: any)
    if
        typeof(result) ~= "table"
        or typeof(result.pass) ~= "boolean"
        or (result.message and typeof(result.message) ~= "string" and typeof(result.message) ~= "function")
    then
        return "hi"
    end
end]]
	local instrumented, added = parser.instrumentSource(source, "test.lua", coverage)
	expect(instrumented).toBe([[function _validateResult(result: any) _G.__covfn(1);
    if
        typeof(result) ~= "table"
        or typeof(result.pass) ~= "boolean"
        or (result.message and typeof(result.message) ~= "string" and typeof(result.message) ~= "function")
    then
        _G.__covbranch(1, 0); _G.__covhit(1); return "hi"
    end
end]])
	expect(added).toBe(3)
end)

addTest("regression: instrumentSource RobloxShared.expect.getObjectSubset", function()
	local coverage = parser.ensureCoverage()
	local source = [[for i, key in
    ipairs(Array.filter(Object.keys(object), function(key)
        return hasPropertyInObject(subset, key)
    end))
do
    print(i, key)
end]]
	local instrumented, added = parser.instrumentSource(source, "test.lua", coverage)
	expect(instrumented).toBe([[_G.__covhit(1); for i, key in
    ipairs(Array.filter(Object.keys(object), function(key) _G.__covfn(1);
        _G.__covhit(2); return hasPropertyInObject(subset, key)
    end))
do
    _G.__covhit(3); print(i, key)
end]])
	expect(added).toBe(4)
end)

addTest("regression: instrumentSource ReactElement.getType", function()
	local coverage = parser.ensureCoverage()
	local source = [[if metatable ~= nil and typeof(metatable.__call) == "function" then
    return if Boolean.toJSBoolean(type_.displayName)
        then type_.displayName
        elseif Boolean.toJSBoolean(type_.name) then type_.name
        else "Unknown"
end]]
	local instrumented, added = parser.instrumentSource(source, "test.lua", coverage)
	expect(instrumented).toBe([[if metatable ~= nil and typeof(metatable.__call) == "function" then
    _G.__covbranch(1, 0); _G.__covhit(1); return if Boolean.toJSBoolean(type_.displayName)
        then _G.__covbranch(2, 0)(type_.displayName)
        elseif Boolean.toJSBoolean(type_.name) then _G.__covbranch(2, 1)(type_.name)
        else _G.__covbranch(2, 2)("Unknown")
end]])
	expect(added).toBe(5)
end)

-- Run the tests
runTests()
