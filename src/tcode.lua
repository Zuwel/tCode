--[[tCode Interpreter and Execution Script]]--
--{made by Zuwel}--
--
-- GitHub (Source Code and Usage): https://github.com/Zuwel/tCode
--
args = {...}

local format = "tcode"
local version = "1.0"

-- Constants
local FUELSLOT = 1
local EQUIPSLOT = 2
local FREESLOT = 16

-- Direction enumerator
local Direction = {
    north = 0,
    east = 1,
    south = 2,
    west = 3
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

local tCode = {
    file = nil,
    line = 1,
    data = {}
}

-- position & orientation
local loc = {
    home = vector.new(0,0,0),
    position = vector.new(0,0,0),
    heading = Direction.north, --The tracked heading of the turtle relative to its orientation upon program start
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
        heading = function() return Types.direction, loc.heading end,
        dig = function() return Types.boolean, tool.digEnabled end,
        suck = function() return Types.boolean, tool.suckEnabled end,
        line = function() return Types.number, tCode.line end
    },
    -- User vars - mutable variables within the tcode
    user = {},
    formatValid = false,
    versionValid = false,
    startLine = 1, -- This should be the first line of the instruction set (after the file header)
    usegps = true,
    lowfuelreturn = true,
    returnmethod = 0,
    fuelmargin = 10,
    digfilter = {},
    digonlyincluded = false, -- true if there are any include filters in the dig filter table
    suckfilter = {},
    suckonlyincluded = false -- true if there are any include filters in the suck filter table
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
        tCode.file = fs.open(vars.args.filePath,"r")
        local line = tCode.file.readLine()
        while line ~= nil do
            table.insert(tCode.data,line)
            line = tCode.file.readLine()
        end
        tCode.file.close()
        return true
    else
        return false
    end
end

--locates the turtle in world space
function gpsLocate()
    --get first location
    local loc1 = vector.new(gps.locate(2, false))
    --move to second location
    if not turtle.forward() then
        for j=1,3 do
            if not turtle.forward() then
                turtle.turnRight()
            else break end
        end
    end
    --get second location
    local loc2 = vector.new(gps.locate(2, false))
    turtle.back()
    local heading = nil
    if loc2.z < loc1.z then
        heading = Direction.north
    elseif loc2.z > loc1.z then
        heading = Direction.south
    elseif loc2.x < loc1.x then
        heading = Direction.west
    elseif loc2.x > loc1.x then
        heading = Direction.east
    end
    return loc1, heading
end

-- dig function
function dig(dir)

    -- NEED SUCK FILTERING!

    if tool.digEnabled then
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
    end
    return false

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
        loc.heading = math.fmod(loc.heading - 1, 4)
        return true
    elseif dir == Rotation.right then
        turtle.turnRight()
        loc.heading = math.fmod(loc.heading + 1, 4)
        return true
    end
    return false
end

-- turtle move function
function move(dir)
    local function calcMovement(f,u)
        local xMove = 0
        local zMove = 0
        if loc.heading == Direction.north then
            zMove = -1
        elseif loc.heading == Direction.south then
            zMove = 1
        elseif loc.heading == Direction.east then
            xMove = 1
        elseif loc.heading == Direction.west then
            xMove = -1
        end
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
    dig(tool.tooldir)
    return true
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
    local t = nil -- Type
    local v = nil -- Value
    local a = nil -- Alternative string format of value
    if string.sub(val,1,1) == "#" then
        local name = string.sub(val,2,string.len(val))
        if vars.user[name] ~= nil then
            local et, ev = vars.user[name]()
            t = et
            v = ev
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
    if t == Types.direction then
        if v == Direction.north then a = "north" end
        if v == Direction.south then a = "south" end
        if v == Direction.east then a = "east" end
        if v == Direction.west then a = "west" end
    elseif t == Types.movement then
        if v == Movement.forward then a = "forward" end
        if v == Movement.up then a = "up" end
        if v == Movement.down then a = "down" end
        if v == Movement.back then a = "back" end
    elseif t == Types.rotation then
        if v == Rotation.left then a = "left" end
        if v == Rotation.right then a = "right" end
    elseif t ~= Types.text then
        a = tostring(v)
    else
        a = val
    end
    return t, v, a
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
local function changeState(newState,arg)
    local startArgs = {}
    local stopArgs = {}
    if arg ~= nil then
        if arg.start ~= nil then startArgs = arg.start end
        if arg.stop ~= nil then stopArgs = arg.stop end
    end
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
        --printError("Can't parse a nil string.")
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

    -- Clear console
    term.clear()
    term.setCursorPos(1,1)
    print("[tCode v"..version.." by Zuwel]\n")

    -- Read and set the args appropriately
    readArgs()
    
    -- Check if computer is a turtle
    if turtle == nil then
        changeState("failed",{start = {
            error = "Can only run tCode on turtles."
        }})
        return false
    end
    
    -- Argument checks
    if vars.args.filePath == nil then
        changeState("failed", {start = {
            error = "No filepath provided in the launch arguments."
        }, stop = {}})
        return false
    end

    if not fs.exists(vars.args.filePath) then
        changeState("failed", {start = {
            error = "File does not exist at '"..vars.args.filePath.."'."
        }, stop = {}})
        return false
    end

    print("Loading tCode file \""..vars.args.filePath.."\"...")
    if not loadFile() then
        changeState("failed", {start = {
            error = "Failed to load file '"..vars.args.filePath.."'."
        }, stop = {}})
        return false
    end

    tCode.line = 1 -- Start from the top

    -- Keep iterating through the header until the parser returns false (from header end or critical error)
    while parseLine(tCode.data[tCode.line]) and state=="starting" do
        tCode.line = tCode.line + 1
    end

end

states.starting.commands["format"] = function(tokens)
    local t, v = parseValue(tokens[1])
    if t == Types.text then
        print("File format is '"..tokens[1].."'.")
        if v == format then
            vars.formatValid = true
        else
            changeState("failed", {start = {
                error = "Incompatible format."
            }})
            return false
        end
    else
        printError("Invalid value type '"..tokens[1].."'!")
    end

    return true
end

states.starting.commands["version"] = function(tokens)
    local t, v = parseValue(tokens[1])
    if t == Types.number or t == Types.text then
        print("File version is '"..tokens[1].."'.")
        if tokens[1] == version then
            vars.versionValid = true
        else
            changeState("failed", { start = {
                error = "Version mismatch ("..tokens[1].." =/= "..version..")."
            }})
            return false
        end
    else
        printError("Invalid value '"..tokens[1].."'!")
    end
    return true
end

states.starting.commands["usegps"] = function(tokens)
    local t, v = parseValue(tokens[1])
    if t ~= Types.boolean then
        print("Error: Invalid value '"..tokens[1].."'!")
        return true
    end
    vars.usegps = v
    return true
end

states.starting.commands["~"] = function(tokens)
    
    -- Check if format and version were verified
    if not vars.formatValid or not vars.versionValid then
        changeState("failed",{start = {
            error = "Could not validate file format and/or version."
        }})
        return false
    end

    -- Get GPS telemetry
    if vars.usegps then
        print("Acquiring GPS telemetry.")
        local gpsAcquire = false
        if peripheral.find("modem") ~= nil then
            local gpsPos, gpsHeading = gpsLocate()
            if gpsPos ~= nil or gpsHeading ~= nil then
                loc.position = gpsPos
                loc.heading = gpsHeading
                gpsAcquire = true
                print("Successfully acquired GPS telemetry.")
            end
        end
        if not gpsAcquire then
            changeState("failed",{start = {
                error = "Could not acquire GPS telemetry."
            }})
            return false
        end
    end

    vars.startLine = tCode.line
    tCode.line = tCode.line + 1
    print("Finished reading file header.\n---")
    changeState("running")
    return true
end

states.starting.stop = function(args)

end



states.running.start = function(args)

    -- Keep iterating through the header until the parser returns false (from header end or critical error)
    while parseLine(tCode.data[tCode.line]) and state=="running" do
        --print(tCode[tCodeLine])
        tCode.line = tCode.line + 1
        if tCode.line > #tCode.data then changeState("completed") break end
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
    tCode.line = tCode.line + 1
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
        tCode.line = tCode.line + 1
        changeState("topos",{ start = {
            target = vector.new(xv,yv,zv)
        }, stop = {}})
    end
end

states.running.commands["look"] = function(tokens)
    local t, v = parseValue(tokens[1])
    if t == Types.direction then
        if v ~= loc.heading then
            if v == math.fmod(loc.heading - 1, 4) then
                turn(Rotation.left)
            elseif v == math.fmod(loc.heading + 1, 4) then
                turn(Rotation.right)
            else -- Turn 180 deg
                turn(Rotation.right)
                turn(Rotation.right)
            end
        end
    else
        printError("Invalid value type.")
    end
    return true
end

states.running.commands["label"] = function(tokens)
    local t, v = parseValue(tokens[1])
    if t == Types.text then
        vars.labels[v] = tCode.line
    else
        printError("Invalid value type.")
    end
    return true
end

states.running.commands["goto"] = function(tokens)
    local t, v = parseValue(tokens[1])
    if t == Types.text then
        if vars.labels[v] ~= nil then
            tCode.line = vars.labels[v]
        else
            printError("Invalid label '"..v.."'.")
        end
    elseif t == Types.number then
        if v > vars.startLine and v <= #tCode.data then
            tCode.line = v
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
        
        if result ~= nil and result then
            local command = tokens[4]
            for i=5, #tokens, 1 do
                command = command.." "..tokens[i]
            end
            return parseLine(command)
        else
            return true
        end

    else
        printError("Invalid expression value type.")
        return true
    end
end

states.running.commands["var"] = function(tokens)
    local ot, ov = parseValue(tokens[1]) -- Variable operation
    local nt, nv = parseValue(tokens[2]) -- Variable name
    local t, v = parseValue(tokens[3]) -- Value
    if ot == nil or nt == nil then 
        printError("Invalid arguments.")
        return true
    end
    if ot == Types.text then
        ov = string.lower(ov)
        local func = nil -- Final type & value function to set
        if ov == "set" then
            func = function() return t, v end
        elseif vars.user[nv] ~= nil then
            local ut, uv = vars.user[nv]() -- Retrieve existing type and value
            if ov == "unset" then
                vars.user[nv] = nil
            elseif ov == "add" then
                if t == Types.number then
                    local value = uv+v
                    func = function() return Types.number, value end
                elseif t == Types.text then
                    local value = tostring(uv)..v
                    func = function() return Types.text, value end
                end
            end
            if t == Types.number and ut == Types.number then
                if ov == "sub" then
                    local value = uv-v
                    func = function() return Types.number, value end
                elseif ov == "mult" then
                    local value = uv*v
                    func = function() return Types.number, value end
                elseif ov == "div" then
                    local value = uv/v
                    func = function() return Types.number, value end
                end
            end
        end
        if func ~= nil then
            vars.user[tostring(nv)] = func
        end
    else
        printError("Invalid operation value type.")
    end

    return true
end

-- This command was made on a whim for testing, but I kind of like it. Might keep it.
states.running.commands["print"] = function(tokens)
    local output = ""
    for i, j in ipairs(tokens) do
        local t, v, a = parseValue(j)
        output = output..a.." "
    end
    print(output)
    return true
end

states.running.commands["lowfuelreturn"] = function(tokens)
    local t, v = parseValue(tokens[1])
    if t == Types.boolean then
        vars.lowfuelreturn = v
    else
        error("Invalid value '"..tokens[1].."'!")
    end
    return true
end

states.running.commands["returnmethod"] = function(tokens)
    local t, v = parseValue(tokens[1])
    if t == Types.number then
        vars.returnmethod = math.floor(math.max(0,math.min(v,2)))
    else
        error("Invalid value '"..tokens[1].."'!")
    end
    return true
end

states.running.commands["fuelmargin"] = function(tokens)
    local t, v = parseValue(tokens[1])
    if t == Types.number then
        vars.fuelmargin = math.floor(math.max(0,math.min(v,9999)))
    else
        error("Invalid value '"..tokens[1].."'!")
    end
    return true
end

states.running.commands["digfilter"] = function(tokens)
    tCode.line = tCode.line + 1 -- increment line
    local line = tCode.data[tCode.line]
    if line == nil then return true end
    local key, tokens = splitTokens(line)
    if not key == "+" or not key == "-" then return true end
    while key == "+" or key == "-" do
        if key == "+" then
            vars.digonlyincluded = true
            vars.digfilter[tokens[1]] = true
        elseif key == "-" then
            vars.digfilter[tokens[1]] = false
        end
        tCode.line = tCode.line + 1
        line = tCode.data[tCode.line]
        if line == nil then break end
        local k, t = splitTokens(line)
        key = k
        tokens = t
    end
    tCode.line = tCode.line - 1
    return true
end

states.running.commands["suckfilter"] = function(tokens)
    tCode.line = tCode.line + 1 -- increment line
    local line = tCode.data[tCode.line]
    if line == nil then return true end
    local key, tokens = splitTokens(line)
    if not key == "+" or not key == "-" then return true end
    while key == "+" or key == "-" do
        if key == "+" then
            vars.suckonlyincluded = true
            vars.suckfilter[tokens[1]] = true
        elseif key == "-" then
            vars.suckfilter[tokens[1]] = false
        end
        tCode.line = tCode.line + 1
        line = tCode.data[tCode.line]
        if line == nil then break end
        local k, t = splitTokens(line)
        key = k
        tokens = t
    end
    tCode.line = tCode.line - 1
    return true
end

states.running.stop = function(args)
    print("---")
end

states.topos.start = function(args)
    changeState(prevState) -- While we don't have any pathfinding logic, just shove the turtle back into the previous state
end

states.failed.start = function(args)
    if args.error ~= nil or args.error ~= "" then
        printError("(Failure in '"..prevState.."') "..args.error)
    else
        printError("Failed")
    end
end

states.completed.start = function(args)
    print("Completed program '"..vars.args.filePath.."'.")
end

-- Start the program
changeState("starting")
