local framework = require("../../framework")
local expect = framework.expect
local describe = framework.describe
local splitSourceByNewlines = require("../../../src/utils/string/splitSourceByNewlines")

describe("splitSourceByNewlines", function()
	local lines = splitSourceByNewlines("a\nb\nc")
	expect(#lines).toBe(3)
	expect(lines[1]).toBe("a")
	expect(lines[2]).toBe("b")
	expect(lines[3]).toBe("c")

	lines = splitSourceByNewlines("a\nb")
	expect(#lines).toBe(2)
	expect(lines[1]).toBe("a")
	expect(lines[2]).toBe("b")

	lines = splitSourceByNewlines("")
	expect(#lines).toBe(1)
	expect(lines[1]).toBe("")
end)

describe("splitSourceByNewlines with trailing newline", function()
	local lines = splitSourceByNewlines("a\nb\nc\n")
	expect(#lines).toBe(4)
	expect(lines[4]).toBe("")
end)

describe("splitSourceByNewlines with only newlines", function()
	local lines = splitSourceByNewlines("\n\n\n")
	expect(#lines).toBe(4)
	expect(lines[1]).toBe("")
	expect(lines[2]).toBe("")
	expect(lines[3]).toBe("")
	expect(lines[4]).toBe("")
end)

describe("splitSourceByNewlines single character", function()
	local lines = splitSourceByNewlines("x")
	expect(#lines).toBe(1)
	expect(lines[1]).toBe("x")
end)