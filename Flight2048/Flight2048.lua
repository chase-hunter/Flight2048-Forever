-- Flight 2048
-- Play 2048 while riding a flight path. Opens when a flight starts and
-- (optionally) closes when you land. Your game is saved between flights.

local ADDON_NAME = ...

local SIZE     = 4
local TILE     = 68
local GAP      = 8
local BOARD_PX = SIZE * TILE + (SIZE + 1) * GAP
local WIN_TILE = 2048
local REPO_URL = "github.com/chase-hunter/Flight2048-Forever"

StaticPopupDialogs["FLIGHT2048_COPY_URL"] = {
    text = "Flight 2048 on GitHub\nPress Ctrl+C to copy:",
    button1 = OKAY or "Okay",
    hasEditBox = true,
    editBoxWidth = 280,
    OnShow = function(self)
        local eb = self.EditBox or self.editBox
        eb:SetText("https://" .. REPO_URL)
        eb:SetFocus()
        eb:HighlightText()
    end,
    EditBoxOnEscapePressed = function(self) self:GetParent():Hide() end,
    EditBoxOnEnterPressed = function(self) self:GetParent():Hide() end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
}

local DEFAULTS = {
    autoOpen  = true,   -- open when a flight starts
    autoClose = true,   -- close when you land
    best      = 0,
    score     = 0,
    won       = false,  -- reached 2048 and chose to keep going
    board     = nil,
}

-- Tiles use item quality colors: 2 is Poor, 4 is Common, 8 is Uncommon...
local TILE_COLORS = {
    [2]    = { 0.62, 0.62, 0.62 }, -- Poor
    [4]    = { 1.00, 1.00, 1.00 }, -- Common
    [8]    = { 0.12, 1.00, 0.00 }, -- Uncommon
    [16]   = { 0.00, 0.44, 0.87 }, -- Rare
    [32]   = { 0.64, 0.21, 0.93 }, -- Epic
    [64]   = { 1.00, 0.50, 0.00 }, -- Legendary
    [128]  = { 0.90, 0.80, 0.50 }, -- Artifact
    [256]  = { 0.00, 0.80, 1.00 }, -- Heirloom
    [512]  = { 1.00, 0.30, 0.30 },
    [1024] = { 1.00, 0.82, 0.00 },
    [2048] = { 1.00, 0.95, 0.60 },
}
local TOP_COLOR = { 1.00, 0.95, 0.60 }

local DB
local frame
local cells = {}
local onTaxi = false
local flightStart
local destination

local function Print(msg)
    DEFAULT_CHAT_FRAME:AddMessage("|cffffd100Flight 2048:|r " .. msg)
end

local function Sound(name)
    if SOUNDKIT and SOUNDKIT[name] then
        PlaySound(SOUNDKIT[name])
    end
end

--------------------------------------------------------------------------------
-- Game logic
--------------------------------------------------------------------------------

local function NewBoard()
    local b = {}
    for r = 1, SIZE do
        b[r] = {}
        for c = 1, SIZE do b[r][c] = 0 end
    end
    return b
end

local function SpawnTile(b)
    local empty = {}
    for r = 1, SIZE do
        for c = 1, SIZE do
            if b[r][c] == 0 then empty[#empty + 1] = { r, c } end
        end
    end
    if #empty == 0 then return nil end
    local p = empty[math.random(#empty)]
    b[p[1]][p[2]] = (math.random() < 0.9) and 2 or 4
    return p
end

local function CanMove(b)
    for r = 1, SIZE do
        for c = 1, SIZE do
            local v = b[r][c]
            if v == 0 then return true end
            if c < SIZE and b[r][c + 1] == v then return true end
            if r < SIZE and b[r + 1][c] == v then return true end
        end
    end
    return false
end

local function HasTile(b, value)
    for r = 1, SIZE do
        for c = 1, SIZE do
            if b[r][c] >= value then return true end
        end
    end
    return false
end

-- Coordinates of line i, ordered from the edge the tiles slide toward.
local function LineCoords(dir, i)
    local t = {}
    for k = 1, SIZE do
        if dir == "LEFT" then
            t[k] = { i, k }
        elseif dir == "RIGHT" then
            t[k] = { i, SIZE + 1 - k }
        elseif dir == "UP" then
            t[k] = { k, i }
        else -- DOWN
            t[k] = { SIZE + 1 - k, i }
        end
    end
    return t
end

-- Slides and merges the board in place. Returns moved, points gained, merged cells.
local function Slide(b, dir)
    local moved, gained, merged = false, 0, {}
    for i = 1, SIZE do
        local coords = LineCoords(dir, i)
        local vals = {}
        for _, p in ipairs(coords) do
            local v = b[p[1]][p[2]]
            if v ~= 0 then vals[#vals + 1] = v end
        end

        local out, mergedAt, j = {}, {}, 1
        while j <= #vals do
            if vals[j + 1] and vals[j] == vals[j + 1] then
                out[#out + 1] = vals[j] * 2
                gained = gained + vals[j] * 2
                mergedAt[#out] = true
                j = j + 2
            else
                out[#out + 1] = vals[j]
                j = j + 1
            end
        end

        for k, p in ipairs(coords) do
            local nv = out[k] or 0
            if b[p[1]][p[2]] ~= nv then moved = true end
            b[p[1]][p[2]] = nv
            if mergedAt[k] then merged[#merged + 1] = p end
        end
    end
    return moved, gained, merged
end

--------------------------------------------------------------------------------
-- UI helpers
--------------------------------------------------------------------------------

local function CreatePop(f, fromScale, duration)
    local ag = f:CreateAnimationGroup()
    local s = ag:CreateAnimation("Scale")
    if not s.SetScaleFrom then return nil end
    s:SetScaleFrom(fromScale, fromScale)
    s:SetScaleTo(1, 1)
    s:SetDuration(duration)
    s:SetOrigin("CENTER", 0, 0)
    return ag
end

local function PanelBackdrop(f, r, g, b, a)
    f:SetBackdrop({
        bgFile   = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 12,
        insets   = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    f:SetBackdropColor(r, g, b, a)
    f:SetBackdropBorderColor(0.6, 0.6, 0.6, 1)
end

local function FormatTime(sec)
    sec = math.floor(sec)
    return string.format("%d:%02d", math.floor(sec / 60), sec % 60)
end

--------------------------------------------------------------------------------
-- Rendering
--------------------------------------------------------------------------------

local function UpdateCell(cell, value)
    if value == 0 then
        cell:SetBackdropColor(0, 0, 0, 0.55)
        cell:SetBackdropBorderColor(0.35, 0.35, 0.35, 0.9)
        cell.text:SetText("")
        return
    end

    local col = TILE_COLORS[value] or TOP_COLOR
    cell:SetBackdropColor(col[1] * 0.28, col[2] * 0.28, col[3] * 0.28, 0.95)
    cell:SetBackdropBorderColor(col[1], col[2], col[3], 1)

    local size = (value < 100 and 30) or (value < 1000 and 26) or (value < 10000 and 21) or 17
    cell.text:SetFont(STANDARD_TEXT_FONT, size, "OUTLINE")
    cell.text:SetTextColor(col[1], col[2], col[3])
    cell.text:SetText(value)
end

local function Render()
    for r = 1, SIZE do
        for c = 1, SIZE do
            UpdateCell(cells[r][c], DB.board[r][c])
        end
    end
    frame.score:SetText(DB.score)
    frame.best:SetText(DB.best)
end

local function ShowOverlay(title, r, g, b, buttonText, onClick)
    local o = frame.overlay
    o.title:SetText(title)
    o.title:SetTextColor(r, g, b)
    o.sub:SetText("Score: " .. DB.score)
    o.button:SetText(buttonText)
    o.button:SetScript("OnClick", onClick)
    o:Show()
end

local function ShowScoreGain(points)
    local fs = frame.gain
    fs:SetText("+" .. points)
    fs.anim:Stop()
    fs:Show()
    fs.anim:Play()
end

--------------------------------------------------------------------------------
-- Game flow
--------------------------------------------------------------------------------

local function NewGame()
    DB.board = NewBoard()
    DB.score = 0
    DB.won = false
    SpawnTile(DB.board)
    SpawnTile(DB.board)
    frame.overlay:Hide()
    Render()
end

local function CheckEndStates()
    if not DB.won and HasTile(DB.board, WIN_TILE) then
        DB.won = true
        Sound("LEVEL_UP")
        ShowOverlay("You Win!", 1, 0.82, 0, "Keep Playing", function() frame.overlay:Hide() end)
    elseif not CanMove(DB.board) then
        Sound("IG_QUEST_FAILED")
        ShowOverlay("Game Over", 1, 0.2, 0.2, "Try Again", NewGame)
    end
end

local function DoMove(dir)
    if frame.overlay:IsShown() then return end

    local moved, gained, merged = Slide(DB.board, dir)
    if not moved then return end

    local spawned = SpawnTile(DB.board)
    DB.score = DB.score + gained
    if DB.score > DB.best then DB.best = DB.score end
    Render()

    for _, p in ipairs(merged) do
        local cell = cells[p[1]][p[2]]
        if cell.merge then cell.merge:Stop(); cell.merge:Play() end
    end
    if spawned then
        local cell = cells[spawned[1]][spawned[2]]
        if cell.spawn then cell.spawn:Stop(); cell.spawn:Play() end
    end
    if gained > 0 then ShowScoreGain(gained) end

    CheckEndStates()
end

--------------------------------------------------------------------------------
-- Frame construction
--------------------------------------------------------------------------------

local KEYMAP = {
    UP = "UP", W = "UP",
    DOWN = "DOWN", S = "DOWN",
    LEFT = "LEFT", A = "LEFT",
    RIGHT = "RIGHT", D = "RIGHT",
}

local function BuildFrame()
    local f = CreateFrame("Frame", "Flight2048Frame", UIParent, "BackdropTemplate")
    frame = f
    f:SetSize(BOARD_PX + 48, 510)
    f:SetPoint("CENTER", UIParent, "CENTER", 0, 40)
    f:SetFrameStrata("DIALOG")
    f:SetToplevel(true)
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:Hide()

    -- Classic dialog box look
    f:SetBackdrop({
        bgFile   = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 32, edgeSize = 32,
        insets = { left = 11, right = 12, top = 12, bottom = 11 },
    })

    local header = f:CreateTexture(nil, "ARTWORK")
    header:SetTexture("Interface\\DialogFrame\\UI-DialogBox-Header")
    header:SetSize(256, 64)
    header:SetPoint("TOP", 0, 12)

    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOP", header, "TOP", 0, -14)
    title:SetText("Flight 2048")

    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -6, -6)

    -- Logo and score boxes
    local logo = f:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
    logo:SetPoint("TOPLEFT", 26, -40)
    logo:SetText("2048")

    local hint = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hint:SetPoint("TOPLEFT", logo, "BOTTOMLEFT", 0, -4)
    hint:SetText("Join the tiles!")

    local function ScoreBox(label, anchorTo, x)
        local box = CreateFrame("Frame", nil, f, "BackdropTemplate")
        box:SetSize(92, 42)
        PanelBackdrop(box, 0, 0, 0, 0.6)
        if anchorTo then
            box:SetPoint("RIGHT", anchorTo, "LEFT", x, 0)
        else
            box:SetPoint("TOPRIGHT", -24, -34)
        end
        local l = box:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        l:SetPoint("TOP", 0, -6)
        l:SetText(label)
        local v = box:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
        v:SetPoint("BOTTOM", 0, 6)
        return box, v
    end

    local bestBox, bestText = ScoreBox("BEST")
    local scoreBox, scoreText = ScoreBox("SCORE", bestBox, -6)
    f.best, f.score = bestText, scoreText

    local gain = f:CreateFontString(nil, "OVERLAY", "GameFontGreenLarge")
    gain:SetPoint("CENTER", scoreBox, "CENTER", 0, 0)
    gain:Hide()
    local gainAnim = gain:CreateAnimationGroup()
    local move = gainAnim:CreateAnimation("Translation")
    move:SetOffset(0, 26)
    move:SetDuration(0.7)
    local fade = gainAnim:CreateAnimation("Alpha")
    fade:SetFromAlpha(1)
    fade:SetToAlpha(0)
    fade:SetDuration(0.7)
    gainAnim:SetScript("OnFinished", function() gain:Hide() end)
    gain.anim = gainAnim
    f.gain = gain

    -- Board
    local board = CreateFrame("Frame", nil, f, "BackdropTemplate")
    board:SetSize(BOARD_PX, BOARD_PX)
    board:SetPoint("TOP", 0, -86)
    PanelBackdrop(board, 0.05, 0.05, 0.05, 0.85)
    board:SetBackdropBorderColor(0.8, 0.7, 0.4, 1)

    for r = 1, SIZE do
        cells[r] = {}
        for c = 1, SIZE do
            local cell = CreateFrame("Frame", nil, board, "BackdropTemplate")
            cell:SetSize(TILE, TILE)
            cell:SetPoint("TOPLEFT", GAP + (c - 1) * (TILE + GAP), -(GAP + (r - 1) * (TILE + GAP)))
            PanelBackdrop(cell, 0, 0, 0, 0.55)
            cell.text = cell:CreateFontString(nil, "OVERLAY")
            cell.text:SetFont(STANDARD_TEXT_FONT, 30, "OUTLINE")
            cell.text:SetPoint("CENTER", 0, 0)
            cell.spawn = CreatePop(cell, 0.2, 0.12)
            cell.merge = CreatePop(cell, 1.2, 0.15)
            cells[r][c] = cell
        end
    end

    -- Mouse swipe on the board
    board:EnableMouse(true)
    board:SetScript("OnMouseDown", function(self)
        self.dragX, self.dragY = GetCursorPosition()
    end)
    board:SetScript("OnMouseUp", function(self)
        if not self.dragX then return end
        local x, y = GetCursorPosition()
        local scale = self:GetEffectiveScale()
        local dx, dy = (x - self.dragX) / scale, (y - self.dragY) / scale
        self.dragX, self.dragY = nil, nil
        if math.max(math.abs(dx), math.abs(dy)) < 20 then return end
        if math.abs(dx) > math.abs(dy) then
            DoMove(dx > 0 and "RIGHT" or "LEFT")
        else
            DoMove(dy > 0 and "UP" or "DOWN")
        end
    end)

    -- Win / game over overlay
    local overlay = CreateFrame("Frame", nil, board)
    overlay:SetAllPoints()
    overlay:SetFrameLevel(board:GetFrameLevel() + 10)
    overlay:EnableMouse(true)
    local shade = overlay:CreateTexture(nil, "BACKGROUND")
    shade:SetAllPoints()
    shade:SetColorTexture(0, 0, 0, 0.75)
    overlay.title = overlay:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
    overlay.title:SetPoint("CENTER", 0, 34)
    overlay.sub = overlay:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    overlay.sub:SetPoint("CENTER", 0, 4)
    overlay.button = CreateFrame("Button", nil, overlay, "UIPanelButtonTemplate")
    overlay.button:SetSize(120, 24)
    overlay.button:SetPoint("CENTER", 0, -32)
    overlay:Hide()
    f.overlay = overlay

    -- Flight status line
    local status = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    status:SetPoint("TOP", board, "BOTTOM", 0, -8)
    status:SetWidth(BOARD_PX)
    f.status = status

    local keys = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    keys:SetPoint("TOP", status, "BOTTOM", 0, -4)
    keys:SetText("Arrow keys, WASD, or drag on the board to move tiles")

    -- Bottom buttons
    local newBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    newBtn:SetSize(120, 22)
    newBtn:SetPoint("BOTTOMLEFT", 24, 36)
    newBtn:SetText("New Game")
    newBtn:SetScript("OnClick", NewGame)

    local closeBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    closeBtn:SetSize(120, 22)
    closeBtn:SetPoint("BOTTOMRIGHT", -24, 36)
    closeBtn:SetText(CLOSE or "Close")
    closeBtn:SetScript("OnClick", function() f:Hide() end)

    -- Branding footer (click to get a copyable link)
    local brand = CreateFrame("Button", nil, f)
    brand:SetPoint("BOTTOM", 0, 17)
    local brandText = brand:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    brandText:SetPoint("CENTER")
    brandText:SetText(REPO_URL)
    brand:SetSize(brandText:GetStringWidth() + 8, 14)
    brand:SetScript("OnEnter", function(self)
        brandText:SetTextColor(1, 0.82, 0)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText("Flight 2048 for WoW Forever")
        GameTooltip:AddLine("Click to copy the GitHub link.", 1, 1, 1)
        GameTooltip:Show()
    end)
    brand:SetScript("OnLeave", function()
        brandText:SetTextColor(0.5, 0.5, 0.5)
        GameTooltip:Hide()
    end)
    brand:SetScript("OnClick", function()
        StaticPopup_Show("FLIGHT2048_COPY_URL")
    end)

    -- Keyboard: arrows always work while the mouse is over the window;
    -- WASD and arrows also work anywhere while flying (you can't move anyway).
    f:EnableKeyboard(true)
    f:SetScript("OnKeyDown", function(self, key)
        local dir = KEYMAP[key]
        local handled = dir and (onTaxi or self:IsMouseOver()) and not IsModifierKeyDown()
        if not InCombatLockdown() then
            self:SetPropagateKeyboardInput(not handled)
        end
        if handled then DoMove(dir) end
    end)

    -- Flight timer
    local elapsed = 0
    f:SetScript("OnUpdate", function(self, dt)
        elapsed = elapsed + dt
        if elapsed < 0.25 then return end
        elapsed = 0
        if onTaxi and flightStart then
            local where = destination and ("Flying to |cffffd100" .. destination .. "|r") or "In flight"
            status:SetText(where .. "  -  " .. FormatTime(GetTime() - flightStart))
        else
            status:SetText("|cff808080Not flying. /f2048 to toggle this window.|r")
        end
    end)

    f:SetScript("OnShow", function() Sound("IG_MAINMENU_OPEN") end)
    f:SetScript("OnHide", function() Sound("IG_MAINMENU_CLOSE") end)

    tinsert(UISpecialFrames, "Flight2048Frame") -- Escape closes it
end

--------------------------------------------------------------------------------
-- Flight detection
--------------------------------------------------------------------------------

local function OnFlightStart()
    flightStart = GetTime()
    if not DB.autoOpen then return end
    if not DB.board or not CanMove(DB.board) then NewGame() end
    Render()
    frame:Show()
end

local function OnFlightEnd()
    destination = nil
    flightStart = nil
    if DB.autoClose and frame:IsShown() then
        frame:Hide()
        Print(string.format("Landed! Score %d (best %d). Your game is saved for the next flight.", DB.score, DB.best))
    end
end

local function CheckTaxi()
    local now = UnitOnTaxi("player") and true or false
    if now == onTaxi then return end
    onTaxi = now
    if now then OnFlightStart() else OnFlightEnd() end
end

local function CheckTaxiSoon()
    CheckTaxi()
    C_Timer.After(0.5, CheckTaxi)
    C_Timer.After(1.5, CheckTaxi)
end

--------------------------------------------------------------------------------
-- Init and events
--------------------------------------------------------------------------------

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:RegisterEvent("PLAYER_CONTROL_LOST")
events:RegisterEvent("PLAYER_CONTROL_GAINED")
events:RegisterEvent("TAXIMAP_CLOSED")

events:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" then
        if arg1 ~= ADDON_NAME then return end
        Flight2048DB = Flight2048DB or {}
        DB = Flight2048DB
        for k, v in pairs(DEFAULTS) do
            if DB[k] == nil then DB[k] = v end
        end
        BuildFrame()
        if not DB.board then NewGame() else Render() end

        -- Remember where we're flying to
        if TakeTaxiNode and TaxiNodeName then
            hooksecurefunc("TakeTaxiNode", function(index)
                local name = TaxiNodeName(index)
                destination = name and name:match("^([^,]+)") or name
            end)
        end

        -- Backup poll in case an event is missed
        C_Timer.NewTicker(1, CheckTaxi)
        self:UnregisterEvent("ADDON_LOADED")
    elseif DB then
        CheckTaxiSoon()
    end
end)

--------------------------------------------------------------------------------
-- Slash commands
--------------------------------------------------------------------------------

SLASH_FLIGHTTWENTYFORTYEIGHT1 = "/f2048"
SLASH_FLIGHTTWENTYFORTYEIGHT2 = "/flight2048"
SlashCmdList.FLIGHTTWENTYFORTYEIGHT = function(msg)
    msg = strlower(strtrim(msg or ""))
    if msg == "" then
        frame:SetShown(not frame:IsShown())
    elseif msg == "new" then
        NewGame()
        frame:Show()
    elseif msg == "auto" then
        DB.autoOpen = not DB.autoOpen
        Print("Open on flight: " .. (DB.autoOpen and "|cff00ff00on|r" or "|cffff0000off|r"))
    elseif msg == "close" then
        DB.autoClose = not DB.autoClose
        Print("Close on landing: " .. (DB.autoClose and "|cff00ff00on|r" or "|cffff0000off|r"))
    elseif msg == "reset" then
        frame:ClearAllPoints()
        frame:SetPoint("CENTER", UIParent, "CENTER", 0, 40)
        Print("Window position reset.")
    else
        Print("Commands:")
        Print("  /f2048 - show or hide the game")
        Print("  /f2048 new - start a new game")
        Print("  /f2048 auto - toggle opening when a flight starts")
        Print("  /f2048 close - toggle closing when you land")
        Print("  /f2048 reset - reset the window position")
        Print("  https://" .. REPO_URL)
    end
end
