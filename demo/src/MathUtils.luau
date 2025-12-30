-- MathUtils.luau
-- A collection of mathematical utility functions

local MathUtils = {}

function MathUtils.add(a: number, b: number): number
    return a + b
end

function MathUtils.subtract(a: number, b: number): number
    return a - b
end

function MathUtils.multiply(a: number, b: number): number
    return a * b
end

function MathUtils.divide(a: number, b: number): number
    if b == 0 then
        error("Division by zero")
    end
    return a / b
end

function MathUtils.factorial(n: number): number
    if n < 0 then
        error("Negative number")
    elseif n == 0 then
        return 1
    else
        local result = 1
        for i = 1, n do
            result = result * i
        end
        return result
    end
end

function MathUtils.isEven(n: number): boolean
    return n % 2 == 0
end

function MathUtils.fibonacci(n: number): number
    if n <= 0 then
        return 0
    elseif n == 1 then
        return 1
    else
        return MathUtils.fibonacci(n - 1) + MathUtils.fibonacci(n - 2)
    end
end

return MathUtils