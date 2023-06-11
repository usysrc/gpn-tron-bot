local socket = require("socket")
local conn = socket.tcp()

-- conn:connect("gpn-tron.duckdns.org", 4000)
conn:connect("localhost", 4000)

local w, h = 0, 0
local player = {
    x = 0,
    y = 0,
}
local DIRECTIONS = {"down", "left", "right", "up" }

local others = {}
local hold = {}
local enemies = {}

local shuffle = function(t)
    for i=1,#t do
        local k = math.random(#t)
        local v = t[i]
        t[i] = t[k]
        t[k] = v
    end
    return t
end

local getArguments = function(packet)
    return packet:match("(%a+)|(%d+)|(%d+)|(%d*)")
end

local function isOccupiedOrWillCollide(x, y)
    -- Check if the new position is occupied by another player or leads to collisions
    if others[x..","..y] then return true end
end

local forAllDirections = function(x,y,dirs, fn)
    for _, direction in ipairs(dirs) do
        local newX, newY = x, y
        -- Calculate the new position based on the direction
        if direction == "left" then
            newX = (newX + w - 1) % w
        elseif direction == "down" then
            newY = (newY + 1) % h
        elseif direction == "up" then
            newY = (newY + h - 1) % h
        elseif direction == "right" then
            newX = (newX + 1) % w
        end
        fn(newX, newY,direction)
    end
end

local function find(x,y,visited, count)
    forAllDirections(x, y, shuffle(DIRECTIONS), function(newX, newY)
        return find(x,y,visited)
    end)
end

local function countFreeSpaces(x, y,visited)
    -- Count the number of free spaces around the given position
    local count = 0
    forAllDirections(x, y, shuffle(DIRECTIONS), function(newX, newY)
        if not visited[newX..","..newY] and not isOccupiedOrWillCollide(newX, newY) then
            visited[newX..","..newY] = true
            count = count + 1 + countFreeSpaces(newX, newY, visited)
        end
    end)
    return count
end

local function chooseMove()
    local nextX, nextY = player.x, player.y
    local availableDirections = {}

    -- Check all available directions and prioritize those that do not lead to collisions
    forAllDirections(nextX, nextY, shuffle(DIRECTIONS), function(newX, newY, direction)
        if not isOccupiedOrWillCollide(newX, newY) then
            table.insert(availableDirections, direction)
        end
    end)

    -- Choose the direction that avoids collisions and maximizes space
    local bestDirection = availableDirections[math.random(#availableDirections)] or "left"
    local maxFreeSpaces = 0
    print("directions", #availableDirections)

    forAllDirections(nextX, nextY, availableDirections,function(newX, newY, direction)
        local freeSpaces = countFreeSpaces(newX, newY, {})
        -- Update the best direction if more free spaces are found
        if freeSpaces > maxFreeSpaces then
            maxFreeSpaces = freeSpaces
            bestDirection = direction
        end
    end)

    print("move|"..bestDirection.."\n")
    conn:send("move|" .. bestDirection.."\n")  -- Send the best direction over the socket
end

local process = function(packet)
    if packet:sub(1,4) == "motd" then
        conn:send("join|have you tried lua?|letsago\n")
    elseif packet:sub(1,5) == "error" then
    elseif packet:sub(1,4) == "game" then
        others = {}
        hold = {}
        local game, cw, ch, id = getArguments(packet)
        print(game, cw, ch, id)
        player.id = id
        w = cw
        h = ch
    elseif packet:sub(1,3) == "pos" then
        local pos, id, x, y = getArguments(packet)
        if id == player.id then
            print(pos, x, y, id)
            player.x = tonumber(x)
            player.y = tonumber(y)
        else
            local lastx, lasty = 0, 0
            if enemies[id] then
                lastx, lasty = enemies[id].x, enemies[id].y
            else
                lastx = x
                lasty = y
            end
            enemies[id] = {
                x = x,
                y = y,
                lastx = lastx,
                lasty = lasty
            }

        end
        others[x..","..y] = id
        hold[id] = true

    elseif packet:sub(1,4) == "tick" then
        -- print("tick",player.x, player.y)
        
        -- remove any player that have died
        for k,v in pairs(others) do
            if not hold[v] then
                others[k] = nil
                enemies[v] = nil
            end
        end
        hold = {}

        -- add simulated
        local toRemove = {}
        for id,e in pairs(enemies) do
            if e.lastx then
                local tx,ty = e.x - e.lastx, e.y - e.lasty
                local nx, ny = e.x+tx, e.y+ty
                others[nx..","..ny] = id
                toRemove = {
                    x = nx,
                    y = ny
                }
            end
        end

        chooseMove()
        
        -- remove simulated
        for i,v in ipairs(toRemove) do
            others[v.x..","..v.y] = nil
        end
    elseif packet:sub(1,3) == "win" then
        conn:send("chat|GG\n")
    elseif packet:sub(1,4) == "lose" then
        local lost, wins = getArguments(packet)
        print("lost!", wins)
    end
end

while true do
    local out = conn:receive('*l')
    if out then
        -- print(out)
        process(out)
    end
end