-- Utils.luau
-- Miscellaneous utility functions

local Utils = {}

function Utils.reverseString(str: string): string
    local reversed = ""
    for i = #str, 1, -1 do
        reversed = reversed .. string.sub(str, i, i)
    end
    return reversed
end

function Utils.isPalindrome(str: string): boolean
    local cleanStr = string.lower(string.gsub(str, "%W", ""))
    return cleanStr == Utils.reverseString(cleanStr)
end

function Utils.sumArray(arr: {number}): number
    local sum = 0
    for _, v in ipairs(arr) do
        sum = sum + v
    end
    return sum
end

function Utils.findMax(arr: {number}): number?
    if #arr == 0 then
        return nil
    end
    local max = arr[1]
    for i = 2, #arr do
        if arr[i] > max then
            max = arr[i]
        end
    end
    return max
end

function Utils.deepCopy(tbl: any): any
    if type(tbl) ~= "table" then
        return tbl
    end
    local copy = {}
    for k, v in pairs(tbl) do
        copy[k] = Utils.deepCopy(v)
    end
    return copy
end

function Utils.mergeTables(t1: {[any]: any}, t2: {[any]: any}): {[any]: any}
    local merged = Utils.deepCopy(t1)
    for k, v in pairs(t2) do
        merged[k] = v
    end
    return merged
end

function Utils.getRandomElement<T>(arr: {T}): T?
    if #arr == 0 then
        return nil
    end
    return arr[math.random(1, #arr)]
end

function Utils.shuffleArray<T>(arr: {T}): {T}
    local shuffled = Utils.deepCopy(arr)
    for i = #shuffled, 2, -1 do
        local j = math.random(1, i)
        shuffled[i], shuffled[j] = shuffled[j], shuffled[i]
    end
    return shuffled
end

return Utils