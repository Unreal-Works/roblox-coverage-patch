local framework = require("../framework")
local expect = framework.expect
local describe = framework.describe
local normalizeNewlines = require("../../src/string/normalizeNewlines")

describe("normalizeNewlines", function()
	expect(normalizeNewlines("a\r\nb\r\nc")).toBe("a\nb\nc")
	expect(normalizeNewlines("a\rb\rc")).toBe("a\nb\nc")
	expect(normalizeNewlines("a\nb\nc")).toBe("a\nb\nc")
	expect(normalizeNewlines("")).toBe("")
end)

describe("normalizeNewlines mixed line endings", function()
	expect(normalizeNewlines("a\r\nb\rc\nd")).toBe("a\nb\nc\nd")
	expect(normalizeNewlines("\r\n\r\n\r\n")).toBe("\n\n\n")
	expect(normalizeNewlines("\n\n\n")).toBe("\n\n\n")
end)

describe("normalizeNewlines with only CR", function()
	expect(normalizeNewlines("a\rb")).toBe("a\nb")
end)
