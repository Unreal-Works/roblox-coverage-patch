local framework = require("./framework")
local expect = framework.expect
local describe = framework.describe
local parser = require("../src/parser")
local ensureCoverage = require("../src/utils/ensureCoverage")

describe("tokenize", function()
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

describe("firstTokenPerLine", function()
	local tokens = parser.tokenize("local x = 1\nlocal y = 2")
	local firstTokens = parser.firstTokenPerLine(tokens)
	expect(firstTokens[1].value).toBe("local")
	expect(firstTokens[2].value).toBe("local")
end)

describe("shouldInstrument", function()
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

describe("extractFunctionName", function()
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

describe("instrumentSource basic", function()
	local coverage = ensureCoverage()
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

-- Edge cases for tokenize
describe("tokenize with strings", function()
	local tokens = parser.tokenize('"hello world"')
	expect(#tokens).toBe(1)
	expect(tokens[1].kind).toBe("string")

	tokens = parser.tokenize("'single quoted'")
	expect(#tokens).toBe(1)
	expect(tokens[1].kind).toBe("string")
end)

describe("tokenize with escaped quotes", function()
	local tokens = parser.tokenize('"hello\\"world"')
	expect(#tokens).toBe(1)
	expect(tokens[1].kind).toBe("string")
end)

describe("tokenize with comments", function()
	local tokens = parser.tokenize("local x = 1 -- comment")
	expect(tokens[4].value).toBe("1")
	expect(#tokens).toBe(4)
end)

describe("tokenize with block comments", function()
	local tokens = parser.tokenize("local x = 1 --[[comment]] + 2")
	expect(#tokens).toBe(6)
	expect(tokens[1].value).toBe("local")
	expect(tokens[4].value).toBe("1")
	expect(tokens[5].value).toBe("+")
	expect(tokens[6].value).toBe("2")
end)

describe("tokenize with numbers", function()
	local tokens = parser.tokenize("1 2.5 1e10 1E-5")
	expect(#tokens).toBe(4)
	expect(tokens[1].value).toBe("1")
	expect(tokens[2].value).toBe("2.5")
	expect(tokens[3].value).toBe("1e10")
	expect(tokens[4].value).toBe("1E-5")
end)

describe("tokenize with operators", function()
	local tokens = parser.tokenize("a == b and c ~= d or e <= f")
	expect(tokens[2].value).toBe("==")
	expect(tokens[4].value).toBe("and")
	expect(tokens[6].value).toBe("~=")
	expect(tokens[8].value).toBe("or")
	expect(tokens[10].value).toBe("<=")
end)

describe("tokenize with ellipsis", function()
	local tokens = parser.tokenize("function f(...) end")
	expect(#tokens).toBe(6)
	expect(tokens[4].value).toBe("...")
end)

describe("tokenize with long strings", function()
	local tokens = parser.tokenize("x = [[hello\nworld]]")
	expect(#tokens).toBe(3)
	expect(tokens[1].value).toBe("x")
	expect(tokens[2].value).toBe("=")
	expect(tokens[3].kind).toBe("string")
end)

describe("tokenize empty string", function()
	local tokens = parser.tokenize("")
	expect(#tokens).toBe(0)
end)

describe("tokenize only whitespace", function()
	local tokens = parser.tokenize("   \n  \t  ")
	expect(#tokens).toBe(0)
end)

-- Edge cases for extractFunctionName
describe("extractFunctionName with nested dots", function()
	local tokens = parser.tokenize("function obj.sub.method() end")
	local name = parser.extractFunctionName(tokens, 2)
	expect(name).toBe("obj.sub.method")
end)

describe("extractFunctionName with colon", function()
	local tokens = parser.tokenize("function a:b:c() end")
	local name = parser.extractFunctionName(tokens, 2)
	expect(name).toBe("a:b:c")
end)

describe("extractFunctionName with mixed separators", function()
	local tokens = parser.tokenize("function obj.method:other() end")
	local name = parser.extractFunctionName(tokens, 2)
	expect(name).toBe("obj.method:other")
end)

describe("extractFunctionName out of bounds", function()
	local tokens = parser.tokenize("function")
	local name = parser.extractFunctionName(tokens, 100)
	expect(name).toBe("<anonymous>")
end)

describe("extractFunctionName no identifier", function()
	local tokens = parser.tokenize("function (x) end")
	local name = parser.extractFunctionName(tokens, 2)
	expect(name).toBe("<anonymous>")
end)

-- Edge cases for instrumentSource
describe("instrumentSource empty source", function()
	local coverage = ensureCoverage()
	local instrumented, added = parser.instrumentSource("", "test.lua", coverage)
	expect(instrumented).toBe("")
	expect(added).toBe(0)
end)

describe("instrumentSource only whitespace", function()
	local coverage = ensureCoverage()
	local instrumented, added = parser.instrumentSource("   \n  \n  ", "test.lua", coverage)
	expect(instrumented).toBe("   \n  \n  ")
	expect(added).toBe(0)
end)

describe("instrumentSource type", function()
	local coverage = ensureCoverage()
	local instrumented, added = parser.instrumentSource("type ABC = string", "test.lua", coverage)
	expect(instrumented).toBe("type ABC = string")
	expect(added).toBe(0)
end)

describe("instrumentSource export type", function()
	local coverage = ensureCoverage()
	local instrumented, added = parser.instrumentSource("export type ABC = string", "test.lua", coverage)
	expect(instrumented).toBe("export type ABC = string")
	expect(added).toBe(0)
end)

describe("instrumentSource with function", function()
	local coverage = ensureCoverage()
	local source = [[function test()
  return 1
end]]
	local instrumented, added = parser.instrumentSource(source, "test.lua", coverage)
	expect(added > 0).toBe(true)

	expect(instrumented).toBe([[function test() _G.__covfn(1);
  _G.__covhit(1); return 1
end]])
end)

describe("instrumentSource with multiple functions", function()
	local coverage = ensureCoverage()
	local source = [[function f1() end
function f2() end]]
	local instrumented, added = parser.instrumentSource(source, "test.lua", coverage)

	expect(instrumented).toBe([[function f1() _G.__covfn(1); _G.__covhit(1); end
function f2() _G.__covfn(2); _G.__covhit(2); end]])
	expect(added > 0).toBe(true)
end)

describe("instrumentSource with nested if", function()
	local coverage = ensureCoverage()
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

describe("instrumentSource with if-elseif-else", function()
	local coverage = ensureCoverage()
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

describe("instrumentSource with comments", function()
	local coverage = ensureCoverage()
	local source = [[local x = 1 -- this is a comment
if x then
end]]
	local instrumented, added = parser.instrumentSource(source, "test.lua", coverage)
	expect(instrumented).toBe([[_G.__covhit(1); local x = 1 -- this is a comment
if x then
_G.__covbranch(1, 0); end]])
	expect(added).toBe(2)
end)

describe("instrumentSource with long strings", function()
	local coverage = ensureCoverage()
	local source = "local x = [[hello\nworld]]\nlocal y = 2"
	local instrumented, added = parser.instrumentSource(source, "test.lua", coverage)
	expect(instrumented).toBe("_G.__covhit(1); local x = [[hello\nworld]]\n_G.__covhit(2); local y = 2")
	expect(added).toBe(2)
end)

describe("instrumentSource with indentation", function()
	local coverage = ensureCoverage()
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

describe("instrumentSource with multi-line if condition", function()
	local coverage = ensureCoverage()
	local source = "if x == 1\n\tand y == 2 then\n\treturn true\nend"
	local instrumented, added = parser.instrumentSource(source, "test.lua", coverage)
	expect(instrumented).toBe("if x == 1\n\tand y == 2 then\n\t_G.__covbranch(1, 0); _G.__covhit(1); return true\nend")
	expect(added).toBe(2)
end)

describe("instrumentSource with multi-line elseif condition", function()
	local coverage = ensureCoverage()
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

describe("instrumentSource does not instrument on strings", function()
    local coverage = ensureCoverage()
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

describe("instrumentSource object assignments", function()
    local coverage = ensureCoverage()
    local source = [[function meta:__newindex(key: unknown, value: unknown): ()
    (original :: any)[key] = value
end]]
    local instrumented, added = parser.instrumentSource(source, "test.lua", coverage)
    expect(instrumented).toBe([[function meta:__newindex(key: unknown, value: unknown): () _G.__covfn(1);
    _G.__covhit(1); (original :: any)[key] = value
end]])
    expect(added).toBe(2)
end)

describe("instrumentSource elseif with body on next line", function()
	local coverage = ensureCoverage()
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

describe("instrumentSource with function literal in method call", function()
	local coverage = ensureCoverage()
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

describe("instrumentSource with literal in function call arguments", function()
	local coverage = ensureCoverage()
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

describe("instrumentSource with multi-line function signature", function()
	local coverage = ensureCoverage()
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

describe("instrumentSource with if statement branch instrumentation", function()
	local coverage = ensureCoverage()
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

describe("instrumentSource with ternary expression", function()
	local coverage = ensureCoverage()
	local source = [[local result = if condition then "true" else "false"]]
	local instrumented, added = parser.instrumentSource(source, "test.lua", coverage)
	-- Should have hit instrumentation for the local statement
	-- Should have branch instrumentation for ternary expressions
	expect(instrumented).toBe(
		[[_G.__covhit(1); local result = if condition then _G.__covbranch(1, 0)("true") else _G.__covbranch(1, 1)("false")]]
	)
	expect(added).toBe(3) -- 1 hit + 2 branch instrumentations
end)

describe("instrumentSource with complex ternary expression", function()
	local coverage = ensureCoverage()
	local source =
		[[local tests = if isArrayTable(taggedTemplateData) then buildArrayTests(title, table_) else buildTemplateTests(title, table_, taggedTemplateData)]]
	local instrumented, added = parser.instrumentSource(source, "test.lua", coverage)
	expect(instrumented).toBe(
		[[_G.__covhit(1); local tests = if isArrayTable(taggedTemplateData) then _G.__covbranch(1, 0)(buildArrayTests(title, table_)) else _G.__covbranch(1, 1)(buildTemplateTests(title, table_, taggedTemplateData))]]
	)
	expect(added).toBe(3) -- 1 hit + 2 branch instrumentations
end)

describe("instrumentSource with multi-line ternary expression", function()
	local coverage = ensureCoverage()
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

describe("regression: instrumentSource Promise.is", function()
	local coverage = ensureCoverage()
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

describe("regression: instrumentSource Error.extend", function()
	local coverage = ensureCoverage()
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

describe("regression: instrumentSource circus.test.todo", function()
	local coverage = ensureCoverage()
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

describe("regression: instrumentSource JestEnvironmentLuau.new", function()
	local coverage = ensureCoverage()
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

describe("regression: instrumentSource JestEach.maybeHandleTemplateString", function()
	local coverage = ensureCoverage()
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

describe("regression: instrumentSource JestEach.each", function()
	local coverage = ensureCoverage()
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

describe("regression: instrumentSource JestEach.bind.eachBind", function()
	local coverage = ensureCoverage()
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

describe("regression: instrumentSource JestEach.install", function()
	local coverage = ensureCoverage()
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

describe("regression: instrumentSource JestEach.bind.applyArguments", function()
	local coverage = ensureCoverage()
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

describe("regression: instrumentSource JestEach.table.interpolation.replaceKeyPathWithValue", function()
	local coverage = ensureCoverage()
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

describe("regression: instrumentSource circus.combined.dispatch", function()
	local coverage = ensureCoverage()
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

describe("regression: instrumentSource circus.combined.dispatch", function()
	local coverage = ensureCoverage()
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

describe("regression: instrumentSource circus.formatNodeAssertErrors", function()
	local coverage = ensureCoverage()
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

describe("regression: instrumentSource circus.legacy-code-todo-rewrite.jestAdapter._addSnapshotData", function()
	local coverage = ensureCoverage()
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

describe("regression: instrumentSource JestMockRbx", function()
	local coverage = ensureCoverage()
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

describe("regression: instrumentSource Expect._validateResult", function()
	local coverage = ensureCoverage()
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

describe("regression: instrumentSource RobloxShared.expect.getObjectSubset", function()
	local coverage = ensureCoverage()
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

describe("regression: instrumentSource ReactElement.getType", function()
	local coverage = ensureCoverage()
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

describe("regression: instrumentSource ReactElement.getType isForwardRef case", function()
	local coverage = ensureCoverage()
	local source = [[local functionName = if typeof(type_.render) == "function"
        and Boolean.toJSBoolean(debug.info(type_.render, "n"))
    then debug.info(type_.render, "n")
    else if typeof(type_.render) == "table"
        then if Boolean.toJSBoolean(type_.render.displayName)
            then type_.render.displayName
            elseif Boolean.toJSBoolean(type_.render.name) then type_.render.name
            else ""
        else ""]]
	local instrumented, added = parser.instrumentSource(source, "test.lua", coverage)
	expect(instrumented).toBe([[_G.__covhit(1); local functionName = if typeof(type_.render) == "function"
        and Boolean.toJSBoolean(debug.info(type_.render, "n"))
    then _G.__covbranch(1, 0)(debug.info(type_.render, "n"))
    else _G.__covbranch(1, 1)(if typeof(type_.render) == "table"
        then _G.__covbranch(2, 0)(if Boolean.toJSBoolean(type_.render.displayName)
            then _G.__covbranch(3, 0)(type_.render.displayName)
            elseif Boolean.toJSBoolean(type_.render.name) then _G.__covbranch(3, 1)(type_.render.name)
            else _G.__covbranch(3, 2)(""))
        else _G.__covbranch(2, 1)(""))]])
	expect(added).toBe(8)
end)

describe("regression: instrumentSource ChalkLua.stringEncaseCRLFWithFirstIndex", function()
	local coverage = ensureCoverage()
	local source = [[repeat
    local gotCR = string.sub(string_, index - 1, index - 1) == "\r"
    returnValue ..= string.sub(string_, endIndex, if gotCR then index - 2 else index - 1) .. prefix .. (if gotCR
        then "\r\n"
        else "\n") .. postfix
    endIndex = index + 1
    index = string.find(string_, "\n", endIndex)
until not (index ~= nil)]]
	local instrumented, added = parser.instrumentSource(source, "test.lua", coverage)
	expect(instrumented).toBe([[_G.__covhit(1); repeat
    _G.__covhit(2); local gotCR = string.sub(string_, index - 1, index - 1) == "\r"
    _G.__covhit(3); returnValue ..= string.sub(string_, endIndex, if gotCR then _G.__covbranch(1, 0)(index - 2) else _G.__covbranch(1, 1)(index - 1)) .. prefix .. (if gotCR
        then _G.__covbranch(2, 0)("\r\n")
        else _G.__covbranch(2, 1)("\n")) .. postfix
    _G.__covhit(4); endIndex = index + 1
    _G.__covhit(5); index = string.find(string_, "\n", endIndex)
until not (index ~= nil)]])
	expect(added).toBe(9)
end)

describe("regression: instrumentSource Collections.printTableEntries", function()
	local coverage = ensureCoverage()
	local source = [[if config.compareKeys ~= nil and config.compareKeys ~= Object.None
    then config.compareKeys
    else function(a, b)
        return if type(a) .. tostring(a) < type(b) .. tostring(b)
            then -1
            else if type(a) .. tostring(a) == type(b) .. tostring(b) then 0 else 1
    end
end]]
	local instrumented, added = parser.instrumentSource(source, "test.lua", coverage)
	expect(instrumented).toBe([[if config.compareKeys ~= nil and config.compareKeys ~= Object.None
    then _G.__covbranch(1, 0)(config.compareKeys)
    else _G.__covbranch(1, 1)(function(a, b) _G.__covfn(1);
        _G.__covhit(1); return if type(a) .. tostring(a) < type(b) .. tostring(b)
            then _G.__covbranch(2, 0)(-1)
            else _G.__covbranch(2, 1)(if type(a) .. tostring(a) == type(b) .. tostring(b) then _G.__covbranch(3, 0)(0) else _G.__covbranch(3, 1)(1))
    end)
end]])
	expect(added).toBe(8)
end)
