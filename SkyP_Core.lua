--[[
    SkyP_Core.lua — GrowBlox Unified Automation Backend (v1.8 Engine)
    Dibangun ulang dari nol berdasarkan struktur client GrowBlox terbaru:
      - Dynamic discovery (tanpa hardcoded nama folder/module teracak):
        gt (world table), Net (ByteNet namespace + seq wrapper),
        ItemDB, inv (Inventory instance), trees (tree map), render + goTo upvalues
      - Sistem Terpadu: Pabrik Smart + Auto Break/Place + Auto Refill + Auto Return + Auto Drop Seed
      - Peta Mini data & Per-World persistence (Lantai, Berdiri, Tile Break, Red Unreachable)
      - 1 HIT MODE & Break Cepat
      - Rute Tetap (Atas->Bawah / Bawah->Atas / Terdekat, zig-zag per lantai, stop tiap 5 tile, mulai dari sisi terdekat)
      - Keamanan Tambahan (Jeda Acak 5-60%, Istirahat Berkala +-45m/+-3m, Batas Waktu Jalan + Discord Webhook)
]]

local Players           = game:GetService("Players")
local RunService        = game:GetService("RunService")
local HttpService       = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local LP                = Players.LocalPlayer

local Core = {}

-- ─────────────────────────────────────────────────────────────────────────────
--  STATE & CONFIGURATION
-- ─────────────────────────────────────────────────────────────────────────────
Core.State = {
    -- Discovery status
    ready        = false,
    worldLoaded  = false,
    worldName    = "",
    diag         = { gt = false, net = false, itemDB = false, inv = false, trees = false, render = false },

    -- Pos
    pos = { x = 0, y = 0, tx = 0, ty = 0, dead = false },

    -- Unified Pabrik & Break+Place config
    pabrikRunning    = false,
    seedId           = 3,       -- default Dirt Seed
    blockId          = 2,       -- default Dirt
    fullWorld        = false,
    routeOrder       = "top",   -- "top" | "bottom" | "nearest"
    harvestThreshold = 70,      -- 10..100 %
    oneHitMode       = true,
    fastBreak        = true,
    breakDelay       = 0.17,
    plantDelay       = 0.145,

    -- Break + Refill + Return
    autoBreakPlace   = true,
    autoRefill       = true,
    autoReturn       = true,

    -- Auto Drop Seed
    autoDropSeed     = true,
    dropThreshold    = 180,     -- max 190
    keepSeedCount    = 20,      -- sisa seed disimpan untuk ditanam
    dropWorld        = "",      -- kosong = world sekarang
    dropX            = 0,
    dropY            = 0,

    -- Auto Farm Grid 5x5 (hanya untuk Auto Farm, bukan Pabrik)
    gridRunning      = false,
    gridBase         = nil,
    grid             = {},
    gridDelay        = 0.25,
    gridAutoCollect  = true,

    -- SkyP v1.8: Dirt Farm (Plant dirt / Harvest Dirt / Build Upper Dirt Farm)
    dirtRunning          = false,
    dirtMode             = "idle",   -- "idle" | "plant" | "harvest" | "build" | "cycle"
    dirtSeedId           = 3,        -- Dirt Seed
    dirtBlockId          = 2,        -- Dirt
    dirtPlatId           = 102,      -- Wooden Platform
    dirtUsePlat          = true,     -- pasang platform di kolom akses sisi saat Build Upper
    dirtUpperStartY      = 2,        -- batas atas y upper dirt farm
    dirtUpperEndY        = 22,       -- batas bawah y upper dirt farm
    dirtStepY            = 2,        -- jarak antar lantai
    dirtLeftMargin       = 2,        -- kolom akses kiri
    dirtRightMargin      = 2,        -- kolom akses kanan
    dirtHarvestThreshold = 70,       -- ambang panen mode Cycle (%)

    -- Auto Vending (CATATAN: Vending tidak ikut istirahat berkala)
    vendRunning          = false,
    vendItemId           = 3,
    vendMinBag           = 0,
    vendDelay            = 0.8,

    -- Movement / Misc
    fly              = false,
    flySpeed         = 22,
    zoom             = 1,

    -- Guard / Mod Watcher
    modWatchOn       = false,
    modAction        = "SLEEP", -- "SLEEP" | "LEAVE"
    modCount         = 0,
    modLog           = {},

    -- Keamanan Tambahan (SEMUA MATI DEFAULT, tetap jalan walau Penjaga dimatikan)
    sec = {
        randomDelayOn     = false,
        randomDelayPct    = 15,     -- 5..60 (%)
        periodicBreakOn   = false,
        breakEveryMin     = 45,     -- +-45 menit
        breakForMin       = 3,      -- +-3 menit
        maxRuntimeOn      = false,
        maxRuntimeHours   = 6,      -- default 6 jam
        discordWebhook    = "",

        -- Runtime trackers
        sessionStartAt    = os.clock(),
        lastBreakEndAt    = os.clock(),
        inBreak           = false,
        breakEndsAt       = 0,
        nextBreakAt       = 0,
        runtimeStopped    = false,
        webhookSent       = false,
        vendingActive     = false,  -- Vending tidak ikut istirahat berkala
    },

    -- Live Status & Counters
    phase            = "IDLE",
    waitReason       = nil,     -- e.g. "Block habis", "Seed penuh", "Break gagal", "Drop gagal"
    routeProgress    = "",      -- e.g. "Rute 5/14, lantai y=20"
    etaText          = "Siap",
    suppressCollect  = false,   -- dimatikan total selama Auto Drop
    inDropTrip       = false,   -- istirahat tidak memotong perjalanan drop

    stats = {
        harvested = 0,
        planted   = 0,
        dropped   = 0,
        broken    = 0,
    },
}

-- Per-world saved data:
-- WorldData[worldName] = { floors = { [y]=true }, standPos = {x=..., y=...}, breakTiles = { {x=..., y=...} }, redTiles = { ["x,y"]=true } }
Core.WorldData = {}
local CONFIG_FILE = "SkyP_WorldConfig.json"
local MAX_MANUAL_FLOORS = 400
local MAX_DROP_THRESHOLD = 190
local MAX_STACK = 200

-- Internal game handles
local H = {
    gt          = nil,
    Net         = nil,
    ItemDB      = nil,
    inv         = nil,
    trees       = nil,
    renderFn    = nil,
    pxIdx       = nil,
    pyIdx       = nil,
    vxIdx       = nil,
    vyIdx       = nil,
    prevXIdx    = nil,
    prevYIdx    = nil,
    deadIdx     = nil,
    zoomIdx     = nil,
    targetZIdx  = nil,
    uiScaleObj  = nil,
    origTakeDrop = nil,
    takeDropHooked = false,
    netHooked   = false,
    lastTileAt  = 0,
    lastDropAt  = 0,
    breakFails  = {}, -- [key] = failCount
    flyConn     = nil,
    modConn     = nil,
    secConn     = nil,
    onUpdate    = nil, -- UI callback
}

-- ─────────────────────────────────────────────────────────────────────────────
--  UTILITY HELPERS
-- ─────────────────────────────────────────────────────────────────────────────
local function safeCall(fn, ...)
    if type(fn) ~= "function" then return false, "not a function" end
    return pcall(fn, ...)
end

local function uv(fn, idx)
    if type(fn) ~= "function" or type(debug) ~= "table" or type(debug.getupvalue) ~= "function" then
        return nil
    end
    local ok, _, val = pcall(debug.getupvalue, fn, idx)
    if ok then return val end
    return nil
end

local function suv(fn, idx, val)
    if type(fn) ~= "function" or type(debug) ~= "table" or type(debug.setupvalue) ~= "function" then
        return false
    end
    return (pcall(debug.setupvalue, fn, idx, val))
end

local function tileKey(x, y)
    return tostring(math.floor(x)) .. "," .. tostring(math.floor(y))
end

local function clamp(v, lo, hi)
    if v < lo then return lo end
    if v > hi then return hi end
    return v
end

local function formatDuration(sec)
    sec = math.max(0, math.floor(sec or 0))
    local h = math.floor(sec / 3600)
    local m = math.floor((sec % 3600) / 60)
    local s = sec % 60
    if h > 0 then
        return string.format("%dj %dm %ds", h, m, s)
    elseif m > 0 then
        return string.format("%dm %ds", m, s)
    else
        return string.format("%ds", s)
    end
end

-- Apply security random delay (5-60%, default 15%)
local function secWait(baseSec)
    local S = Core.State
    local d = baseSec or 0
    if S.sec.randomDelayOn then
        local pct = clamp(tonumber(S.sec.randomDelayPct) or 15, 5, 60) / 100
        d = d * (1 + math.random() * pct)
    end
    if d > 0 then
        task.wait(d)
    end
end

-- ─────────────────────────────────────────────────────────────────────────────
--  PER-WORLD PERSISTENCE
-- ─────────────────────────────────────────────────────────────────────────────
local function getWorldEntry(wName)
    wName = (wName and wName ~= "") and tostring(wName) or "_DEFAULT"
    if not Core.WorldData[wName] then
        Core.WorldData[wName] = {
            floors     = {},
            standPos   = nil,
            breakTiles = {},
            redTiles   = {},
        }
    end
    return Core.WorldData[wName]
end

function Core.GetCurrentWorldData()
    local wName = (H.gt and H.gt.name and H.gt.name ~= "") and H.gt.name or Core.State.worldName
    return getWorldEntry(wName)
end

function Core.SaveWorldConfig()
    if type(writefile) ~= "function" then return false end
    local serializable = {}
    for wName, wd in pairs(Core.WorldData) do
        local floorList = {}
        for y, on in pairs(wd.floors) do
            if on then floorList[#floorList + 1] = tonumber(y) end
        end
        local redList = {}
        for k, on in pairs(wd.redTiles) do
            if on then redList[#redList + 1] = k end
        end
        serializable[wName] = {
            floors     = floorList,
            standPos   = wd.standPos,
            breakTiles = wd.breakTiles,
            redTiles   = redList,
        }
    end
    local ok, encoded = pcall(function() return HttpService:JSONEncode(serializable) end)
    if ok and encoded then
        pcall(writefile, CONFIG_FILE, encoded)
        return true
    end
    return false
end

function Core.LoadWorldConfig()
    if type(readfile) ~= "function" or type(isfile) ~= "function" then return false end
    local okExists, exists = pcall(isfile, CONFIG_FILE)
    if not okExists or not exists then return false end
    local okRead, raw = pcall(readfile, CONFIG_FILE)
    if not okRead or type(raw) ~= "string" or raw == "" then return false end
    local okDec, decoded = pcall(function() return HttpService:JSONDecode(raw) end)
    if not okDec or type(decoded) ~= "table" then return false end
    for wName, entry in pairs(decoded) do
        if type(entry) == "table" then
            local wd = getWorldEntry(wName)
            wd.floors = {}
            for _, y in ipairs(entry.floors or {}) do
                wd.floors[tonumber(y)] = true
            end
            if type(entry.standPos) == "table" and entry.standPos.x and entry.standPos.y then
                wd.standPos = { x = math.floor(entry.standPos.x), y = math.floor(entry.standPos.y) }
            end
            wd.breakTiles = {}
            for _, bt in ipairs(entry.breakTiles or {}) do
                if type(bt) == "table" and bt.x and bt.y then
                    wd.breakTiles[#wd.breakTiles + 1] = { x = math.floor(bt.x), y = math.floor(bt.y) }
                end
            end
            wd.redTiles = {}
            for _, rk in ipairs(entry.redTiles or {}) do
                wd.redTiles[tostring(rk)] = true
            end
        end
    end
    return true
end

-- ─────────────────────────────────────────────────────────────────────────────
--  DYNAMIC MEMORY DISCOVERY (Latest GrowBlox Build Compatible)
-- ─────────────────────────────────────────────────────────────────────────────
local function isValidGT(t)
    if type(t) ~= "table" then return false end
    local ok, res = pcall(function()
        return type(rawget(t, "goTo")) == "function"
            and type(rawget(t, "touchBlocks")) == "function"
            and type(rawget(t, "dropList")) == "function"
            and type(rawget(t, "takeDrop")) == "function"
            and type(rawget(t, "fg")) == "table"
            and type(rawget(t, "bg")) == "table"
            and type(rawget(t, "w")) == "number"
            and type(rawget(t, "h")) == "number"
            and type(rawget(t, "name")) == "string"
    end)
    return ok and res == true
end

local function isValidNet(t)
    if type(t) ~= "table" then return false end
    local ok, res = pcall(function()
        local tile = rawget(t, "tile")
        local drop = rawget(t, "drop")
        local take = rawget(t, "take")
        local move = rawget(t, "move")
        return type(tile) == "table" and type(rawget(tile, "send")) == "function"
            and type(drop) == "table" and type(rawget(drop, "send")) == "function"
            and type(take) == "table" and type(rawget(take, "send")) == "function"
            and type(move) == "table" and type(rawget(move, "send")) == "function"
            and type(rawget(t, "worldTag")) == "function"
    end)
    return ok and res == true
end

local function isValidItemDB(t)
    if type(t) ~= "table" then return false end
    local ok, res = pcall(function()
        local d2 = rawget(t, 2)
        local d3 = rawget(t, 3)
        return type(d2) == "table" and d2.name == "Dirt"
            and type(d3) == "table" and d3.kind == "seed"
    end)
    return ok and res == true
end

local function isValidInv(t)
    if type(t) ~= "table" then return false end
    local ok, res = pcall(function()
        return type(rawget(t, "slots")) == "table"
            and type(rawget(t, "capacity")) == "number"
            and type(t.count) == "function"
            and type(t.add) == "function"
            and type(t.remove) == "function"
    end)
    return ok and res == true
end

local function inspectGoToAndRender(gt)
    if not gt or type(gt.goTo) ~= "function" then return end
    -- In lvzJPYBZmoBS.lua: gt.goTo upvalues contain px (v_u_716), py (v_u_718), gt (v_u_49), dead, prevX, prevY, vx, vy
    -- Match RenderStepped connection whose uv(fn, 1) == gt
    local renderFn = nil
    if type(getconnections) == "function" then
        local ok, conns = pcall(getconnections, RunService.RenderStepped)
        if ok and type(conns) == "table" then
            for _, c in ipairs(conns) do
                local fn = type(c) == "table" and (c.Function or c["function"]) or nil
                if type(fn) == "function" and uv(fn, 1) == gt then
                    -- Check for UIScale upvalue and numeric 64 upvalue
                    local hasScale, has64 = false, false
                    for idx = 1, 70 do
                        local val = uv(fn, idx)
                        if val == nil and idx > 55 then break end
                        if typeof(val) == "Instance" and val:IsA("UIScale") then
                            hasScale = true
                            H.uiScaleObj = val
                        elseif val == 64 then
                            has64 = true
                        elseif isValidInv(val) and not H.inv then
                            H.inv = val
                        end
                    end
                    if hasScale and has64 then
                        renderFn = fn
                        break
                    end
                end
            end
        end
    end

    if renderFn then
        H.renderFn = renderFn
        -- Find upvalue indices in RenderStepped dynamically by matching values/positions
        -- In lvzJPYBZmoBS.lua: goTo sets px=tx+0.5, py=ty+1; RenderStepped has:
        -- #7=dead(bool), #17=vx, #18=vy, #20=px, #21=py, #23=prevX, #24=prevY, #39=zoom, #43=targetZoom
        -- Verify px/py using goTo upvalue 1 & 2 if debug.getupvalue works
        local gpx = uv(gt.goTo, 1)
        local gpy = uv(gt.goTo, 2)
        if type(gpx) == "number" and type(gpy) == "number" then
            -- Match in renderFn around 15..30
            for idx = 15, 30 do
                if uv(renderFn, idx) == gpx and uv(renderFn, idx + 1) == gpy then
                    H.pxIdx = idx
                    H.pyIdx = idx + 1
                    break
                end
            end
        end
        if not H.pxIdx then
            H.pxIdx = 20
            H.pyIdx = 21
        end
        H.vxIdx = 17
        H.vyIdx = 18
        H.prevXIdx = 23
        H.prevYIdx = 24
        H.deadIdx = 7
    end

    -- Also discover trees table (v_u_324) from gt.treeLook or RenderStepped or getgc
    if type(gt.treeLook) == "function" then
        for idx = 1, 20 do
            local val = uv(gt.treeLook, idx)
            if type(val) == "table" and val ~= gt and val ~= H.ItemDB then
                -- treeLook has v_u_326 (visual cache); try gt.ride or treeChanged listener for v_u_324
            end
        end
    end
    if type(gt.ride) == "function" then
        for idx = 1, 20 do
            local val = uv(gt.ride, idx)
            if type(val) == "table" and val ~= gt and val ~= H.ItemDB then
                -- Check if any value looks like { p = number, f = number }
                local okTree, isTreeMap = pcall(function()
                    local k, v = next(val)
                    return k == nil or (type(k) == "number" and type(v) == "table" and type(v.p) == "number")
                end)
                if okTree and isTreeMap and not H.trees then
                    -- gt.ride upvalue 6 is v_u_324 in lvzJPYBZmoBS.lua
                    if idx == 6 then
                        H.trees = val
                    end
                end
            end
        end
    end
end

local function installHooks()
    -- 1. Hook gt.takeDrop so we can suppress ALL auto-collect (both bot & game RenderStepped!) during Auto Drop
    if H.gt and type(H.gt.takeDrop) == "function" and not H.takeDropHooked then
        H.origTakeDrop = H.gt.takeDrop
        H.gt.takeDrop = function(uid, want)
            if Core.State.suppressCollect then
                return 0
            end
            return H.origTakeDrop(uid, want)
        end
        H.takeDropHooked = true
    end

    -- 2. Listen to Net.treeChanged & Net.tileChanged to keep a mirrored tree map accurate even if v_u_324 isn't directly found
    if H.Net and not H.netHooked then
        H.netHooked = true
        Core._mirroredTrees = Core._mirroredTrees or {}
        if H.Net.treeChanged and type(H.Net.treeChanged.listen) == "function" then
            pcall(function()
                H.Net.treeChanged.listen(function(pkt)
                    if not H.gt or not pkt then return end
                    if pkt.w == H.Net.worldTag(H.gt.name or "") then
                        local idx = pkt.y * H.gt.w + pkt.x
                        Core._mirroredTrees[idx] = pkt.tree
                        if H.trees then
                            H.trees[idx] = pkt.tree
                        end
                    end
                end)
            end)
        end
        if H.Net.tileChanged and type(H.Net.tileChanged.listen) == "function" then
            pcall(function()
                H.Net.tileChanged.listen(function(pkt)
                    if not H.gt or not pkt then return end
                    if pkt.w == H.Net.worldTag(H.gt.name or "") then
                        if pkt.layer ~= 2 then
                            local id = pkt.id or 0
                            local e = H.ItemDB and H.ItemDB[id]
                            if not e or e.kind ~= "seed" then
                                local idx = pkt.y * H.gt.w + pkt.x
                                Core._mirroredTrees[idx] = nil
                                if H.trees then H.trees[idx] = nil end
                            end
                        end
                    end
                end)
            end)
        end
    end
end

function Core.Discover()
    -- 1. Try scanning ReplicatedStorage / shared / getgc(true)
    if type(getgc) == "function" then
        local ok, gc = pcall(getgc, true)
        if ok and type(gc) == "table" then
            for i = 1, #gc do
                local v = gc[i]
                if type(v) == "table" then
                    if not H.gt and isValidGT(v) then
                        H.gt = v
                    elseif not H.Net and isValidNet(v) then
                        H.Net = v
                    elseif not H.ItemDB and isValidItemDB(v) then
                        H.ItemDB = v
                    elseif not H.inv and isValidInv(v) then
                        H.inv = v
                    end
                    if H.gt and H.Net and H.ItemDB and H.inv then break end
                end
            end
        end
    end

    -- Fallback: try ReplicatedStorage.Shared if running on older un-obfuscated build
    if not H.Net or not H.ItemDB then
        local sh = ReplicatedStorage:FindFirstChild("Shared")
        if sh then
            if not H.Net and sh:FindFirstChild("Net") then
                pcall(function() H.Net = require(sh.Net) end)
            end
            if not H.ItemDB and sh:FindFirstChild("ItemDB") then
                pcall(function() H.ItemDB = require(sh.ItemDB) end)
            end
        end
    end

    if H.gt then
        inspectGoToAndRender(H.gt)
        installHooks()
    end

    local d = Core.State.diag
    d.gt     = H.gt ~= nil
    d.net    = H.Net ~= nil
    d.itemDB = H.ItemDB ~= nil
    d.inv    = H.inv ~= nil
    d.trees  = (H.trees ~= nil) or (Core._mirroredTrees ~= nil)
    d.render = H.renderFn ~= nil

    Core.State.ready = d.gt and d.net and d.itemDB
    if H.gt and H.gt.name and H.gt.name ~= "" then
        Core.State.worldLoaded = true
        if Core.State.worldName ~= H.gt.name then
            Core.State.worldName = H.gt.name
            Core._mirroredTrees = {}
            H.breakFails = {}
        end
    else
        Core.State.worldLoaded = false
    end
    return Core.State.ready
end

function Core.GetHandles()
    return H
end

-- ─────────────────────────────────────────────────────────────────────────────
--  POSITION & MOVEMENT (Authoritative goTo + Net.move.send)
-- ─────────────────────────────────────────────────────────────────────────────
function Core.ReadPos()
    local gt = H.gt
    if H.renderFn and H.pxIdx then
        local x = uv(H.renderFn, H.pxIdx)
        local y = uv(H.renderFn, H.pyIdx)
        if type(x) == "number" then Core.State.pos.x = x end
        if type(y) == "number" then Core.State.pos.y = y end
        Core.State.pos.dead = uv(H.renderFn, H.deadIdx) == true
    elseif gt and type(gt.goTo) == "function" then
        local x = uv(gt.goTo, 1)
        local y = uv(gt.goTo, 2)
        if type(x) == "number" then Core.State.pos.x = x end
        if type(y) == "number" then Core.State.pos.y = y end
    end
    Core.State.pos.tx = math.floor(Core.State.pos.x)
    Core.State.pos.ty = math.floor(Core.State.pos.y - 0.5)
    return Core.State.pos
end

function Core.SendMove()
    local gt, net = H.gt, H.Net
    if not gt or not net or not net.move or gt.name == "" then return false end
    return pcall(function()
        net.move.send({
            x     = Core.State.pos.x,
            y     = Core.State.pos.y,
            vx    = 0,
            vy    = 0,
            flags = 2,
            t     = math.floor((os.clock() * 1000) % 65535),
        })
    end)
end

-- Move to tile (tx, ty) cleanly: updates gt internal coords + sends move packet
function Core.MoveToTile(tx, ty)
    local gt = H.gt
    if not gt then return false end
    tx = math.floor(tx)
    ty = math.floor(ty)
    if tx < 0 or tx >= gt.w or ty < 0 or ty >= gt.h then return false end

    local px = tx + 0.5
    local py = ty + 1
    if H.renderFn and H.pxIdx then
        suv(H.renderFn, H.pxIdx, px)
        suv(H.renderFn, H.pyIdx, py)
        suv(H.renderFn, H.vxIdx, 0)
        suv(H.renderFn, H.vyIdx, 0)
        suv(H.renderFn, H.prevXIdx, px)
        suv(H.renderFn, H.prevYIdx, py)
        gt.stuckAt = nil
        gt.portalGo = nil
    end
    if type(gt.goTo) == "function" then
        pcall(gt.goTo, tx, ty)
    end
    Core.State.pos.x  = px
    Core.State.pos.y  = py
    Core.State.pos.tx = tx
    Core.State.pos.ty = ty
    Core.SendMove()
    return true
end

function Core.SetFly(on, speed)
    Core.State.fly = on == true
    if type(speed) == "number" then Core.State.flySpeed = clamp(speed, 8, 60) end
    if H.flyConn then H.flyConn:Disconnect(); H.flyConn = nil end
    if Core.State.fly then
        local UIS = game:GetService("UserInputService")
        H.flyConn = RunService.RenderStepped:Connect(function(dt)
            if not H.gt or not H.renderFn or not H.pxIdx or H.gt.name == "" then return end
            local dx, dy = 0, 0
            if UIS:IsKeyDown(Enum.KeyCode.A) or UIS:IsKeyDown(Enum.KeyCode.Left) then dx -= 1 end
            if UIS:IsKeyDown(Enum.KeyCode.D) or UIS:IsKeyDown(Enum.KeyCode.Right) then dx += 1 end
            if UIS:IsKeyDown(Enum.KeyCode.W) or UIS:IsKeyDown(Enum.KeyCode.Up) or UIS:IsKeyDown(Enum.KeyCode.Space) then dy -= 1 end
            if UIS:IsKeyDown(Enum.KeyCode.S) or UIS:IsKeyDown(Enum.KeyCode.Down) then dy += 1 end
            local p = Core.ReadPos()
            local nx = clamp(p.x + dx * Core.State.flySpeed * dt, 0.5, H.gt.w - 0.5)
            local ny = clamp(p.y + dy * Core.State.flySpeed * dt, 1, H.gt.h - 0.5)
            suv(H.renderFn, H.pxIdx, nx)
            suv(H.renderFn, H.pyIdx, ny)
            suv(H.renderFn, H.vxIdx, 0)
            suv(H.renderFn, H.vyIdx, 0)
            suv(H.renderFn, H.prevXIdx, nx)
            suv(H.renderFn, H.prevYIdx, ny)
        end)
    end
end

-- ─────────────────────────────────────────────────────────────────────────────
--  INVENTORY & ITEM DB HELPERS
-- ─────────────────────────────────────────────────────────────────────────────
function Core.GetItemInfo(id)
    return H.ItemDB and H.ItemDB[id] or nil
end

function Core.GetItemName(id)
    local e = Core.GetItemInfo(id)
    return e and e.name or ("Item#" .. tostring(id))
end

function Core.CountItem(id)
    if not H.inv or not id then return 0 end
    local ok, c = pcall(function() return H.inv:count(id) end)
    return (ok and type(c) == "number") and c or 0
end

function Core.RemoveItemLocal(id, n)
    if not H.inv or not id then return false end
    local ok, res = pcall(function() return H.inv:remove(id, n or 1) end)
    return ok and res ~= false
end

function Core.GetItemRoom(id)
    if not H.inv or not id then return 0 end
    if type(H.inv.room) == "function" then
        local ok, r = pcall(function() return H.inv:room(id) end)
        if ok and type(r) == "number" then return r end
    end
    local cnt = Core.CountItem(id)
    return math.max(0, MAX_STACK - cnt)
end

function Core.IsBackpackFullFor(id)
    if not H.inv then return false end
    if Core.CountItem(id) >= MAX_STACK then return true end
    local room = Core.GetItemRoom(id)
    return room <= 0
end

function Core.GetInventoryList()
    local list = {}
    if not H.inv or type(H.inv.slots) ~= "table" then return list end
    for _, slot in ipairs(H.inv.slots) do
        if type(slot) == "table" and slot.id and (slot.n or 0) > 0 then
            local info = Core.GetItemInfo(slot.id)
            list[#list + 1] = {
                id   = slot.id,
                n    = slot.n,
                name = info and info.name or ("Item#" .. slot.id),
                kind = info and info.kind or "block",
            }
        end
    end
    return list
end

function Core.SearchItems(query)
    local res = {}
    if not H.ItemDB then return res end
    local q = string.lower(tostring(query or ""))
    for id, e in pairs(H.ItemDB) do
        if type(id) == "number" and type(e) == "table" and e.name then
            if q == "" or string.find(string.lower(e.name), q, 1, true) or tostring(id) == q then
                res[#res + 1] = {
                    id   = id,
                    name = e.name,
                    kind = e.kind or (e.background and "bg" or "fg"),
                    hits = e.hits or 0,
                }
                if #res >= 80 then break end
            end
        end
    end
    table.sort(res, function(a, b) return a.id < b.id end)
    return res
end

-- ─────────────────────────────────────────────────────────────────────────────
--  WORLD TILE / TREE / REACHABILITY HELPERS
-- ─────────────────────────────────────────────────────────────────────────────
function Core.GetFG(x, y)
    local gt = H.gt
    if not gt or not gt.fg then return 0 end
    local row = gt.fg[y]
    return row and row[x] or 0
end

function Core.GetBG(x, y)
    local gt = H.gt
    if not gt or not gt.bg then return 0 end
    local row = gt.bg[y]
    return row and row[x] or 0
end

function Core.IsSolid(x, y)
    local gt = H.gt
    if not gt then return true end
    if x < 0 or x >= gt.w or y >= gt.h then return true end
    if y < 0 then return false end
    local id = Core.GetFG(x, y)
    if id == 0 then return false end
    local e = Core.GetItemInfo(id)
    if not e then return false end
    if e.door or e.entrance then
        return false
    end
    return e.solid == true
end

function Core.CanEditTile(x, y)
    local gt = H.gt
    if not gt then return false end
    if x < 0 or x >= gt.w or y < 0 or y >= gt.h then return false end
    if gt.areas and type(gt.areas.canEdit) == "function" then
        local ok, can = pcall(gt.areas.canEdit, x, y)
        if ok then return can == true end
    end
    if gt.areas and type(gt.areas.mayBuild) == "function" then
        local ok, can = pcall(gt.areas.mayBuild, gt.lock, x, y)
        if ok then return can == true end
    end
    return true
end

function Core.IsProtectedTile(id)
    if id == 0 then return false end
    local e = Core.GetItemInfo(id)
    if not e then return true end
    local n = string.lower(e.name or "")
    if n == "blank" or string.find(n, "bedrock", 1, true) or string.find(n, "door", 1, true) then
        return true
    end
    if e.lock or e.area or e.vend or e.display or e.displayOne or e.worldKey or e.entrance or e.vip or e.combiner then
        return true
    end
    return false
end

-- Check if tile (x, y) is a valid place to plant a seed (empty fg, solid/platform below, editable)
function Core.IsPlantable(x, y)
    local gt = H.gt
    if not gt or x < 0 or x >= gt.w or y < 0 or y >= gt.h - 1 then return false end
    local fgId = Core.GetFG(x, y)
    if fgId ~= 0 then return false end
    local belowId = Core.GetFG(x, y + 1)
    if belowId == 0 then return false end
    local below = Core.GetItemInfo(belowId)
    if not below or not (below.solid == true or below.platform == true) then return false end
    return Core.CanEditTile(x, y)
end

-- Check if row y is a valid farm floor (has at least 1 solid/platform tile below it and open space at y)
function Core.IsValidFloorRow(y)
    local gt = H.gt
    if not gt or y < 1 or y >= gt.h - 1 then return false end
    local count = 0
    for x = 0, gt.w - 1 do
        local belowId = Core.GetFG(x, y + 1)
        if belowId ~= 0 then
            local below = Core.GetItemInfo(belowId)
            if below and (below.solid == true or below.platform == true) then
                local curId = Core.GetFG(x, y)
                local curInfo = Core.GetItemInfo(curId)
                if curId == 0 or (curInfo and curInfo.kind == "seed") then
                    if Core.CanEditTile(x, y) then
                        count += 1
                    end
                end
            end
        end
    end
    return count >= 3
end

-- Tree helpers
function Core.GetTreeAt(x, y)
    local gt = H.gt
    if not gt then return nil end
    local idx = y * gt.w + x
    if H.trees and H.trees[idx] then
        return H.trees[idx]
    end
    if Core._mirroredTrees and Core._mirroredTrees[idx] then
        return Core._mirroredTrees[idx]
    end
    return nil
end

function Core.IsTreeRipe(x, y)
    local fgId = Core.GetFG(x, y)
    if fgId == 0 then return false end
    local info = Core.GetItemInfo(fgId)
    if not info then return false end
    if info.kind ~= "seed" then return false end
    local tr = Core.GetTreeAt(x, y)
    if not tr or type(tr.p) ~= "number" then
        return false
    end
    local grow = info.grow or 0
    return workspace:GetServerTimeNow() >= (tr.p + grow)
end

function Core.GetTreeRemainingSec(x, y)
    local fgId = Core.GetFG(x, y)
    local info = Core.GetItemInfo(fgId)
    local tr = Core.GetTreeAt(x, y)
    if not info or info.kind ~= "seed" or not tr or type(tr.p) ~= "number" then
        return nil
    end
    local rem = (tr.p + (info.grow or 0)) - workspace:GetServerTimeNow()
    return math.max(0, rem)
end

-- BFS Reachability from current player tile (marks impassable/walled-off tiles so bot never loops forever)
function Core.ComputeReachableSet()
    local gt = H.gt
    if not gt then return {} end
    local p = Core.ReadPos()
    local sx = clamp(p.tx, 0, gt.w - 1)
    local sy = clamp(p.ty, 0, gt.h - 1)
    if Core.IsSolid(sx, sy) and gt.spawn then
        sx = clamp(math.floor(gt.spawn.X), 0, gt.w - 1)
        sy = clamp(math.floor(gt.spawn.Y), 0, gt.h - 1)
    end

    local w, h = gt.w, gt.h
    local visited = {}
    local queue = { sy * w + sx }
    visited[sy * w + sx] = true
    local head = 1
    while head <= #queue do
        local cur = queue[head]
        head += 1
        local cx = cur % w
        local cy = math.floor(cur / w)
        local neighbors = {
            { cx + 1, cy }, { cx - 1, cy },
            { cx, cy + 1 }, { cx, cy - 1 }
        }
        for _, nb in ipairs(neighbors) do
            local nx, ny = nb[1], nb[2]
            if nx >= 0 and nx < w and ny >= 0 and ny < h then
                local nIdx = ny * w + nx
                if not visited[nIdx] and not Core.IsSolid(nx, ny) then
                    visited[nIdx] = true
                    queue[#queue + 1] = nIdx
                end
            end
        end
    end
    return visited
end

function Core.IsTileReachable(reachableSet, x, y)
    local gt = H.gt
    if not gt then return false end
    if x < 0 or x >= gt.w or y < 0 or y >= gt.h then return false end
    -- A tile is reachable if the tile itself OR one of its 4 cardinal neighbors is in reachableSet
    local w = gt.w
    if reachableSet[y * w + x] then return true end
    if x > 0 and reachableSet[y * w + (x - 1)] then return true end
    if x < w - 1 and reachableSet[y * w + (x + 1)] then return true end
    if y > 0 and reachableSet[(y - 1) * w + x] then return true end
    if y < gt.h - 1 and reachableSet[(y + 1) * w + x] then return true end
    return false
end

-- ─────────────────────────────────────────────────────────────────────────────
--  LOW-LEVEL PACKET SENDERS (MATCH LATEST ByteNet Net.lua)
-- ─────────────────────────────────────────────────────────────────────────────
function Core.SendTilePacket(layer, x, y, id, flip)
    local net = H.Net
    local gt = H.gt
    if not net or not net.tile or not net.tile.send or not gt then return false end
    x = math.floor(x)
    y = math.floor(y)
    if x < 0 or x >= gt.w or y < 0 or y >= gt.h then return false end

    local ok = pcall(function()
        net.tile.send({
            layer = layer or 1,
            x     = x,
            y     = y,
            id    = math.floor(id or 0),
            flip  = flip == true,
        })
    end)
    if ok then
        -- Mirror local state cleanly like game's setTile does
        if layer == 2 then
            if gt.bg and gt.bg[y] then gt.bg[y][x] = id end
        else
            if gt.fg and gt.fg[y] then gt.fg[y][x] = id end
        end
        H.lastTileAt = os.clock()
    end
    return ok
end

function Core.BreakTile(x, y, layer)
    layer = layer or 1
    local cur = (layer == 2) and Core.GetBG(x, y) or Core.GetFG(x, y)
    if cur == 0 then return true end
    if Core.IsProtectedTile(cur) then return false end

    local info = Core.GetItemInfo(cur)
    -- If it's a tree/seed, harvest via tile id=0 (or harvest packet if provider)
    if info and info.kind == "seed" and info.provider and H.Net and H.Net.harvest then
        local ok = pcall(function()
            H.Net.harvest.send({ x = math.floor(x), y = math.floor(y) })
        end)
        return ok
    end

    -- 1 HIT MODE: sends single break tile packet (id = 0)
    -- If 1 HIT MODE is disabled and block requires multiple hits, still respects breakDelay per hit/action
    if Core.State.oneHitMode then
        return Core.SendTilePacket(layer, x, y, 0, false)
    else
        local hits = (info and info.hits) or 3
        if H.Net and H.Net.act and H.Net.act.send then
            for _ = 1, math.max(1, hits - 1) do
                pcall(function()
                    H.Net.act.send({ kind = 1, x = x + 0.5, y = y + 0.5 })
                end)
                secWait(0.16)
            end
        end
        return Core.SendTilePacket(layer, x, y, 0, false)
    end
end

function Core.PlaceTile(x, y, itemId)
    if not itemId or itemId <= 0 then return false end
    if Core.CountItem(itemId) <= 0 then return false end
    local info = Core.GetItemInfo(itemId)
    local layer = (info and info.background) and 2 or 1
    local cur = (layer == 2) and Core.GetBG(x, y) or Core.GetFG(x, y)
    if cur ~= 0 then return false end

    local ok = Core.SendTilePacket(layer, x, y, itemId, false)
    if ok then
        Core.RemoveItemLocal(itemId, 1)
    end
    return ok
end

function Core.RemoteTakeDrop(uid, want)
    local gt = H.gt
    if not gt or Core.State.suppressCollect then return 0 end
    local takeFn = H.origTakeDrop or gt.takeDrop
    if type(takeFn) ~= "function" then return 0 end
    local ok, got = pcall(takeFn, uid, want or 1)
    if ok and type(got) == "number" then
        return got
    end
    return 0
end

function Core.CollectDropsInRadius(cx, cy, radius, filterId)
    local gt = H.gt
    if not gt or Core.State.suppressCollect or type(gt.dropList) ~= "function" then return 0 end
    local ok, drops = pcall(gt.dropList)
    if not ok or type(drops) ~= "table" then return 0 end

    local now = os.clock()
    local copy = {}
    for i = 1, #drops do copy[i] = drops[i] end

    local totalTaken = 0
    for _, d in ipairs(copy) do
        if Core.State.suppressCollect then break end
        if type(d) == "table" and d.uid and d.x and d.y and (d.n or 0) > 0 then
            if (d.readyAt or 0) <= now then
                if not filterId or d.id == filterId then
                    local dist = math.max(math.abs(d.x - (cx + 0.5)), math.abs(d.y - (cy + 0.5)))
                    if dist <= (radius or 5) then
                        -- Prevent item overflow (Aman dari tas penuh, max 200)
                        if d.id == 112 or not Core.IsBackpackFullFor(d.id) then
                            local room = (d.id == 112) and d.n or Core.GetItemRoom(d.id)
                            local want = math.min(d.n, room)
                            if want > 0 then
                                local got = Core.RemoteTakeDrop(d.uid, want)
                                if got > 0 then
                                    totalTaken += got
                                    if d.id ~= 112 and H.inv and type(H.inv.add) == "function" then
                                        pcall(function() H.inv:add(d.id, got) end)
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
    end
    return totalTaken
end

function Core.DropItemPacket(itemId, count, dropX, dropY)
    local gt, net = H.gt, H.Net
    if not gt or not net or not net.drop or not net.drop.send then return false, "net nil" end
    count = math.floor(tonumber(count) or 0)
    if count <= 0 then return false, "count <= 0" end
    if Core.CountItem(itemId) < count then
        count = Core.CountItem(itemId)
    end
    if count <= 0 then return false, "item tidak cukup" end

    -- Respect server DROP_COOLDOWN (1.05s)
    local since = os.clock() - (H.lastDropAt or 0)
    if since < 1.08 then
        task.wait(1.08 - since)
    end

    if type(gt.dropOk) == "function" then
        local okChk, canDrop = pcall(gt.dropOk, dropX)
        if okChk and canDrop == false then
            return false, "lokasi drop terhalang"
        end
    end

    local ok = pcall(function()
        net.drop.send({
            id = math.floor(itemId),
            n  = count,
            x  = dropX,
            y  = dropY,
        })
    end)
    if ok then
        H.lastDropAt = os.clock()
        Core.RemoveItemLocal(itemId, count)
        return true
    end
    return false, "gagal kirim drop packet"
end

function Core.EnterWorld(worldName)
    local gt = H.gt
    if not gt or type(gt.enter) ~= "function" then return false, "gt.enter nil" end
    worldName = string.upper(tostring(worldName or ""):gsub("^%s+", ""):gsub("%s+$", ""))
    if worldName == "" then return false, "nama world kosong" end
    if gt.name == worldName then return true end

    local ok, res, msg = pcall(gt.enter, worldName)
    if not ok then return false, tostring(res) end
    if not res then return false, tostring(msg or "gagal masuk world") end

    -- Wait until world finishes loading
    local deadline = os.clock() + 12
    while os.clock() < deadline do
        if gt.name == worldName and gt.fg and gt.w and gt.w > 0 then
            task.wait(0.35)
            Core.Discover()
            return true
        end
        task.wait(0.15)
    end
    return gt.name == worldName, "timeout loading world"
end

-- ─────────────────────────────────────────────────────────────────────────────
--  PETA MINI INTERACTIVE MODIFIERS
-- ─────────────────────────────────────────────────────────────────────────────
function Core.CountSelectedFloors(wd)
    wd = wd or Core.GetCurrentWorldData()
    local n = 0
    for _, on in pairs(wd.floors) do
        if on then n += 1 end
    end
    return n
end

function Core.ToggleFloor(y)
    if Core.State.fullWorld then return false, "Full World aktif (lantai dikunci)" end
    local wd = Core.GetCurrentWorldData()
    y = math.floor(y)
    if wd.floors[y] then
        wd.floors[y] = nil
        Core.SaveWorldConfig()
        return true, false
    else
        if Core.CountSelectedFloors(wd) >= MAX_MANUAL_FLOORS then
            return false, "Batas lantai maksimal " .. MAX_MANUAL_FLOORS
        end
        wd.floors[y] = true
        Core.SaveWorldConfig()
        return true, true
    end
end

function Core.SetStandPos(x, y)
    local wd = Core.GetCurrentWorldData()
    wd.standPos = { x = math.floor(x), y = math.floor(y) }
    wd.redTiles[tileKey(x, y)] = nil
    Core.SaveWorldConfig()
    return wd.standPos
end

function Core.ToggleBreakTile(x, y)
    local wd = Core.GetCurrentWorldData()
    x, y = math.floor(x), math.floor(y)
    for i, bt in ipairs(wd.breakTiles) do
        if bt.x == x and bt.y == y then
            table.remove(wd.breakTiles, i)
            Core.SaveWorldConfig()
            return false
        end
    end
    wd.breakTiles[#wd.breakTiles + 1] = { x = x, y = y }
    wd.redTiles[tileKey(x, y)] = nil
    Core.SaveWorldConfig()
    return true
end

function Core.ClearRedTiles()
    local wd = Core.GetCurrentWorldData()
    wd.redTiles = {}
    H.breakFails = {}
    Core.SaveWorldConfig()
end

function Core.IsBreakTileCoord(wd, x, y)
    for _, bt in ipairs(wd.breakTiles) do
        if bt.x == x and bt.y == y then return true end
    end
    return false
end

-- ─────────────────────────────────────────────────────────────────────────────
--  SMART AUTO-BREAK SPOT PICKER (When user hasn't set manual Stand/Break tiles)
-- ─────────────────────────────────────────────────────────────────────────────
local function findSmartBreakSpot(wd, reachable)
    local gt = H.gt
    if not gt then return nil, nil end
    local p = Core.ReadPos()
    local bestScore = math.huge
    local bestStand, bestBreak = nil, nil

    -- Search around player or world for a pair: stand (sx, sy) on solid/platform, break (bx, by) = (sx+1, sy) or (sx-1, sy)
    for y = 1, gt.h - 2 do
        for x = 1, gt.w - 2 do
            if Core.IsTileReachable(reachable, x, y) and not Core.IsSolid(x, y) and Core.IsSolid(x, y + 1) then
                local candidates = { { x + 1, y }, { x - 1, y } }
                for _, c in ipairs(candidates) do
                    local bx, by = c[1], c[2]
                    local key = tileKey(bx, by)
                    if not wd.redTiles[key] and Core.CanEditTile(bx, by) then
                        local fgId = Core.GetFG(bx, by)
                        local info = Core.GetItemInfo(fgId)
                        -- Do not overwrite existing trees with break tiles
                        if fgId == 0 or (info and info.kind ~= "seed" and not Core.IsProtectedTile(fgId)) then
                            local dist = math.abs(x - p.tx) + math.abs(y - p.ty)
                            if dist < bestScore then
                                bestScore = dist
                                bestStand = { x = x, y = y }
                                bestBreak = { { x = bx, y = by } }
                            end
                        end
                    end
                end
            end
        end
    end
    return bestStand, bestBreak
end

-- ─────────────────────────────────────────────────────────────────────────────
--  DISCORD WEBHOOK + KEAMANAN TAMBAHAN
-- ─────────────────────────────────────────────────────────────────────────────
function Core.SendDiscordWebhook(title, description, colorInt)
    local url = tostring(Core.State.sec.discordWebhook or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if url == "" then return false, "URL webhook kosong" end

    local payload = HttpService:JSONEncode({
        username = "SkyP Guard",
        embeds = {
            {
                title       = title or "SkyP Notifikasi",
                description = description or "",
                color       = colorInt or 15158332,
                timestamp   = os.date("!%Y-%m-%dT%H:%M:%SZ"),
            }
        }
    })

    local reqFn = request or http_request or (syn and syn.request) or (http and http.request)
    if type(reqFn) == "function" then
        local ok, resp = pcall(reqFn, {
            Url     = url,
            Method  = "POST",
            Headers = { ["Content-Type"] = "application/json" },
            Body    = payload,
        })
        return ok and resp and (resp.StatusCode == 200 or resp.StatusCode == 204), ok and "sent" or tostring(resp)
    end
    return false, "executor tidak mendukung HTTP request"
end

function Core.GetSecurityStatus()
    local sec = Core.State.sec
    local now = os.clock()
    local totalRun = now - (sec.sessionStartAt or now)

    local nextBreakIn = nil
    local breakRem = nil
    if sec.periodicBreakOn then
        if sec.inBreak then
            breakRem = math.max(0, sec.breakEndsAt - now)
        else
            if sec.nextBreakAt <= 0 then
                sec.nextBreakAt = now + (sec.breakEveryMin * 60)
            end
            nextBreakIn = math.max(0, sec.nextBreakAt - now)
        end
    end

    local maxLeft = nil
    if sec.maxRuntimeOn then
        maxLeft = math.max(0, (sec.maxRuntimeHours * 3600) - totalRun)
    end

    return {
        totalRunSec     = totalRun,
        totalRunText    = formatDuration(totalRun),
        inBreak         = sec.inBreak,
        breakRemText    = breakRem and formatDuration(breakRem) or nil,
        nextBreakText   = nextBreakIn and formatDuration(nextBreakIn) or "Mati",
        maxLeftText     = maxLeft and formatDuration(maxLeft) or "Mati",
        runtimeStopped  = sec.runtimeStopped,
    }
end

function Core.ResetSecurityTimers()
    local sec = Core.State.sec
    local now = os.clock()
    sec.sessionStartAt = now
    sec.lastBreakEndAt = now
    sec.inBreak        = false
    sec.runtimeStopped = false
    sec.webhookSent    = false
    -- Slight random variance (+- 5%) around 45m & 3m
    local jitter = 0.95 + math.random() * 0.1
    sec.nextBreakAt    = now + (sec.breakEveryMin * 60 * jitter)
end

-- Check and execute security pause/stop (runs independently of Penjaga/Mod Watcher!)
local function checkSecurityGate()
    local S = Core.State
    local sec = S.sec
    local now = os.clock()

    -- 1. Batas waktu jalan (stops ALL activities except Vending doesn't care about periodic break)
    if sec.maxRuntimeOn then
        local elapsed = now - (sec.sessionStartAt or now)
        if elapsed >= (sec.maxRuntimeHours * 3600) then
            sec.runtimeStopped = true
            S.pabrikRunning = false
            S.gridRunning   = false
            S.dirtRunning   = false
            S.vendRunning   = false
            sec.vendingActive = false
            S.waitReason    = "Batas waktu jalan tercapai (" .. tostring(sec.maxRuntimeHours) .. " jam)"
            S.phase         = "STOPPED"
            if not sec.webhookSent then
                sec.webhookSent = true
                task.spawn(function()
                    Core.SendDiscordWebhook(
                        "SkyP Batas Waktu Jalan Tercapai",
                        string.format(
                            "Bot berhenti otomatis setelah **%s**.\nWorld: `%s`\nPanen: **%d** | Tanam: **%d** | Drop: **%d**",
                            formatDuration(elapsed),
                            tostring(S.worldName),
                            S.stats.harvested, S.stats.planted, S.stats.dropped
                        ),
                        15105570
                    )
                end)
            end
            return false
        end
    end

    -- 2. Istirahat berkala (+-45m kerja, +-3m istirahat)
    -- CATATAN: Istirahat tidak memotong perjalanan drop Pabrik, dan Vending tidak ikut istirahat berkala
    if sec.periodicBreakOn and not S.inDropTrip and not sec.vendingActive then
        if sec.nextBreakAt <= 0 then
            sec.nextBreakAt = now + (sec.breakEveryMin * 60 * (0.95 + math.random() * 0.1))
        end
        if not sec.inBreak and now >= sec.nextBreakAt then
            sec.inBreak = true
            local dur = sec.breakForMin * 60 * (0.9 + math.random() * 0.2)
            sec.breakEndsAt = now + dur
        end
        while sec.inBreak and (S.pabrikRunning or S.gridRunning or S.dirtRunning) do
            local rem = sec.breakEndsAt - os.clock()
            if rem <= 0 or not sec.periodicBreakOn then
                sec.inBreak = false
                sec.lastBreakEndAt = os.clock()
                sec.nextBreakAt = sec.lastBreakEndAt + (sec.breakEveryMin * 60 * (0.95 + math.random() * 0.1))
                S.waitReason = nil
                break
            end
            S.phase = "ISTIRAHAT"
            S.waitReason = "Istirahat berkala (" .. formatDuration(rem) .. ")"
            task.wait(1)
        end
    end

    return true
end

-- ─────────────────────────────────────────────────────────────────────────────
--  MOD GUARD / PENJAGA
-- ─────────────────────────────────────────────────────────────────────────────
function Core.SetModWatch(on, action)
    Core.State.modWatchOn = on == true
    if action == "SLEEP" or action == "LEAVE" then
        Core.State.modAction = action
    end
    if H.modConn then H.modConn:Disconnect(); H.modConn = nil end
    if Core.State.modWatchOn then
        local function checkPlayer(plr)
            if plr == LP then return end
            local isMod = false
            pcall(function()
                if plr:GetAttribute("Staff") or plr:GetAttribute("Moderator") or plr:GetAttribute("Admin") then
                    isMod = true
                end
            end)
            if isMod then
                Core.State.modCount += 1
                table.insert(Core.State.modLog, 1, string.format("[%s] %s terdeteksi", os.date("%H:%M:%S"), plr.Name))
                if #Core.State.modLog > 30 then table.remove(Core.State.modLog) end
                if Core.State.modAction == "LEAVE" and H.Net and H.Net.leave then
                    pcall(H.Net.leave.send)
                    Core.StopAllFarming()
                else
                    Core.StopAllFarming()
                    Core.State.waitReason = "Mod terdeteksi (" .. plr.Name .. ")"
                end
            end
        end
        for _, p in ipairs(Players:GetPlayers()) do checkPlayer(p) end
        H.modConn = Players.PlayerAdded:Connect(checkPlayer)
    end
end

-- ─────────────────────────────────────────────────────────────────────────────
--  PHASE 2: AUTO DROP SEED (Between Phases, Collect 100% Disabled)
-- ─────────────────────────────────────────────────────────────────────────────
local function runDropPhaseIfNeeded(forceDrop)
    local S = Core.State
    local gt = H.gt
    if not gt or not S.autoDropSeed then return true end

    local seedId = S.seedId
    if not seedId or seedId <= 0 then return true end

    local capThreshold = clamp(tonumber(S.dropThreshold) or 180, 1, MAX_DROP_THRESHOLD)
    local currentSeeds = Core.CountItem(seedId)
    if not forceDrop and currentSeeds < capThreshold then
        return true
    end

    local keep = clamp(tonumber(S.keepSeedCount) or 20, 0, capThreshold - 1)
    local toDrop = currentSeeds - keep
    if toDrop <= 0 then return true end

    local farmWorld = gt.name
    local targetWorld = tostring(S.dropWorld or ""):gsub("^%s+", ""):gsub("%s+$", "")
    local crossWorld = (targetWorld ~= "" and string.upper(targetWorld) ~= string.upper(farmWorld))

    S.phase = "DROP SEED"
    S.inDropTrip = true
    -- MATIKAN COLLECT TOTAL SELAMA PERGI DROP (prevents picking up own drops!)
    S.suppressCollect = true

    local dropSuccess = false
    local errMsg = nil

    local okPhase, phaseErr = pcall(function()
        if crossWorld then
            local okEnter, eMsg = Core.EnterWorld(targetWorld)
            if not okEnter then
                errMsg = "Drop gagal (" .. tostring(eMsg) .. ")"
                return
            end
        end

        local dx = math.floor(tonumber(S.dropX) or Core.ReadPos().tx)
        local dy = math.floor(tonumber(S.dropY) or Core.ReadPos().ty)
        Core.MoveToTile(dx, dy)
        task.wait(0.25)

        local okDrop, dErr = Core.DropItemPacket(seedId, toDrop, dx + 0.5, dy + 0.55)
        if okDrop then
            S.stats.dropped += toDrop
            dropSuccess = true
        else
            errMsg = "Drop gagal (" .. tostring(dErr) .. ")"
        end

        -- Move slightly away & wait past PICKUP_DELAY before re-enabling collect!
        if crossWorld then
            task.wait(0.4)
            Core.EnterWorld(farmWorld)
        else
            local wd = Core.GetCurrentWorldData()
            if wd.standPos then
                Core.MoveToTile(wd.standPos.x, wd.standPos.y)
            else
                Core.MoveToTile(clamp(dx + 2, 0, H.gt.w - 1), dy)
            end
            task.wait(1.25) -- > gt.PICKUP_DELAY (1s)
        end
    end)

    -- Auto Return back to standPos if defined
    local wd = Core.GetCurrentWorldData()
    if wd.standPos and H.gt and H.gt.name == farmWorld then
        Core.MoveToTile(wd.standPos.x, wd.standPos.y)
    end

    S.suppressCollect = false
    S.inDropTrip = false

    if not okPhase or not dropSuccess then
        S.waitReason = errMsg or ("Drop gagal: " .. tostring(phaseErr))
        return false
    end
    S.waitReason = nil
    return true
end

-- ─────────────────────────────────────────────────────────────────────────────
--  PHASE 1: PABRIK SMART FIXED ROUTE (Rute Tetap, Stop tiap 5 Tile, Sentuhan Badan)
-- ─────────────────────────────────────────────────────────────────────────────
local function getActiveFloors(wd, reachable)
    local S = Core.State
    local gt = H.gt
    if not gt then return {} end

    local floors = {}
    if S.fullWorld then
        for y = 1, gt.h - 2 do
            if Core.IsValidFloorRow(y) then
                floors[#floors + 1] = y
            end
        end
    else
        for y, on in pairs(wd.floors) do
            if on and y >= 1 and y < gt.h - 1 then
                floors[#floors + 1] = y
            end
        end
    end

    local p = Core.ReadPos()
    if S.routeOrder == "top" then
        table.sort(floors, function(a, b) return a < b end)
    elseif S.routeOrder == "bottom" then
        table.sort(floors, function(a, b) return a > b end)
    else -- "nearest"
        table.sort(floors, function(a, b)
            local da = math.abs(a - p.ty)
            local db = math.abs(b - p.ty)
            if da == db then return a < b end
            return da < db
        end)
    end
    return floors
end

local function analyzeFloorsReadiness(floors, wd, reachable)
    local gt = H.gt
    if not gt then return 0, 0, 0, nil end
    local planted, ripe, emptyPlantable = 0, 0, 0
    local minRemaining = nil

    for _, y in ipairs(floors) do
        for x = 0, gt.w - 1 do
            local key = tileKey(x, y)
            if not wd.redTiles[key] and not Core.IsBreakTileCoord(wd, x, y) then
                local fgId = Core.GetFG(x, y)
                if fgId == 0 then
                    if Core.IsPlantable(x, y) and Core.IsTileReachable(reachable, x, y) then
                        emptyPlantable += 1
                    end
                else
                    local info = Core.GetItemInfo(fgId)
                    if info and info.kind == "seed" and Core.CanEditTile(x, y) then
                        planted += 1
                        if Core.IsTreeRipe(x, y) then
                            ripe += 1
                        else
                            local rem = Core.GetTreeRemainingSec(x, y)
                            if rem and (not minRemaining or rem < minRemaining) then
                                minRemaining = rem
                            end
                        end
                    end
                end
            end
        end
    end

    local pct = (planted > 0) and (ripe / planted * 100) or 0
    return planted, ripe, emptyPlantable, pct, minRemaining
end

local function runHarvestAndPlantRoute(floors, wd, reachable)
    local S = Core.State
    local gt = H.gt
    if not gt or #floors == 0 then return end

    local totalFloors = #floors
    local p = Core.ReadPos()
    local curX = p.tx
    local leftToRight = true -- first floor starts from whichever side is closer to character!

    for fIdx, y in ipairs(floors) do
        if not S.pabrikRunning then break end
        if not checkSecurityGate() then break end

        -- Collect all actionable x on this floor y (ripe trees + empty plantable tiles, excluding breakTiles & redTiles)
        local rowTiles = {}
        for x = 0, gt.w - 1 do
            local key = tileKey(x, y)
            if not wd.redTiles[key] and not Core.IsBreakTileCoord(wd, x, y) and Core.IsTileReachable(reachable, x, y) then
                local fgId = Core.GetFG(x, y)
                local info = Core.GetItemInfo(fgId)
                local isRipe = (fgId ~= 0 and info and info.kind == "seed" and Core.IsTreeRipe(x, y) and Core.CanEditTile(x, y))
                local isEmpty = (fgId == 0 and Core.IsPlantable(x, y))
                if isRipe or isEmpty then
                    rowTiles[#rowTiles + 1] = x
                end
            end
        end

        if #rowTiles > 0 then
            -- First floor starts from side closest to character; subsequent floors alternate zig-zag!
            if fIdx == 1 then
                local firstX = rowTiles[1]
                local lastX  = rowTiles[#rowTiles]
                leftToRight = math.abs(curX - firstX) <= math.abs(curX - lastX)
            else
                leftToRight = not leftToRight
            end

            if not leftToRight then
                local rev = {}
                for i = #rowTiles, 1, -1 do rev[#rev + 1] = rowTiles[i] end
                rowTiles = rev
            end

            S.routeProgress = string.format("Rute %d/%d, lantai y=%d", fIdx, totalFloors, y)

            -- Stop every 5 tiles ("berhenti tiap 5 tile")
            local i = 1
            while i <= #rowTiles do
                if not S.pabrikRunning then break end
                if not checkSecurityGate() then break end

                local stopEnd = math.min(i + 4, #rowTiles)
                local stopMid = rowTiles[math.floor((i + stopEnd) / 2)]

                -- Move to stop on THIS floor only
                Core.MoveToTile(stopMid, y)
                curX = stopMid
                secWait(0.06)

                -- 1. Harvest ripe trees at this stop (sentuhan badan on current floor y!)
                for j = i, stopEnd do
                    if not S.pabrikRunning then break end
                    local tx = rowTiles[j]
                    if Core.IsTreeRipe(tx, y) then
                        -- Sentuhan badan: step right onto tile on the same floor
                        Core.MoveToTile(tx, y)
                        curX = tx
                        local ok = Core.BreakTile(tx, y, 1)
                        if ok then
                            S.stats.harvested += 1
                        end
                        secWait(0.05)
                    end
                end

                -- 2. Collect drops around this stop (unless tas penuh)
                if not S.suppressCollect then
                    Core.CollectDropsInRadius(stopMid, y, 4)
                end

                -- 3. Plant seeds at empty tiles in this stop (if seed available and < 190 limit check later)
                for j = i, stopEnd do
                    if not S.pabrikRunning then break end
                    local tx = rowTiles[j]
                    if Core.CountItem(S.seedId) <= 0 then
                        break
                    end
                    if Core.GetFG(tx, y) == 0 and Core.IsPlantable(tx, y) then
                        local okPlant = Core.PlaceTile(tx, y, S.seedId)
                        if okPlant then
                            S.stats.planted += 1
                        end
                        secWait(S.plantDelay)
                    end
                end

                -- Check if seed reached drop threshold -> note: drop happens BETWEEN phases, never mid-route,
                -- UNLESS inventory hits hard 200 cap so we don't lose items
                if Core.IsBackpackFullFor(S.seedId) then
                    S.waitReason = "Seed penuh (drop setelah rute)"
                end

                i = stopEnd + 1
            end
        end
    end
end

-- ─────────────────────────────────────────────────────────────────────────────
--  PHASE 3: AUTO BREAK + PLACE + AUTO REFILL + AUTO RETURN + REMOTE COLLECT
-- ─────────────────────────────────────────────────────────────────────────────
local function tryRefillBlock(blockId, standPos)
    local S = Core.State
    local gt = H.gt
    if not gt or not S.autoRefill or not blockId or blockId <= 0 then return false end
    if Core.CountItem(blockId) > 0 then return true end
    if type(gt.dropList) ~= "function" then return false end

    S.phase = "REFILL BLOCK"
    local ok, drops = pcall(gt.dropList)
    if not ok or type(drops) ~= "table" then return false end

    local pickedAny = false
    for _, d in ipairs(drops) do
        if not (S.pabrikRunning or S.dirtRunning) then break end
        if type(d) == "table" and d.id == blockId and d.uid and (d.n or 0) > 0 then
            if Core.IsBackpackFullFor(blockId) then break end
            Core.MoveToTile(math.floor(d.x), math.floor(d.y))
            task.wait(0.08)
            local room = Core.GetItemRoom(blockId)
            local want = math.min(d.n, room)
            if want > 0 then
                local got = Core.RemoteTakeDrop(d.uid, want)
                if got > 0 then
                    pickedAny = true
                    if H.inv and type(H.inv.add) == "function" then
                        pcall(function() H.inv:add(blockId, got) end)
                    end
                end
            end
            if Core.CountItem(blockId) >= 50 then break end
        end
    end

    -- Auto Return back to stand position
    if S.autoReturn and standPos then
        S.phase = "AUTO RETURN"
        Core.MoveToTile(standPos.x, standPos.y)
        task.wait(0.08)
    end

    return Core.CountItem(blockId) > 0 or pickedAny
end

local function runBreakPhase(wd, reachable)
    local S = Core.State
    local gt = H.gt
    if not gt or not S.autoBreakPlace then return false end
    local blockId = S.blockId
    if not blockId or blockId <= 0 then return false end

    -- Ensure standPos and breakTiles exist (smart auto-picker if missing)
    if not wd.standPos or #wd.breakTiles == 0 then
        local autoStand, autoBreak = findSmartBreakSpot(wd, reachable)
        if autoStand and autoBreak then
            wd.standPos   = wd.standPos or autoStand
            if #wd.breakTiles == 0 then
                wd.breakTiles = autoBreak
            end
            Core.SaveWorldConfig()
        else
            S.waitReason = "Break gagal (tidak ada posisi terjangkau)"
            return false
        end
    end

    local stand = wd.standPos
    if not Core.IsTileReachable(reachable, stand.x, stand.y) then
        wd.redTiles[tileKey(stand.x, stand.y)] = true
        wd.standPos = nil
        Core.SaveWorldConfig()
        S.waitReason = "Break gagal (posisi berdiri tidak terjangkau)"
        return false
    end

    -- Refill if blockId == 0 in inventory and no pre-placed block on breakTiles
    local hasPlaced = false
    for _, bt in ipairs(wd.breakTiles) do
        if Core.GetFG(bt.x, bt.y) == blockId then
            hasPlaced = true
            break
        end
    end

    if Core.CountItem(blockId) <= 0 and not hasPlaced then
        local refilled = tryRefillBlock(blockId, stand)
        if not refilled and Core.CountItem(blockId) <= 0 then
            S.waitReason = "Block habis"
            return false
        end
    end

    -- Run a break batch (up to 15 cycles or until blocks empty or seed approaches dropThreshold)
    S.phase = "BREAK + PLACE"
    local cycles = 0
    local maxCycles = 25

    while S.pabrikRunning and cycles < maxCycles do
        if not checkSecurityGate() then break end

        -- Lock standing position: if body drifted (> 0.65 tiles), Auto Return first!
        local p = Core.ReadPos()
        if math.abs(p.x - (stand.x + 0.5)) > 0.65 or math.abs(p.y - (stand.y + 1)) > 0.65 then
            Core.MoveToTile(stand.x, stand.y)
            task.wait(0.06)
        end

        local didWork = false
        for _, bt in ipairs(wd.breakTiles) do
            if not S.pabrikRunning then break end
            local bx, by = bt.x, bt.y
            local key = tileKey(bx, by)
            if not wd.redTiles[key] then
                local curFg = Core.GetFG(bx, by)
                local curInfo = Core.GetItemInfo(curFg)

                -- Never break session if a tree/seed happens to be on the tile; skip/harvest gently
                if curFg ~= 0 and curInfo and curInfo.kind == "seed" then
                    if Core.IsTreeRipe(bx, by) then
                        Core.BreakTile(bx, by, 1)
                        S.stats.harvested += 1
                    end
                else
                    -- Place if empty and we have blocks
                    if curFg == 0 and Core.CountItem(blockId) > 0 then
                        if Core.PlaceTile(bx, by, blockId) then
                            didWork = true
                            secWait(S.fastBreak and 0.135 or S.plantDelay)
                        end
                    end

                    -- Break if block present
                    if Core.GetFG(bx, by) ~= 0 then
                        local okBrk = Core.BreakTile(bx, by, 1)
                        secWait(S.fastBreak and 0.165 or S.breakDelay)
                        if okBrk and Core.GetFG(bx, by) == 0 then
                            S.stats.broken += 1
                            H.breakFails[key] = 0
                            didWork = true
                        else
                            H.breakFails[key] = (H.breakFails[key] or 0) + 1
                            -- Gagal 2 kali -> tandai merah & cari tempat lain!
                            if H.breakFails[key] >= 2 then
                                wd.redTiles[key] = true
                                Core.SaveWorldConfig()
                                S.waitReason = "Break gagal 2x di (" .. bx .. "," .. by .. ")"
                            end
                        end
                    end
                end
            end
        end

        -- Collect saat break pakai Remote ke semua tile break, bot DIAM di titik berdiri!
        if not S.suppressCollect then
            for _, bt in ipairs(wd.breakTiles) do
                Core.CollectDropsInRadius(bt.x, bt.y, 2.5)
            end
        end

        -- Stop break batch if seed reached drop threshold (drop hanya di antara fase!)
        if S.autoDropSeed and Core.CountItem(S.seedId) >= clamp(S.dropThreshold, 1, MAX_DROP_THRESHOLD) then
            break
        end

        if Core.CountItem(blockId) <= 0 then
            if not tryRefillBlock(blockId, stand) then
                S.waitReason = "Block habis"
                break
            end
        end

        if not didWork then break end
        cycles += 1
    end

    return true
end

-- ─────────────────────────────────────────────────────────────────────────────
--  MAIN UNIFIED PABRIK CONTROLLER
-- ─────────────────────────────────────────────────────────────────────────────
function Core.StartPabrik()
    if Core.State.pabrikRunning then return true end
    Core.Discover()
    if not Core.State.ready or not Core.State.worldLoaded then
        Core.State.waitReason = "Belum masuk world / game belum siap"
        return false, Core.State.waitReason
    end

    Core.State.sec.runtimeStopped = false
    Core.State.sec.webhookSent    = false
    Core.State.pabrikRunning      = true
    Core.State.waitReason         = nil

    task.spawn(function()
        while Core.State.pabrikRunning do
            local S = Core.State
            Core.Discover()
            if not S.worldLoaded then
                S.phase = "TUNGGU"
                S.waitReason = "Menunggu world terbuka"
                task.wait(0.8)
            elseif not checkSecurityGate() then
                break
            else
                local wd = Core.GetCurrentWorldData()
                local reachable = Core.ComputeReachableSet()
                local floors = getActiveFloors(wd, reachable)

                -- Phase 2 (pre-check): Drop seed between phases if >= threshold (max 190)
                if S.autoDropSeed and S.seedId and Core.CountItem(S.seedId) >= clamp(S.dropThreshold, 1, MAX_DROP_THRESHOLD) then
                    runDropPhaseIfNeeded(false)
                end

                -- Analyze readiness on floors
                local planted, ripe, emptyPlantable, pct, minRem = analyzeFloorsReadiness(floors, wd, reachable)
                local needHarvest = (planted > 0 and pct >= clamp(S.harvestThreshold, 10, 100))
                local needPlant   = (emptyPlantable > 0 and Core.CountItem(S.seedId) > 0)

                if minRem then
                    S.etaText = "Panen " .. formatDuration(minRem) .. " lagi"
                elseif needHarvest then
                    S.etaText = "Panen siap (" .. math.floor(pct) .. "%)"
                else
                    S.etaText = planted > 0 and ("Siap " .. math.floor(pct) .. "%") or "Kosong"
                end

                -- Phase 1: Harvest + Plant once per route if ready OR empty plantable tiles with seeds
                if #floors > 0 and (needHarvest or needPlant) then
                    S.phase = "PANEN & TANAM"
                    S.waitReason = nil
                    runHarvestAndPlantRoute(floors, wd, reachable)

                    -- Phase 2 (post-route): Auto Drop Seed between phases
                    if S.pabrikRunning and S.autoDropSeed and Core.CountItem(S.seedId) >= clamp(S.dropThreshold, 1, MAX_DROP_THRESHOLD) then
                        runDropPhaseIfNeeded(false)
                    end
                elseif #floors == 0 and not S.autoBreakPlace then
                    S.phase = "TUNGGU"
                    S.waitReason = "Pilih lantai di Peta Mini atau aktifkan Full World"
                end

                -- Phase 3: Auto Break + Place + Refill + Return (runs EVEN IF all floors are selected!)
                if S.pabrikRunning and S.autoBreakPlace and S.blockId and S.blockId > 0 then
                    runBreakPhase(wd, reachable)
                    -- Drop between phases if break produced seeds >= threshold
                    if S.pabrikRunning and S.autoDropSeed and Core.CountItem(S.seedId) >= clamp(S.dropThreshold, 1, MAX_DROP_THRESHOLD) then
                        runDropPhaseIfNeeded(false)
                    end
                elseif S.pabrikRunning and not needHarvest and not needPlant then
                    if planted > 0 then
                        S.phase = "TUNGGU"
                        S.waitReason = string.format("Menunggu pohon siap (%d%%/%d%%)", math.floor(pct), S.harvestThreshold)
                    end
                end

                task.wait(0.35)
            end
        end

        Core.State.suppressCollect = false
        Core.State.inDropTrip      = false
        Core.State.pabrikRunning   = false
        if not Core.State.sec.runtimeStopped then
            Core.State.phase = "IDLE"
        end
    end)

    return true
end

function Core.StopPabrik()
    Core.State.pabrikRunning   = false
    Core.State.suppressCollect = false
    Core.State.inDropTrip      = false
    Core.State.phase           = "IDLE"
end

-- ─────────────────────────────────────────────────────────────────────────────
--  AUTO FARM 5x5 GRID (KHUSUS AUTO FARM MODE, TERPISAH DARI PABRIK)
-- ─────────────────────────────────────────────────────────────────────────────
function Core.SetGridBase()
    local p = Core.ReadPos()
    Core.State.gridBase = { x = p.tx, y = p.ty }
    return Core.State.gridBase
end

function Core.StartGridPNB()
    if Core.State.gridRunning then return true end
    Core.Discover()
    if not Core.State.ready or not Core.State.worldLoaded then
        return false, "game belum siap"
    end
    if not Core.State.gridBase then Core.SetGridBase() end
    Core.State.gridRunning = true

    task.spawn(function()
        while Core.State.gridRunning do
            if not checkSecurityGate() then break end
            local base = Core.State.gridBase
            local item = Core.State.blockId or Core.State.seedId
            for r = 1, 5 do
                for c = 1, 5 do
                    if not Core.State.gridRunning then break end
                    local row = Core.State.grid[r]
                    if row and row[c] and not (r == 3 and c == 3) then
                        local tx = base.x + (c - 3)
                        local ty = base.y + (3 - r)
                        Core.MoveToTile(base.x, base.y)
                        if Core.GetFG(tx, ty) == 0 and item and Core.CountItem(item) > 0 then
                            Core.PlaceTile(tx, ty, item)
                            secWait(0.14)
                        end
                        if Core.GetFG(tx, ty) ~= 0 then
                            Core.BreakTile(tx, ty, 1)
                            secWait(Core.State.fastBreak and 0.165 or Core.State.gridDelay)
                        end
                    end
                end
            end
            if Core.State.gridAutoCollect and not Core.State.suppressCollect then
                Core.CollectDropsInRadius(base.x, base.y, 4)
            end
            secWait(Core.State.gridDelay)
        end
        Core.State.gridRunning = false
    end)
    return true
end

function Core.StopGridPNB()
    Core.State.gridRunning = false
end

-- ─────────────────────────────────────────────────────────────────────────────
--  SKYP v1.8 - DIRT FARM (Plant Dirt, Harvest Dirt, Build Upper Dirt Farm)
-- ─────────────────────────────────────────────────────────────────────────────
function Core.AutoDetectUpperEndY()
    local gt = H.gt
    if not gt or not gt.fg then return 22 end
    for y = 0, gt.h - 1 do
        local row = gt.fg[y]
        if row then
            for x = 0, gt.w - 1 do
                -- Item 6 = Main Door
                if row[x] == 6 then
                    local suggested = math.max(4, y - 2)
                    -- Pastikan paritas sama dengan dirtUpperStartY agar jarak kelipatan 2
                    if (suggested - Core.State.dirtUpperStartY) % math.max(1, Core.State.dirtStepY) ~= 0 then
                        suggested = math.max(4, suggested - 1)
                    end
                    Core.State.dirtUpperEndY = suggested
                    return suggested
                end
            end
        end
    end
    return Core.State.dirtUpperEndY
end

local function getDirtFarmRows()
    local gt = H.gt
    if not gt then return {} end
    local S = Core.State
    local startY = clamp(math.floor(S.dirtUpperStartY), 1, gt.h - 2)
    local endY   = clamp(math.floor(S.dirtUpperEndY), startY, gt.h - 2)
    local stepY  = clamp(math.floor(S.dirtStepY), 2, 6)
    local rows = {}
    for y = startY, endY, stepY do
        rows[#rows + 1] = y
    end
    return rows
end

local function collectDirtFloorXList(y, predicate)
    local gt = H.gt
    if not gt then return {} end
    local wd = Core.GetCurrentWorldData()
    local res = {}
    for x = 0, gt.w - 1 do
        local key = tileKey(x, y)
        if not wd.redTiles[key] and not Core.IsBreakTileCoord(wd, x, y) and predicate(x, y) then
            res[#res + 1] = x
        end
    end
    return res
end

local function runDirtPlantPass()
    local S = Core.State
    local gt = H.gt
    if not gt then return false, 0 end
    local reachable = Core.ComputeReachableSet()
    local dirtSeed = S.dirtSeedId or 3
    local plantedCount = 0

    -- Kumpulkan semua baris yang valid punya tile plantable di world
    local rawFloors = {}
    for y = 1, gt.h - 2 do
        local xs = collectDirtFloorXList(y, function(x, fy)
            return Core.IsTileReachable(reachable, x, fy)
                and Core.GetFG(x, fy) == 0
                and Core.IsPlantable(x, fy)
        end)
        if #xs > 0 then
            rawFloors[#rawFloors + 1] = y
        end
    end

    if #rawFloors == 0 then
        return true, 0
    end

    local p = Core.ReadPos()
    local curX = p.tx
    local leftToRight = true
    local total = #rawFloors

    for fIdx, y in ipairs(rawFloors) do
        if not S.dirtRunning then break end
        if not checkSecurityGate() then break end
        if Core.CountItem(dirtSeed) <= 0 then
            -- Coba kumpulkan drop seed dirt sekitar dulu
            if not S.suppressCollect then
                Core.CollectDropsInRadius(curX, y, 6)
            end
            if Core.CountItem(dirtSeed) <= 0 then
                S.waitReason = "Dirt Seed habis"
                return false, plantedCount
            end
        end

        local xs = collectDirtFloorXList(y, function(x, fy)
            return Core.IsTileReachable(reachable, x, fy)
                and Core.GetFG(x, fy) == 0
                and Core.IsPlantable(x, fy)
        end)

        if #xs > 0 then
            if fIdx == 1 then
                leftToRight = math.abs(curX - xs[1]) <= math.abs(curX - xs[#xs])
            else
                leftToRight = not leftToRight
            end
            if not leftToRight then
                local rev = {}
                for k = #xs, 1, -1 do rev[#rev + 1] = xs[k] end
                xs = rev
            end

            S.phase = "PLANT DIRT"
            S.routeProgress = string.format("Plant Dirt %d/%d (y=%d)", fIdx, total, y)
            S.etaText = "Plant Dirt y=" .. y

            local i = 1
            while i <= #xs do
                if not S.dirtRunning then break end
                if not checkSecurityGate() then break end
                local stopEnd = math.min(i + 4, #xs)
                local stopMid = xs[math.floor((i + stopEnd) / 2)]
                Core.MoveToTile(stopMid, y)
                curX = stopMid
                secWait(0.05)

                for j = i, stopEnd do
                    if not S.dirtRunning then break end
                    if Core.CountItem(dirtSeed) <= 0 then break end
                    local tx = xs[j]
                    if Core.GetFG(tx, y) == 0 and Core.IsPlantable(tx, y) then
                        if Core.PlaceTile(tx, y, dirtSeed) then
                            S.stats.planted = S.stats.planted + 1
                            plantedCount = plantedCount + 1
                        end
                        secWait(S.plantDelay)
                    end
                end

                if not S.suppressCollect then
                    Core.CollectDropsInRadius(stopMid, y, 4)
                end
                i = stopEnd + 1
            end
        end
    end

    return true, plantedCount
end

local function runDirtHarvestPass()
    local S = Core.State
    local gt = H.gt
    if not gt then return false, 0 end
    local reachable = Core.ComputeReachableSet()
    local dirtSeed = S.dirtSeedId or 3
    local harvestedCount = 0

    local rawFloors = {}
    for y = 1, gt.h - 2 do
        local xs = collectDirtFloorXList(y, function(x, fy)
            return Core.IsTileReachable(reachable, x, fy)
                and Core.GetFG(x, fy) == dirtSeed
                and Core.IsTreeRipe(x, fy)
                and Core.CanEditTile(x, fy)
        end)
        if #xs > 0 then
            rawFloors[#rawFloors + 1] = y
        end
    end

    if #rawFloors == 0 then
        return true, 0
    end

    local p = Core.ReadPos()
    local curX = p.tx
    local leftToRight = true
    local total = #rawFloors

    for fIdx, y in ipairs(rawFloors) do
        if not S.dirtRunning then break end
        if not checkSecurityGate() then break end

        local xs = collectDirtFloorXList(y, function(x, fy)
            return Core.IsTileReachable(reachable, x, fy)
                and Core.GetFG(x, fy) == dirtSeed
                and Core.IsTreeRipe(x, fy)
                and Core.CanEditTile(x, fy)
        end)

        if #xs > 0 then
            if fIdx == 1 then
                leftToRight = math.abs(curX - xs[1]) <= math.abs(curX - xs[#xs])
            else
                leftToRight = not leftToRight
            end
            if not leftToRight then
                local rev = {}
                for k = #xs, 1, -1 do rev[#rev + 1] = xs[k] end
                xs = rev
            end

            S.phase = "HARVEST DIRT"
            S.routeProgress = string.format("Harvest Dirt %d/%d (y=%d)", fIdx, total, y)
            S.etaText = "Harvest Dirt y=" .. y

            local i = 1
            while i <= #xs do
                if not S.dirtRunning then break end
                if not checkSecurityGate() then break end
                local stopEnd = math.min(i + 4, #xs)
                local stopMid = xs[math.floor((i + stopEnd) / 2)]
                Core.MoveToTile(stopMid, y)
                curX = stopMid
                secWait(0.05)

                for j = i, stopEnd do
                    if not S.dirtRunning then break end
                    local tx = xs[j]
                    if Core.GetFG(tx, y) == dirtSeed and Core.IsTreeRipe(tx, y) then
                        Core.MoveToTile(tx, y)
                        curX = tx
                        if Core.BreakTile(tx, y, 1) then
                            S.stats.harvested = S.stats.harvested + 1
                            harvestedCount = harvestedCount + 1
                        end
                        secWait(0.05)
                    end
                end

                if not S.suppressCollect then
                    Core.CollectDropsInRadius(stopMid, y, 5)
                end
                i = stopEnd + 1
            end
        end
    end

    return true, harvestedCount
end

local function ensureUpperSlotCleared(x, y, standX, standY, blockKeepId)
    local S = Core.State
    local cur = Core.GetFG(x, y)
    if cur == 0 or cur == blockKeepId then return true end
    if Core.IsProtectedTile(cur) or not Core.CanEditTile(x, y) then return false end

    local info = Core.GetItemInfo(cur)
    if info and info.kind == "seed" and not Core.IsTreeRipe(x, y) then
        return false
    end

    Core.MoveToTile(standX, standY)
    secWait(0.04)
    local ok = Core.BreakTile(x, y, 1)
    secWait(S.fastBreak and 0.165 or S.breakDelay)
    if ok and Core.GetFG(x, y) == 0 then
        if info and info.kind == "seed" then
            S.stats.harvested = S.stats.harvested + 1
        else
            S.stats.broken = S.stats.broken + 1
        end
        return true
    end
    return false
end

local function runBuildUpperDirtPass()
    local S = Core.State
    local gt = H.gt
    if not gt then return false, 0 end
    local wd = Core.GetCurrentWorldData()
    local dirtId = S.dirtBlockId or 2
    local platId = S.dirtPlatId or 102
    local rows = getDirtFarmRows()
    if #rows == 0 then
        S.waitReason = "Range Y Upper Dirt tidak valid"
        return false, 0
    end

    local leftX  = clamp(math.floor(S.dirtLeftMargin), 0, gt.w - 4)
    local rightX = clamp(gt.w - 1 - math.floor(S.dirtRightMargin), leftX, gt.w - 1)
    local placedCount = 0

    -- Bangun dari atas ke bawah agar setiap lantai baru mudah diinjak dari ruang di atasnya
    for rIdx, floorY in ipairs(rows) do
        if not S.dirtRunning then break end
        if not checkSecurityGate() then break end

        local standY = floorY - 1
        if standY >= 0 then
            S.phase = "BUILD UPPER DIRT"
            S.routeProgress = string.format("Build %d/%d (lantai y=%d)", rIdx, #rows, floorY)
            S.etaText = "Build Upper Dirt y=" .. floorY

            local p = Core.ReadPos()
            local leftToRight = math.abs(p.tx - leftX) <= math.abs(p.tx - rightX)
            local xStart = leftToRight and leftX or rightX
            local xEnd   = leftToRight and rightX or leftX
            local xStep  = leftToRight and 1 or -1

            -- Opsional: pasang Wooden Platform di kolom akses sisi (leftX-1 & rightX+1) bila tersedia di tas
            if S.dirtUsePlat and Core.CountItem(platId) > 0 then
                for _, ax in ipairs({ leftX - 1, rightX + 1 }) do
                    if ax >= 0 and ax < gt.w and Core.GetFG(ax, floorY) == 0 and Core.CanEditTile(ax, floorY) then
                        local sx = clamp(ax, 0, gt.w - 1)
                        Core.MoveToTile(sx, standY)
                        secWait(0.04)
                        if Core.PlaceTile(ax, floorY, platId) then
                            secWait(S.plantDelay)
                        end
                    end
                end
            end

            for x = xStart, xEnd, xStep do
                if not S.dirtRunning then break end
                if not checkSecurityGate() then break end

                local keyFloor = tileKey(x, floorY)
                if not wd.redTiles[keyFloor] and not Core.IsBreakTileCoord(wd, x, floorY) then
                    local standX = clamp(x, 0, gt.w - 1)
                    -- 1. Bersihkan headroom (standY = floorY - 1) agar selalu bisa dilalui & ditanami
                    if Core.GetFG(x, standY) ~= 0 then
                        ensureUpperSlotCleared(x, standY, standX, math.max(0, standY - 1), 0)
                    end

                    -- 2. Pastikan floorY siap diisi Dirt
                    local curFloor = Core.GetFG(x, floorY)
                    if curFloor ~= dirtId and Core.CanEditTile(x, floorY) and not Core.IsProtectedTile(curFloor) then
                        if curFloor ~= 0 then
                            ensureUpperSlotCleared(x, floorY, standX, standY, dirtId)
                        end
                        if Core.GetFG(x, floorY) == 0 then
                            if Core.CountItem(dirtId) <= 0 then
                                local refilled = tryRefillBlock(dirtId, { x = standX, y = standY })
                                if not refilled and Core.CountItem(dirtId) <= 0 then
                                    S.waitReason = "Block Dirt habis"
                                    return false, placedCount
                                end
                            end
                            Core.MoveToTile(standX, standY)
                            secWait(0.03)
                            if Core.PlaceTile(x, floorY, dirtId) then
                                placedCount = placedCount + 1
                            end
                            secWait(S.plantDelay)
                        end
                    end
                end

                if not S.suppressCollect and (x % 6 == 0) then
                    Core.CollectDropsInRadius(x, standY, 5)
                end
            end

            if not S.suppressCollect then
                Core.CollectDropsInRadius(math.floor((leftX + rightX) / 2), standY, 6)
            end
        end
    end

    return true, placedCount
end

local function startDirtWorker(mode, fn)
    if Core.State.dirtRunning then return false, "Dirt Farm sedang berjalan" end
    Core.Discover()
    if not Core.State.ready or not Core.State.worldLoaded then
        Core.State.waitReason = "Belum masuk world / game belum siap"
        return false, Core.State.waitReason
    end
    Core.State.sec.runtimeStopped = false
    Core.State.sec.webhookSent    = false
    Core.State.dirtRunning        = true
    Core.State.dirtMode           = mode
    Core.State.waitReason         = nil

    task.spawn(function()
        fn()
        Core.State.dirtRunning = false
        Core.State.dirtMode    = "idle"
        if not Core.State.sec.runtimeStopped and not Core.State.pabrikRunning then
            Core.State.phase = "IDLE"
        end
    end)
    return true
end

function Core.StartDirtPlant()
    return startDirtWorker("plant", function()
        local ok = runDirtPlantPass()
        if ok and Core.State.dirtRunning then
            Core.State.etaText = "Plant Dirt selesai"
        end
    end)
end

function Core.StartDirtHarvest()
    return startDirtWorker("harvest", function()
        local ok = runDirtHarvestPass()
        if ok and Core.State.dirtRunning then
            Core.State.etaText = "Harvest Dirt selesai"
        end
    end)
end

function Core.StartBuildUpperDirtFarm()
    return startDirtWorker("build", function()
        local ok = runBuildUpperDirtPass()
        if ok and Core.State.dirtRunning then
            Core.State.etaText = "Upper Dirt Farm selesai"
        end
    end)
end

function Core.StartDirtCycle()
    return startDirtWorker("cycle", function()
        while Core.State.dirtRunning do
            if not checkSecurityGate() then break end
            Core.Discover()

            -- Pre-drop jika Auto Drop Seed aktif
            local S = Core.State
            if S.autoDropSeed and Core.CountItem(S.dirtSeedId) >= clamp(S.dropThreshold, 1, MAX_DROP_THRESHOLD) then
                local savedSeed = S.seedId
                S.seedId = S.dirtSeedId
                runDropPhaseIfNeeded(false)
                S.seedId = savedSeed
            end

            runDirtHarvestPass()
            if not S.dirtRunning then break end

            runDirtPlantPass()
            if not S.dirtRunning then break end

            -- Tunggu sampai persentase pohon dirt siap dipanen
            local gt = H.gt
            if gt then
                local planted, ripe = 0, 0
                local ds = S.dirtSeedId or 3
                for y = 1, gt.h - 2 do
                    for x = 0, gt.w - 1 do
                        if Core.GetFG(x, y) == ds then
                            planted = planted + 1
                            if Core.IsTreeRipe(x, y) then
                                ripe = ripe + 1
                            end
                        end
                    end
                end
                local pct = planted > 0 and (ripe / planted * 100) or 0
                if planted > 0 and pct < clamp(S.dirtHarvestThreshold, 10, 100) then
                    S.phase = "TUNGGU DIRT"
                    S.etaText = string.format("Dirt siap %d%%/%d%%", math.floor(pct), S.dirtHarvestThreshold)
                    task.wait(1.5)
                elseif planted == 0 and Core.CountItem(ds) <= 0 then
                    S.waitReason = "Dirt Seed habis"
                    task.wait(2.0)
                else
                    task.wait(0.4)
                end
            else
                task.wait(0.5)
            end
        end
    end)
end

function Core.StopDirtFarm()
    Core.State.dirtRunning = false
    Core.State.dirtMode    = "idle"
    if not Core.State.pabrikRunning then
        Core.State.phase = "IDLE"
    end
end

-- ─────────────────────────────────────────────────────────────────────────────
--  AUTO VENDING HELPER (Vending TIDAK ikut Istirahat Berkala)
-- ─────────────────────────────────────────────────────────────────────────────
local function checkVendingGate()
    local sec = Core.State.sec
    local now = os.clock()
    if sec.maxRuntimeOn then
        local elapsed = now - (sec.sessionStartAt or now)
        if elapsed >= (sec.maxRuntimeHours * 3600) then
            sec.runtimeStopped = true
            Core.State.vendRunning = false
            sec.vendingActive = false
            return false
        end
    end
    return true
end

function Core.FindOwnedVends()
    local gt = H.gt
    local list = {}
    if not gt or not gt.fg then return list end
    for y = 0, gt.h - 1 do
        local row = gt.fg[y]
        if row then
            for x = 0, gt.w - 1 do
                local id = row[x]
                if id and id > 0 then
                    local info = Core.GetItemInfo(id)
                    if info and info.vend then
                        local owned = true
                        if type(gt.vendOwner) == "function" then
                            local ok, res = pcall(gt.vendOwner, x, y)
                            owned = ok and res == true
                        end
                        if owned then
                            list[#list + 1] = { x = x, y = y, id = id }
                        end
                    end
                end
            end
        end
    end
    return list
end

function Core.StartAutoVend()
    if Core.State.vendRunning then return true end
    Core.Discover()
    if not Core.State.ready or not Core.State.worldLoaded then
        return false, "game belum siap"
    end
    Core.State.vendRunning       = true
    Core.State.sec.vendingActive = true

    task.spawn(function()
        while Core.State.vendRunning do
            if not checkVendingGate() then break end
            local S = Core.State
            local gt = H.gt
            local vends = Core.FindOwnedVends()
            if #vends == 0 then
                S.etaText = "Vend: Tidak ada mesin milikmu"
                task.wait(1.5)
            else
                for _, v in ipairs(vends) do
                    if not S.vendRunning or not checkVendingGate() then break end
                    local have = Core.CountItem(S.vendItemId)
                    local room = have - math.max(0, math.floor(S.vendMinBag or 0))
                    if room > 0 and gt and type(gt.vendCall) == "function" then
                        Core.MoveToTile(v.x, v.y)
                        task.wait(0.08)
                        S.phase = "AUTO VEND"
                        S.etaText = string.format("Restock Vend (%d,%d)", v.x, v.y)
                        pcall(gt.vendCall, "stock", v.x, v.y, S.vendItemId, room)
                        secWait(S.vendDelay)
                    end
                end
                task.wait(1.0)
            end
        end
        Core.State.vendRunning       = false
        Core.State.sec.vendingActive = false
    end)
    return true
end

function Core.StopAutoVend()
    Core.State.vendRunning       = false
    Core.State.sec.vendingActive = false
end

function Core.StopAllFarming()
    Core.StopPabrik()
    Core.StopGridPNB()
    Core.StopDirtFarm()
    Core.StopAutoVend()
end

function Core.ResetStats()
    Core.State.stats.harvested = 0
    Core.State.stats.planted   = 0
    Core.State.stats.dropped   = 0
    Core.State.stats.broken    = 0
end

-- ─────────────────────────────────────────────────────────────────────────────
--  ONE-LINE STATUS BUILDER
-- ─────────────────────────────────────────────────────────────────────────────
function Core.GetOneLineStatus()
    local S = Core.State
    local seedCnt = Core.CountItem(S.dirtRunning and S.dirtSeedId or S.seedId)
    local blkCnt  = Core.CountItem(S.dirtRunning and S.dirtBlockId or S.blockId)

    if S.waitReason and S.waitReason ~= "" then
        return string.format("TUNGGU: %s | Seed %d | Blk %d | Tanam %d",
            S.waitReason, seedCnt, blkCnt, S.stats.planted)
    end

    if S.dirtRunning then
        local routePart = (S.routeProgress ~= "" and (" | " .. S.routeProgress) or "")
        return string.format("[DIRT FARM] %s | Seed %d | Blk %d%s",
            S.etaText or S.phase, seedCnt, blkCnt, routePart)
    end

    if S.vendRunning then
        return string.format("[VENDING] %s | Stok Tas %d",
            S.etaText or "Aktif", Core.CountItem(S.vendItemId))
    end

    local orderTag = S.routeOrder == "top" and "Atas->Bawah" or (S.routeOrder == "bottom" and "Bawah->Atas" or "Terdekat")
    local fwTag = S.fullWorld and " [FULL WORLD]" or ""
    local routePart = (S.routeProgress ~= "" and (" | " .. S.routeProgress) or "")

    return string.format("%s | Seed %d | Tanam %d tile%s [%s]%s",
        S.etaText or S.phase, seedCnt, S.stats.planted, routePart, orderTag, fwTag)
end

-- ═══════════════════════════════════════════════════════════════
-- PHASE 4: LIFECYCLE SHUTDOWN & READ-ONLY EXPOSURE SCANNER (KAT. D/E)
-- ═══════════════════════════════════════════════════════════════

local SENSITIVE_PLAYER_ATTRS = {
    Tag             = "Role / Staff Tag",
    OwnTitle        = "Owned Title",
    WornTitle       = "Equipped Title",
    DrTitle         = "Doctor Title",
    HasLegend       = "Legendary Status",
    HideLegendUntil = "Legend Hide Expiry",
    HideDrUntil     = "Doctor Hide Expiry",
    GuildRank       = "Guild Rank",
    GuildMascot     = "Guild Mascot",
    Country         = "Country Metadata",
    Nick            = "Nickname Override",
    GameName        = "In-Game Alias",
    DiscordBooster  = "Discord Booster Flag",
    Frozen          = "Moderation Freeze",
    MindUntil       = "Effect Expiry",
    StillTag        = "Still Tag",
    ModZoom         = "Moderator Zoom Flag",
    OneHitUntil     = "One-Hit Effect Expiry",
}

local function formatAttrValue(val)
    local t = typeof(val)
    if t == "string" then
        return val
    elseif t == "number" or t == "boolean" then
        return tostring(val)
    elseif t == "Vector2" or t == "Vector3" or t == "Color3" then
        return tostring(val)
    elseif t == "table" then
        local count = 0
        for _ in pairs(val) do count = count + 1 end
        return string.format("<table:%d>", count)
    end
    return tostring(val)
end

local function extractAccessList(rawAccess)
    local out = {}
    if type(rawAccess) ~= "table" then return out end
    for k, entry in pairs(rawAccess) do
        if type(entry) == "table" then
            local uid  = entry[1] or entry.userId or entry.id or k
            local name = entry[2] or entry.name or entry.username or "?"
            table.insert(out, {
                userId = tonumber(uid) or uid,
                name   = tostring(name),
            })
        elseif type(k) == "number" and (type(entry) == "number" or type(entry) == "string") then
            table.insert(out, {
                userId = tonumber(entry) or entry,
                name   = type(entry) == "string" and entry or "?",
            })
        else
            table.insert(out, {
                userId = tonumber(k) or k,
                name   = type(entry) == "string" and entry or tostring(entry),
            })
        end
    end
    table.sort(out, function(a, b)
        return tostring(a.name):lower() < tostring(b.name):lower()
    end)
    return out
end

local function normalizeLockInfo(lockObj, kind, tileCount, areasMod)
    if type(lockObj) ~= "table" then return nil end
    local access = extractAccessList(lockObj.access)
    local ownerId = lockObj.owner
    local ownerName = tostring(lockObj.ownerName or "?")
    local localRole = "none"
    if areasMod and type(areasMod.role) == "function" then
        local okR, r = pcall(areasMod.role, lockObj)
        if okR and r ~= nil then localRole = tostring(r) end
    elseif LP and ownerId == LP.UserId then
        localRole = "owner"
    end
    return {
        kind          = kind,
        x             = tonumber(lockObj.x),
        y             = tonumber(lockObj.y),
        owner         = ownerId,
        ownerName     = ownerName,
        access        = access,
        accessCount   = #access,
        tileCount     = tileCount or (type(lockObj.tiles) == "table" and #lockObj.tiles or 0),
        public        = lockObj.public == true,
        ignoreAir     = lockObj.ignoreAir == true,
        buildOnly     = lockObj.buildOnly == true,
        adminsLimited = lockObj.adminsLimited == true,
        guildLevel    = lockObj.guildLevel,
        guildMascot   = lockObj.guildMascot,
        localRole     = localRole,
    }
end

--- Menghentikan semua worker, koneksi event, dan hook client saat reload.
function Core.Shutdown()
    pcall(Core.StopAllFarming)
    if H.flyConn then
        pcall(function() H.flyConn:Disconnect() end)
        H.flyConn = nil
    end
    if H.modConn then
        pcall(function() H.modConn:Disconnect() end)
        H.modConn = nil
    end
    if H.takeDropHooked and H.gt and H.origTakeDrop then
        pcall(function()
            H.gt.takeDrop = H.origTakeDrop
        end)
        H.takeDropHooked = false
        H.origTakeDrop = nil
    end
end

--- Memindai data lock & daftar akses yang sudah tereplikasi ke client (Kat. D & E, read-only).
function Core.ScanLockExposure()
    if not H.gt then Core.Discover() end
    local gt = H.gt
    if not gt then
        return {
            ok = false,
            error = "Game table (gt) belum ditemukan.",
            areaLocks = {},
            findings = {},
        }
    end

    local w = tonumber(gt.w) or 100
    local h = tonumber(gt.h) or 60
    local areas = gt.areas
    local worldLockInfo = nil
    if type(gt.lock) == "table" and gt.lock.owner ~= nil then
        worldLockInfo = normalizeLockInfo(gt.lock, "WorldLock", w * h, areas)
    end

    local areaLocks = {}
    local seen = {}
    local holderCounts = {}

    if areas and type(areas.holder) == "function" then
        for y = 0, h - 1 do
            for x = 0, w - 1 do
                local okH, holder = pcall(areas.holder, x, y)
                if okH and type(holder) == "table" then
                    holderCounts[holder] = (holderCounts[holder] or 0) + 1
                end
            end
        end
    end

    if areas and type(areas.lockAt) == "function" then
        for y = 0, h - 1 do
            for x = 0, w - 1 do
                local okL, lk = pcall(areas.lockAt, x, y)
                if okL and type(lk) == "table" and not seen[lk] then
                    seen[lk] = true
                    local tCount = holderCounts[lk] or (type(lk.tiles) == "table" and #lk.tiles or 0)
                    table.insert(areaLocks, normalizeLockInfo(lk, "AreaLock", tCount, areas))
                end
            end
        end
    elseif next(holderCounts) ~= nil then
        for lk, cnt in pairs(holderCounts) do
            if lk ~= gt.lock and not seen[lk] then
                seen[lk] = true
                table.insert(areaLocks, normalizeLockInfo(lk, "AreaLock", cnt, areas))
            end
        end
    end

    table.sort(areaLocks, function(a, b)
        if (a.y or 0) ~= (b.y or 0) then return (a.y or 0) < (b.y or 0) end
        return (a.x or 0) < (b.x or 0)
    end)

    local totalProtectedTiles = 0
    local totalAccessEntries = 0
    local publicLocks = 0
    local buildOnlyLocks = 0

    local allLocks = {}
    if worldLockInfo then table.insert(allLocks, worldLockInfo) end
    for _, lk in ipairs(areaLocks) do table.insert(allLocks, lk) end

    for _, lk in ipairs(allLocks) do
        if lk.kind == "AreaLock" then
            totalProtectedTiles = totalProtectedTiles + (lk.tileCount or 0)
        end
        totalAccessEntries = totalAccessEntries + (lk.accessCount or 0)
        if lk.public then publicLocks = publicLocks + 1 end
        if lk.buildOnly then buildOnlyLocks = buildOnlyLocks + 1 end
    end
    if worldLockInfo then
        totalProtectedTiles = w * h
    end

    local findings = {}
    if #allLocks > 0 then
        table.insert(findings, {
            id         = "EXP-D1",
            category   = "Kat. E/D",
            severity   = "Medium",
            confidence = 95,
            title      = string.format("Metadata Lock & Access List Tereplikasi (%d lock, %d member)", #allLocks, totalAccessEntries),
            detail     = "Seluruh pemilik lock (UserId & nama), koordinat, dan daftar access user tereplikasi penuh ke memori client (gt.lock / gt.areas).",
            remediation = "Minimalkan daftar access yang dikirim ke non-member; server cukup kirim flag hasAccess boolean untuk client biasa.",
        })
    end
    if publicLocks > 0 then
        table.insert(findings, {
            id         = "EXP-D2",
            category   = "Kat. D",
            severity   = "Low",
            confidence = 95,
            title      = string.format("%d Lock Berstatus PUBLIC", publicLocks),
            detail     = "Terdapat lock dengan flag public=true yang dapat diubah/berinteraksi sesuai aturan akses publik.",
            remediation = "Audit apakah area public memang disengaja oleh pemilik lock.",
        })
    end

    return {
        ok                  = true,
        worldName           = tostring(gt.name or Core.State.worldName or "?"),
        width               = w,
        height              = h,
        hasWorldLock        = worldLockInfo ~= nil,
        worldLock           = worldLockInfo,
        areaLocks           = areaLocks,
        totalLocks          = #allLocks,
        totalProtectedTiles = totalProtectedTiles,
        totalAccessEntries  = totalAccessEntries,
        publicLocks         = publicLocks,
        buildOnlyLocks      = buildOnlyLocks,
        findings            = findings,
    }
end

--- Memeriksa hak akses & pemilik tile pada koordinat tertentu (default posisi bot saat ini).
function Core.ScanTileAccess(tx, ty)
    if not H.gt then Core.Discover() end
    local gt = H.gt
    if not gt then
        return { ok = false, error = "Game table (gt) belum ditemukan." }
    end

    if tx == nil or ty == nil then
        local px, py = Core.ReadPos()
        tx = tx or px or 0
        ty = ty or py or 0
    end
    local w = tonumber(gt.w) or 100
    local h = tonumber(gt.h) or 60
    tx = math.clamp(math.floor(tonumber(tx) or 0), 0, w - 1)
    ty = math.clamp(math.floor(tonumber(ty) or 0), 0, h - 1)

    local fgId = Core.GetFG(tx, ty) or 0
    local bgId = Core.GetBG(tx, ty) or 0
    local areas = gt.areas
    local canEdit = true
    local holder = nil
    local mayBuild = nil

    if areas then
        if type(areas.canEdit) == "function" then
            local okE, ce, lk = pcall(areas.canEdit, tx, ty)
            if okE then
                canEdit = ce == true
                holder = lk
            end
        end
        if type(areas.holder) == "function" and holder == nil then
            local okH, lk = pcall(areas.holder, tx, ty)
            if okH then holder = lk end
        end
        if type(areas.mayBuild) == "function" then
            local okB, mb = pcall(areas.mayBuild, tx, ty)
            if okB then mayBuild = mb == true end
        end
    end

    local kind = "AreaLock"
    if holder == nil and type(gt.lock) == "table" and gt.lock.owner ~= nil then
        holder = gt.lock
        kind = "WorldLock"
    elseif holder == gt.lock then
        kind = "WorldLock"
    end

    local lockInfo = normalizeLockInfo(holder, kind, nil, areas)
    return {
        ok       = true,
        x        = tx,
        y        = ty,
        fgId     = fgId,
        fgName   = Core.GetItemName(fgId),
        bgId     = bgId,
        bgName   = Core.GetItemName(bgId),
        canEdit  = canEdit,
        mayBuild = mayBuild,
        lock     = lockInfo,
    }
end

--- Memindai atribut player yang tereplikasi di workspace Players & status StaffUI lokal (read-only).
function Core.ScanPlayersExposure()
    local Players = game:GetService("Players")
    local list = {}
    local totalAttrs = 0
    local sensitiveCount = 0
    local taggedPlayers = 0

    for _, p in ipairs(Players:GetPlayers()) do
        local attrsList = {}
        local okA, rawAttrs = pcall(function() return p:GetAttributes() end)
        if okA and type(rawAttrs) == "table" then
            for k, v in pairs(rawAttrs) do
                totalAttrs = totalAttrs + 1
                local sensLabel = SENSITIVE_PLAYER_ATTRS[k]
                if sensLabel then sensitiveCount = sensitiveCount + 1 end
                if k == "Tag" and v ~= nil and tostring(v) ~= "" then
                    taggedPlayers = taggedPlayers + 1
                end
                table.insert(attrsList, {
                    key       = tostring(k),
                    value     = formatAttrValue(v),
                    sensitive = sensLabel ~= nil,
                    label     = sensLabel,
                })
            end
        end
        table.sort(attrsList, function(a, b)
            if a.sensitive ~= b.sensitive then return a.sensitive end
            return a.key < b.key
        end)

        table.insert(list, {
            name          = p.Name,
            displayName   = p.DisplayName,
            userId        = p.UserId,
            isLocalPlayer = (LP ~= nil and p == LP),
            attrCount     = #attrsList,
            attributes    = attrsList,
        })
    end

    table.sort(list, function(a, b)
        if a.isLocalPlayer ~= b.isLocalPlayer then return a.isLocalPlayer end
        return a.name:lower() < b.name:lower()
    end)

    -- Audit read-only keberadaan StaffUI pada LocalPlayer.PlayerGui
    local staffAudit = { present = false, rank = nil, ownStateAttrs = {} }
    pcall(function()
        if not LP then return end
        local pgui = LP:FindFirstChildOfClass("PlayerGui")
        local gg = pgui and pgui:FindFirstChild("GameGui")
        local sui = gg and gg:FindFirstChild("StaffUI")
        if sui then
            staffAudit.present = true
            staffAudit.rank = sui:GetAttribute("Rank")
            local own = sui:FindFirstChild("OwnState")
            if own then
                for k, v in pairs(own:GetAttributes()) do
                    staffAudit.ownStateAttrs[tostring(k)] = formatAttrValue(v)
                end
            end
        end
    end)

    local findings = {}
    if totalAttrs > 0 then
        table.insert(findings, {
            id         = "EXP-E1",
            category   = "Kat. E",
            severity   = "Low",
            confidence = 95,
            title      = string.format("%d Atribut Player Tereplikasi (%d sensitif/metadata)", totalAttrs, sensitiveCount),
            detail     = "Atribut seperti Tag, OwnTitle, GuildRank, Country, Nick, dan DiscordBooster dapat dibaca langsung pada instance Player di client.",
            remediation = "Batasi replikasi atribut yang bersifat moderasi/privat (misal ModZoom, HiddenIds, Frozen) hanya untuk client berwenang.",
        })
    end
    if staffAudit.present then
        table.insert(findings, {
            id         = "EXP-B1",
            category   = "Kat. B/E",
            severity   = "Info",
            confidence = 90,
            title      = "Container StaffUI Terdeteksi di PlayerGui Lokal",
            detail     = string.format("GameGui.StaffUI ada di client (Rank=%s). Pastikan verifikasi aksi admin tetap 100%% di server.", tostring(staffAudit.rank)),
            remediation = "Hapus/jangan kirim UI maupun folder StaffUI ke PlayerGui pemain non-staff dari server.",
        })
    end

    return {
        ok                     = true,
        playerCount            = #list,
        totalAttributesExposed = totalAttrs,
        sensitiveAttrCount     = sensitiveCount,
        taggedPlayers          = taggedPlayers,
        players                = list,
        localStaffUI           = staffAudit,
        findings               = findings,
    }
end

--- Menyusun teks laporan audit eksposur Kat. D & E untuk disalin atau disimpan.
function Core.BuildExposureReportText(scanResult)
    local res = scanResult or H.lastScanResult
    if not res then return "Belum ada hasil scan." end

    local lines = {
        "=== SkyP Read-Only Exposure Audit (Kat. D & E) ===",
        string.format("World: %s (%dx%d)", tostring(res.lock and res.lock.worldName or "?"), res.lock and res.lock.width or 0, res.lock and res.lock.height or 0),
        string.format("Waktu: %s", os.date("%Y-%m-%d %H:%M:%S")),
        "",
        "[1] RINGKASAN TEMUAN",
    }
    for _, f in ipairs(res.findings or {}) do
        table.insert(lines, string.format("- [%s | %s | Conf %d%%] %s", f.id, f.category, f.confidence, f.title))
        table.insert(lines, string.format("  Detail: %s", f.detail))
        table.insert(lines, string.format("  Mitigasi: %s", f.remediation))
    end

    table.insert(lines, "")
    table.insert(lines, "[2] TILE POSISI BOT SAAT INI")
    if res.tile and res.tile.ok then
        local t = res.tile
        table.insert(lines, string.format("- Pos (%d,%d) | FG: %s (%d) | BG: %s (%d) | canEdit=%s",
            t.x, t.y, tostring(t.fgName), t.fgId, tostring(t.bgName), t.bgId, tostring(t.canEdit)))
        if t.lock then
            table.insert(lines, string.format("  Pemegang Tile: [%s] %s (UserId: %s) | Role Lokal: %s",
                t.lock.kind, t.lock.ownerName, tostring(t.lock.owner), t.lock.localRole))
        else
            table.insert(lines, "  Pemegang Tile: Tidak terkunci (Open)")
        end
    end

    table.insert(lines, "")
    table.insert(lines, "[3] PEMILIK LOCK & ACCESS LIST")
    if res.lock and res.lock.ok then
        local function appendLock(lk)
            local flags = {}
            if lk.public then table.insert(flags, "PUBLIC") end
            if lk.buildOnly then table.insert(flags, "BUILD_ONLY") end
            if lk.ignoreAir then table.insert(flags, "IGNORE_AIR") end
            if lk.adminsLimited then table.insert(flags, "ADMINS_LIMITED") end
            local flagStr = #flags > 0 and table.concat(flags, ", ") or "PRIVATE"
            table.insert(lines, string.format("- [%s @ %s,%s] Owner: %s (%s) | Tiles: %d | Flags: %s | LocalRole: %s",
                lk.kind, tostring(lk.x or "-"), tostring(lk.y or "-"), lk.ownerName, tostring(lk.owner),
                lk.tileCount or 0, flagStr, lk.localRole))
            if lk.accessCount > 0 then
                local accStr = {}
                for _, m in ipairs(lk.access) do
                    table.insert(accStr, string.format("%s(%s)", m.name, tostring(m.userId)))
                end
                table.insert(lines, "  Access: " .. table.concat(accStr, ", "))
            else
                table.insert(lines, "  Access: (kosong)")
            end
        end
        if res.lock.worldLock then appendLock(res.lock.worldLock) end
        for _, lk in ipairs(res.lock.areaLocks or {}) do appendLock(lk) end
        if res.lock.totalLocks == 0 then
            table.insert(lines, "- Tidak ada lock terdeteksi di world ini.")
        end
    end

    table.insert(lines, "")
    table.insert(lines, "[4] PLAYER & ATRIBUT TEREPLIKASI")
    if res.players and res.players.ok then
        for _, p in ipairs(res.players.players or {}) do
            table.insert(lines, string.format("- %s (@%s) [UserId: %s]%s | %d attr",
                p.name, p.displayName, tostring(p.userId), p.isLocalPlayer and " [ME]" or "", p.attrCount))
            for _, a in ipairs(p.attributes) do
                table.insert(lines, string.format("    %s%s = %s", a.sensitive and "* " or "  ", a.key, a.value))
            end
        end
    end

    return table.concat(lines, "\n")
end

--- Menjalankan audit lengkap Kat. D & E (Lock/Access + Tile Saat Ini + Player Attributes).
function Core.RunFullExposureScan(tx, ty)
    local lockRes   = Core.ScanLockExposure()
    local tileRes   = Core.ScanTileAccess(tx, ty)
    local playerRes = Core.ScanPlayersExposure()

    local findings = {}
    for _, f in ipairs(lockRes.findings or {}) do table.insert(findings, f) end
    for _, f in ipairs(playerRes.findings or {}) do table.insert(findings, f) end

    local res = {
        timestamp = os.time(),
        lock      = lockRes,
        tile      = tileRes,
        players   = playerRes,
        findings  = findings,
    }
    res.reportText = Core.BuildExposureReportText(res)
    H.lastScanResult = res
    return res
end

--- Mengekspor laporan scan terakhir ke file teks jika executor mendukung writefile.
function Core.ExportExposureReport(scanResult)
    local res = scanResult or H.lastScanResult or Core.RunFullExposureScan()
    local text = Core.BuildExposureReportText(res)
    local world = tostring(res.lock and res.lock.worldName or "world"):gsub("[^%w_%-]", "_")
    local filename = string.format("SkyP_Exposure_%s_%d.txt", world, os.time())
    if type(writefile) == "function" then
        local ok, err = pcall(writefile, filename, text)
        if ok then
            return true, filename, text
        end
        return false, tostring(err), text
    end
    return false, "Fungsi writefile tidak tersedia di executor.", text
end

-- Initialize config & background world watcher
Core.LoadWorldConfig()
Core.ResetSecurityTimers()
Core.Discover()

return Core
