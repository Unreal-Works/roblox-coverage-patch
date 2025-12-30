-- GameObject.luau
-- A simple game object class

local GameObject = {}
GameObject.__index = GameObject

function GameObject.new(name: string, position: Vector3?): GameObject
    local self = setmetatable({}, GameObject)
    self.name = name
    self.position = position or Vector3.new(0, 0, 0)
    self.health = 100
    self.isActive = true
    return self
end

function GameObject:takeDamage(amount: number)
    self.health = self.health - amount
    if self.health <= 0 then
        self:die()
    end
end

function GameObject:heal(amount: number)
    self.health = math.min(self.health + amount, 100)
end

function GameObject:move(newPosition: Vector3)
    self.position = newPosition
end

function GameObject:die()
    self.isActive = false
    print(self.name .. " has died!")
end

function GameObject:getInfo(): string
    return string.format("Name: %s, Health: %d, Position: (%f, %f, %f)", 
        self.name, self.health, self.position.X, self.position.Y, self.position.Z)
end

-- Static method
function GameObject.createRandom(): GameObject
    local names = {"Player", "Enemy", "NPC", "Item"}
    local randomName = names[math.random(1, #names)]
    local randomPos = Vector3.new(math.random(-10, 10), math.random(-10, 10), math.random(-10, 10))
    return GameObject.new(randomName, randomPos)
end

return GameObject