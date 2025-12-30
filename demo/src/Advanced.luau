-- Advanced.luau
-- Advanced Luau features: closures, coroutines, etc.

local Advanced = {}

-- Closure example: counter
function Advanced.createCounter(initial: number): () -> number
    local count = initial
    return function(): number
        count = count + 1
        return count
    end
end

-- Closure example: accumulator
function Advanced.createAccumulator(): (number) -> number
    local sum = 0
    return function(value: number): number
        sum = sum + value
        return sum
    end
end

-- Coroutine example: simple producer-consumer
function Advanced.createProducerConsumer()
    local channel = {}
    
    local producer = coroutine.create(function()
        for i = 1, 10 do
            table.insert(channel, i * 2)
            coroutine.yield()
        end
    end)
    
    local consumer = coroutine.create(function()
        while true do
            if #channel > 0 then
                local value = table.remove(channel, 1)
                print("Consumed:", value)
            else
                coroutine.yield()
            end
        end
    end)
    
    return {
        producer = producer,
        consumer = consumer,
        channel = channel
    }
end

-- Metatable example: read-only table
function Advanced.createReadOnlyTable(tbl: {[any]: any}): {[any]: any}
    local proxy = {}
    local mt = {
        __index = tbl,
        __newindex = function(t, k, v)
            error("Attempt to modify read-only table")
        end,
        __pairs = function(t)
            return pairs(tbl)
        end,
        __ipairs = function(t)
            return ipairs(tbl)
        end
    }
    setmetatable(proxy, mt)
    return proxy
end

-- Pattern matching simulation
function Advanced.match(value: any, patterns: {[any]: (any) -> any}): any
    for pattern, handler in pairs(patterns) do
        if type(pattern) == "string" and type(value) == "string" then
            if string.match(value, pattern) then
                return handler(value)
            end
        elseif pattern == value then
            return handler(value)
        end
    end
    return nil
end

-- Higher-order function: map
function Advanced.map<T, U>(arr: {T}, func: (T) -> U): {U}
    local result = {}
    for i, v in ipairs(arr) do
        result[i] = func(v)
    end
    return result
end

-- Higher-order function: filter
function Advanced.filter<T>(arr: {T}, predicate: (T) -> boolean): {T}
    local result = {}
    for _, v in ipairs(arr) do
        if predicate(v) then
            table.insert(result, v)
        end
    end
    return result
end

-- Higher-order function: reduce
function Advanced.reduce<T, U>(arr: {T}, initial: U, func: (U, T) -> U): U
    local acc = initial
    for _, v in ipairs(arr) do
        acc = func(acc, v)
    end
    return acc
end

-- Error handling with pcall
function Advanced.safeCall(func: () -> any): (boolean, any)
    return pcall(func)
end

return Advanced