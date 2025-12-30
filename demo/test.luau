local ReplicatedStorage = game:GetService("ReplicatedStorage")
local src = ReplicatedStorage:WaitForChild("src")
local MathUtils = require(src.MathUtils)
local GameObject = require(src.GameObject)
local Utils = require(src.Utils)
local DataStructures = require(src.DataStructures)
local Advanced = require(src.Advanced)

local covpatch = require(ReplicatedStorage.covpatch)

covpatch.run()

-- Test MathUtils
print("Testing MathUtils:")
print("5 + 3 =", MathUtils.add(5, 3))
print("10 - 4 =", MathUtils.subtract(10, 4))
print("6 * 7 =", MathUtils.multiply(6, 7))
print("15 / 3 =", MathUtils.divide(15, 3))
print("Factorial of 5 =", MathUtils.factorial(5))
print("Is 4 even?", MathUtils.isEven(4))
print("Fibonacci of 8 =", MathUtils.fibonacci(8))

-- Test GameObject
print("\nTesting GameObject:")
local player = GameObject.new("Player1", Vector3.new(1, 2, 3))
print(player:getInfo())
player:takeDamage(30)
print("After damage:", player:getInfo())
player:heal(20)
print("After heal:", player:getInfo())
player:move(Vector3.new(5, 5, 5))
print("After move:", player:getInfo())

local randomObj = GameObject.createRandom()
print("Random object:", randomObj:getInfo())

-- Test Utils
print("\nTesting Utils:")
print("Reverse 'hello' =", Utils.reverseString("hello"))
print("Is 'racecar' palindrome?", Utils.isPalindrome("racecar"))
local numbers = {1, 2, 3, 4, 5}
print("Sum of {1,2,3,4,5} =", Utils.sumArray(numbers))
print("Max of {1,2,3,4,5} =", Utils.findMax(numbers))
local original = {a = 1, b = {c = 2}}
local copy = Utils.deepCopy(original)
copy.b.c = 3
print("Original b.c =", original.b.c, "Copy b.c =", copy.b.c)
local merged = Utils.mergeTables({x = 1}, {y = 2})
print("Merged table has x and y:", merged.x, merged.y)
print("Random element from numbers:", Utils.getRandomElement(numbers))
local shuffled = Utils.shuffleArray(numbers)
print("Shuffled array:", table.concat(shuffled, ", "))

-- Test DataStructures
print("\nTesting DataStructures:")
local stack = DataStructures.Stack.new()
stack:push(1)
stack:push(2)
stack:push(3)
print("Stack peek:", stack:peek())
print("Stack pop:", stack:pop())
print("Stack is empty?", stack:isEmpty())

local queue = DataStructures.Queue.new()
queue:enqueue("a")
queue:enqueue("b")
queue:enqueue("c")
print("Queue peek:", queue:peek())
print("Queue dequeue:", queue:dequeue())
print("Queue is empty?", queue:isEmpty())

local hashmap = DataStructures.HashMap.new()
hashmap:put("key1", "value1")
hashmap:put("key2", "value2")
print("HashMap get key1:", hashmap:get("key1"))
print("HashMap contains key2:", hashmap:contains("key2"))
print("HashMap size:", hashmap:size())

local sortedArray = {1, 3, 5, 7, 9}
print("Binary search for 5 in sorted array:", DataStructures.binarySearch(sortedArray, 5))

-- Test Advanced
print("\nTesting Advanced:")
local counter = Advanced.createCounter(10)
print("Counter:", counter(), counter(), counter())

local accumulator = Advanced.createAccumulator()
print("Accumulator:", accumulator(5), accumulator(10), accumulator(3))

local pc = Advanced.createProducerConsumer()
coroutine.resume(pc.producer)
coroutine.resume(pc.consumer)
coroutine.resume(pc.producer)
coroutine.resume(pc.consumer)

local readOnly = Advanced.createReadOnlyTable({x = 1, y = 2})
print("Read-only table x:", readOnly.x)

local result = Advanced.match("hello", {
    ["^h"] = function(s) return "Starts with h: " .. s end,
    ["world"] = function(s) return "Is world: " .. s end
})
print("Pattern match result:", result)

local doubled = Advanced.map({1, 2, 3}, function(x) return x * 2 end)
print("Mapped array:", table.concat(doubled, ", "))

local evens = Advanced.filter({1, 2, 3, 4, 5}, function(x) return x % 2 == 0 end)
print("Filtered evens:", table.concat(evens, ", "))

local sum = Advanced.reduce({1, 2, 3, 4}, 0, function(acc, x) return acc + x end)
print("Reduced sum:", sum)

local success, value = Advanced.safeCall(function() return "safe" end)
print("Safe call success:", success, "value:", value)

return covpatch.finalize()