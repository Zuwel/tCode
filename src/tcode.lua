--[[tCode Interpreter and Execution Script]]--
--{made by Zuwel}--
--
-- GitHub (Source Code and Usage): https://github.com/Zuwel/tCode
--
args = {...}

local format = "tcode"
local version = 1.0

local tCodeFile = nil
local tCode = {}
local tCodeLine = 0

-- Header vars
local usegps = true
local lowfuelreturn = true
local returnmethod = 0
local fuelmargin = 10
local digfilter = {}
local digonlyincluded = false -- true if there are any include filters in the dig filter table
local suckfilter = {}
local suckonlyincluded = false -- true if there are any include filters in the suck filter table


-- Direction enumerator
local Direction = {
    north = 1,
    south = 2,
    east = 3,
    west = 4
}

-- Value types and associated functions
local Types = {
    number = 1,
    boolean = 2,
    text = 3,
    direction = 4,
}

-- position & orientation
local loc = {
    home = vector.new(0,0,0),
    position = vector.new(0,0,0),
    rot = Direction.north, --The tracked rotation of the turtle relative to its orientation upon program start
    xRotOffset = 0, --The offset from the tracked rotation that is assumed to point towards the positive x (requires GPS network)
    getOffsetRot = function(self) return math.fmod(self.rot+self.xRotOffset,4) end
}

-- both safetys enabled by default
local tool = {
    digEnabled = false,
    suckEnabled = false,
    tooldir = "d"
}

-- Program relevant variables
local vars = {
    -- Argument vars
    args = {
        filePath = args[1],
        host = ""
    },
    -- Exposed vars - accessible within the tcode
    exposed = {
        posx = function() return Types.number, loc.position.x end,
        posy = function() return Types.number, loc.position.y end,
        posz = function() return Types.number, loc.position.z end,
        dir = function() return Types.number, loc.getOffsetRot() end,
        dig = function() return Types.boolean, tool.digEnabled end,
        suck = function() return Types.boolean, tool.suckEnabled end,
    },
    -- User vars - mutable variables within the tcode
    user = {}
}


--automatically assign values to program vars from the arguments
function readArgs()
    for i, j in ipairs(args) do
        for k, v in pairs(vars.args) do
            if j == k then
                vars.args[k] = args[i+1]
                i = i+1
                break
            end
        end
    end
end

-- Checks if file exists and loads it
function loadFile()
    if fs.find(vars.args.filePath) then
        tCodeFile = fs.open(vars.args.filePath,"r")
        local line = tCodeFile.readLine()
        while line ~= nil do
            table.insert(tCode,line)
            line = tCodeFile.readLine()
        end
        tCodeFile.close()
        return true
    else
        return false
    end
end

--locates the turtle in world space
function gpsLocate()
    --get first location
    loc1 = vector.new(gps.locate(2, false))
    --move to second location
    if not turtle.forward() then
        for j=1,3 do
            if not turtle.forward() then
                turn("r")
            else break end
        end
    end
    --get second location
    loc2 = vector.new(gps.locate(2, false))
    heading = loc2 - loc1
    return loc1, ((heading.x + math.abs(heading.x) * 2) + (heading.z + math.abs(heading.z) * 3))
end

function getOffsetRot()
    
end

-- dig function w/ suck filtering
function dig(dir)

    local function tryDig(trySuck)
        local success = false
        if dir == "f" then
            success = turtle.dig()
        elseif dir == "u" then
            success = turtle.digUp()
        elseif dir == "d" then
            success = turtle.digDown()
        end
        if success then
            if trySuck then suck(dir) end
            return true
        else
            return false
        end
    end

    local success, data = nil
    if dir == "f" then
        success, data = turtle.inspect()
    elseif dir == "u" then
        success, data = turtle.inspectUp()
    elseif dir == "d" then
        success, data = turtle.inspectDown()
    else
        return false
    end
    local trySuck = not suckonlyincluded
    if success then
        for k, v in pairs(digfilter) do
            if data.name == k then
                if v then
                    for sk, sv in pairs(suckfilter) do
                        if data.name == sk then
                            trySuck = sv
                        end
                    end
                    return tryDig(trySuck)
                end
            end
        end
        if not digonlyincluded then
            return tryDig()
        end
    end
    return false
end

-- suck function
function suck(dir)
    if dir == "f" then
        return turtle.suck()
    elseif dir == "u" then
        return turtle.suckUp()
    elseif dir == "d" then
        return turtle.suckDown()
    end
    return false
end


-- turn the turtle and update the 
function turn(dir)
    if dir == "l" then
        turtle.turnLeft()
        rot = math.fmod(rot - 1, 3)
        return true
    elseif dir == "r" then
        turtle.turnRight()
        rot = math.fmod(rot + 1, 3)
        return true
    else
        return false
    end
end

-- turtle move function
function move(dir)
    local function calcMovement(f,u)
        local xMove = (getOffsetRot() - 2) * (getOffsetRot() % 2)
        local zMove = (getOffsetRot() - 3) * ((getOffsetRot() + 1) % 2)
        return vector.new(xMove*f, u, zMove*f)
    end

    if dir == "f" then
        if turtle.forward() then
            position = position + calcMovement(1,0)
        elseif dig() then
            return true
        end
    elseif dir == "u" then
        if turtle.up() then
            position = position + calcMovement(0,1)
        elseif dig() then
            return true
        end
    elseif dir == "b" then
        if turtle.back() then
            position = position + calcMovement(-1,0)
        else
            return false
        end
    elseif dir == "d" then
        if turtle.down() then
            position = position + calcMovement(0,1)
        elseif dig() then
            return true
        end
    else
        return false
    end
    dig(tooldir)
end

function splitTokens(line)
    if line == nil then return {} end
    local key = nil
    local tokens = {}
    for i in string.gmatch(line, "%S+") do
        if key == nil then key = i
        else table.insert(tokens,i) end
    end
    return key, tokens
end

function parseValue(val)
    local t = nil
    local v = nil
    if string.sub(val,1,1) == "#" then
        local name = string.sub(val,2,string.len(val))
        if vars.user[name] ~= nil then
            t = vars.user[name].t
            v = vars.user[name].v
        else
            error("Not a valid user variable.")
        end
    elseif string.sub(val,1,1) == "@" then
        local name = string.sub(val,2,string.len(val))
        if vars.exposed[name] ~= nil then
            local et, ev = vars.exposed[name]()
            t = et
            v = ev
        else
            error("Not a valid exposed variable.")
        end
    else
        if val == "true" then
            t = Types.boolean
            v = true
        elseif val == "false" then
            t = Types.boolean
            v = false
        elseif tonumber(val) ~= nil then
            t = Types.number
            v = tonumber(val)
        else
            t = Types.text
            v = val
        end
    end
    return t, v
end

local labels = {}

-- States contain the variables and functions for each run state.
local states = {
    starting = {name = "starting", commands = {}},
    running = {name = "running", commands = {}},
    paused = {name = "paused", commands = {}},
    gohome = {name = "gohome", commands = {}},
    nofuel = {name = "nofuel", commands = {}},
    failed = {name = "failed", commands = {}},
    completed = {name = "completed", commands = {}},
}

local state = nil -- The active state of the turtle
local prevState = nil -- The previously active state

-- Used to change the active state, running the associated scripts with either
local function changeState(newState,...)
    local startArgs = {}
    local stopArgs = {}
    if args.start ~= nil then startArgs = args.start end
    if args.stop ~= nil then stopArgs = args.stop end
    if newState == nil then return false end
    if states[newState] == nil then return false end
    if state ~= nil then
        -- set the prev state and run its stop function
        prevState = state
        if states[prevState].stop ~= nil then -- if a stop function is available, run it and feed in the arguments
            states[prevState].stop(stopArgs)
        end
    end
    -- set the new state and run its start function
    state = newState
    if states[state].start == nil then
        error("No start function for '"..state.."' state.")
        return false
    end
    states[state].start(startArgs)
    return true
end

local function parseLine(line)
    if line == nil then
        print("Can't parse a nil string.")
        return true
    end
    local key, tokens = splitTokens(line)
    if states[state].commands[key] == nil then
        print("No command named '"..key.."' in '"..state.."' state.")
        return true
    end
    local success = states[state].commands[key](tokens)
    return success
end

states.starting.commands.format = function(tokens)
    local t, v = parseValue(tokens[1])
    if t ~= Types.text then
        error("Invalid value type '"..tokens[1].."'!")
        return true
    end
    if v ~= format then
        error("Incompatible format!")
        changeState("failed")
        return false
    end
    return true
end

states.starting.commands.version = function(tokens)
    local t, v = parseValue(tokens[1])
    if t ~= Types.number then
        error("Invalid value '"..tokens[1].."'!")
        return true
    end
    if v ~= version then
        error("Incompatible version!")
        changeState("failed", { start = {}, stop = { run = false }})
        return false
    end
    return true
end

states.starting.commands.usegps = function(tokens)
    local t, v = parseValue(tokens[1])
    if t ~= Types.boolean then
        print("Error: Invalid value '"..tokens[1].."'!")
        return true
    end
    usegps = v
    return true
end

states.starting.commands.lowfuelreturn = function(tokens)
    local t, v = parseValue(tokens[1])
    if t ~= Types.boolean then
        error("Invalid value '"..tokens[1].."'!")
        return true
    end
    lowfuelreturn = v
    return true
end

states.starting.commands.returnmethod = function(tokens)
    local t, v = parseValue(tokens[1])
    if t ~= Types.number then
        error("Invalid value '"..tokens[1].."'!")
        return true
    end
    returnmethod = math.floor(math.max(0,math.min(v,2)))
    return true
end

states.starting.commands.fuelmargin = function(tokens)
    local t, v = parseValue(tokens[1])
    if t ~= Types.number then
        error("Invalid value '"..tokens[1].."'!")
        return true
    end
    fuelmargin = math.floor(math.max(0,math.min(v,9999)))
    return true
end

states.starting.commands.digfilter = function(tokens)
    tCodeLine = tCodeLine + 1 -- increment line
    local line = tCode[tCodeLine]
    if line == nil then return false end
    local key, tokens = splitTokens(line)
    if not key == "+" or not key == "-" then return true end
    while key == "+" or key == "-" do
        if key == "+" then
            digonlyincluded = true
            digfilter[tokens[1]] = true
        elseif key == "-" then
            digfilter[tokens[1]] = false
        end
        tCodeLine = tCodeLine + 1
        line = tCode[tCodeLine]
        if line == nil then break end
        local k, t = splitTokens(line)
        key = k
        tokens = t
    end
    tCodeLine = tCodeLine - 1
    return true
end

states.starting.commands.suckfilter = function(tokens)
    tCodeLine = tCodeLine + 1 -- increment line
    local line = tCode[tCodeLine]
    if line == nil then return false end
    local key, tokens = splitTokens(line)
    if not key == "+" or not key == "-" then return true end
    while key == "+" or key == "-" do
        if key == "+" then
            suckonlyincluded = true
            suckfilter[tokens[1]] = true
        elseif key == "-" then
            suckfilter[tokens[1]] = false
        end
        tCodeLine = tCodeLine + 1
        line = tCode[tCodeLine]
        if line == nil then break end
        local k, t = splitTokens(line)
        key = k
        tokens = t
    end
    tCodeLine = tCodeLine - 1
    return true
end

states.starting.commands._ = function(tokens)
    tCodeLine = tCodeLine + 1
    changeState("running")
end

states.starting.start = function(args)

    --Clear console
    term.clear()
    term.setCursorPos(1,1)
    print("[tCode v"..version.." by Zuwel]\n")

    --Read and set the args appropriately
    readArgs()

    print("Loading tCode file \""..vars.args.filePath.."\"...")
    if not loadFile() then
        error("Failed to load file!")
        changeState("failed")
    end

    tCodeLine = 1 -- Start from the top

    -- Keep iterating through the header until the parser returns false (from header end or critical error)
    while parseLine(tCode[tCodeLine]) and state=="starting" do
        tCodeLine = tCodeLine + 1
    end

end

states.starting.stop = function(args)

    if usegps then
        local gpsPos, gpsHeading = gpsLocate()
        loc.position = gpsPos
        loc.xRotOffset = fmod(2-gpsHeading,4)
    end

    print("Finished reading file header!")

end

states.running.start = function(args)

    -- Keep iterating through the header until the parser returns false (from header end or critical error)
    while parseLine(tCode[tCodeLine]) and state=="running" do
        tCodeLine = tCodeLine + 1
        if tCodeLine > #tCode then changeState("completed") break end
    end

end

-- Turn all this into individual state command functions, this old garbage is gross.
--[[ local function states.running.execute(line)
    
    local tokens = splitTokens(line) -- split line into individual tokens

    if #tokens < 1 then return end

    print(line)
    local key = tokens[1] -- retrieve the key token
    local values = {}
    for i=2, #tokens do
        table.insert(values, tokens[i])
    end

    if key == "move" then
        local dir = string.lower(values[1])
        if dir == "f" or dir == "u" or dir == "b" or dir == "d" then
            move(dir)
            if #values > 1 then
                local rep = tonumber(values[2])
                if rep >= 1 and rep <= 1000 then
                    readCommands(key.." "..dir.." "..tostring(rep-1))
                end
            end
        else
            error("Invalid input '"..dir.."'!")
        end
    elseif key == "turn" then
        local dir = string.lower(values[1])
        if dir == "l" or dir == "r" then
            turn(dir)
            if #values > 1 then
                local rep = tonumber(values[2])
                if rep >= 1 and rep <= 1000 then
                    parallel.waitForAll(readCommands(key.." "..dir.." "..tostring(rep-1)))
                end
            end
        else
            error("Invalid input '"..dir.."'!")
        end
    elseif key == "dig" then
        local bool = string.lower(value[1])
        if bool == "true" then
            digEnabled = true
        elseif bool == "false" then
            digEnabled = false
        else
            error("Invalid value '"..bool.."'!")
        end
    elseif key == "suck" then
        local bool = string.lower(value[1])
        if bool == "true" then
            suckEnabled = true
        elseif bool == "false" then
            suckEnabled = false
        else
            error("Invalid value '"..bool.."'!")
        end
    else
        error("Invalid tCode command '"..line.."'!")
    end

    return

end ]]

states.failed.start = function(args)
    print("Failed")
end

states.completed.start = function(args)
    print("Completed")
end

-- Start the program
changeState("starting")

print("Finished.")
