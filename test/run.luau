local fs = require("@lune/fs")
local framework = require("./framework")

local testFiles = {}

-- Recursively find all .test.luau files in the test directory
local function findTestFiles(dir)
    for _, item in ipairs(fs.readDir(dir)) do
        local fullPath = dir .. "/" .. item
        if fs.isDir(fullPath) then
            findTestFiles(fullPath)
        elseif item:match("%.test%.luau$") then
            table.insert(testFiles, "." .. fullPath:sub(5, -6)) -- Remove the .luau extension
        end
    end
end
findTestFiles("test")

for _, testFile in ipairs(testFiles) do
    require(testFile)
end

framework.run()