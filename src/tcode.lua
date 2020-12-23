--[[tCode Interpreter and Execution Script]]--
--{made by Zuwel}--
--
-- tCode (turtle-code) format:
-- - HEADER:
-- - - format (string) - the file format, which must read "tCode" for to ensure interpreter compatibility
-- - - version (string) - the tCode version number, used for ensuring interpreter compatibility
-- - - usegps (bool) - if the turtle should use gps
-- - - lowfuelreturn (bool) - if the turtle should automatically return home if it only has the fuel required (plus margin) to return home
-- - - returnmethod (integer) - the method in which the turtle returns home, either by traceback (0), direct path (1), or rise and return (2)
-- - - fuelmargin (integer) - amount of additional fuel saved in addition to the minimum required to return home
-- - - digfilter (array) - array of blocks to consider digging (+) or not (-) ("(+/-) stone") [Warning: Could result in an automatic failure]
-- - -   If any inclusion (+) filters are specified, it is assumed that the turtle will only dig the specified blocks [Warning: Use digfilter inclusions with caution]
-- - - suckfilter (array) - array of blocks/items to consider sucking (+) or not (-) ("(+/-) diamond")
-- - -   If any inclusion (+) filters are specified, it is assumed that the turtle will only suck the specified blocks/items
-- - - _ - a simple marker indicating that the header section has been read to completion
-- - COMMANDS:
-- - - move (f/u/d/b) <value> - moves the turtle either forward (f), up (u), down (d), back (b), with an optional command repeat parameter
-- - - turn (l/r) <value> - turns the turtle either left (l) or right (r), with an optional command repeat parameter
-- - - dig (false/true) - enables (true) or disables (false) the turtles ability to dig
-- - - suck (false/true) - enables (false) or disables (false) the turtles ability to suck
-- - - tooldir (f/u/d) - specifies the relative direction in which the turtle digs and sucks, forward (f), up (u), down (d)
-- - - dump <string> - dumps all items, excluding valid fuel sources, or optionally, all of a specified item in the turtles inventory
-- - - home - turtle attempts to navigate home, either by tracing back its path ()
-- - - pos (x), (y), (z) - automatically tracks back to the specified position using the fastest route, using gps coordinates if possible or relative position.
-- - - look (r) - turns the turtle to face the specified rotation, using gps heading if possible or relative rotation.
-- - - label (string) - a label which references a line position within the tCode file
-- - - goto (string) - skips the execution back to a specified label within the tCode file
-- - - if (value) (expression) (value) (command) (args) -- checks if the comparison is true; if so, it will run the command specified. [if commands can be chained]
-- - - ifnt (value) (expression) (value) (command) (args) -- checks if the comparison is not true; if so, it will run the command specified. [ifnt commands can be chained]
-- - - var (set/unset/add/sub/mult/div) (name) (value) -- sets user variable which can be referenced in tcode with "#<name>"
-- - REDNET COMMANDS:
-- - - TODO

-- ARGS: (* is required)
-- - *filePath (string) - tcode text file path to read from
-- - hostName (string) - host name of the wirelessly controlling computer
args = {...}

local format = "tcode"
local version = "1.0"

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
    position = Vector.new(0,0,0),
    rot = Direction.north, --The tracked rotation of the turtle relative to its orientation upon program start
    xRotOffset = 0, --The offset from the tracked rotation that is assumed to point towards the positive x (requires GPS network)
    getOffsetRot = function(self) return math.fmod(self.rot+self.xRotOffset,4) end
}

-- both safetys enabled by default
local digEnabled = false
local suckEnabled = false
local tooldir = "d"


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
        dig = function() return Types.boolean, digEnabled end,
        suck = function() return Types.boolean, suckEnabled end,
    }
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
    if fs.exists(vars.filePath) then
        tCodeFile = fs.open(vars.filePath,"r")
        local line = tCodeFile.readLine()
        while line ~= nil do
            table.insert(tCode,line)
            line = tCodeFile.readLine()
        end
        print("length: "..#tCode)
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

function error(msg)
    print("Error ("..tCodeLine.."): "..msg)
    return false
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
        v = vars.user[name]
        assert(v ~= nil, "Not a valid user variable.")
    elseif string.sub(val,1,1) == "@" then
        local name = string.sub(val,2,string.len(val))
        v = vars.exposed[name]
        assert(value ~= nil, "Not a valid exposed variable.")
    else
        if str:match
        v = val
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
local function changeState(newState,args)
    startArgs = args.start or {}
    stopArgs = args.stop or {}
    if newState == nil then
        error("")
        exit()
    end
    if states[newState] == nil then return false end
    if not state == nil then
        -- set the prev state and run its stop function
        prevState = state
        if states[prevState].stop ~= nil then -- if a stop function is available, run it and feed in the arguments
            states[prevState].stop(stopArgs)
        end
    end
    -- set the new state and run its start function
    state = newState
    print(assert(states[state].start(startArgs),"No associated start function with "..state))
    return true
end

local function parseLine(line)
    local key, tokens = splitTokens(line)
    if states[state].commands[key] == nil then
        return error("No command named '"..key.."' in active state."))
    end
    local success = states[state].commands[key](tokens)
    return success
end

states.starting.commands.format = function(tokens)
    local t, v = parseValue(tokens[1])
    if t ~= Types.number then
        error("Invalid value '"..tokens[1].."'!")
        return true
    end
    if v ~= version then
        error("Incompatible version!")
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
        changeState("failed", { start = {
            --Failure info goes here
        }, stop = {
            "run" = false
        }})
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
        print("Error: Invalid value '"..tokens[1].."'!")
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
    returnmethod = math.floor(math.max(0,math.min(v,2))
    return true
end

states.starting.commands.fuelmargin = function(tokens)
    local t, v = parseValue(tokens[1])
    if t ~= Types.number then
        error("Invalid value '"..tokens[1].."'!")
        return true
    end
    fuelmargin = math.max(0,math.min(v,turtle.getFuelLimit()))
    return true
end

states.starting.commands._ = function(tokens)
    print("Finished reading file header!")
    changeState("running")
end

states.starting.start = function(args)

    --Clear console
    term.clear()
    term.setCursorPos(1,1)
    print("[tCode v"..version.." by Zuwel]\n")

    --Read and set the args appropriately
    readArgs()

    print("Loading tCode file \""..vars.filePath.."\"...")
    if not loadFile() then
        print("Error: Failed to load file!")
        exit()
    end

    readHeader()
    
    print(tCodeLine)

    if usegps then
        local gpsPos, gpsHeading = gpsLocate()
        loc.position = gpsPos
        loc.xRotOffset = fmod(2-gpsHeading,4)
    end

    tCodeLine = 1 -- Start from the top

    -- Keep iterating through the header until the parser returns false (from header end or critical error)
    while parseLine(tCode[tCodeLine]) do
        tCodeLine = tCodeLine + 1
    end

end

states.start.stop = function(args)

    

end

local function states.start.execute(line)

    tCodeLine = tCodeLine + 1
    if tCodeLine > #tCode then 
        running = false
        return
    end
    local line = tCode[tCodeLine] -- read next line
    print(line)
    local tokens = splitTokens(line) -- split line into individual tokens

    if #tokens < 1 then readHeader() end

    local key = tokens[1] -- retrieve the key token
    local values = {}
    for i=2, #tokens do
        table.insert(values, tokens[i])
    end

    if filter ~= nil then
        if key == "+" then
            if filter == "dig" then
                digfilter[values[1]] = true
                digonlyincluded = true
                readHeader(filter)
            elseif filter == "suck" then
                suckfilter[values[1]] = true
                suckonlyincluded = true
                readHeader(filter)
            else
                print("Error: Invalid header filter '"..filter.."'!")
                readHeader(filter)
                return
            end
        elseif key == "-" then
            if filter == "dig" then
                digfilter[values[1]] = false
                readHeader(filter)
            elseif filter == "suck" then
                suckfilter[values[1]] = false
                readHeader(filter)
            else
                print("Error: Invalid header filter '"..filter.."'!")
                readHeader(filter)
                return
            end
        end
    end

    if key == "digfilter" then
        readHeader("dig")
    elseif key == "suckfilter" then
        readHeader("suck")
    else
        readHeader()
    end
end

local function states.running.execute(line)
    
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

end

-- Start the program
changeState("starting")

print("Finished.")
