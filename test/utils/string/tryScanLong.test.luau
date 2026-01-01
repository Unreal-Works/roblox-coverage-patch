local framework = require("../../framework")
local expect = framework.expect
local describe = framework.describe
local tryScanLong = require("../../../src/utils/string/tryScanLong")

describe("tryScanLong", function()
	local nextIndex, nl = tryScanLong("[[hello]]", 1)
	expect(nextIndex).toBe(10)
	expect(nl).toBe(0)

	nextIndex, nl = tryScanLong("[[hello\nworld]]", 1)
	expect(nextIndex).toBe(16)
	expect(nl).toBe(1)

	nextIndex, nl = tryScanLong("[==[hello]==]", 1)
	expect(nextIndex).toBe(14)
	expect(nl).toBe(0)

	expect(tryScanLong("hello", 1)).toBeUndefined()
end)

-- Edge cases for tryScanLong
describe("tryScanLong with nested equals", function()
	local nextIndex, nl = tryScanLong("[==[hello]==]", 1)
	expect(nextIndex).toBe(14)
	expect(nl).toBe(0)

	nextIndex, nl = tryScanLong("[===[hello]===]", 1)
	expect(nextIndex).toBe(16)
	expect(nl).toBe(0)
end)

describe("tryScanLong with multiple newlines", function()
	local nextIndex, nl = tryScanLong("[[line1\nline2\nline3]]", 1)
	expect(nextIndex).toBe(22)
	expect(nl).toBe(2)
end)

describe("tryScanLong unclosed", function()
	local nextIndex, nl = tryScanLong("[[unclosed", 1)
	expect(nextIndex).toBe(11)
	expect(nl).toBe(0)
end)

describe("tryScanLong not a long string", function()
	expect(tryScanLong("[x]", 1)).toBeUndefined()
	expect(tryScanLong("hello", 1)).toBeUndefined()
end)