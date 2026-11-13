--[[
    SkyP_Load.lua - Loader untuk SkyP v1.8 (Pabrik Smart + Peta Mini + Dirt Farm + Scanner)
    Mendukung load dari GitHub (Mytzcodes/D-BOM) maupun file lokal workspace executor.
]]

local REPO_PATH = "Mytzcodes/D-BOM"
local BASE_URL  = "https://raw.githubusercontent.com/" .. REPO_PATH .. "/refs/heads/main/"

local function tryLoadModule(filename)
    local env = (type(getgenv) == "function" and getgenv()) or _G
    local forceRemote = env and env.SkyP_FORCE_REMOTE == true

    local paths = {
        filename,
        "D-BOM/" .. filename,
        "D-BOM/SkyP/" .. filename,
        "SkyP/" .. filename,
        "skyp/" .. filename,
        "ScriptExport_112863874972771/" .. filename,
    }

    if not forceRemote and type(isfile) == "function" and type(readfile) == "function" then
        for _, p in ipairs(paths) do
            local okExists, exists = pcall(isfile, p)
            if okExists and exists then
                local okRead, src = pcall(readfile, p)
                if okRead and type(src) == "string" and #src > 0 then
                    local fn, err = loadstring(src, "@" .. filename)
                    if not fn then
                        error("[SkyP_Load] Syntax error pada " .. p .. ": " .. tostring(err))
                    end
                    return fn()
                end
            end
        end
    end

    if not forceRemote and type(loadfile) == "function" then
        for _, p in ipairs(paths) do
            local okFn, fnOrErr = pcall(loadfile, p)
            if okFn and type(fnOrErr) == "function" then
                return fnOrErr()
            end
        end
    end

    local candidateUrls = {}
    local customBase = env and env.SkyP_BASE_URL
    if type(customBase) == "string" and customBase ~= "" then
        if string.sub(customBase, -1) ~= "/" then customBase = customBase .. "/" end
        table.insert(candidateUrls, customBase .. filename)
    end
    for _, base in ipairs({
        BASE_URL,
        "https://raw.githubusercontent.com/" .. REPO_PATH .. "/refs/heads/main/SkyP/",
        "https://raw.githubusercontent.com/" .. REPO_PATH .. "/main/",
        "https://raw.githubusercontent.com/" .. REPO_PATH .. "/refs/heads/master/",
        "https://raw.githubusercontent.com/" .. REPO_PATH .. "/master/",
    }) do
        if type(base) == "string" and base ~= "" then
            table.insert(candidateUrls, base .. filename)
        end
    end

    local lastErr = "tidak ada respons HTTP valid"
    for _, url in ipairs(candidateUrls) do
        local okGet, src = pcall(function()
            return game:HttpGet(url)
        end)
        if okGet and type(src) == "string" and #src > 0 then
            local trimmed = string.match(src, "^%s*(.-)%s*$") or ""
            local isHttpErrorPage = string.sub(trimmed, 1, 4) == "404:"
                or string.sub(trimmed, 1, 1) == "<"
            if not isHttpErrorPage then
                local fn, err = loadstring(src, "@" .. filename)
                if fn then
                    return fn()
                end
                lastErr = "Syntax error dari " .. url .. ": " .. tostring(err)
            else
                lastErr = "HTTP 404/HTML dari " .. url
            end
        elseif not okGet then
            lastErr = "HttpGet gagal (" .. url .. "): " .. tostring(src)
        end
    end

    error(
        "[SkyP_Load] Gagal memuat '" .. filename .. "' dari lokal maupun GitHub (" .. REPO_PATH .. "). "
        .. "Detail terakhir: " .. tostring(lastErr)
    )
end

-- Hentikan worker, koneksi, & hook dari instance sebelumnya jika reload (T-02)
local _skypEnv = (type(getgenv) == "function" and getgenv()) or _G
if type(_skypEnv.__SkyP_Shutdown) == "function" then
    pcall(_skypEnv.__SkyP_Shutdown)
    _skypEnv.__SkyP_Shutdown = nil
end

-- Tutup instance UI lama jika dijalankan ulang
pcall(function()
    local Players = game:GetService("Players")
    local CoreGui = game:GetService("CoreGui")
    local lp = Players.LocalPlayer
    for _, parent in ipairs({ CoreGui, lp and lp:FindFirstChildOfClass("PlayerGui") }) do
        if parent then
            local old = parent:FindFirstChild("SkyP_HUD")
            if old then
                old:Destroy()
            end
        end
    end
end)

local Core = tryLoadModule("SkyP_Core.lua")
local UI = tryLoadModule("SkyP_UI.lua")

if type(Core) ~= "table" or type(UI) ~= "function" then
    error("[SkyP_Load] Modul Core atau UI tidak valid.")
end

if type(Core.Shutdown) == "function" then
    _skypEnv.__SkyP_Shutdown = Core.Shutdown
end

local okDisc, discErr = pcall(function()
    Core.Discover()
end)
if not okDisc then
    warn("[SkyP_Load] Discover awal belum siap (akan di-retry di UI):", discErr)
end

local okUI, uiErr = pcall(function()
    UI(Core)
end)
if not okUI then
    error("[SkyP_Load] Gagal menjalankan SkyP UI: " .. tostring(uiErr))
end

return Core
