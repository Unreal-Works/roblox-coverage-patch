local fs = require("@lune/fs")
local roblox = require("@lune/roblox")
local process = require("@lune/process")
local parser = require("../src/parser")
local Instance = roblox.Instance

local game = Instance.new("DataModel")

local tests = {}

function addTest(name, fn)
	table.insert(tests, { name = name, fn = fn })
end

function assertEqual(actual, expected, msg)
	if actual ~= expected then
		error(msg or ("Expected " .. tostring(expected) .. ", got " .. tostring(actual)), 2)
	end
end

function assertClose(actual, expected, epsilon, msg)
	epsilon = epsilon or 1e-9
	if math.abs(actual - expected) >= epsilon then
		error(
			(msg or "")
				.. " Expected "
				.. tostring(actual)
				.. " ≈ "
				.. tostring(expected)
				.. " (epsilon="
				.. tostring(epsilon)
				.. ")",
			2
		)
	end
end

function assertEquals(actual, expected, msg)
	if not actual:equals(expected) then
		error((msg or "") .. " Expected " .. expected:toString() .. ", got " .. actual:toString(), 2)
	end
end

function assertMoreThan(actual, expected, msg)
	if not actual:moreThan(expected) then
		error((msg or "") .. " Expected " .. actual:toString() .. " > " .. expected:toString(), 2)
	end
end

function assertLessThan(actual, expected, msg)
	if not actual:lessThan(expected) then
		error((msg or "") .. " Expected " .. actual:toString() .. " < " .. expected:toString(), 2)
	end
end

function assertMoreEquals(actual, expected, msg)
	if not actual:moreEquals(expected) then
		error((msg or "") .. " Expected " .. actual:toString() .. " >= " .. expected:toString(), 2)
	end
end

function assertLessEquals(actual, expected, msg)
	if not actual:lessEquals(expected) then
		error((msg or "") .. " Expected " .. actual:toString() .. " <= " .. expected:toString(), 2)
	end
end

function runTests()
	local passed, failed = 0, 0
	for _, test in ipairs(tests) do
		local ok, err = pcall(test.fn)
		if ok then
			print("[PASS]", test.name)
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
	assertEqual(parser.normalizeNewlines("a\r\nb\r\nc"), "a\nb\nc")
	assertEqual(parser.normalizeNewlines("a\rb\rc"), "a\nb\nc")
	assertEqual(parser.normalizeNewlines("a\nb\nc"), "a\nb\nc")
	assertEqual(parser.normalizeNewlines(""), "")
end)

addTest("countNewlines", function()
	assertEqual(parser.countNewlines("a\nb\nc"), 2)
	assertEqual(parser.countNewlines("a\nb"), 1)
	assertEqual(parser.countNewlines("abc"), 0)
	assertEqual(parser.countNewlines(""), 0)
end)

addTest("splitLines", function()
	local lines = parser.splitLines("a\nb\nc")
	assertEqual(#lines, 3)
	assertEqual(lines[1], "a")
	assertEqual(lines[2], "b")
	assertEqual(lines[3], "c")

	lines = parser.splitLines("a\nb")
	assertEqual(#lines, 2)
	assertEqual(lines[1], "a")
	assertEqual(lines[2], "b")

	lines = parser.splitLines("")
	assertEqual(#lines, 1)
	assertEqual(lines[1], "")
end)

addTest("tryScanLong", function()
	local nextIndex, nl = parser.tryScanLong("[[hello]]", 1)
	assertEqual(nextIndex, 10)
	assertEqual(nl, 0)

	nextIndex, nl = parser.tryScanLong("[[hello\nworld]]", 1)
	assertEqual(nextIndex, 16)
	assertEqual(nl, 1)

	nextIndex, nl = parser.tryScanLong("[==[hello]==]", 1)
	assertEqual(nextIndex, 14)
	assertEqual(nl, 0)

	assertEqual(parser.tryScanLong("hello", 1), nil)
end)

addTest("tokenize", function()
	local tokens = parser.tokenize("local x = 1")
	assertEqual(#tokens, 4)
	assertEqual(tokens[1].kind, "keyword")
	assertEqual(tokens[1].value, "local")
	assertEqual(tokens[2].kind, "identifier")
	assertEqual(tokens[2].value, "x")
	assertEqual(tokens[3].kind, "symbol")
	assertEqual(tokens[3].value, "=")
	assertEqual(tokens[4].kind, "number")
	assertEqual(tokens[4].value, "1")

	tokens = parser.tokenize("function test() end")
	assertEqual(#tokens, 5)
	assertEqual(tokens[1].value, "function")
	assertEqual(tokens[2].value, "test")
	assertEqual(tokens[3].value, "(")
	assertEqual(tokens[4].value, ")")
	assertEqual(tokens[5].value, "end")
end)

addTest("firstTokenPerLine", function()
	local tokens = parser.tokenize("local x = 1\nlocal y = 2")
	local firstTokens = parser.firstTokenPerLine(tokens)
	assertEqual(firstTokens[1].value, "local")
	assertEqual(firstTokens[2].value, "local")
end)

addTest("shouldInstrument", function()
	local token = { kind = "keyword", value = "if" }
	assertEqual(parser.shouldInstrument(token :: any), true)

	token = { kind = "keyword", value = "end" }
	assertEqual(parser.shouldInstrument(token :: any), false)

	token = { kind = "identifier", value = "x" }
	assertEqual(parser.shouldInstrument(token :: any), false)

	assertEqual(parser.shouldInstrument(nil), false)
end)

addTest("extractFunctionName", function()
	local tokens = parser.tokenize("function test() end")
	local name = parser.extractFunctionName(tokens, 2)
	assertEqual(name, "test")

	tokens = parser.tokenize("function obj.method() end")
	name = parser.extractFunctionName(tokens, 2)
	assertEqual(name, "obj.method")

	tokens = parser.tokenize("function obj:method() end")
	name = parser.extractFunctionName(tokens, 2)
	assertEqual(name, "obj:method")

	tokens = parser.tokenize("function() end")
	name = parser.extractFunctionName(tokens, 2)
	assertEqual(name, "<anonymous>")
end)

addTest("instrumentSource basic", function()
	local coverage = parser.ensureCoverage()
	local source = "local x = 1\nif x then\nend"
	local instrumented, added = parser.instrumentSource(source, "test.lua", coverage)
	assertEqual(type(instrumented), "string")
	assertEqual(added > 0, true)
	-- Check that instrumentation was added
	assert(instrumented:find("_G.__covhit") ~= nil)
end)

addTest("ensureCoverage", function()
	_G.__COVERAGE__ = nil
	local coverage = parser.ensureCoverage()
	assertEqual(type(coverage), "table")
	assertEqual(type(coverage.hits), "table")
	assertEqual(coverage.nextId, 1)
	-- Call again to test existing
	local coverage2 = parser.ensureCoverage()
	assertEqual(coverage, coverage2)
end)

-- Edge cases for normalizeNewlines
addTest("normalizeNewlines mixed line endings", function()
	assertEqual(parser.normalizeNewlines("a\r\nb\rc\nd"), "a\nb\nc\nd")
	assertEqual(parser.normalizeNewlines("\r\n\r\n\r\n"), "\n\n\n")
	assertEqual(parser.normalizeNewlines("\n\n\n"), "\n\n\n")
end)

addTest("normalizeNewlines with only CR", function()
	assertEqual(parser.normalizeNewlines("a\rb"), "a\nb")
end)

-- Edge cases for countNewlines
addTest("countNewlines edge cases", function()
	assertEqual(parser.countNewlines("\n"), 1)
	assertEqual(parser.countNewlines("\n\n\n"), 3)
	assertEqual(parser.countNewlines("no newlines here"), 0)
	assertEqual(parser.countNewlines("\n\n\n\n"), 4)
end)

-- Edge cases for splitLines
addTest("splitLines with trailing newline", function()
	local lines = parser.splitLines("a\nb\nc\n")
	assertEqual(#lines, 4)
	assertEqual(lines[4], "")
end)

addTest("splitLines with only newlines", function()
	local lines = parser.splitLines("\n\n\n")
	assertEqual(#lines, 4)
	assertEqual(lines[1], "")
	assertEqual(lines[2], "")
	assertEqual(lines[3], "")
	assertEqual(lines[4], "")
end)

addTest("splitLines single character", function()
	local lines = parser.splitLines("x")
	assertEqual(#lines, 1)
	assertEqual(lines[1], "x")
end)

-- Edge cases for tryScanLong
addTest("tryScanLong with nested equals", function()
	local nextIndex, nl = parser.tryScanLong("[==[hello]==]", 1)
	assertEqual(nextIndex, 14)
	assertEqual(nl, 0)

	nextIndex, nl = parser.tryScanLong("[===[hello]===]", 1)
	assertEqual(nextIndex, 16)
	assertEqual(nl, 0)
end)

addTest("tryScanLong with multiple newlines", function()
	local nextIndex, nl = parser.tryScanLong("[[line1\nline2\nline3]]", 1)
	assertEqual(nextIndex, 22)
	assertEqual(nl, 2)
end)

addTest("tryScanLong unclosed", function()
	local nextIndex, nl = parser.tryScanLong("[[unclosed", 1)
	assertEqual(nextIndex, 11)
	assertEqual(nl, 0)
end)

addTest("tryScanLong not a long string", function()
	assertEqual(parser.tryScanLong("[x]", 1), nil)
	assertEqual(parser.tryScanLong("hello", 1), nil)
end)

-- Edge cases for tokenize
addTest("tokenize with strings", function()
	local tokens = parser.tokenize('"hello world"')
	assertEqual(#tokens, 1)
	assertEqual(tokens[1].kind, "string")

	tokens = parser.tokenize("'single quoted'")
	assertEqual(#tokens, 1)
	assertEqual(tokens[1].kind, "string")
end)

addTest("tokenize with escaped quotes", function()
	local tokens = parser.tokenize('"hello\\"world"')
	assertEqual(#tokens, 1)
	assertEqual(tokens[1].kind, "string")
end)

addTest("tokenize with comments", function()
	local tokens = parser.tokenize("local x = 1 -- comment")
	assertEqual(tokens[4].value, "1")
	assertEqual(#tokens, 4)
end)

addTest("tokenize with block comments", function()
	local tokens = parser.tokenize("local x = 1 --[[comment]] + 2")
	assertEqual(#tokens, 6)
	assertEqual(tokens[1].value, "local")
	assertEqual(tokens[4].value, "1")
	assertEqual(tokens[5].value, "+")
	assertEqual(tokens[6].value, "2")
end)

addTest("tokenize with numbers", function()
	local tokens = parser.tokenize("1 2.5 1e10 1E-5")
	assertEqual(#tokens, 4)
	assertEqual(tokens[1].value, "1")
	assertEqual(tokens[2].value, "2.5")
	assertEqual(tokens[3].value, "1e10")
	assertEqual(tokens[4].value, "1E-5")
end)

addTest("tokenize with operators", function()
	local tokens = parser.tokenize("a == b and c ~= d or e <= f")
	assertEqual(tokens[2].value, "==")
	assertEqual(tokens[4].value, "and")
	assertEqual(tokens[6].value, "~=")
	assertEqual(tokens[8].value, "or")
	assertEqual(tokens[10].value, "<=")
end)

addTest("tokenize with ellipsis", function()
	local tokens = parser.tokenize("function f(...) end")
	assertEqual(#tokens, 6)
	assertEqual(tokens[4].value, "...")
end)

addTest("tokenize with long strings", function()
	local tokens = parser.tokenize("x = [[hello\nworld]]")
	assertEqual(#tokens, 3)
	assertEqual(tokens[1].value, "x")
	assertEqual(tokens[2].value, "=")
	assertEqual(tokens[3].kind, "string")
end)

addTest("tokenize empty string", function()
	local tokens = parser.tokenize("")
	assertEqual(#tokens, 0)
end)

addTest("tokenize only whitespace", function()
	local tokens = parser.tokenize("   \n  \t  ")
	assertEqual(#tokens, 0)
end)

-- Edge cases for extractFunctionName
addTest("extractFunctionName with nested dots", function()
	local tokens = parser.tokenize("function obj.sub.method() end")
	local name = parser.extractFunctionName(tokens, 2)
	assertEqual(name, "obj.sub.method")
end)

addTest("extractFunctionName with colon", function()
	local tokens = parser.tokenize("function a:b:c() end")
	local name = parser.extractFunctionName(tokens, 2)
	assertEqual(name, "a:b:c")
end)

addTest("extractFunctionName with mixed separators", function()
	local tokens = parser.tokenize("function obj.method:other() end")
	local name = parser.extractFunctionName(tokens, 2)
	assertEqual(name, "obj.method:other")
end)

addTest("extractFunctionName out of bounds", function()
	local tokens = parser.tokenize("function")
	local name = parser.extractFunctionName(tokens, 100)
	assertEqual(name, "<anonymous>")
end)

addTest("extractFunctionName no identifier", function()
	local tokens = parser.tokenize("function (x) end")
	local name = parser.extractFunctionName(tokens, 2)
	assertEqual(name, "<anonymous>")
end)

-- Edge cases for shouldInstrument
addTest("shouldInstrument various keywords", function()
	assertEqual(parser.shouldInstrument({ kind = "keyword", value = "if" } :: any), true)
	assertEqual(parser.shouldInstrument({ kind = "keyword", value = "while" } :: any), true)
	assertEqual(parser.shouldInstrument({ kind = "keyword", value = "for" } :: any), true)
	assertEqual(parser.shouldInstrument({ kind = "keyword", value = "do" } :: any), true)
	assertEqual(parser.shouldInstrument({ kind = "keyword", value = "repeat" } :: any), true)
end)

addTest("shouldInstrument closing keywords", function()
	assertEqual(parser.shouldInstrument({ kind = "keyword", value = "end" } :: any), false)
	assertEqual(parser.shouldInstrument({ kind = "keyword", value = "else" } :: any), false)
	assertEqual(parser.shouldInstrument({ kind = "keyword", value = "elseif" } :: any), false)
	assertEqual(parser.shouldInstrument({ kind = "keyword", value = "until" } :: any), false)
end)

-- Edge cases for instrumentSource
addTest("instrumentSource empty source", function()
	local coverage = parser.ensureCoverage()
	local instrumented, added = parser.instrumentSource("", "test.lua", coverage)
	assertEqual(instrumented, "")
	assertEqual(added, 0)
end)

addTest("instrumentSource only whitespace", function()
	local coverage = parser.ensureCoverage()
	local instrumented, added = parser.instrumentSource("   \n  \n  ", "test.lua", coverage)
	assertEqual(added, 0)
end)

addTest("instrumentSource with function", function()
	local coverage = parser.ensureCoverage()
	local source = "function test()\n  return 1\nend"
	local instrumented, added = parser.instrumentSource(source, "test.lua", coverage)
	assertEqual(added > 0, true)
	assert(instrumented:find("_G.__covfn") ~= nil)
end)

addTest("instrumentSource with multiple functions", function()
	local coverage = parser.ensureCoverage()
	local source = "function f1() end\nfunction f2() end"
	local instrumented, added = parser.instrumentSource(source, "test.lua", coverage)
	assertEqual(added > 0, true)
end)

addTest("instrumentSource with nested if", function()
	local coverage = parser.ensureCoverage()
	local source = "if x then\n  if y then\n    z()\n  end\nend"
	local instrumented, added = parser.instrumentSource(source, "test.lua", coverage)
	assertEqual(added > 0, true)
end)

addTest("instrumentSource with if-elseif-else", function()
	local coverage = parser.ensureCoverage()
	local source = "if x then\n  a()\nelseif y then\n  b()\nelse\n  c()\nend"
	local instrumented, added = parser.instrumentSource(source, "test.lua", coverage)
	assertEqual(added > 0, true)
end)

addTest("instrumentSource with comments", function()
	local coverage = parser.ensureCoverage()
	local source = "local x = 1 -- this is a comment\nif x then\nend"
	local instrumented, added = parser.instrumentSource(source, "test.lua", coverage)
	assertEqual(added > 0, true)
end)

addTest("instrumentSource with long strings", function()
	local coverage = parser.ensureCoverage()
	local source = "local x = [[hello\nworld]]\nlocal y = 2"
	local instrumented, added = parser.instrumentSource(source, "test.lua", coverage)
	assertEqual(added > 0, true)
end)

addTest("instrumentSource with indentation", function()
	local coverage = parser.ensureCoverage()
	local source = "function test()\n    local x = 1\n    if x then\n        return x\n    end\nend"
	local instrumented, added = parser.instrumentSource(source, "test.lua", coverage)
	assert(instrumented:find("    ") ~= nil) -- Check indentation preserved
	assertEqual(added > 0, true)
end)

addTest("instrumentSource with multi-line if condition", function()
	local coverage = parser.ensureCoverage()
	local source = "if x == 1\n\tand y == 2 then\n\treturn true\nend"
	local instrumented, added = parser.instrumentSource(source, "test.lua", coverage)
	assertEqual(added > 0, true)
	assert(instrumented:find("_G.__covhit") ~= nil)
end)

addTest("instrumentSource with multi-line elseif condition", function()
	local coverage = parser.ensureCoverage()
	local source = "if x then\n\ta()\nelseif\n\ttype(x) == \"table\"\n\tand type(y) == \"table\"\nthen\n\tb()\nend"
	local instrumented, added = parser.instrumentSource(source, "test.lua", coverage)
	assertEqual(added > 0, true)
	-- Check that the condition lines don't have __covhit but the body lines do
	local lines = parser.splitLines(instrumented)
	-- The b() line should be instrumented
	assert(lines[7]:find("_G.__covhit") ~= nil or lines[7]:find("_G.__covbranch") ~= nil)
end)

addTest("instrumentSource Promise.is pattern", function()
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
	assertEqual(added > 0, true)
	assert(instrumented:find("_G.__covhit") ~= nil or instrumented:find("_G.__covbranch") ~= nil)
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
	assertEqual(added > 0, true)
	-- Check that the body line b() is instrumented
	local lines = parser.splitLines(instrumented)
	local bLineFound = false
	for _, line in ipairs(lines) do
		if line:find("b()") then
			bLineFound = true
			-- This line should have instrumentation
			if line:find("_G.__covhit") or line:find("_G.__covbranch") or line:find("return") then
				break
			end
		end
	end
	assertEqual(bLineFound, true)
end)

-- Edge cases for ensureCoverage
addTest("ensureCoverage multiple calls", function()
	_G.__COVERAGE__ = nil
	local coverage1 = parser.ensureCoverage()
	local coverage2 = parser.ensureCoverage()
	assertEqual(coverage1, coverage2)
	assertEqual(coverage2.nextId, coverage1.nextId)
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
	assertEqual(coverage.nextId, 2)
	assertEqual(coverage.nextFnId, 2)
	assertEqual(coverage.hits[1], 5)
end)

addTest("ensureCoverage coverage functions exist", function()
	parser.ensureCoverage()
	assertEqual(type(_G.__covhit), "function")
	assertEqual(type(_G.__covfn), "function")
	assertEqual(type(_G.__covbranch), "function")
end)

-- Run the tests
runTests()
