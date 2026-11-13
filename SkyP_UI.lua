--[[
    SkyP_UI.lua — Custom ScreenGui + Peta Mini Interaktif (v1.8)
    Ringan, responsif PC & Mobile, terhubung penuh ke SkyP_Core.lua
]]

return function(Core)
    local Players          = game:GetService("Players")
    local UIS              = game:GetService("UserInputService")
    local RunService       = game:GetService("RunService")
    local CoreGui          = game:GetService("CoreGui")
    local LP               = Players.LocalPlayer
    local PG               = LP:WaitForChild("PlayerGui")

    -- Remove previous instance if reloaded
    local guiParent = (pcall(function() return CoreGui.Name end) and CoreGui) or PG
    local old = guiParent:FindFirstChild("SkyP_HUD") or PG:FindFirstChild("SkyP_HUD")
    if old then old:Destroy() end

    local S = Core.State

    -- ─────────────────────────────────────────────────────────────────────────
    --  PALETTE & UI HELPERS
    -- ─────────────────────────────────────────────────────────────────────────
    local C = {
        bg       = Color3.fromRGB(17, 19, 24),
        panel    = Color3.fromRGB(24, 27, 34),
        card     = Color3.fromRGB(31, 35, 44),
        border   = Color3.fromRGB(50, 56, 70),
        accent   = Color3.fromRGB(56, 189, 248),
        green    = Color3.fromRGB(34, 197, 94),
        red      = Color3.fromRGB(239, 68, 68),
        amber    = Color3.fromRGB(245, 158, 11),
        purple   = Color3.fromRGB(168, 85, 247),
        text     = Color3.fromRGB(240, 244, 250),
        muted    = Color3.fromRGB(148, 163, 184),
        input    = Color3.fromRGB(15, 17, 22),
    }

    local function make(cls, props, parent)
        local inst = Instance.new(cls)
        for k, v in pairs(props or {}) do
            inst[k] = v
        end
        if parent then inst.Parent = parent end
        return inst
    end

    local function corner(parent, rad)
        return make("UICorner", { CornerRadius = UDim.new(0, rad or 6) }, parent)
    end

    local function stroke(parent, col, thick)
        return make("UIStroke", { Color = col or C.border, Thickness = thick or 1, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, parent)
    end

    local function pad(parent, l, r, t, b)
        return make("UIPadding", {
            PaddingLeft   = UDim.new(0, l or 8),
            PaddingRight  = UDim.new(0, r or l or 8),
            PaddingTop    = UDim.new(0, t or 6),
            PaddingBottom = UDim.new(0, b or t or 6),
        }, parent)
    end

    local function makeDraggable(handle, target)
        local dragging, dragStart, startPos
        handle.InputBegan:Connect(function(inp)
            if inp.UserInputType == Enum.UserInputType.MouseButton1 or inp.UserInputType == Enum.UserInputType.Touch then
                dragging = true
                dragStart = inp.Position
                startPos = target.Position
                inp.Changed:Connect(function()
                    if inp.UserInputState == Enum.UserInputState.End then
                        dragging = false
                    end
                end)
            end
        end)
        UIS.InputChanged:Connect(function(inp)
            if dragging and (inp.UserInputType == Enum.UserInputType.MouseMovement or inp.UserInputType == Enum.UserInputType.Touch) then
                local delta = inp.Position - dragStart
                target.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
            end
        end)
    end

    -- ─────────────────────────────────────────────────────────────────────────
    --  MAIN SCREENGUI & SHELL
    -- ─────────────────────────────────────────────────────────────────────────
    local gui = make("ScreenGui", {
        Name           = "SkyP_HUD",
        ResetOnSpawn   = false,
        ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
    }, guiParent)

    local win = make("Frame", {
        Name             = "MainWindow",
        Size             = UDim2.fromOffset(560, 440),
        Position         = UDim2.new(0.5, -280, 0.5, -220),
        BackgroundColor3 = C.bg,
        BorderSizePixel  = 0,
    }, gui)
    corner(win, 10)
    stroke(win, C.border, 1.5)

    -- Header
    local header = make("Frame", {
        Size             = UDim2.new(1, 0, 0, 36),
        BackgroundColor3 = C.panel,
        BorderSizePixel  = 0,
    }, win)
    corner(header, 10)
    make("Frame", {
        Size             = UDim2.new(1, 0, 0, 10),
        Position         = UDim2.new(0, 0, 1, -10),
        BackgroundColor3 = C.panel,
        BorderSizePixel  = 0,
    }, header)
    makeDraggable(header, win)

    local titleLbl = make("TextLabel", {
        Size                   = UDim2.new(1, -150, 1, 0),
        Position               = UDim2.fromOffset(12, 0),
        BackgroundTransparency = 1,
        Font                   = Enum.Font.GothamBold,
        TextSize               = 14,
        TextColor3             = C.text,
        TextXAlignment         = Enum.TextXAlignment.Left,
        Text                   = "SkyP v1.8  |  World: —",
    }, header)

    local minBtn = make("TextButton", {
        Size             = UDim2.fromOffset(26, 22),
        Position         = UDim2.new(1, -60, 0.5, -11),
        BackgroundColor3 = C.card,
        Font             = Enum.Font.GothamBold,
        TextSize         = 13,
        TextColor3       = C.text,
        Text             = "—",
    }, header)
    corner(minBtn, 5)

    local closeBtn = make("TextButton", {
        Size             = UDim2.fromOffset(26, 22),
        Position         = UDim2.new(1, -30, 0.5, -11),
        BackgroundColor3 = C.red,
        Font             = Enum.Font.GothamBold,
        TextSize         = 12,
        TextColor3       = C.text,
        Text             = "X",
    }, header)
    corner(closeBtn, 5)

    -- Floating reopen pill when minimized
    local openPill = make("TextButton", {
        Visible          = false,
        Size             = UDim2.fromOffset(116, 30),
        Position         = UDim2.new(0, 14, 0.5, -15),
        BackgroundColor3 = C.panel,
        Font             = Enum.Font.GothamBold,
        TextSize         = 12,
        TextColor3       = C.accent,
        Text             = "SkyP v1.8",
    }, gui)
    corner(openPill, 8)
    stroke(openPill, C.accent, 1.2)
    makeDraggable(openPill, openPill)

    minBtn.MouseButton1Click:Connect(function()
        win.Visible = false
        openPill.Visible = true
    end)
    openPill.MouseButton1Click:Connect(function()
        openPill.Visible = false
        win.Visible = true
    end)
    closeBtn.MouseButton1Click:Connect(function()
        Core.StopAllFarming()
        Core.SetFly(false)
        Core.SetModWatch(false)
        gui:Destroy()
    end)

    -- ─────────────────────────────────────────────────────────────────────────
    --  STATUS SATU BARIS + RINCIAN DRAWER
    -- ─────────────────────────────────────────────────────────────────────────
    local statusBar = make("Frame", {
        Size             = UDim2.new(1, -16, 0, 28),
        Position         = UDim2.fromOffset(8, 42),
        BackgroundColor3 = C.card,
        BorderSizePixel  = 0,
    }, win)
    corner(statusBar, 6)
    stroke(statusBar, C.border, 1)

    local statusLine = make("TextLabel", {
        Size                   = UDim2.new(1, -76, 1, 0),
        Position               = UDim2.fromOffset(8, 0),
        BackgroundTransparency = 1,
        Font                   = Enum.Font.GothamMedium,
        TextSize               = 11,
        TextColor3             = C.accent,
        TextXAlignment         = Enum.TextXAlignment.Left,
        TextTruncate           = Enum.TextTruncate.AtEnd,
        Text                   = "Siap | Seed 0 | Tanam 0 tile",
    }, statusBar)

    local detailToggleBtn = make("TextButton", {
        Size             = UDim2.new(0, 66, 0, 20),
        Position         = UDim2.new(1, -70, 0.5, -10),
        BackgroundColor3 = C.panel,
        Font             = Enum.Font.GothamBold,
        TextSize         = 10,
        TextColor3       = C.text,
        Text             = "Rincian v",
    }, statusBar)
    corner(detailToggleBtn, 4)

    local detailDrawer = make("Frame", {
        Visible          = false,
        Size             = UDim2.new(1, -16, 0, 62),
        Position         = UDim2.fromOffset(8, 73),
        BackgroundColor3 = C.panel,
        BorderSizePixel  = 0,
        ZIndex           = 5,
    }, win)
    corner(detailDrawer, 6)
    stroke(detailDrawer, C.accent, 1)

    local detailText = make("TextLabel", {
        Size                   = UDim2.new(1, -100, 1, -8),
        Position               = UDim2.fromOffset(8, 4),
        BackgroundTransparency = 1,
        Font                   = Enum.Font.Code,
        TextSize               = 11,
        TextColor3             = C.text,
        TextXAlignment         = Enum.TextXAlignment.Left,
        TextYAlignment         = Enum.TextYAlignment.Top,
        TextWrapped            = true,
        Text                   = "",
        ZIndex                 = 6,
    }, detailDrawer)

    local resetStatsBtn = make("TextButton", {
        Size             = UDim2.fromOffset(86, 26),
        Position         = UDim2.new(1, -92, 0.5, -13),
        BackgroundColor3 = C.amber,
        Font             = Enum.Font.GothamBold,
        TextSize         = 10,
        TextColor3       = Color3.new(0, 0, 0),
        Text             = "Reset Hitung",
        ZIndex           = 6,
    }, detailDrawer)
    corner(resetStatsBtn, 5)
    resetStatsBtn.MouseButton1Click:Connect(function()
        Core.ResetStats()
    end)

    detailToggleBtn.MouseButton1Click:Connect(function()
        detailDrawer.Visible = not detailDrawer.Visible
        detailToggleBtn.Text = detailDrawer.Visible and "Rincian ^" or "Rincian v"
    end)

    -- ─────────────────────────────────────────────────────────────────────────
    --  TAB BAR (Pabrik, Peta Mini, Penjaga, Tools) — NO Tab Lahan / Bangun Lahan
    -- ─────────────────────────────────────────────────────────────────────────
    local tabBar = make("Frame", {
        Size             = UDim2.new(1, -16, 0, 28),
        Position         = UDim2.fromOffset(8, 74),
        BackgroundColor3 = C.panel,
        BorderSizePixel  = 0,
    }, win)
    corner(tabBar, 6)
    make("UIListLayout", {
        FillDirection = Enum.FillDirection.Horizontal,
        Padding       = UDim.new(0, 4),
        VerticalAlignment = Enum.VerticalAlignment.Center,
    }, tabBar)
    pad(tabBar, 4, 4, 3, 3)

    local bodyContainer = make("Frame", {
        Size                   = UDim2.new(1, -16, 1, -114),
        Position               = UDim2.fromOffset(8, 106),
        BackgroundTransparency = 1,
    }, win)

    local tabs = {}
    local tabButtons = {}
    local activeTab = nil

    local function selectTab(name)
        activeTab = name
        for tName, page in pairs(tabs) do
            page.Visible = (tName == name)
        end
        for tName, btn in pairs(tabButtons) do
            local on = (tName == name)
            btn.BackgroundColor3 = on and C.accent or C.card
            btn.TextColor3       = on and Color3.new(0, 0, 0) or C.text
        end
    end

    local function createTab(name, isScroll)
        local btn = make("TextButton", {
            Size             = UDim2.new(1 / 6, -3.5, 1, 0),
            BackgroundColor3 = C.card,
            Font             = Enum.Font.GothamBold,
            TextSize         = 10,
            TextColor3       = C.text,
            Text             = name,
        }, tabBar)
        corner(btn, 5)
        tabButtons[name] = btn

        local page
        if isScroll then
            page = make("ScrollingFrame", {
                Visible              = false,
                Size                 = UDim2.fromScale(1, 1),
                BackgroundTransparency = 1,
                BorderSizePixel      = 0,
                ScrollBarThickness   = 5,
                AutomaticCanvasSize  = Enum.AutomaticSize.Y,
                CanvasSize           = UDim2.new(0, 0, 0, 0),
            }, bodyContainer)
            make("UIListLayout", {
                Padding   = UDim.new(0, 6),
                SortOrder = Enum.SortOrder.LayoutOrder,
            }, page)
            pad(page, 2, 6, 2, 6)
        else
            page = make("Frame", {
                Visible              = false,
                Size                 = UDim2.fromScale(1, 1),
                BackgroundTransparency = 1,
            }, bodyContainer)
        end
        tabs[name] = page
        btn.MouseButton1Click:Connect(function() selectTab(name) end)
        return page
    end

    -- Reusable Form Controls
    local function addSection(parent, title)
        local lbl = make("TextLabel", {
            Size                   = UDim2.new(1, 0, 0, 20),
            BackgroundTransparency = 1,
            Font                   = Enum.Font.GothamBold,
            TextSize               = 12,
            TextColor3             = C.accent,
            TextXAlignment         = Enum.TextXAlignment.Left,
            Text                   = title,
        }, parent)
        return lbl
    end

    local function addCard(parent, height)
        local f = make("Frame", {
            Size             = UDim2.new(1, 0, 0, height or 34),
            BackgroundColor3 = C.panel,
            BorderSizePixel  = 0,
        }, parent)
        corner(f, 6)
        stroke(f, C.border, 1)
        return f
    end

    local function addToggle(parent, label, initial, onChanged)
        local row = addCard(parent, 32)
        make("TextLabel", {
            Size                   = UDim2.new(1, -64, 1, 0),
            Position               = UDim2.fromOffset(10, 0),
            BackgroundTransparency = 1,
            Font                   = Enum.Font.GothamMedium,
            TextSize               = 12,
            TextColor3             = C.text,
            TextXAlignment         = Enum.TextXAlignment.Left,
            Text                   = label,
        }, row)

        local val = initial == true
        local btn = make("TextButton", {
            Size             = UDim2.fromOffset(46, 20),
            Position         = UDim2.new(1, -54, 0.5, -10),
            BackgroundColor3 = val and C.green or C.card,
            Font             = Enum.Font.GothamBold,
            TextSize         = 11,
            TextColor3       = val and Color3.new(0, 0, 0) or C.muted,
            Text             = val and "ON" or "OFF",
        }, row)
        corner(btn, 10)

        local function set(v, silent)
            val = v == true
            btn.BackgroundColor3 = val and C.green or C.card
            btn.TextColor3       = val and Color3.new(0, 0, 0) or C.muted
            btn.Text             = val and "ON" or "OFF"
            if not silent and onChanged then onChanged(val) end
        end

        btn.MouseButton1Click:Connect(function() set(not val) end)
        return { Frame = row, Set = set, Get = function() return val end }
    end

    local function addInputRow(parent, label, initial, placeholder, onSubmit)
        local row = addCard(parent, 34)
        make("TextLabel", {
            Size                   = UDim2.new(0.5, -10, 1, 0),
            Position               = UDim2.fromOffset(10, 0),
            BackgroundTransparency = 1,
            Font                   = Enum.Font.GothamMedium,
            TextSize               = 12,
            TextColor3             = C.text,
            TextXAlignment         = Enum.TextXAlignment.Left,
            Text                   = label,
        }, row)

        local box = make("TextBox", {
            Size              = UDim2.new(0.5, -14, 0, 24),
            Position          = UDim2.new(0.5, 4, 0.5, -12),
            BackgroundColor3  = C.input,
            Font              = Enum.Font.Code,
            TextSize          = 12,
            TextColor3        = C.text,
            PlaceholderColor3 = C.muted,
            PlaceholderText   = placeholder or "",
            Text              = tostring(initial or ""),
            ClearTextOnFocus  = false,
        }, row)
        corner(box, 5)
        stroke(box, C.border, 1)

        box.FocusLost:Connect(function()
            if onSubmit then onSubmit(box.Text, box) end
        end)
        return { Frame = row, Box = box }
    end

    local function addStepper(parent, label, initial, minV, maxV, step, suffix, onChange)
        local row = addCard(parent, 34)
        local val = clamp(tonumber(initial) or minV, minV, maxV)

        local lbl = make("TextLabel", {
            Size                   = UDim2.new(1, -136, 1, 0),
            Position               = UDim2.fromOffset(10, 0),
            BackgroundTransparency = 1,
            Font                   = Enum.Font.GothamMedium,
            TextSize               = 12,
            TextColor3             = C.text,
            TextXAlignment         = Enum.TextXAlignment.Left,
            Text                   = label,
        }, row)

        local minus = make("TextButton", {
            Size             = UDim2.fromOffset(26, 22),
            Position         = UDim2.new(1, -126, 0.5, -11),
            BackgroundColor3 = C.card,
            Font             = Enum.Font.GothamBold,
            TextSize         = 14,
            TextColor3       = C.text,
            Text             = "-",
        }, row)
        corner(minus, 5)

        local valBox = make("TextBox", {
            Size             = UDim2.fromOffset(58, 22),
            Position         = UDim2.new(1, -96, 0.5, -11),
            BackgroundColor3 = C.input,
            Font             = Enum.Font.Code,
            TextSize         = 12,
            TextColor3       = C.accent,
            Text             = tostring(val) .. (suffix or ""),
            ClearTextOnFocus = false,
        }, row)
        corner(valBox, 5)

        local plus = make("TextButton", {
            Size             = UDim2.fromOffset(26, 22),
            Position         = UDim2.new(1, -34, 0.5, -11),
            BackgroundColor3 = C.card,
            Font             = Enum.Font.GothamBold,
            TextSize         = 14,
            TextColor3       = C.text,
            Text             = "+",
        }, row)
        corner(plus, 5)

        local function set(n)
            val = clamp(tonumber(n) or val, minV, maxV)
            valBox.Text = tostring(val) .. (suffix or "")
            if onChange then onChange(val) end
        end

        minus.MouseButton1Click:Connect(function() set(val - step) end)
        plus.MouseButton1Click:Connect(function() set(val + step) end)
        valBox.FocusLost:Connect(function()
            local num = tonumber(string.match(valBox.Text, "[-%d%.]+"))
            set(num or val)
        end)

        return { Frame = row, Label = lbl, Set = set, Get = function() return val end }
    end

    -- ─────────────────────────────────────────────────────────────────────────
    --  TAB 1: PABRIK (SISTEM TERPADU)
    -- ─────────────────────────────────────────────────────────────────────────
    local pagePabrik = createTab("Pabrik", true)

    -- Start / Stop row
    local ctrlRow = addCard(pagePabrik, 40)
    local startBtn = make("TextButton", {
        Size             = UDim2.new(0.42, -6, 0, 28),
        Position         = UDim2.new(0, 6, 0.5, -14),
        BackgroundColor3 = C.green,
        Font             = Enum.Font.GothamBold,
        TextSize         = 12,
        TextColor3       = Color3.new(0, 0, 0),
        Text             = "START PABRIK",
    }, ctrlRow)
    corner(startBtn, 6)

    local stopBtn = make("TextButton", {
        Size             = UDim2.new(0.28, -4, 0, 28),
        Position         = UDim2.new(0.42, 4, 0.5, -14),
        BackgroundColor3 = C.red,
        Font             = Enum.Font.GothamBold,
        TextSize         = 12,
        TextColor3       = C.text,
        Text             = "STOP",
    }, ctrlRow)
    corner(stopBtn, 6)

    local openMapBtn = make("TextButton", {
        Size             = UDim2.new(0.30, -8, 0, 28),
        Position         = UDim2.new(0.70, 2, 0.5, -14),
        BackgroundColor3 = C.accent,
        Font             = Enum.Font.GothamBold,
        TextSize         = 11,
        TextColor3       = Color3.new(0, 0, 0),
        Text             = "Peta Mini",
    }, ctrlRow)
    corner(openMapBtn, 6)

    startBtn.MouseButton1Click:Connect(function() Core.StartPabrik() end)
    stopBtn.MouseButton1Click:Connect(function() Core.StopPabrik() end)
    openMapBtn.MouseButton1Click:Connect(function() selectTab("Peta Mini") end)

    addSection(pagePabrik, "Target Item (Seed & Block)")
    local seedRow = addInputRow(pagePabrik, "Seed ID (Tanam/Panen)", S.seedId, "Contoh: 3", function(txt, box)
        local id = tonumber(txt)
        if id and id > 0 then
            S.seedId = math.floor(id)
        end
        box.Text = tostring(S.seedId) .. " (" .. Core.GetItemName(S.seedId) .. ")"
    end)
    seedRow.Box.Text = tostring(S.seedId) .. " (" .. Core.GetItemName(S.seedId) .. ")"

    local blkRow = addInputRow(pagePabrik, "Block ID (Break + Place)", S.blockId, "Contoh: 2", function(txt, box)
        local id = tonumber(txt)
        if id and id > 0 then
            S.blockId = math.floor(id)
        end
        box.Text = tostring(S.blockId) .. " (" .. Core.GetItemName(S.blockId) .. ")"
    end)
    blkRow.Box.Text = tostring(S.blockId) .. " (" .. Core.GetItemName(S.blockId) .. ")"

    addSection(pagePabrik, "Pengaturan Rute & Mode Pabrik")
    addToggle(pagePabrik, "Full World (Pakai semua lantai otomatis)", S.fullWorld, function(v)
        S.fullWorld = v
    end)

    -- Urutan rute selector (Atas ke bawah / Bawah ke atas / Terdekat dulu)
    local routeCard = addCard(pagePabrik, 36)
    make("TextLabel", {
        Size                   = UDim2.new(0.38, 0, 1, 0),
        Position               = UDim2.fromOffset(10, 0),
        BackgroundTransparency = 1,
        Font                   = Enum.Font.GothamMedium,
        TextSize               = 12,
        TextColor3             = C.text,
        TextXAlignment         = Enum.TextXAlignment.Left,
        Text                   = "Urutan Rute",
    }, routeCard)

    local routeBtns = {}
    local routeOpts = {
        { id = "top",     label = "Atas->Bawah" },
        { id = "bottom",  label = "Bawah->Atas" },
        { id = "nearest", label = "Terdekat" },
    }
    local function refreshRouteBtns()
        for id, b in pairs(routeBtns) do
            local on = (S.routeOrder == id)
            b.BackgroundColor3 = on and C.accent or C.card
            b.TextColor3       = on and Color3.new(0, 0, 0) or C.text
        end
    end
    for idx, opt in ipairs(routeOpts) do
        local b = make("TextButton", {
            Size             = UDim2.new(0.20, -4, 0, 24),
            Position         = UDim2.new(0.38 + (idx - 1) * 0.205, 0, 0.5, -12),
            BackgroundColor3 = C.card,
            Font             = Enum.Font.GothamBold,
            TextSize         = 10,
            TextColor3       = C.text,
            Text             = opt.label,
        }, routeCard)
        corner(b, 5)
        routeBtns[opt.id] = b
        b.MouseButton1Click:Connect(function()
            S.routeOrder = opt.id
            refreshRouteBtns()
        end)
    end
    refreshRouteBtns()

    addStepper(pagePabrik, "Mulai panen saat pohon siap", S.harvestThreshold, 10, 100, 5, "%", function(v)
        S.harvestThreshold = v
    end)
    addToggle(pagePabrik, "1 HIT MODE (Break 1 Paket)", S.oneHitMode, function(v) S.oneHitMode = v end)
    addToggle(pagePabrik, "Break Cepat (Secepat batas server)", S.fastBreak, function(v) S.fastBreak = v end)

    addSection(pagePabrik, "Auto Break + Place + Refill + Return")
    addToggle(pagePabrik, "Auto Break + Place di Tile Break", S.autoBreakPlace, function(v) S.autoBreakPlace = v end)
    addToggle(pagePabrik, "Auto Refill Block (Ambil block sekitar)", S.autoRefill, function(v) S.autoRefill = v end)
    addToggle(pagePabrik, "Auto Return (Balik ke posisi Berdiri)", S.autoReturn, function(v) S.autoReturn = v end)

    addSection(pagePabrik, "Auto Drop Seed (Antar-Fase, Maks 190)")
    addToggle(pagePabrik, "Auto Drop Seed", S.autoDropSeed, function(v) S.autoDropSeed = v end)
    addStepper(pagePabrik, "Batas Drop Seed (Maks 190)", S.dropThreshold, 10, 190, 10, "", function(v)
        S.dropThreshold = math.min(190, v)
    end)
    addStepper(pagePabrik, "Sisakan Seed di Tas", S.keepSeedCount, 0, 180, 5, "", function(v)
        S.keepSeedCount = v
    end)
    addInputRow(pagePabrik, "World Drop (Kosong = world ini)", S.dropWorld, "NAMA_WORLD", function(txt)
        S.dropWorld = string.upper(tostring(txt or ""):gsub("^%s+", ""):gsub("%s+$", ""))
    end)

    local dropPosCard = addCard(pagePabrik, 36)
    local dropXBox = make("TextBox", {
        Size             = UDim2.fromOffset(58, 24),
        Position         = UDim2.new(0, 8, 0.5, -12),
        BackgroundColor3 = C.input,
        Font             = Enum.Font.Code,
        TextSize         = 12,
        TextColor3       = C.text,
        PlaceholderText  = "Drop X",
        Text             = tostring(S.dropX),
    }, dropPosCard)
    corner(dropXBox, 5)
    local dropYBox = make("TextBox", {
        Size             = UDim2.fromOffset(58, 24),
        Position         = UDim2.new(0, 72, 0.5, -12),
        BackgroundColor3 = C.input,
        Font             = Enum.Font.Code,
        TextSize         = 12,
        TextColor3       = C.text,
        PlaceholderText  = "Drop Y",
        Text             = tostring(S.dropY),
    }, dropPosCard)
    corner(dropYBox, 5)
    dropXBox.FocusLost:Connect(function() S.dropX = tonumber(dropXBox.Text) or S.dropX end)
    dropYBox.FocusLost:Connect(function() S.dropY = tonumber(dropYBox.Text) or S.dropY end)

    local setDropHereBtn = make("TextButton", {
        Size             = UDim2.new(1, -144, 0, 24),
        Position         = UDim2.new(0, 136, 0.5, -12),
        BackgroundColor3 = C.card,
        Font             = Enum.Font.GothamBold,
        TextSize         = 11,
        TextColor3       = C.accent,
        Text             = "Pakai Posisi Sekarang (Drop)",
    }, dropPosCard)
    corner(setDropHereBtn, 5)
    setDropHereBtn.MouseButton1Click:Connect(function()
        local p = Core.ReadPos()
        S.dropX = p.tx
        S.dropY = p.ty
        S.dropWorld = S.worldName or ""
        dropXBox.Text = tostring(S.dropX)
        dropYBox.Text = tostring(S.dropY)
    end)

    -- Grid 5x5 ONLY for Auto Farm (NOT Pabrik!)
    addSection(pagePabrik, "Auto Farm Grid 5x5 (Khusus Auto Farm)")
    local gridCard = addCard(pagePabrik, 138)
    local gridHolder = make("Frame", {
        Size                   = UDim2.fromOffset(120, 120),
        Position               = UDim2.fromOffset(10, 9),
        BackgroundTransparency = 1,
    }, gridCard)
    for r = 1, 5 do
        S.grid[r] = S.grid[r] or {}
        for c = 1, 5 do
            local isCenter = (r == 3 and c == 3)
            if isCenter then S.grid[r][c] = false end
            local cell = make("TextButton", {
                Size             = UDim2.fromOffset(22, 22),
                Position         = UDim2.fromOffset((c - 1) * 24, (r - 1) * 24),
                BackgroundColor3 = isCenter and C.purple or (S.grid[r][c] and C.accent or C.card),
                Font             = Enum.Font.GothamBold,
                TextSize         = 10,
                TextColor3       = Color3.new(1, 1, 1),
                Text             = isCenter and "P" or "",
            }, gridHolder)
            corner(cell, 4)
            if not isCenter then
                cell.MouseButton1Click:Connect(function()
                    S.grid[r][c] = not S.grid[r][c]
                    cell.BackgroundColor3 = S.grid[r][c] and C.accent or C.card
                end)
            end
        end
    end

    local setBaseBtn = make("TextButton", {
        Size             = UDim2.new(1, -148, 0, 28),
        Position         = UDim2.fromOffset(140, 12),
        BackgroundColor3 = C.card,
        Font             = Enum.Font.GothamBold,
        TextSize         = 11,
        TextColor3       = C.text,
        Text             = "Set Base Grid (Posisi)",
    }, gridCard)
    corner(setBaseBtn, 5)
    setBaseBtn.MouseButton1Click:Connect(function()
        local b = Core.SetGridBase()
        setBaseBtn.Text = string.format("Base: (%d, %d)", b.x, b.y)
    end)

    local startGridBtn = make("TextButton", {
        Size             = UDim2.new(1, -148, 0, 28),
        Position         = UDim2.fromOffset(140, 48),
        BackgroundColor3 = C.green,
        Font             = Enum.Font.GothamBold,
        TextSize         = 11,
        TextColor3       = Color3.new(0, 0, 0),
        Text             = "START AUTO FARM GRID",
    }, gridCard)
    corner(startGridBtn, 5)
    startGridBtn.MouseButton1Click:Connect(function() Core.StartGridPNB() end)

    local stopGridBtn = make("TextButton", {
        Size             = UDim2.new(1, -148, 0, 28),
        Position         = UDim2.fromOffset(140, 84),
        BackgroundColor3 = C.red,
        Font             = Enum.Font.GothamBold,
        TextSize         = 11,
        TextColor3       = C.text,
        Text             = "STOP GRID",
    }, gridCard)
    corner(stopGridBtn, 5)
    stopGridBtn.MouseButton1Click:Connect(function() Core.StopGridPNB() end)

    -- ─────────────────────────────────────────────────────────────────────────
    --  TAB 1B: DIRT FARM (SkyP v1.8 - Plant Dirt, Harvest Dirt, Build Upper)
    -- ─────────────────────────────────────────────────────────────────────────
    local pageDirt = createTab("Dirt Farm", true)

    addSection(pageDirt, "Aksi Cepat Dirt Farm (SkyP v1.8)")
    local dirtActCard = addCard(pageDirt, 72)
    local dirtBtns = {
        { label = "Plant Dirt",       x = 6,   y = 6,  w = 0.48, col = C.green,  txtCol = Color3.new(0,0,0), fn = function() Core.StartDirtPlant() end },
        { label = "Harvest Dirt",     x = 0.5, y = 6,  w = 0.48, col = C.accent, txtCol = Color3.new(0,0,0), fn = function() Core.StartDirtHarvest() end },
        { label = "Build Upper Dirt", x = 6,   y = 38, w = 0.34, col = C.amber,  txtCol = Color3.new(0,0,0), fn = function() Core.StartBuildUpperDirtFarm() end },
        { label = "Cycle Dirt",       x = 0.37,y = 38, w = 0.33, col = C.accent, txtCol = Color3.new(0,0,0), fn = function() Core.StartDirtCycle() end },
        { label = "STOP DIRT",        x = 0.72,y = 38, w = 0.26, col = C.red,    txtCol = C.text,            fn = function() Core.StopDirtFarm() end },
    }
    for _, bInfo in ipairs(dirtBtns) do
        local posX = bInfo.x >= 1 and UDim2.fromOffset(bInfo.x, bInfo.y) or UDim2.new(bInfo.x, 4, 0, bInfo.y)
        local b = make("TextButton", {
            Size             = UDim2.new(bInfo.w, -6, 0, 26),
            Position         = posX,
            BackgroundColor3 = bInfo.col,
            Font             = Enum.Font.GothamBold,
            TextSize         = 11,
            TextColor3       = bInfo.txtCol,
            Text             = bInfo.label,
        }, dirtActCard)
        corner(b, 5)
        b.MouseButton1Click:Connect(bInfo.fn)
    end

    addSection(pageDirt, "Pengaturan ID & Build Upper Dirt Farm")
    local dSeedRow = addInputRow(pageDirt, "Dirt Seed ID", tostring(S.dirtSeedId), "3", function(txt, box)
        local id = tonumber(string.match(txt, "%d+"))
        if id and id > 0 then S.dirtSeedId = math.floor(id) end
        box.Text = tostring(S.dirtSeedId) .. " (" .. Core.GetItemName(S.dirtSeedId) .. ")"
    end)
    dSeedRow.Box.Text = tostring(S.dirtSeedId) .. " (" .. Core.GetItemName(S.dirtSeedId) .. ")"

    local dBlkRow = addInputRow(pageDirt, "Dirt Block ID", tostring(S.dirtBlockId), "2", function(txt, box)
        local id = tonumber(string.match(txt, "%d+"))
        if id and id > 0 then S.dirtBlockId = math.floor(id) end
        box.Text = tostring(S.dirtBlockId) .. " (" .. Core.GetItemName(S.dirtBlockId) .. ")"
    end)
    dBlkRow.Box.Text = tostring(S.dirtBlockId) .. " (" .. Core.GetItemName(S.dirtBlockId) .. ")"

    addStepper(pageDirt, "Upper Farm Mulai Y (Atas)", S.dirtUpperStartY, 1, 40, 1, "", function(v)
        S.dirtUpperStartY = v
    end)
    addStepper(pageDirt, "Upper Farm Batas Y (Bawah)", S.dirtUpperEndY, 2, 55, 1, "", function(v)
        S.dirtUpperEndY = v
    end)

    local autoDetectBtn = make("TextButton", {
        Size = UDim2.new(1, 0, 0, 26), BackgroundColor3 = C.card,
        Font = Enum.Font.GothamBold, TextSize = 11, TextColor3 = C.accent,
        Text = "Auto Deteksi Batas Y (Di Atas Main Door)",
    }, pageDirt)
    corner(autoDetectBtn, 5)
    autoDetectBtn.MouseButton1Click:Connect(function()
        local y = Core.AutoDetectUpperEndY()
        autoDetectBtn.Text = "Terdeteksi Upper End Y = " .. tostring(y)
        task.delay(2, function()
            if autoDetectBtn then
                autoDetectBtn.Text = "Auto Deteksi Batas Y (Di Atas Main Door)"
            end
        end)
    end)

    addStepper(pageDirt, "Margin Sisi Akses Kiri/Kanan", S.dirtLeftMargin, 0, 8, 1, " tile", function(v)
        S.dirtLeftMargin  = v
        S.dirtRightMargin = v
    end)
    addToggle(pageDirt, "Pasang Wooden Platform (102) di Sisi Akses", S.dirtUsePlat, function(v)
        S.dirtUsePlat = v
    end)
    addStepper(pageDirt, "Cycle: Mulai Panen Saat Pohon Siap", S.dirtHarvestThreshold, 10, 100, 10, "%", function(v)
        S.dirtHarvestThreshold = v
    end)

    -- ─────────────────────────────────────────────────────────────────────────
    --  TAB 2: PETA MINI INTERAKTIF (Pan, Zoom, Mode Lantai / Berdiri / Tile Break)
    -- ─────────────────────────────────────────────────────────────────────────
    local pageMap = createTab("Peta Mini", false)

    local mapMode = "Lantai" -- "Lantai" | "Berdiri" | "Tile break"
    local mapToolbar = make("Frame", {
        Size             = UDim2.new(1, 0, 0, 32),
        BackgroundColor3 = C.panel,
        BorderSizePixel  = 0,
    }, pageMap)
    corner(mapToolbar, 6)
    stroke(mapToolbar, C.border, 1)

    local modeBtns = {}
    local function refreshModeBtns()
        for m, b in pairs(modeBtns) do
            local locked = (m == "Lantai" and S.fullWorld)
            local on = (mapMode == m) and not locked
            b.BackgroundColor3 = locked and C.input or (on and C.accent or C.card)
            b.TextColor3       = locked and C.muted or (on and Color3.new(0, 0, 0) or C.text)
            if m == "Lantai" then
                b.Text = locked and "Lantai [KUNCI]" or "Lantai"
            end
        end
    end

    local modeList = { "Lantai", "Berdiri", "Tile break" }
    for idx, mName in ipairs(modeList) do
        local b = make("TextButton", {
            Size             = UDim2.fromOffset(82, 22),
            Position         = UDim2.fromOffset(6 + (idx - 1) * 86, 5),
            BackgroundColor3 = C.card,
            Font             = Enum.Font.GothamBold,
            TextSize         = 10,
            TextColor3       = C.text,
            Text             = mName,
        }, mapToolbar)
        corner(b, 5)
        modeBtns[mName] = b
        b.MouseButton1Click:Connect(function()
            if mName == "Lantai" and S.fullWorld then return end
            mapMode = mName
            refreshModeBtns()
        end)
    end
    refreshModeBtns()

    local zoomOutBtn = make("TextButton", {
        Size = UDim2.fromOffset(24, 22), Position = UDim2.new(1, -184, 0, 5),
        BackgroundColor3 = C.card, Font = Enum.Font.GothamBold, TextSize = 13, TextColor3 = C.text, Text = "-",
    }, mapToolbar)
    corner(zoomOutBtn, 4)

    local zoomInBtn = make("TextButton", {
        Size = UDim2.fromOffset(24, 22), Position = UDim2.new(1, -156, 0, 5),
        BackgroundColor3 = C.card, Font = Enum.Font.GothamBold, TextSize = 13, TextColor3 = C.text, Text = "+",
    }, mapToolbar)
    corner(zoomInBtn, 4)

    local zoomResetBtn = make("TextButton", {
        Size = UDim2.fromOffset(44, 22), Position = UDim2.new(1, -128, 0, 5),
        BackgroundColor3 = C.card, Font = Enum.Font.GothamBold, TextSize = 10, TextColor3 = C.text, Text = "Reset",
    }, mapToolbar)
    corner(zoomResetBtn, 4)

    local clearRedBtn = make("TextButton", {
        Size = UDim2.fromOffset(74, 22), Position = UDim2.new(1, -80, 0, 5),
        BackgroundColor3 = C.red, Font = Enum.Font.GothamBold, TextSize = 10, TextColor3 = C.text, Text = "Hapus Merah",
    }, mapToolbar)
    corner(clearRedBtn, 4)
    clearRedBtn.MouseButton1Click:Connect(function()
        Core.ClearRedTiles()
    end)

    -- Viewport + Canvas
    local mapView = make("Frame", {
        Size             = UDim2.new(1, 0, 1, -60),
        Position         = UDim2.fromOffset(0, 36),
        BackgroundColor3 = Color3.fromRGB(11, 13, 18),
        ClipsDescendants = true,
        BorderSizePixel  = 0,
    }, pageMap)
    corner(mapView, 6)
    stroke(mapView, C.border, 1)

    local mapCanvas = make("Frame", {
        Size                   = UDim2.fromOffset(500, 300),
        Position               = UDim2.fromOffset(10, 10),
        BackgroundTransparency = 1,
    }, mapView)

    local mapInfoLbl = make("TextLabel", {
        Size                   = UDim2.new(1, 0, 0, 20),
        Position               = UDim2.new(0, 0, 1, -20),
        BackgroundTransparency = 1,
        Font                   = Enum.Font.GothamMedium,
        TextSize               = 10,
        TextColor3             = C.muted,
        TextXAlignment         = Enum.TextXAlignment.Left,
        Text                   = "Geser: Drag peta | Zoom: Scroll / +/- | Biru=Lantai | Ungu=Berdiri | Oranye=Break | Merah=Gagal/Tak terjangkau | Hijau=Pohon",
    }, pageMap)

    -- Map pan & zoom state
    local mapTilePx = 5.2
    local mapPanX, mapPanY = 8, 8

    local function updateCanvasTransform()
        local H = Core.GetHandles()
        local w = (H.gt and H.gt.w) or 100
        local h = (H.gt and H.gt.h) or 60
        mapCanvas.Size = UDim2.fromOffset(w * mapTilePx, h * mapTilePx)
        mapCanvas.Position = UDim2.fromOffset(mapPanX, mapPanY)
    end

    zoomInBtn.MouseButton1Click:Connect(function()
        mapTilePx = clamp(mapTilePx * 1.25, 3, 22)
        updateCanvasTransform()
    end)
    zoomOutBtn.MouseButton1Click:Connect(function()
        mapTilePx = clamp(mapTilePx / 1.25, 3, 22)
        updateCanvasTransform()
    end)
    zoomResetBtn.MouseButton1Click:Connect(function()
        mapTilePx = 5.2
        mapPanX, mapPanY = 8, 8
        updateCanvasTransform()
    end)

    -- Pan (drag) & Tap-to-Select Tile on Map
    do
        local isDown = false
        local moved  = false
        local startScreen, startPan

        mapView.InputBegan:Connect(function(inp)
            if inp.UserInputType == Enum.UserInputType.MouseButton1 or inp.UserInputType == Enum.UserInputType.Touch then
                isDown = true
                moved = false
                startScreen = inp.Position
                startPan = Vector2.new(mapPanX, mapPanY)
            elseif inp.UserInputType == Enum.UserInputType.MouseWheel then
                -- handled in InputChanged
            end
        end)

        mapView.InputChanged:Connect(function(inp)
            if isDown and (inp.UserInputType == Enum.UserInputType.MouseMovement or inp.UserInputType == Enum.UserInputType.Touch) then
                local delta = inp.Position - startScreen
                if delta.Magnitude > 6 then
                    moved = true
                    mapPanX = startPan.X + delta.X
                    mapPanY = startPan.Y + delta.Y
                    updateCanvasTransform()
                end
            elseif inp.UserInputType == Enum.UserInputType.MouseWheel then
                local factor = inp.Position.Z > 0 and 1.15 or (1 / 1.15)
                mapTilePx = clamp(mapTilePx * factor, 3, 22)
                updateCanvasTransform()
            end
        end)

        mapView.InputEnded:Connect(function(inp)
            if isDown and (inp.UserInputType == Enum.UserInputType.MouseButton1 or inp.UserInputType == Enum.UserInputType.Touch) then
                isDown = false
                if not moved then
                    -- Convert screen click to tile (tx, ty)
                    local absPos = mapCanvas.AbsolutePosition
                    local relX = inp.Position.X - absPos.X
                    local relY = inp.Position.Y - absPos.Y
                    local tx = math.floor(relX / mapTilePx)
                    local ty = math.floor(relY / mapTilePx)
                    local H = Core.GetHandles()
                    local w = (H.gt and H.gt.w) or 100
                    local h = (H.gt and H.gt.h) or 60
                    if tx >= 0 and tx < w and ty >= 0 and ty < h then
                        if mapMode == "Lantai" then
                            Core.ToggleFloor(ty)
                        elseif mapMode == "Berdiri" then
                            Core.SetStandPos(tx, ty)
                        elseif mapMode == "Tile break" then
                            Core.ToggleBreakTile(tx, ty)
                        end
                    end
                end
            end
        end)
    end

    -- High-performance pooled map renderer (run-length spans for blocks + overlays)
    local mapPool = {}
    local function getMapBox(idx, z, bgCol, trans)
        local f = mapPool[idx]
        if not f then
            f = Instance.new("Frame")
            f.BorderSizePixel = 0
            f.Parent = mapCanvas
            mapPool[idx] = f
        end
        f.Visible = true
        f.ZIndex = z
        f.BackgroundColor3 = bgCol
        f.BackgroundTransparency = trans or 0
        return f
    end

    local lastMapDraw = 0
    local function renderMiniMap()
        if not pageMap.Visible or not win.Visible then return end
        local now = os.clock()
        if now - lastMapDraw < 0.25 then return end
        lastMapDraw = now

        updateCanvasTransform()
        local H = Core.GetHandles()
        local gt = H.gt
        if not gt or not gt.fg then return end

        local w, h = gt.w, gt.h
        local px = mapTilePx
        local used = 0

        -- 1. Render solid terrain as horizontal run-length spans (fast!)
        for y = 0, h - 1 do
            local row = gt.fg[y]
            if row then
                local x = 0
                while x < w do
                    local id = row[x] or 0
                    local info = id ~= 0 and Core.GetItemInfo(id) or nil
                    if info and (info.solid or info.platform) then
                        local sx = x
                        while x < w do
                            local nid = row[x] or 0
                            local ninfo = nid ~= 0 and Core.GetItemInfo(nid) or nil
                            if not (ninfo and (ninfo.solid or ninfo.platform)) then break end
                            x += 1
                        end
                        used += 1
                        local f = getMapBox(used, 1, Color3.fromRGB(82, 88, 102), 0)
                        f.Position = UDim2.fromOffset(sx * px, y * px)
                        f.Size     = UDim2.fromOffset((x - sx) * px, math.max(1, px))
                    else
                        x += 1
                    end
                end
            end
        end

        -- 2. Render selected floors (Lantai)
        local wd = Core.GetCurrentWorldData()
        if S.fullWorld then
            for y = 1, h - 2 do
                if Core.IsValidFloorRow(y) then
                    used += 1
                    local f = getMapBox(used, 2, C.accent, 0.72)
                    f.Position = UDim2.fromOffset(0, y * px)
                    f.Size     = UDim2.fromOffset(w * px, math.max(1, px))
                end
            end
        else
            for y, on in pairs(wd.floors) do
                if on then
                    used += 1
                    local f = getMapBox(used, 2, C.accent, 0.55)
                    f.Position = UDim2.fromOffset(0, y * px)
                    f.Size     = UDim2.fromOffset(w * px, math.max(1, px))
                end
            end
        end

        -- 3. Render trees (green = growing, bright gold = ready!)
        for y = 0, h - 1 do
            local row = gt.fg[y]
            if row then
                for x = 0, w - 1 do
                    local id = row[x] or 0
                    if id ~= 0 then
                        local info = Core.GetItemInfo(id)
                        if info and info.kind == "seed" then
                            local ripe = Core.IsTreeRipe(x, y)
                            used += 1
                            local f = getMapBox(used, 3, ripe and C.amber or C.green, 0.1)
                            f.Position = UDim2.fromOffset(x * px, y * px)
                            f.Size     = UDim2.fromOffset(math.max(2, px), math.max(2, px))
                        end
                    end
                end
            end
        end

        -- 4. Render Red unreachable tiles
        for key, on in pairs(wd.redTiles) do
            if on then
                local rx, ry = string.match(key, "(-?%d+),(-?%d+)")
                rx, ry = tonumber(rx), tonumber(ry)
                if rx and ry then
                    used += 1
                    local f = getMapBox(used, 4, C.red, 0.15)
                    f.Position = UDim2.fromOffset(rx * px, ry * px)
                    f.Size     = UDim2.fromOffset(math.max(2, px), math.max(2, px))
                end
            end
        end

        -- 5. Render Break tiles (Orange)
        for _, bt in ipairs(wd.breakTiles) do
            used += 1
            local f = getMapBox(used, 5, Color3.fromRGB(251, 146, 60), 0)
            f.Position = UDim2.fromOffset(bt.x * px, bt.y * px)
            f.Size     = UDim2.fromOffset(math.max(3, px), math.max(3, px))
        end

        -- 6. Render Stand Pos (Purple)
        if wd.standPos then
            used += 1
            local f = getMapBox(used, 6, C.purple, 0)
            f.Position = UDim2.fromOffset(wd.standPos.x * px, wd.standPos.y * px)
            f.Size     = UDim2.fromOffset(math.max(3, px), math.max(3, px))
        end

        -- 7. Render Bot live position (Bright Cyan-White)
        local p = Core.ReadPos()
        used += 1
        local botBox = getMapBox(used, 7, Color3.fromRGB(255, 255, 255), 0)
        botBox.Position = UDim2.fromOffset(p.tx * px, p.ty * px)
        botBox.Size     = UDim2.fromOffset(math.max(4, px), math.max(4, px))

        -- Hide unused pooled frames
        for i = used + 1, #mapPool do
            mapPool[i].Visible = false
        end

        local fCount = S.fullWorld and "FULL WORLD" or (tostring(Core.CountSelectedFloors(wd)) .. "/400")
        mapInfoLbl.Text = string.format("Lantai: %s | Break: %d | Merah: %d | Bot: (%d,%d) | Drag=Geser, Scroll/+/-=Zoom",
            fCount, #wd.breakTiles, (function() local c = 0; for _ in pairs(wd.redTiles) do c += 1 end; return c end)(), p.tx, p.ty)
    end

    -- ─────────────────────────────────────────────────────────────────────────
    --  TAB 3: PENJAGA & KEAMANAN TAMBAHAN
    -- ─────────────────────────────────────────────────────────────────────────
    local pageGuard = createTab("Penjaga", true)

    addSection(pageGuard, "Penjaga (Mod Watcher)")
    addToggle(pageGuard, "Mod Watcher (Deteksi Staff/Mod)", S.modWatchOn, function(v)
        Core.SetModWatch(v, S.modAction)
    end)

    local actCard = addCard(pageGuard, 34)
    make("TextLabel", {
        Size = UDim2.new(0.5, 0, 1, 0), Position = UDim2.fromOffset(10, 0),
        BackgroundTransparency = 1, Font = Enum.Font.GothamMedium, TextSize = 12, TextColor3 = C.text,
        TextXAlignment = Enum.TextXAlignment.Left, Text = "Aksi saat Mod masuk",
    }, actCard)
    local sleepBtn = make("TextButton", {
        Size = UDim2.fromOffset(70, 22), Position = UDim2.new(1, -150, 0.5, -11),
        BackgroundColor3 = S.modAction == "SLEEP" and C.accent or C.card,
        Font = Enum.Font.GothamBold, TextSize = 11, TextColor3 = Color3.new(0, 0, 0), Text = "SLEEP",
    }, actCard)
    corner(sleepBtn, 5)
    local leaveBtn = make("TextButton", {
        Size = UDim2.fromOffset(70, 22), Position = UDim2.new(1, -74, 0.5, -11),
        BackgroundColor3 = S.modAction == "LEAVE" and C.accent or C.card,
        Font = Enum.Font.GothamBold, TextSize = 11, TextColor3 = C.text, Text = "LEAVE",
    }, actCard)
    corner(leaveBtn, 5)
    sleepBtn.MouseButton1Click:Connect(function()
        S.modAction = "SLEEP"
        sleepBtn.BackgroundColor3 = C.accent; sleepBtn.TextColor3 = Color3.new(0,0,0)
        leaveBtn.BackgroundColor3 = C.card;   leaveBtn.TextColor3 = C.text
    end)
    leaveBtn.MouseButton1Click:Connect(function()
        S.modAction = "LEAVE"
        leaveBtn.BackgroundColor3 = C.accent; leaveBtn.TextColor3 = Color3.new(0,0,0)
        sleepBtn.BackgroundColor3 = C.card;   sleepBtn.TextColor3 = C.text
    end)

    addSection(pageGuard, "Keamanan Tambahan (Tetap jalan walau Penjaga mati)")
    addToggle(pageGuard, "Jeda Acak (Berlaku juga untuk Break Cepat)", S.sec.randomDelayOn, function(v)
        S.sec.randomDelayOn = v
    end)
    addStepper(pageGuard, "Persentase Jeda Acak (5-60%)", S.sec.randomDelayPct, 5, 60, 5, "%", function(v)
        S.sec.randomDelayPct = v
    end)

    addToggle(pageGuard, "Istirahat Berkala (+-45m kerja, +-3m jeda)", S.sec.periodicBreakOn, function(v)
        S.sec.periodicBreakOn = v
        if v then
            S.sec.nextBreakAt = os.clock() + (S.sec.breakEveryMin * 60 * (0.95 + math.random() * 0.1))
        else
            S.sec.inBreak = false
        end
    end)

    addToggle(pageGuard, "Batas Waktu Jalan + Notif Discord", S.sec.maxRuntimeOn, function(v)
        S.sec.maxRuntimeOn = v
        S.sec.runtimeStopped = false
        S.sec.webhookSent = false
    end)
    addStepper(pageGuard, "Batas Maksimal Jalan (Jam)", S.sec.maxRuntimeHours, 1, 24, 1, " jam", function(v)
        S.sec.maxRuntimeHours = v
    end)
    addInputRow(pageGuard, "Discord Webhook URL", S.sec.discordWebhook, "https://discord.com/api/webhooks/...", function(txt)
        S.sec.discordWebhook = txt
    end)

    local secBtnRow = addCard(pageGuard, 34)
    local testHookBtn = make("TextButton", {
        Size = UDim2.new(0.48, -6, 0, 24), Position = UDim2.new(0, 6, 0.5, -12),
        BackgroundColor3 = C.accent, Font = Enum.Font.GothamBold, TextSize = 11, TextColor3 = Color3.new(0, 0, 0),
        Text = "Test Webhook Discord",
    }, secBtnRow)
    corner(testHookBtn, 5)
    local resetTimerBtn = make("TextButton", {
        Size = UDim2.new(0.48, -6, 0, 24), Position = UDim2.new(0.52, 0, 0.5, -12),
        BackgroundColor3 = C.card, Font = Enum.Font.GothamBold, TextSize = 11, TextColor3 = C.text,
        Text = "Reset Timer Keamanan",
    }, secBtnRow)
    corner(resetTimerBtn, 5)
    testHookBtn.MouseButton1Click:Connect(function()
        task.spawn(function()
            local ok = Core.SendDiscordWebhook("SkyP Test Webhook", "Koneksi Discord Webhook aktif di world `" .. tostring(S.worldName) .. "`.", 3066993)
            testHookBtn.Text = ok and "Terkirim!" or "Gagal Kirim"
            task.delay(2, function() if testHookBtn then testHookBtn.Text = "Test Webhook Discord" end end)
        end)
    end)
    resetTimerBtn.MouseButton1Click:Connect(function() Core.ResetSecurityTimers() end)

    local secStatusCard = addCard(pageGuard, 56)
    local secStatusLbl = make("TextLabel", {
        Size = UDim2.new(1, -16, 1, -8), Position = UDim2.fromOffset(8, 4),
        BackgroundTransparency = 1, Font = Enum.Font.Code, TextSize = 11, TextColor3 = C.text,
        TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top, TextWrapped = true,
        Text = "Status keamanan...",
    }, secStatusCard)

    -- ─────────────────────────────────────────────────────────────────────────
    --  TAB 4: TOOLS & TAS (Pilih Seed/Block dari Tas & ItemDB + Diagnostics)
    -- ─────────────────────────────────────────────────────────────────────────
    local pageTools = createTab("Tools", true)

    addSection(pageTools, "Diagnostik Backend & Koneksi Paket")
    local diagCard = addCard(pageTools, 54)
    local diagLbl = make("TextLabel", {
        Size = UDim2.new(1, -96, 1, -8), Position = UDim2.fromOffset(8, 4),
        BackgroundTransparency = 1, Font = Enum.Font.Code, TextSize = 11, TextColor3 = C.text,
        TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top, TextWrapped = true,
        Text = "Scanning...",
    }, diagCard)
    local rescanBtn = make("TextButton", {
        Size = UDim2.fromOffset(82, 26), Position = UDim2.new(1, -88, 0.5, -13),
        BackgroundColor3 = C.accent, Font = Enum.Font.GothamBold, TextSize = 11, TextColor3 = Color3.new(0, 0, 0),
        Text = "Re-Scan",
    }, diagCard)
    corner(rescanBtn, 5)
    rescanBtn.MouseButton1Click:Connect(function() Core.Discover() end)

    addSection(pageTools, "Gerak & World")
    addToggle(pageTools, "Fly (WASD / Space)", S.fly, function(v) Core.SetFly(v, S.flySpeed) end)
    addStepper(pageTools, "Fly Speed", S.flySpeed, 8, 60, 2, "", function(v)
        S.flySpeed = v
        if S.fly then Core.SetFly(true, v) end
    end)

    local warpCard = addCard(pageTools, 34)
    local warpBox = make("TextBox", {
        Size = UDim2.new(1, -92, 0, 24), Position = UDim2.fromOffset(8, 5),
        BackgroundColor3 = C.input, Font = Enum.Font.Code, TextSize = 12, TextColor3 = C.text,
        PlaceholderText = "Nama World untuk Warp...", Text = "",
    }, warpCard)
    corner(warpBox, 5)
    local warpBtn = make("TextButton", {
        Size = UDim2.fromOffset(74, 24), Position = UDim2.new(1, -80, 0, 5),
        BackgroundColor3 = C.green, Font = Enum.Font.GothamBold, TextSize = 11, TextColor3 = Color3.new(0, 0, 0),
        Text = "WARP",
    }, warpCard)
    corner(warpBtn, 5)
    warpBtn.MouseButton1Click:Connect(function()
        task.spawn(function() Core.EnterWorld(warpBox.Text) end)
    end)

    addSection(pageTools, "Auto Vending (Kebal Istirahat Berkala)")
    local vItemRow = addInputRow(pageTools, "Item ID Restock Vend", tostring(S.vendItemId), "3", function(txt, box)
        local id = tonumber(string.match(txt, "%d+"))
        if id and id > 0 then S.vendItemId = math.floor(id) end
        box.Text = tostring(S.vendItemId) .. " (" .. Core.GetItemName(S.vendItemId) .. ")"
    end)
    vItemRow.Box.Text = tostring(S.vendItemId) .. " (" .. Core.GetItemName(S.vendItemId) .. ")"
    addStepper(pageTools, "Sisakan Stok Minimal di Tas", S.vendMinBag, 0, 190, 5, "", function(v)
        S.vendMinBag = v
    end)
    local vendCtrlCard = addCard(pageTools, 34)
    local startVendBtn = make("TextButton", {
        Size = UDim2.new(0.48, -6, 0, 24), Position = UDim2.new(0, 6, 0.5, -12),
        BackgroundColor3 = C.green, Font = Enum.Font.GothamBold, TextSize = 11, TextColor3 = Color3.new(0,0,0),
        Text = "START AUTO VEND",
    }, vendCtrlCard)
    corner(startVendBtn, 5)
    local stopVendBtn = make("TextButton", {
        Size = UDim2.new(0.48, -6, 0, 24), Position = UDim2.new(0.52, 0, 0.5, -12),
        BackgroundColor3 = C.red, Font = Enum.Font.GothamBold, TextSize = 11, TextColor3 = C.text,
        Text = "STOP VEND",
    }, vendCtrlCard)
    corner(stopVendBtn, 5)
    startVendBtn.MouseButton1Click:Connect(function() Core.StartAutoVend() end)
    stopVendBtn.MouseButton1Click:Connect(function() Core.StopAutoVend() end)

    addSection(pageTools, "Isi Tas & Cari ItemDB (Klik untuk Set Seed / Block ID)")
    local searchCard = addCard(pageTools, 34)
    local searchBox = make("TextBox", {
        Size = UDim2.new(1, -16, 0, 24), Position = UDim2.fromOffset(8, 5),
        BackgroundColor3 = C.input, Font = Enum.Font.Code, TextSize = 12, TextColor3 = C.text,
        PlaceholderText = "Cari nama/ID di ItemDB (kosong = tampilkan Isi Tas)...", Text = "",
    }, searchCard)
    corner(searchBox, 5)

    local invListCard = addCard(pageTools, 150)
    local invScroll = make("ScrollingFrame", {
        Size = UDim2.new(1, -8, 1, -8), Position = UDim2.fromOffset(4, 4),
        BackgroundTransparency = 1, BorderSizePixel = 0, ScrollBarThickness = 4,
        AutomaticCanvasSize = Enum.AutomaticSize.Y, CanvasSize = UDim2.new(0, 0, 0, 0),
    }, invListCard)
    make("UIListLayout", { Padding = UDim.new(0, 3) }, invScroll)

    local function refreshInvList()
        for _, ch in ipairs(invScroll:GetChildren()) do
            if ch:IsA("Frame") then ch:Destroy() end
        end
        local q = (searchBox.Text or ""):gsub("^%s+", ""):gsub("%s+$", "")
        local items = (q ~= "") and Core.SearchItems(q) or Core.GetInventoryList()
        for _, it in ipairs(items) do
            local r = make("Frame", {
                Size = UDim2.new(1, -4, 0, 24), BackgroundColor3 = C.card, BorderSizePixel = 0,
            }, invScroll)
            corner(r, 4)
            local qtyText = it.n and (" x" .. tostring(it.n)) or (it.kind and (" (" .. tostring(it.kind) .. ")") or "")
            make("TextLabel", {
                Size = UDim2.new(1, -110, 1, 0), Position = UDim2.fromOffset(6, 0),
                BackgroundTransparency = 1, Font = Enum.Font.Code, TextSize = 11, TextColor3 = C.text,
                TextXAlignment = Enum.TextXAlignment.Left,
                Text = string.format("[%d] %s%s", it.id, it.name, qtyText),
            }, r)
            local bSeed = make("TextButton", {
                Size = UDim2.fromOffset(46, 18), Position = UDim2.new(1, -100, 0.5, -9),
                BackgroundColor3 = C.green, Font = Enum.Font.GothamBold, TextSize = 10, TextColor3 = Color3.new(0,0,0),
                Text = "Seed",
            }, r)
            corner(bSeed, 4)
            local bBlk = make("TextButton", {
                Size = UDim2.fromOffset(46, 18), Position = UDim2.new(1, -50, 0.5, -9),
                BackgroundColor3 = C.accent, Font = Enum.Font.GothamBold, TextSize = 10, TextColor3 = Color3.new(0,0,0),
                Text = "Block",
            }, r)
            corner(bBlk, 4)
            bSeed.MouseButton1Click:Connect(function()
                S.seedId = it.id
                seedRow.Box.Text = tostring(S.seedId) .. " (" .. Core.GetItemName(S.seedId) .. ")"
            end)
            bBlk.MouseButton1Click:Connect(function()
                S.blockId = it.id
                blkRow.Box.Text = tostring(S.blockId) .. " (" .. Core.GetItemName(S.blockId) .. ")"
            end)
        end
    end

    searchBox:GetPropertyChangedSignal("Text"):Connect(refreshInvList)

    local refInvBtn = make("TextButton", {
        Size = UDim2.new(1, 0, 0, 26), BackgroundColor3 = C.card,
        Font = Enum.Font.GothamBold, TextSize = 11, TextColor3 = C.accent, Text = "Refresh Isi Tas",
    }, pageTools)
    corner(refInvBtn, 5)
    refInvBtn.MouseButton1Click:Connect(refreshInvList)

    -- ─────────────────────────────────────────────────────────────────────────
    --  TAB 6: SCANNER (Audit Eksposur Lock, Akses & Atribut Player - Kat. D/E)
    -- ─────────────────────────────────────────────────────────────────────────
    local pageScanner = createTab("Scanner", true)

    addSection(pageScanner, "Audit Eksposur Client (Read-Only Kat. D & E)")

    local scanState = {
        result = nil,
        mode   = "ALL", -- "ALL" | "LOCKS" | "PLAYERS"
        query  = "",
    }

    local scanActionCard = addCard(pageScanner, 66)
    local function makeActionBtn(text, color, textColor, pos, size)
        local b = make("TextButton", {
            Size = size, Position = pos,
            BackgroundColor3 = color, Font = Enum.Font.GothamBold,
            TextSize = 11, TextColor3 = textColor, Text = text,
        }, scanActionCard)
        corner(b, 5)
        return b
    end
    local btnScanAll   = makeActionBtn("Scan Semua (Full)", C.accent, Color3.new(0, 0, 0), UDim2.new(0, 6, 0, 6), UDim2.new(0.5, -9, 0, 25))
    local btnScanTile  = makeActionBtn("Cek Tile Posisi Ini", C.green, Color3.new(0, 0, 0), UDim2.new(0.5, 3, 0, 6), UDim2.new(0.5, -9, 0, 25))
    local btnCopyScan  = makeActionBtn("Salin Laporan", C.panel, C.text, UDim2.new(0, 6, 0, 35), UDim2.new(0.5, -9, 0, 25))
    local btnExportTxt = makeActionBtn("Export .txt", C.purple, C.text, UDim2.new(0.5, 3, 0, 35), UDim2.new(0.5, -9, 0, 25))

    local scanStatusLbl = make("TextLabel", {
        Size = UDim2.new(1, 0, 0, 20), BackgroundTransparency = 1,
        Font = Enum.Font.Code, TextSize = 11, TextColor3 = C.muted,
        TextXAlignment = Enum.TextXAlignment.Left,
        Text = "Siap memindai data client (gt.lock, gt.areas, Players).",
    }, pageScanner)

    -- Filter & Search bar
    local scanFilterCard = addCard(pageScanner, 64)
    local scanSearchBox = make("TextBox", {
        Size = UDim2.new(1, -12, 0, 24), Position = UDim2.fromOffset(6, 6),
        BackgroundColor3 = C.input, Font = Enum.Font.Code, TextSize = 11, TextColor3 = C.text,
        PlaceholderText = "Filter nama owner / access / player / UserId / atribut...",
        Text = "", ClearTextOnFocus = false,
    }, scanFilterCard)
    corner(scanSearchBox, 5)

    local filterBtns = {}
    local filterDefs = {
        { id = "ALL",     label = "Semua",            x = 0 },
        { id = "LOCKS",   label = "Lock & Akses",     x = 1 / 3 },
        { id = "PLAYERS", label = "Player & Atribut", x = 2 / 3 },
    }
    for _, fd in ipairs(filterDefs) do
        local fb = make("TextButton", {
            Size = UDim2.new(1 / 3, -6, 0, 22), Position = UDim2.new(fd.x, 4, 0, 35),
            BackgroundColor3 = C.panel, Font = Enum.Font.GothamBold, TextSize = 10,
            TextColor3 = C.text, Text = fd.label,
        }, scanFilterCard)
        corner(fb, 4)
        filterBtns[fd.id] = fb
    end

    local function updateFilterStyles()
        for id, fb in pairs(filterBtns) do
            local on = (scanState.mode == id)
            fb.BackgroundColor3 = on and C.accent or C.panel
            fb.TextColor3       = on and Color3.new(0, 0, 0) or C.text
        end
    end

    -- Dynamic auto-height container helper for clean cards inside ScrollingFrame
    local function makeDynamicBox(parent)
        local box = make("Frame", {
            Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y,
            BackgroundTransparency = 1,
        }, parent)
        make("UIListLayout", { Padding = UDim.new(0, 5), SortOrder = Enum.SortOrder.LayoutOrder }, box)
        return box
    end

    local function clearChildren(frame)
        for _, ch in ipairs(frame:GetChildren()) do
            if not ch:IsA("UIListLayout") and not ch:IsA("UIPadding") and not ch:IsA("UICorner") then
                ch:Destroy()
            end
        end
    end

    local function makeInfoCard(parent, accentColor, headerText, bodyText)
        local card = make("Frame", {
            Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y,
            BackgroundColor3 = C.card, BorderSizePixel = 0,
        }, parent)
        corner(card, 6)
        local bar = make("Frame", {
            Size = UDim2.new(0, 4, 1, 0), Position = UDim2.fromOffset(0, 0),
            BackgroundColor3 = accentColor, BorderSizePixel = 0,
        }, card)
        corner(bar, 2)
        local inner = make("Frame", {
            Size = UDim2.new(1, -12, 0, 0), Position = UDim2.fromOffset(10, 0),
            AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1,
        }, card)
        pad(inner, 6, 6, 4, 6)
        make("UIListLayout", { Padding = UDim.new(0, 3), SortOrder = Enum.SortOrder.LayoutOrder }, inner)
        make("TextLabel", {
            Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y,
            BackgroundTransparency = 1, Font = Enum.Font.GothamBold, TextSize = 11,
            TextColor3 = accentColor, TextXAlignment = Enum.TextXAlignment.Left,
            TextWrapped = true, Text = headerText,
        }, inner)
        if bodyText and bodyText ~= "" then
            make("TextLabel", {
                Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y,
                BackgroundTransparency = 1, Font = Enum.Font.Code, TextSize = 10,
                TextColor3 = C.text, TextXAlignment = Enum.TextXAlignment.Left,
                TextWrapped = true, Text = bodyText,
            }, inner)
        end
        return card
    end

    local summaryBox = makeDynamicBox(pageScanner)
    local tileBox    = makeDynamicBox(pageScanner)
    local lockHeader = addSection(pageScanner, "Pemilik Lock & Daftar Akses (Kat. D / E)")
    local lockBox    = makeDynamicBox(pageScanner)
    local plyHeader  = addSection(pageScanner, "Player & Atribut Tereplikasi (Kat. E)")
    local plyBox     = makeDynamicBox(pageScanner)

    local function matchesQuery(haystack)
        if scanState.query == "" then return true end
        return string.find(string.lower(tostring(haystack or "")), scanState.query, 1, true) ~= nil
    end

    local function renderScanResults()
        updateFilterStyles()
        clearChildren(summaryBox)
        clearChildren(tileBox)
        clearChildren(lockBox)
        clearChildren(plyBox)

        local res = scanState.result
        if not res then
            makeInfoCard(summaryBox, C.muted, "Belum ada hasil scan", "Tekan 'Scan Semua (Full)' atau 'Cek Tile Posisi Ini'.")
            return
        end

        local lRes = res.lock or {}
        local pRes = res.players or {}
        local tRes = res.tile or {}
        local showLocks   = (scanState.mode == "ALL" or scanState.mode == "LOCKS")
        local showPlayers = (scanState.mode == "ALL" or scanState.mode == "PLAYERS")
        lockHeader.Visible = showLocks
        lockBox.Visible    = showLocks
        plyHeader.Visible  = showPlayers
        plyBox.Visible     = showPlayers

        -- 1. Ringkasan Audit
        local suiText = (pRes.localStaffUI and pRes.localStaffUI.present)
            and string.format("Ada (Rank=%s)", tostring(pRes.localStaffUI.rank))
            or "Tidak ada"
        local sumHeader = string.format(
            "World: %s (%dx%d) | Lock: %d | Access: %d | Public: %d",
            tostring(lRes.worldName or "?"), lRes.width or 0, lRes.height or 0,
            lRes.totalLocks or 0, lRes.totalAccessEntries or 0, lRes.publicLocks or 0
        )
        local sumLines = {
            string.format("Tile Terproteksi: %d | Player Online: %d | Total Atribut: %d (%d sensitif) | StaffUI: %s",
                lRes.totalProtectedTiles or 0, pRes.playerCount or 0,
                pRes.totalAttributesExposed or 0, pRes.sensitiveAttrCount or 0, suiText),
        }
        for _, f in ipairs(res.findings or {}) do
            table.insert(sumLines, string.format("• [%s %s | Conf %d%%] %s", f.id, f.category, f.confidence, f.title))
        end
        makeInfoCard(summaryBox, C.accent, sumHeader, table.concat(sumLines, "\n"))

        -- 2. Tile Saat Ini
        if tRes.ok then
            local tAccent = tRes.canEdit and C.green or C.red
            local tHead = string.format("Tile (%d, %d) | canEdit=%s | FG: %s (%d) | BG: %s (%d)",
                tRes.x, tRes.y, tostring(tRes.canEdit), tostring(tRes.fgName), tRes.fgId, tostring(tRes.bgName), tRes.bgId)
            local tBody
            if tRes.lock then
                tBody = string.format("Pemegang: [%s] Owner: %s (%s) | LocalRole: %s | Public=%s | BuildOnly=%s",
                    tRes.lock.kind, tRes.lock.ownerName, tostring(tRes.lock.owner),
                    tRes.lock.localRole, tostring(tRes.lock.public), tostring(tRes.lock.buildOnly))
            else
                tBody = "Tile ini tidak berada dalam AreaLock maupun WorldLock (terbuka)."
            end
            makeInfoCard(tileBox, tAccent, tHead, tBody)
        end

        -- 3. Daftar Lock & Access
        if showLocks then
            local locks = {}
            if lRes.worldLock then table.insert(locks, lRes.worldLock) end
            for _, lk in ipairs(lRes.areaLocks or {}) do table.insert(locks, lk) end

            local shown = 0
            for _, lk in ipairs(locks) do
                local accParts = {}
                for _, m in ipairs(lk.access or {}) do
                    table.insert(accParts, string.format("%s (%s)", m.name, tostring(m.userId)))
                end
                local accStr = #accParts > 0 and table.concat(accParts, ", ") or "(kosong)"
                local searchBlob = table.concat({
                    lk.kind, lk.ownerName, tostring(lk.owner), tostring(lk.x), tostring(lk.y), accStr,
                }, " ")

                if matchesQuery(searchBlob) then
                    shown = shown + 1
                    local flags = {}
                    if lk.public then table.insert(flags, "PUBLIC") end
                    if lk.buildOnly then table.insert(flags, "BUILD_ONLY") end
                    if lk.ignoreAir then table.insert(flags, "IGNORE_AIR") end
                    if lk.adminsLimited then table.insert(flags, "ADMINS_LIMITED") end
                    local flagStr = #flags > 0 and table.concat(flags, ", ") or "PRIVATE"

                    local accent = (lk.public and C.red) or (lk.kind == "WorldLock" and C.amber) or C.accent
                    local head = string.format("[%s @ %s,%s] Owner: %s (%s) | Role: %s",
                        lk.kind, tostring(lk.x or "-"), tostring(lk.y or "-"),
                        lk.ownerName, tostring(lk.owner), lk.localRole)
                    local body = string.format("Tiles: %d | Flags: %s\nAccess (%d): %s",
                        lk.tileCount or 0, flagStr, lk.accessCount or 0, accStr)
                    makeInfoCard(lockBox, accent, head, body)
                end
            end
            if shown == 0 then
                makeInfoCard(lockBox, C.muted, "Tidak ada Lock / Access yang cocok",
                    lRes.ok and "World tidak punya lock atau filter tidak cocok." or tostring(lRes.error or ""))
            end
        end

        -- 4. Daftar Player & Atribut
        if showPlayers then
            local shown = 0
            for _, p in ipairs(pRes.players or {}) do
                local attrLines = {}
                local hasSens = false
                for _, a in ipairs(p.attributes or {}) do
                    if a.sensitive then hasSens = true end
                    local prefix = a.sensitive and "[!] " or "    "
                    local note = a.label and (" (" .. a.label .. ")") or ""
                    table.insert(attrLines, string.format("%s%s = %s%s", prefix, a.key, a.value, note))
                end
                local attrStr = #attrLines > 0 and table.concat(attrLines, "\n") or "(tidak ada atribut tereplikasi)"
                local searchBlob = table.concat({ p.name, p.displayName, tostring(p.userId), attrStr }, " ")

                if matchesQuery(searchBlob) then
                    shown = shown + 1
                    local accent = p.isLocalPlayer and C.green or (hasSens and C.purple or C.border)
                    local head = string.format("%s (@%s) [UserId: %s]%s — %d attr",
                        p.name, p.displayName, tostring(p.userId),
                        p.isLocalPlayer and " [ME]" or "", p.attrCount or 0)
                    makeInfoCard(plyBox, accent, head, attrStr)
                end
            end
            if shown == 0 then
                makeInfoCard(plyBox, C.muted, "Tidak ada Player yang cocok", "Coba kosongkan kotak filter.")
            end
        end
    end

    local function runScan(onlyTile)
        local res = scanState.result
        if onlyTile and res then
            res.tile = Core.ScanTileAccess()
            res.reportText = Core.BuildExposureReportText(res)
        else
            res = Core.RunFullExposureScan()
            scanState.result = res
        end
        renderScanResults()
        scanStatusLbl.TextColor3 = C.green
        scanStatusLbl.Text = string.format("Scan selesai @ %s | %d lock, %d player.",
            os.date("%H:%M:%S"), res.lock and res.lock.totalLocks or 0, res.players and res.players.playerCount or 0)
    end

    btnScanAll.MouseButton1Click:Connect(function() runScan(false) end)
    btnScanTile.MouseButton1Click:Connect(function() runScan(true) end)
    btnCopyScan.MouseButton1Click:Connect(function()
        if not scanState.result then runScan(false) end
        local txt = Core.BuildExposureReportText(scanState.result)
        if type(setclipboard) == "function" then
            local ok = pcall(setclipboard, txt)
            scanStatusLbl.TextColor3 = ok and C.green or C.red
            scanStatusLbl.Text = ok and "Laporan scan berhasil disalin ke clipboard." or "Gagal menyalin ke clipboard."
        else
            scanStatusLbl.TextColor3 = C.amber
            scanStatusLbl.Text = "setclipboard tidak tersedia; gunakan Export .txt."
        end
    end)
    btnExportTxt.MouseButton1Click:Connect(function()
        if not scanState.result then runScan(false) end
        local ok, info = Core.ExportExposureReport(scanState.result)
        scanStatusLbl.TextColor3 = ok and C.green or C.amber
        scanStatusLbl.Text = ok and ("Tersimpan: " .. tostring(info)) or ("Export gagal: " .. tostring(info))
    end)

    for id, fb in pairs(filterBtns) do
        fb.MouseButton1Click:Connect(function()
            scanState.mode = id
            renderScanResults()
        end)
    end
    scanSearchBox:GetPropertyChangedSignal("Text"):Connect(function()
        scanState.query = string.lower(scanSearchBox.Text or "")
        renderScanResults()
    end)

    renderScanResults()

    -- Default tab
    selectTab("Pabrik")

    -- ─────────────────────────────────────────────────────────────────────────
    --  LIVE UI REFRESH LOOP
    -- ─────────────────────────────────────────────────────────────────────────
    local lastUiTick = 0
    local conn
    conn = RunService.Heartbeat:Connect(function()
        if not gui.Parent then
            conn:Disconnect()
            return
        end
        renderMiniMap()

        local now = os.clock()
        if now - lastUiTick < 0.25 then return end
        lastUiTick = now

        Core.ReadPos()
        local H = Core.GetHandles()
        if H.gt and H.gt.name ~= "" and S.worldName ~= H.gt.name then
            Core.Discover()
            refreshInvList()
        end

        titleLbl.Text = string.format("SkyP v1.8  |  World: %s (%d,%d)",
            (S.worldName ~= "" and S.worldName or "—"), S.pos.tx, S.pos.ty)

        statusLine.Text = Core.GetOneLineStatus()
        local anyRunning = S.pabrikRunning or S.dirtRunning or S.vendRunning or S.gridRunning
        statusLine.TextColor3 = (S.waitReason and S.waitReason ~= "") and C.amber or (anyRunning and C.green or C.accent)

        if detailDrawer.Visible then
            detailText.Text = string.format(
                "Fase: %s | Alasan: %s\nPanen: %d | Tanam: %d | Break: %d | Di-drop: %d\nTas Seed: %d/200 | Tas Block: %d/200",
                tostring(S.phase),
                tostring(S.waitReason or "-"),
                S.stats.harvested, S.stats.planted, S.stats.broken, S.stats.dropped,
                Core.CountItem(S.seedId), Core.CountItem(S.blockId)
            )
        end

        refreshModeBtns()

        local secSt = Core.GetSecurityStatus()
        secStatusLbl.Text = string.format(
            "Total Jalan: %s | Istirahat Berikutnya: %s\nSisa Batas Waktu: %s | Status: %s",
            secSt.totalRunText,
            secSt.inBreak and ("ISTIRAHAT (" .. tostring(secSt.breakRemText) .. ")") or secSt.nextBreakText,
            secSt.maxLeftText,
            secSt.runtimeStopped and "BERHENTI (Batas Waktu)" or "Aktif"
        )

        local d = S.diag
        diagLbl.Text = string.format(
            "gt:%s  Net:%s  ItemDB:%s\ninv:%s  trees:%s  render:%s",
            d.gt and "OK" or "NO", d.net and "OK" or "NO", d.itemDB and "OK" or "NO",
            d.inv and "OK" or "NO", d.trees and "OK" or "NO", d.render and "OK" or "NO"
        )
    end)

    task.defer(refreshInvList)
    return gui
end
