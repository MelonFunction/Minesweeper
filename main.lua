local buffer = require("string.buffer")

local MAX_SIZE = 14
local STARTING_SIZE = 4
local SIZE_INCR = 2
local BOMB_PERCENTAGE = 0.15
local BOARD_PADDING = 0.04 -- % of smallest window dimension
local TILE_PADDING = 0.1   -- % of tile size

-- Hex String -> R G B Numbers
-- @param string hex
-- @return number, number, number representing hex color triplet
local function splitHex(hex)
    hex = hex:gsub("#", "")
    return tonumber(hex:sub(1, 2), 16), tonumber(hex:sub(3, 4), 16), tonumber(hex:sub(5, 6), 16)
end

local colors        = {
    background = { love.math.colorFromBytes(splitHex("2c283f")) },
    foreground = { love.math.colorFromBytes(splitHex("fffcf3")) },
    foregroundDimmed = { love.math.colorFromBytes(splitHex("726F7B")) },
    flag = { love.math.colorFromBytes(splitHex("fb2c86")) },
}
local startTime     = 0
local currentTime   = 0
local splitsTimers  = {
    [4] = 0,
    [6] = 0,
    [8] = 0,
    [10] = 0,
    [12] = 0,
    [14] = 0,
}
local loadedSplitsTimers
local countFlags    = -1 -- starts as -1 because we +1 to math.floor
local currentFlags  = 0  -- placed flags
local clickedTiles  = 0  -- number of uncovered tiles
local isGameStarted = false
local isDead        = false
local isGameWon     = false
local currentSize   = STARTING_SIZE
local smallestDimension
local tileSize
local boardPadding
local tilePadding
local textScale     = 1
local origHeight    = love.graphics.getHeight()

local board         = {} -- for mines
local BOMB          = 9  -- every other value is the number of bombs around the tile

local plays         = {} -- for guesses/flags
local UNTOUCHED     = 0
local SAFE          = 1
local FLAG          = 2
local DEAD          = 3

-- resizeBoard resizes the tiles on the board
-- @param number w is the new width
-- @param number h is the new height
local function resizeBoard(w, h)
    smallestDimension = w < h and w or h
    tileSize = smallestDimension / currentSize -- tile size
    boardPadding = smallestDimension * BOARD_PADDING
    tileSize = tileSize - (boardPadding * 2) / currentSize
    tilePadding = tileSize * TILE_PADDING
end

-- createBoard sets up the board with empty guesses
-- @param number rows
-- @param number cols
local function createBoard(rows, cols)
    isDead = false
    countFlags = -1
    currentFlags = 0
    clickedTiles = 0
    board = {}
    plays = {}
    resizeBoard(love.graphics.getDimensions())
    for x = 1, rows do
        board[x] = {}
        plays[x] = {}
        for y = 1, cols do
            board[x][y] = 0
            plays[x][y] = 0
        end
    end
end

-- populateBoard places mines on the board and counts surrounding bombs
-- @param number ex is the starting position to exclude
-- @param number ey is the starting position to exclude
local function populateBoard(ex, ey)
    isGameStarted = true
    isDead = false
    currentFlags = 0
    clickedTiles = 0
    local countBombs = currentSize * currentSize * BOMB_PERCENTAGE
    countFlags = countBombs
    while countBombs > 0 do
        local x, y = love.math.random(1, currentSize), love.math.random(1, currentSize)
        if board[x][y] ~= BOMB and not (x == ex and y == ey) then
            -- don't exclude 3x3 area on smallest size
            if currentSize == STARTING_SIZE or (not (math.abs(ex - x) == 1) and not (math.abs(ey - y) == 1)) then
                board[x][y] = BOMB
                countBombs = countBombs - 1
                for xx = x - 1, x + 1 do
                    for yy = y - 1, y + 1 do
                        if xx > 0 and xx <= currentSize and yy > 0 and yy <= currentSize then
                            if board[xx][yy] ~= BOMB then -- don't incr bombs
                                board[xx][yy] = board[xx][yy] + 1
                            end
                        end
                    end
                end
            end
        end
    end
end

-- loadSplits loads values from savedata.txt into loadedSplitsTimers
local function loadSplits()
    loadedSplitsTimers = love.filesystem.read("savedata.txt")
    if loadedSplitsTimers then
        local contents = love.filesystem.read("savedata.txt")
        loadedSplitsTimers = buffer.decode(contents)
    else
        love.filesystem.write("savedata.txt", buffer.encode(splitsTimers))
        loadedSplitsTimers = {}
        for key, value in pairs(splitsTimers) do
            loadedSplitsTimers[key] = value
        end
    end
end

local font
local splitsFont
function love.load()
    loadSplits()

    font = love.graphics.setNewFont("/Rubik-Bold.ttf", 32)
    splitsFont = love.graphics.setNewFont("/Rubik-Bold.ttf", 24)

    createBoard(currentSize, currentSize)
    local w, h = love.graphics.getDimensions()
    resizeBoard(w, h)
end

-- clickTile handles tile clicking logic
-- @param number x is the x position of the click
-- @param number y is the y position of the click
-- @param number button is the mouse button that was clicked. 1 is left, 2 is right.
-- @param boolean isFlood if true, removes flags on flood fill
local function clickTile(x, y, button, isFlood)
    if not (x > 0 and x <= currentSize and y > 0 and y <= currentSize) then
        return
    end

    if button == 1 then
        if plays[x][y] == SAFE or (plays[x][y] == FLAG and not isFlood) or isDead then
            return
        end

        -- Start game
        if clickedTiles == 0 then
            plays[x][y] = SAFE
            clickedTiles = clickedTiles + 1
            populateBoard(x, y)
        end

        if plays[x][y] == FLAG then -- flag was on a safe tile during a flood
            currentFlags = currentFlags - 1
        end

        plays[x][y] = SAFE
        clickedTiles = clickedTiles + 1
        if board[x][y] == 0 then
            for xx = x - 1, x + 1 do
                for yy = y - 1, y + 1 do
                    clickTile(xx, yy, button, true)
                end
            end
        end
    elseif button == 2 then
        if plays[x][y] == UNTOUCHED then
            plays[x][y] = FLAG
            currentFlags = currentFlags + 1
        elseif plays[x][y] == FLAG then
            currentFlags = currentFlags - 1
            plays[x][y] = UNTOUCHED
        end
    end
end

function love.keypressed(key)
    if key == "space" or key == "r" then
        isGameWon = false
        currentTime = 0
        for k, v in pairs(splitsTimers) do
            splitsTimers[k] = 0
        end
        startTime = love.timer.getTime()
        currentSize = STARTING_SIZE
        createBoard(currentSize, currentSize)
    elseif key == "escape" then
        love.event.quit()
    end
end

function love.mousereleased(x, y, button)
    local tx = math.floor((x - boardPadding) / tileSize) + 1
    local ty = math.floor((y - boardPadding) / tileSize) + 1
    if tx > 0 and ty > 0 and tx <= currentSize and ty <= currentSize then
        clickTile(tx, ty, button)

        if button == 1 then
            -- Win condition
            if clickedTiles == currentSize * currentSize - math.ceil(currentSize * currentSize * BOMB_PERCENTAGE) then
                splitsTimers[currentSize] = currentTime
                currentSize = currentSize + SIZE_INCR
                if currentSize > MAX_SIZE then -- Game won
                    if loadedSplitsTimers[MAX_SIZE] == 0 or splitsTimers[MAX_SIZE] < loadedSplitsTimers[MAX_SIZE] then
                        love.filesystem.write("savedata.txt", buffer.encode(splitsTimers))
                        loadSplits()
                        isGameWon = true
                    end
                else -- Next level
                    if loadedSplitsTimers[currentSize - SIZE_INCR] == 0 then
                        love.filesystem.write("savedata.txt", buffer.encode(splitsTimers))
                        loadSplits()
                    end
                    createBoard(currentSize, currentSize)
                end
            end

            -- Death condition
            if board[tx][ty] == BOMB then
                plays[tx][ty] = DEAD
                currentTime = 0
                for k, v in pairs(splitsTimers) do
                    splitsTimers[k] = 0
                end
                startTime = love.timer.getTime()
                currentSize = STARTING_SIZE
                isDead = true
                for zx, cols in ipairs(board) do
                    for zy, tile in ipairs(cols) do
                        if board[zx][zy] == BOMB then
                            plays[zx][zy] = DEAD
                        end
                    end
                end
                -- Save split anyways
                if loadedSplitsTimers[currentSize] == 0 then
                    love.filesystem.write("savedata.txt", buffer.encode(splitsTimers))
                    loadSplits()
                end
            end
        end
    end
end

function love.update(dt)
    if isGameStarted and not isDead then
        currentTime = love.timer.getTime() - startTime
    end
end

function love.draw()
    love.graphics.clear(colors.background)
    love.graphics.setColor(colors.foreground)
    love.graphics.setLineWidth(4)
    love.graphics.rectangle("line", boardPadding - tilePadding,
        boardPadding - tilePadding,
        smallestDimension - boardPadding * 2 + tilePadding * 2,
        smallestDimension - boardPadding * 2 + tilePadding * 2,
        tilePadding, tilePadding)

    local ts = tileSize - tilePadding
    local l = ts * 1 / 16

    local drawTileRect = function(x, y, round)
        local tx = (x - 1) * tileSize + boardPadding + tilePadding / 2
        local ty = (y - 1) * tileSize + boardPadding + tilePadding / 2
        love.graphics.rectangle("fill", tx, ty, ts, ts, tilePadding / 2, tilePadding / 2)

        round = round or ""
        local hts = ts / 2
        if not string.find(round, "TL") then
            love.graphics.rectangle("fill", tx, ty, hts, hts, 64)
        end
        if not string.find(round, "TR") then
            love.graphics.rectangle("fill", tx + hts, ty, hts, hts, 64)
        end
        if not string.find(round, "BL") then
            love.graphics.rectangle("fill", tx, ty + hts, hts, hts, 64)
        end
        if not string.find(round, "BR") then
            love.graphics.rectangle("fill", tx + hts, ty + hts, hts, hts, 64)
        end
    end

    -- draw the grid
    for x, cols in ipairs(plays) do
        for y, tile in ipairs(cols) do
            local tx = (x - 1) * tileSize + boardPadding + tilePadding / 2
            local ty = (y - 1) * tileSize + boardPadding + tilePadding / 2

            love.graphics.setColor(colors.foreground)
            if tile == UNTOUCHED then
            elseif tile == SAFE or tile == DEAD then
                love.graphics.setColor(colors.background)
            end

            if x == 1 and y == 1 then
                drawTileRect(x, y, "TL")
            elseif x == currentSize and y == 1 then
                drawTileRect(x, y, "TR")
            elseif x == 1 and y == currentSize then
                drawTileRect(x, y, "BL")
            elseif x == currentSize and y == currentSize then
                drawTileRect(x, y, "BR")
            else
                drawTileRect(x, y)
            end
            if tile == SAFE then
                love.graphics.setColor(colors.foreground)
                if board[x][y] > 0 then
                    local fw, fh = font:getWidth(board[x][y]), font:getHeight(board[x][y])
                    love.graphics.print(board[x][y], tx + ts / 2 - fw / 2, ty + ts / 2 - fh / 2)
                end
            elseif tile == FLAG then
                love.graphics.setColor(colors.flag)
                love.graphics.polygon("fill",
                    tx + l * 4, ty + l * 3,
                    tx + l * 4, ty + ts - l * 3,
                    tx + l * 6, ty + ts - l * 3,
                    tx + l * 6, ty + ts - l * 7,
                    tx + ts - l * 4, ty + ts - l * 7,
                    tx + ts - l * 4, ty + l * 3
                )
            elseif tile == DEAD then
                love.graphics.setColor(colors.flag)
                love.graphics.circle("fill", tx + ts / 2, ty + ts / 2, ts / 3)
            end
        end
    end

    -- Controls border
    local w, h = love.graphics.getDimensions()
    local boardWidth = smallestDimension
    local controlsWidth = w - boardWidth - boardPadding
    local x, y = boardWidth, boardPadding - tilePadding
    love.graphics.setColor(colors.foreground)
    love.graphics.setLineWidth(4)
    love.graphics.rectangle("line", x, y, controlsWidth, h - boardPadding * 2 + tilePadding * 2, tilePadding,
        tilePadding)

    -- Some welcoming text
    love.graphics.setFont(font)
    love.graphics.setColor(isGameWon and colors.flag or colors.foreground)
    local text = isGameWon and "WIN!" or "Minesweeper"
    love.graphics.print(text, x + boardPadding / 2, y + boardPadding * 0.55)

    -- Flag icon + amount
    love.graphics.setColor(colors.flag)
    x = x + font:getWidth("Minesweeper") + boardPadding * 2
    y = y
    ts = font:getHeight("Minesweeper") * 1.5
    l = ts * 1 / 16
    love.graphics.polygon("fill",
        x + l * 4, y + l * 3,
        x + l * 4, y + ts - l * 3,
        x + l * 6, y + ts - l * 3,
        x + l * 6, y + ts - l * 7,
        x + ts - l * 4, y + ts - l * 7,
        x + ts - l * 4, y + l * 3
    )
    love.graphics.setColor(colors.foreground)
    love.graphics.print(math.floor(countFlags - currentFlags) + 1, x + boardPadding / 4 + ts,
        y + boardPadding * 0.55)

    local formatTime = function(seconds)
        local minutes = math.floor(seconds / 60)
        local remainingSeconds = seconds % 60
        return string.format("%02d:%05.2f", minutes, remainingSeconds)
    end

    -- Separating line
    love.graphics.setColor(colors.foreground)
    x = boardWidth
    y = y + font:getHeight(math.ceil(countFlags - currentFlags)) + boardPadding
    love.graphics.line(x, y, x + controlsWidth, y)

    -- Splits
    x = boardWidth + boardPadding / 2
    y = y + boardPadding / 2
    for split, timeValue in pairs(splitsTimers) do
        love.graphics.setFont(splitsFont)
        if split == currentSize then
            love.graphics.setColor(colors.foreground)
        else
            if timeValue > 0 and splitsTimers[split] <= loadedSplitsTimers[split] then
                love.graphics.setColor(colors.flag)
            else
                love.graphics.setColor(colors.foregroundDimmed)
            end
        end
        -- Name/Breakpoint
        love.graphics.print(split .. ":", x, y)
        -- Current time
        love.graphics.print(
            formatTime(split == currentSize and currentTime or timeValue), x + splitsFont:getWidth("00000"), y)
        -- Best time
        love.graphics.print(
            formatTime(loadedSplitsTimers[split]),
            x + splitsFont:getWidth("0000000" .. formatTime(0)), y)
        y = y + boardPadding / 4 + splitsFont:getHeight(split)
    end
end

function love.resize(w, h)
    resizeBoard(w, h)
    textScale = h / origHeight
    font = love.graphics.setNewFont("/Rubik-Bold.ttf", 32 * textScale)
    splitsFont = love.graphics.newFont("/Rubik-Bold.ttf", 24 * textScale)
end
