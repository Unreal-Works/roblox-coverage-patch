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
	assertEqual(parser.shouldInstrument(token), true)

	token = { kind = "keyword", value = "end" }
	assertEqual(parser.shouldInstrument(token), false)

	token = { kind = "identifier", value = "x" }
	assertEqual(parser.shouldInstrument(token), false)

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

-- Run the tests
runTests()
