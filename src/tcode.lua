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

-- Constants
local FUELSLOT = 1
local FREESLOT = 16

-- Direction enumerator
local Direction = {
    north = 1,
    south = 2,
    east = 3,
    west = 4
}

-- Movement enumerator
local Movement = {
    forward = 1,
    up = 2,
    down = 3,
    back = 4
}

-- Rotation enumerator
local Rotation = {
    left = 1,
    right = 2
}

-- Value types and associated functions
local Types = {
    number = 1,
    boolean = 2,
    text = 3,
    direction = 4,
    movement = 5,
    rotation = 6
}

-- position & orientation
local loc = {
    home = vector.new(0,0,0),
    position = vector.new(0,0,0),
    rot = Direction.north, --The tracked rotation of the turtle relative to its orientation upon program start
    xRotOffset = 0, --The offset from the tracked rotation that is assumed to point towards the positive x (requires GPS network)
    getOffsetRot = function(loc) return math.fmod(loc.rot+loc.xRotOffset,4) end
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
    labels = {},
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
    user = {},
    startLine = 1 -- This should be the first line of the instruction set (after the file header)
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

-- dig function w/ suck filtering
function dig(dir)

--[[     local function tryDig(trySuck)
        local success = false
        if dir == Movement.forward then
            success = turtle.dig()
        elseif dir == Movement.up then
            success = turtle.digUp()
        elseif dir == Movement.down then
            success = turtle.digDown()
        end
        if success then
            if trySuck then suck(dir) end
            return true
        else
            return false
        end
    end ]]

    local success, data = nil
    if dir == Movement.forward then
        success, data = turtle.inspect()
        return turtle.dig()
    elseif dir == Movement.up then
        success, data = turtle.inspectUp()
        return turtle.digUp()
    elseif dir == Movement.down then
        success, data = turtle.inspectDown()
        return turtle.digDown()
    end
    
    return false

    --[[ local trySuck = not suckonlyincluded
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
    end ]]
end

-- suck function
function suck(dir)
    if dir == Movement.forward then
        return turtle.suck()
    elseif dir == Movement.up then
        return turtle.suckUp()
    elseif dir == Movement.down then
        return turtle.suckDown()
    end
    return false
end


-- turn the turtle and update the 
function turn(dir)
    if dir == Rotation.left then
        turtle.turnLeft()
        loc.rot = math.fmod(loc.rot - 1, 3)
        return true
    elseif dir == Rotation.right then
        turtle.turnRight()
        loc.rot = math.fmod(loc.rot + 1, 3)
        return true
    end
    return false
end

-- turtle move function
function move(dir)
    local function calcMovement(f,u)
        local xMove = (loc.getOffsetRot(loc) - 2) * (loc.getOffsetRot(loc) % 2)
        local zMove = (loc.getOffsetRot(loc) - 3) * ((loc.getOffsetRot(loc) + 1) % 2)
        return vector.new(xMove*f, u, zMove*f)
    end

    if dir == Movement.forward then
        if turtle.forward() then
            loc.position = loc.position + calcMovement(1,0)
        elseif dig(dir) then
            return move(dir)
        end
    elseif dir == Movement.up then
        if turtle.up() then
            loc.position = loc.position + calcMovement(0,1)
        elseif dig(dir) then
            return move(dir)
        end
    elseif dir == Movement.back then
        if turtle.back() then
            loc.position = loc.position + calcMovement(-1,0)
        else
            return false
        end
    elseif dir == Movement.down then
        if turtle.down() then
            loc.position = loc.position + calcMovement(0,-1)
        elseif dig(dir) then
            return move(dir)
        end
    else
        return false
    end
    if tool.digEnabled then dig(tool.tooldir) end
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

-- The super duper, incredible value parser.
function parseValue(val)
    local t = nil
    local v = nil
    if string.sub(val,1,1) == "#" then
        local name = string.sub(val,2,string.len(val))
        if vars.user[name] ~= nil then
            t = vars.user[name].t
            v = vars.user[name].v
        else
            printError("Not a valid user variable.")
        end
    elseif string.sub(val,1,1) == "@" then
        local name = string.sub(val,2,string.len(val))
        if vars.exposed[name] ~= nil then
            local et, ev = vars.exposed[name]()
            t = et
            v = ev
        else
            printError("Not a valid exposed variable.")
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
        elseif string.lower(val) == "north" or string.lower(val) == "south" or string.lower(val) == "east" or string.lower(val) == "west" then
            t = Types.direction
            v = Direction[string.lower(val)]
        elseif string.lower(val) == "forward" or string.lower(val) == "up" or string.lower(val) == "down" or string.lower(val) == "back" then
            t = Types.movement
            v = Movement[string.lower(val)]
        elseif string.lower(val) == "left" or string.lower(val) == "right" then
            t = Types.rotation
            v = Rotation[string.lower(val)]
        else
            t = Types.text
            v = val
        end
    end
    return t, v
end

-- States contain the variables and functions for each run state.
local states = {
    starting = {name = "starting", commands = {}},
    running = {name = "running", commands = {}},
    paused = {name = "paused", commands = {}},
    topos = {name = "topos", commands = {}},
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
    if line == nil or line == "" then
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

states.starting.start = function(args)

    --Clear console
    term.clear()
    term.setCursorPos(1,1)
    print("[tCode v"..version.." by Zuwel]\n")

    --Read and set the args appropriately
    readArgs()
    
    -- Need to add argument checking!!!

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

states.starting.commands["format"] = function(tokens)
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

states.starting.commands["version"] = function(tokens)
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

states.starting.commands["usegps"] = function(tokens)
    local t, v = parseValue(tokens[1])
    if t ~= Types.boolean then
        print("Error: Invalid value '"..tokens[1].."'!")
        return true
    end
    usegps = v
    return true
end

states.starting.commands["~"] = function(tokens)
    vars.startLine = tCodeLine
    tCodeLine = tCodeLine + 1
    changeState("running")
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

    print(state)

    -- Keep iterating through the header until the parser returns false (from header end or critical error)
    while parseLine(tCode[tCodeLine]) and state=="running" do
        --print(tCode[tCodeLine])
        tCodeLine = tCodeLine + 1
        if tCodeLine > #tCode then changeState("completed") break end
    end

end

states.running.commands["move"] = function(tokens)
    local t, v = parseValue(tokens[1])
    if t == Types.movement then
        local rep = 1
        if tokens[2] ~= nil then
            local rt, rv = parseValue(tokens[2])
            if rt ~= Types.number or rv < 1 then
                printError("Invalid repeat value.")
            else
                rep = rv
            end
        end
        for i=1, rep, 1 do
            move(v)
        end
    else
        printError("Invalid value type.")
    end
    return true
end

states.running.commands["turn"] = function(tokens)
    local t, v = parseValue(tokens[1])
    if t == Types.rotation then
        local rep = 1
        if tokens[2] ~= nil then
            local rt, rv = parseValue(tokens[2])
            if rt ~= Types.number or rv < 1 then
                printError("Invalid repeat value.")
            else
                rep = rv
            end
        end
        for i=1, rep, 1 do
            turn(v)
        end
    else
        printError("Invalid value type.")
    end
    return true
end

-- This one will be revised a lot...
states.running.commands["place"] = function(tokens)
    local dt, dv = parseValue(tokens[1]) -- Direction value
    local bt, bv = parseValue(tokens[2]) -- Block value
    -- Fill this in at some point!
end

states.running.commands["dig"] = function(tokens)
    local t, v = parseValue(tokens[1])
    if t == Types.boolean then
        tool.digEnabled = v
    else
        printError("Invalid value type.")
    end
    return true
end

states.running.commands["suck"] = function(tokens)
    local t, v = parseValue(tokens[1])
    if t == Types.boolean then
        tool.suckEnabled = v
    else
        printError("Invalid value type.")
    end
    return true
end

-- Might keep, might remove, still debating
states.running.commands["tooldir"] = function(tokens)
    local t, v = parseValue(tokens[1])
    if t == Types.movement then
        if v ~= Movement.back then
            tool.tooldir = v
        else
            printError("Invalid direction value.")
        end
    else
        printError("Invalid value type.")
    end
    return true
end

states.running.commands["dump"] = function(tokens)
    -- Need a proper item management solution before I can do anything with this.
end

states.running.commands["home"] = function(tokens)
    tCodeLine = tCodeLine + 1
    changeState("topos",{ start = {
        target = loc.home
    }, stop = {}})
end

states.running.commands["pos"] = function(tokens)
    local xt, xv = parseValue(tokens[1])
    local yt, yv = parseValue(tokens[2])
    local zt, zv = parseValue(tokens[3])
    if xt ~= Types.number or yt ~= Types.number or zt ~= Types.number then
        printError("Invalid value types.")
    else
        tCodeLine = tCodeLine + 1
        changeState("topos",{ start = {
            target = vector.new(xv,yv,zv)
        }, stop = {}})
    end
end

states.running.commands["look"] = function(tokens)
    local t, v = parseValue(tokens[1])
    if t ~= Types.direction then
        printError("Invalid value type.")
    else
        -- Rotations can be hard. Once our implementation is better, lets fill this in.
    end
end

states.running.commands["label"] = function(tokens)
    local t, v = parseValue(tokens[1])
    if t == Types.text then
        vars.labels[v] = tCodeLine
    else
        printError("Invalid value type.")
    end
    return true
end

states.running.commands["goto"] = function(tokens)
    local t, v = parseValue(tokens[1])
    if t == Types.text then
        if vars.labels[v] ~= nil then
            tCodeLine = vars.labels[v]
        else
            printError("Invalid label '"..v.."'.")
        end
    elseif t == Types.number then
        if v > vars.startLine and v <= #tCode then
            tCodeLine = v
        else
            printError("Cannot goto line "..v..", out of bounds.")
        end
    else
        printError("Invalid value type.")
    end
    return true
end

states.running.commands["if"] = function(tokens)
    local at, av = parseValue(tokens[1]) -- First value
    local bt, bv = parseValue(tokens[3]) -- Second value
    local et, ev = parseValue(tokens[2]) -- Expression
    if at == nil or bt == nil or et == nil then 
        printError("Invalid arguments.")
        return true
    end
    if at ~= bt then
        printError("Cannot compare values of differing types.")
        return true
    end
    if et == Types.text then
        local result = nil
        if ev == "=" then
            result = av == bv
        elseif ev == "!=" then
            result = av ~= bv
        elseif ev == ">" then
            if at == Types.text then
                printError("Cannot use expression '"..ev.."' with text.")
                return true
            end
            result = av > bv
        elseif ev == "<" then
            if at == Types.text then
                printError("Cannot use expression '"..ev.."' with text.")
                return true
            end
            result = av < bv
        elseif ev == ">=" then
            if at == Types.text then
                printError("Cannot use expression '"..ev.."' with text.")
                return true
            end
            result = av >= bv
        elseif ev == "<=" then
            if at == Types.text then
                printError("Cannot use expression '"..ev.."' with text.")
                return true
            end
            result = av <= bv
        else
            printError("Invalid expression.")
            return true
        end
        
        if result then
            local command = ""
            for i=4, #tokens, 1 do
                command = command..tokens[i].." "
            end
            return parseLine(command)
        end

    else
        printError("Invalid expression value type.")
        return true
    end
end

states.running.commands["var"] = function(tokens)
    local ot, ov = parseValue(tokens[1]) -- Variable operation
    local nt, nv = paresValue(tokens[2]) -- Variable name
    local t, v = parseValue(tokens[3]) -- Value
    if ot == nil or nt == nil or t == nil then 
        printError("Invalid arguments.")
        return true
    end
    -- Fill this part in!
    return true
end

-- This command was made on a whim for testing, but I kind of like it. Might keep it.
states.running.commands["print"] = function(tokens)
    local output = ""
    for i, j in ipairs(tokens) do
        local t, v = parseValue(j)
        output = output..tostring(v).." "
    end
    print(output)
    return true
end

states.running.commands["lowfuelreturn"] = function(tokens)
    local t, v = parseValue(tokens[1])
    if t == Types.boolean then
        lowfuelreturn = v
    else
        error("Invalid value '"..tokens[1].."'!")
    end
    return true
end

states.running.commands["returnmethod"] = function(tokens)
    local t, v = parseValue(tokens[1])
    if t == Types.number then
        returnmethod = math.floor(math.max(0,math.min(v,2)))
    else
        error("Invalid value '"..tokens[1].."'!")
    end
    return true
end

states.running.commands["fuelmargin"] = function(tokens)
    local t, v = parseValue(tokens[1])
    if t == Types.number then
        fuelmargin = math.floor(math.max(0,math.min(v,9999)))
    else
        error("Invalid value '"..tokens[1].."'!")
    end
    return true
end

states.running.commands["digfilter"] = function(tokens)
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

states.running.commands["suckfilter"] = function(tokens)
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

states.running.stop = function(args)
    print("Running state stopping.")
end

states.topos.start = function(args)
    changeState(prevState) -- While we don't have any pathfinding logic, just shove the turtle back into the previous state
end

states.failed.start = function(args)
    print("Failed")
end

states.completed.start = function(args)
    print("Completed")
end

-- Start the program
changeState("starting")
