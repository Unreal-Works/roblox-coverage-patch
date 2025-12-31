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

-- Run the tests
runTests()
