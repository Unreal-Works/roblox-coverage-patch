-- DataStructures.luau
-- Various data structures implementations

local DataStructures = {}

-- Stack implementation
local Stack = {}
Stack.__index = Stack

function Stack.new()
    return setmetatable({items = {}}, Stack)
end

function Stack:push(item)
    table.insert(self.items, item)
end

function Stack:pop()
    if #self.items == 0 then
        return nil
    end
    return table.remove(self.items)
end

function Stack:peek()
    return self.items[#self.items]
end

function Stack:isEmpty(): boolean
    return #self.items == 0
end

DataStructures.Stack = Stack

-- Queue implementation
local Queue = {}
Queue.__index = Queue

function Queue.new()
    return setmetatable({items = {}, front = 1, rear = 0}, Queue)
end

function Queue:enqueue(item)
    self.rear = self.rear + 1
    self.items[self.rear] = item
end

function Queue:dequeue()
    if self:isEmpty() then
        return nil
    end
    local item = self.items[self.front]
    self.items[self.front] = nil
    self.front = self.front + 1
    return item
end

function Queue:peek()
    return self.items[self.front]
end

function Queue:isEmpty(): boolean
    return self.front > self.rear
end

DataStructures.Queue = Queue

-- Simple hash map
local HashMap = {}
HashMap.__index = HashMap

function HashMap.new()
    return setmetatable({data = {}}, HashMap)
end

function HashMap:put(key, value)
    self.data[key] = value
end

function HashMap:get(key)
    return self.data[key]
end

function HashMap:remove(key)
    local value = self.data[key]
    self.data[key] = nil
    return value
end

function HashMap:contains(key): boolean
    return self.data[key] ~= nil
end

function HashMap:size(): number
    local count = 0
    for _ in pairs(self.data) do
        count = count + 1
    end
    return count
end

DataStructures.HashMap = HashMap

-- Binary search on sorted array
function DataStructures.binarySearch(arr: {number}, target: number): number?
    local left, right = 1, #arr
    while left <= right do
        local mid = math.floor((left + right) / 2)
        if arr[mid] == target then
            return mid
        elseif arr[mid] < target then
            left = mid + 1
        else
            right = mid - 1
        end
    end
    return nil
end

return DataStructures