local framework = require("../../framework")
local expect = framework.expect
local describe = framework.describe
local countNewlines = require("../../../src/utils/string/countNewlines")

describe("countNewlines", function()
	expect(countNewlines("a\nb\nc")).toBe(2)
	expect(countNewlines("a\nb")).toBe(1)
	expect(countNewlines("abc")).toBe(0)
	expect(countNewlines("")).toBe(0)
end)

describe("countNewlines edge cases", function()
	expect(countNewlines("\n")).toBe(1)
	expect(countNewlines("\n\n\n")).toBe(3)
	expect(countNewlines("no newlines here")).toBe(0)
	expect(countNewlines("\n\n\n\n")).toBe(4)
end)
