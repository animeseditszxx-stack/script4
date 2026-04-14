--[[
    Arsenal Script By Toddyx
    Version: 4.0 ULTIMATE
    Architecture: Event-Driven + Cache + Adaptive Performance
]]

-- ========================
-- CORE SERVICES
-- ========================
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local UIS = game:GetService("UserInputService")
local Lighting = game:GetService("Lighting")
local TweenService = game:GetService("TweenService")
local Stats = game:GetService("Stats")
local Cam = game.Workspace.CurrentCamera
local LP = Players.LocalPlayer
local isMobile = UIS.TouchEnabled and not UIS.KeyboardEnabled

-- ========================
-- CONFIG MANAGER
-- ========================
local ConfigManager = {
    data = {
        Aim = {
            Enabled = false, FOV = 100, Smooth = 0.1, Bone = "Head",
            Prediction = false, VisibleCheck = false,
            Keybind = Enum.UserInputType.MouseButton2,
            TargetLock = false, TargetLockKey = Enum.KeyCode.E,
            Priority = "Closest to Crosshair", AntiSwitch = true,
            AntiSwitchTime = 1.5, DynamicSmooth = false,
            AimDelay = 0, RandomOffset = 0, HitChance = 100,
            ClutchMode = false, ClutchHP = 30,
            ReactionMin = 50, ReactionMax = 150,
            Humanizer = false, TremorStrength = 0.2,
            AdaptiveAim = false, MultiBoneScan = false,
        },
        ESP = {
            Enabled = false, Boxes = false, Tracers = false,
            Names = false, Skeleton = false, HealthBar = false,
            Distance = false, Offscreen = false, Chams = false,
            VisibleOnly = false, FadeDistance = false,
            PriorityHighlight = false, PriorityRange = 30,
            TeamCheck = true, Color = Color3.fromRGB(255,0,0),
            SkeletonColor = Color3.fromRGB(255,255,255),
            KeyToggle = false, KeyBind = Enum.KeyCode.Z,
            Visible = true, TrailESP = false, LastPosition = false,
            DangerZone = false, GradientHP = false,
        },
        Player = {
            WalkSpeed = 16, WSEnabled = false,
            JumpPower = 50, JPEnabled = false,
            FlyEnabled = false, FlySpeed = 50,
            Noclip = false, AntiRagdoll = false,
            AntiFall = false, BunnyHop = false,
            Strafe = false, VelocityControl = false,
            VelocityAmount = 1.0, AntiLock = false,
            FakeMovement = false, MovementRandomizer = false,
            QuickStop = false, SpeedBurst = false,
            SpeedBurstAmount = 80,
        },
        Combat = {
            Hitbox = false, HitboxTeamCheck = true,
            NoRecoil = false, NoSpread = false,
            HitSound = false, Hitmarker = false,
            AutoReload = false, BestWeapon = false,
        },
        Performance = {
            FPSBoost = false, AdaptiveFPS = false,
            FPSLimit = 0, DynamicRender = false,
            TargetFPS = 60,
        },
        Misc = {
            AntiAFK = false, DebugMode = false,
            KeybindOverlay = false, SpectatorDetection = false,
            EnemyWarning = false, EnemyWarningRange = 50,
            StreamMode = false, StreamKey = Enum.KeyCode.F8,
            PanicKey = Enum.KeyCode.F9,
            RiskSystem = false, FakeLegit = false,
            AntiSpectator = false,
        },
        Mode = "Legit",
        DevAccess = false,
    }
}

function ConfigManager:get(path)
    local keys = string.split(path, ".")
    local cur = self.data
    for _, k in pairs(keys) do
        if cur[k] == nil then return nil end
        cur = cur[k]
    end
    return cur
end

function ConfigManager:set(path, value)
    local keys = string.split(path, ".")
    local cur = self.data
    for i = 1, #keys - 1 do
        cur = cur[keys[i]]
    end
    cur[keys[#keys]] = value
end

function ConfigManager:export()
    local ok, encoded = pcall(function()
        return game:GetService("HttpService"):JSONEncode(self.data)
    end)
    if ok then setclipboard(encoded) end
    return ok and encoded or nil
end

function ConfigManager:import(str)
    local ok, decoded = pcall(function()
        return game:GetService("HttpService"):JSONDecode(str)
    end)
    if ok and type(decoded) == "table" then
        for k, v in pairs(decoded) do
            if type(self.data[k]) == "table" then
                for k2, v2 in pairs(v) do
                    self.data[k][k2] = v2
                end
            end
        end
        return true
    end
    return false
end

local C = ConfigManager.data

-- ========================
-- STATE
-- ========================
local State = {
    currentTarget = nil,
    lastTargetSwitch = 0,
    lockedTarget = nil,
    lockActive = false,
    spectators = {},
    flyConn = nil,
    flyEnabled = false,
    mobileAim = false,
    mobileFlyUp = false,
    mobileFlyDown = false,
    dashCD = false,
    tpConn = nil,
    tpEnabled = false,
    threatTable = {},
    lastSeenPos = {},
    enemyTrails = {},
    lastPositionGhosts = {},
    dangerZoneCircles = {},
    reactionTimer = 0,
    stressLevel = 0,
    behaviorSeed = math.random(1, 9999),
    removedEffects = {},
    originalSizes = {},
    devAccess = false,
    streamMode = false,
    clutchActive = false,
    weakSpot = {},
    fps = 60,
    ping = 0,
    lastFPSCheck = 0,
}

-- ========================
-- UTILS
-- ========================
local Utils = {}

function Utils.isEnemy(p)
    if not p or not p.Character then return false end
    if p.Team == nil or LP.Team == nil then return true end
    return p.Team ~= LP.Team
end

function Utils.isVisible(p)
    if not p or not p.Character then return false end
    local head = p.Character:FindFirstChild("Head")
    if not head then return false end
    local origin = Cam.CFrame.Position
    local dir = (head.Position - origin).Unit * 999
    local ray = Ray.new(origin, dir)
    local hit = workspace:FindPartOnRayWithIgnoreList(ray, {LP.Character, Cam})
    return hit and hit:IsDescendantOf(p.Character)
end

function Utils.getScreenPos(pos)
    return Cam:WorldToViewportPoint(pos)
end

function Utils.getDistance(p)
    local myHRP = LP.Character and LP.Character:FindFirstChild("HumanoidRootPart")
    local hrp = p and p.Character and p.Character:FindFirstChild("HumanoidRootPart")
    if myHRP and hrp then return (hrp.Position - myHRP.Position).Magnitude end
    return math.huge
end

function Utils.getHP(p)
    local hum = p and p.Character and p.Character:FindFirstChild("Humanoid")
    return hum and hum.Health or math.huge
end

function Utils.getCrosshairDist(p, bone)
    if not p or not p.Character then return math.huge end
    local part = p.Character:FindFirstChild(bone) or p.Character:FindFirstChild("Head")
    if not part then return math.huge end
    local pos, vis = Cam:WorldToViewportPoint(part.Position)
    if not vis then return math.huge end
    local center = Vector2.new(Cam.ViewportSize.X/2, Cam.ViewportSize.Y/2)
    return (Vector2.new(pos.X, pos.Y) - center).Magnitude
end

function Utils.randomInRange(a, b)
    return a + math.random() * (b - a)
end

function Utils.lerp(a, b, t)
    return a + (b - a) * t
end

function Utils.getPing()
    local ok, ping = pcall(function()
        return Stats.Network.ServerStatsItem["Data Ping"]:GetValue()
    end)
    return ok and ping or 0
end

-- ========================
-- PERFORMANCE MANAGER
-- ========================
local PerformanceManager = {}
local schedulers = {}
local lastFPSTime = tick()
local frameCount = 0

function PerformanceManager.registerScheduler(name, interval, fn)
    schedulers[name] = {interval = interval, fn = fn, last = 0}
end

function PerformanceManager.tick()
    local now = tick()
    frameCount = frameCount + 1
    if (now - lastFPSTime) >= 1 then
        State.fps = frameCount
        frameCount = 0
        lastFPSTime = now
        State.ping = Utils.getPing()

        -- Adaptive FPS Boost
        if C.Performance.AdaptiveFPS then
            if State.fps < 40 and not C.Performance.FPSBoost then
                PerformanceManager.enableFPSBoost()
            elseif State.fps > 80 and C.Performance.FPSBoost then
                PerformanceManager.disableFPSBoost()
            end
        end
    end

    for name, s in pairs(schedulers) do
        if (now - s.last) >= s.interval then
            s.last = now
            local ok, err = pcall(s.fn)
            if not ok and C.Misc.DebugMode then
                warn("[Scheduler:" .. name .. "] " .. tostring(err))
            end
        end
    end
end

function PerformanceManager.enableFPSBoost()
    C.Performance.FPSBoost = true
    for _, obj in pairs(Lighting:GetDescendants()) do
        if obj:IsA("PostEffect") or obj:IsA("Sky") then
            obj.Enabled = false
            table.insert(State.removedEffects, obj)
        end
    end
    for _, obj in pairs(workspace:GetDescendants()) do
        if obj:IsA("ParticleEmitter") or obj:IsA("Trail") or
           obj:IsA("Smoke") or obj:IsA("Fire") or obj:IsA("Sparkles") then
            obj.Enabled = false
            table.insert(State.removedEffects, obj)
        end
    end
    Lighting.GlobalShadows = false
    Lighting.FogEnd = 9e9
end

function PerformanceManager.disableFPSBoost()
    C.Performance.FPSBoost = false
    for _, obj in pairs(State.removedEffects) do
        pcall(function() obj.Enabled = true end)
    end
    State.removedEffects = {}
    Lighting.GlobalShadows = true
end

-- ========================
-- AUDIO MODULE
-- ========================
local AudioModule = {}
local sounds = {}

function AudioModule.createSound(id, volume, parent)
    local s = Instance.new("Sound")
    s.SoundId = id
    s.Volume = volume or 0.5
    s.Parent = parent or workspace
    return s
end

sounds.hit = AudioModule.createSound("rbxassetid://4612378535", 0.7)
sounds.fov = AudioModule.createSound("rbxassetid://6042053626", 0.4)
sounds.stream = AudioModule.createSound("rbxassetid://3398229412", 0.3)
sounds.clutch = AudioModule.createSound("rbxassetid://1848354536", 0.5)

function AudioModule.play(name)
    if sounds[name] then pcall(function() sounds[name]:Play() end) end
end

-- ========================
-- BRAIN / DECISION ENGINE
-- ========================
local Brain = {}

function Brain.getStressLevel()
    local count = 0
    local myHRP = LP.Character and LP.Character:FindFirstChild("HumanoidRootPart")
    if not myHRP then return 0 end
    for _, p in pairs(Players:GetPlayers()) do
        if p ~= LP and p.Character and Utils.isEnemy(p) then
            if Utils.getDistance(p) < 50 then count = count + 1 end
        end
    end
    return math.clamp(count / 3, 0, 1)
end

function Brain.isThreat(player)
    return State.threatTable[player.Name] == true
end

function Brain.updateThreats()
    for _, p in pairs(Players:GetPlayers()) do
        if p ~= LP and p.Character then
            local char = p.Character
            local hrp = char:FindFirstChild("HumanoidRootPart")
            local myHRP = LP.Character and LP.Character:FindFirstChild("HumanoidRootPart")
            if hrp and myHRP then
                local dir = (myHRP.Position - hrp.Position).Unit
                local lookDir = hrp.CFrame.LookVector
                local dot = dir:Dot(lookDir)
                State.threatTable[p.Name] = dot > 0.7 and Utils.getDistance(p) < 100
            end
        end
    end
end

function Brain.shouldReduceAggression()
    if not C.Misc.RiskSystem then return false end
    return #State.spectators > 1
end

function Brain.getAdaptiveSmooth(target)
    local base = C.Aim.Smooth
    local dist = Utils.getDistance(target)

    if C.Aim.DynamicSmooth then
        base = base * math.clamp(dist / 150, 1, 3)
    end

    -- Stress modifica smooth
    local stress = Brain.getStressLevel()
    base = base + stress * 0.05

    -- Clutch mode
    local myHum = LP.Character and LP.Character:FindFirstChild("Humanoid")
    if C.Aim.ClutchMode and myHum and myHum.Health <= C.Aim.ClutchHP then
        base = base * 0.4
        if not State.clutchActive then
            State.clutchActive = true
            AudioModule.play("clutch")
        end
    else
        State.clutchActive = false
    end

    -- Risk reduction
    if Brain.shouldReduceAggression() then
        base = base * 1.5
    end

    return math.clamp(base, 0.01, 1)
end

function Brain.getHumanizedOffset()
    if not C.Aim.Humanizer then return Vector3.new(0,0,0) end
    local t = tick()
    local seed = State.behaviorSeed
    local stress = Brain.getStressLevel()
    local str = C.Aim.TremorStrength * (1 + stress)
    return Vector3.new(
        math.sin(t * 7.3 + seed) * str,
        math.cos(t * 5.1 + seed) * str,
        math.sin(t * 9.7 + seed) * str * 0.5
    )
end

function Brain.shouldFakeMiss()
    if not C.Misc.FakeLegit then return false end
    return math.random(1, 100) > 85
end

function Brain.getReactionDelay()
    local base = Utils.randomInRange(C.Aim.ReactionMin, C.Aim.ReactionMax) / 1000
    local stress = Brain.getStressLevel()
    return base * (1 - stress * 0.3)
end

-- ========================
-- AIM MODULE
-- ========================
local AimModule = {}
local BONES_LIST = {
    {"Head","UpperTorso"},{"UpperTorso","LowerTorso"},
    {"UpperTorso","RightUpperArm"},{"RightUpperArm","RightLowerArm"},{"RightLowerArm","RightHand"},
    {"UpperTorso","LeftUpperArm"},{"LeftUpperArm","LeftLowerArm"},{"LeftLowerArm","LeftHand"},
    {"LowerTorso","RightUpperLeg"},{"RightUpperLeg","RightLowerLeg"},{"RightLowerLeg","RightFoot"},
    {"LowerTorso","LeftUpperLeg"},{"LeftUpperLeg","LeftLowerLeg"},{"LeftLowerLeg","LeftFoot"},
}

function AimModule.getBonePos(char, bone)
    if bone == "Random" then
        local b = {"Head","UpperTorso","LowerTorso"}
        bone = b[math.random(1,#b)]
    end
    local part = char:FindFirstChild(bone) or char:FindFirstChild("UpperTorso")
    return part and part.Position
end

function AimModule.getBestBone(char)
    if not C.Aim.MultiBoneScan then return C.Aim.Bone end
    local best, bestDist = C.Aim.Bone, math.huge
    local center = Vector2.new(Cam.ViewportSize.X/2, Cam.ViewportSize.Y/2)
    for _, b in pairs({"Head","UpperTorso","LowerTorso"}) do
        local part = char:FindFirstChild(b)
        if part then
            local pos, vis = Cam:WorldToViewportPoint(part.Position)
            if vis then
                local d = (Vector2.new(pos.X,pos.Y) - center).Magnitude
                if d < bestDist then bestDist = d best = b end
            end
        end
    end
    return best
end

function AimModule.getPredicted(p, bone)
    if not p.Character then return nil end
    local hrp = p.Character:FindFirstChild("HumanoidRootPart")
    local bonePos = AimModule.getBonePos(p.Character, bone)
    if not hrp or not bonePos then return nil end

    if C.Aim.Prediction then
        local vel = hrp.Velocity
        local dist = (bonePos - Cam.CFrame.Position).Magnitude
        local ping = State.ping / 1000
        local travelTime = dist / 600 + ping
        -- Prediction V2: considera mudança de direção
        local prevVel = State.lastSeenPos[p.Name] and State.lastSeenPos[p.Name].vel or vel
        local accel = (vel - prevVel)
        return bonePos + vel * travelTime + accel * travelTime * 0.5
    end
    return bonePos
end

function AimModule.getTarget()
    -- Target lock
    if State.lockActive and State.lockedTarget then
        local t = State.lockedTarget
        if t.Character and t.Character:FindFirstChild("Humanoid") and
           t.Character.Humanoid.Health > 0 then
            return t
        else
            State.lockedTarget = nil
            State.lockActive = false
        end
    end

    -- Anti-switch
    local now = tick()
    if C.Aim.AntiSwitch and State.currentTarget and
       (now - State.lastTargetSwitch) < C.Aim.AntiSwitchTime then
        local t = State.currentTarget
        if t.Character and t.Character:FindFirstChild("Humanoid") and
           t.Character.Humanoid.Health > 0 then
            if Utils.getCrosshairDist(t, C.Aim.Bone) <= C.Aim.FOV then
                return t
            end
        end
    end

    local candidates = {}
    for _, p in pairs(Players:GetPlayers()) do
        if p ~= LP and p.Character and Utils.isEnemy(p) then
            if C.Aim.VisibleCheck and not Utils.isVisible(p) then continue end
            local cd = Utils.getCrosshairDist(p, AimModule.getBestBone(p.Character or workspace))
            if cd <= C.Aim.FOV then
                local isThreat = Brain.isThreat(p) and 1 or 0
                table.insert(candidates, {
                    player = p,
                    crossDist = cd,
                    hp = Utils.getHP(p),
                    dist = Utils.getDistance(p),
                    threat = isThreat,
                })
            end
        end
    end

    if #candidates == 0 then return nil end

    -- Priority Engine 2.0
    table.sort(candidates, function(a, b)
        local p = C.Aim.Priority
        if p == "Lowest HP" then
            if a.threat ~= b.threat then return a.threat > b.threat end
            return a.hp < b.hp
        elseif p == "Closest" then
            if a.threat ~= b.threat then return a.threat > b.threat end
            return a.dist < b.dist
        else -- Closest to Crosshair
            if a.threat ~= b.threat then return a.threat > b.threat end
            return a.crossDist < b.crossDist
        end
    end)

    local best = candidates[1].player
    if best ~= State.currentTarget then
        State.lastTargetSwitch = now
        State.currentTarget = best
        State.behaviorSeed = math.random(1, 9999)
    end
    return best
end

function AimModule.doAim(target)
    if Brain.shouldFakeMiss() then return end
    if math.random(1, 100) > C.Aim.HitChance then return end

    local bone = AimModule.getBestBone(target.Character)
    local bonePos = AimModule.getPredicted(target, bone)
    if not bonePos then return end

    local humanOffset = Brain.getHumanizedOffset()
    bonePos = bonePos + humanOffset

    local randomOff = C.Aim.RandomOffset
    if randomOff > 0 then
        bonePos = bonePos + Vector3.new(
            (math.random() - 0.5) * randomOff,
            (math.random() - 0.5) * randomOff,
            0
        )
    end

    local smooth = Brain.getAdaptiveSmooth(target)
    local targetCF = CFrame.new(Cam.CFrame.Position, bonePos)
    Cam.CFrame = Cam.CFrame:Lerp(targetCF, smooth)

    -- Update last seen
    local hrp = target.Character:FindFirstChild("HumanoidRootPart")
    if hrp then
        State.lastSeenPos[target.Name] = {
            pos = hrp.Position,
            vel = hrp.Velocity,
            time = tick()
        }
    end
end

-- ========================
-- DRAWING CACHE SYSTEM
-- ========================
local DrawCache = {}
local drawPool = {lines = {}, circles = {}, squares = {}, texts = {}, triangles = {}}
local activeDrawings = {}

local function getFromPool(type)
    if #drawPool[type] > 0 then
        local d = table.remove(drawPool[type])
        d.Visible = false
        return d
    end
    return Drawing.new(type == "lines" and "Line" or
                       type == "circles" and "Circle" or
                       type == "squares" and "Square" or
                       type == "texts" and "Text" or "Triangle")
end

local function returnToPool(type, drawing)
    drawing.Visible = false
    table.insert(drawPool[type], drawing)
end

-- ========================
-- ESP MODULE
-- ========================
local ESPModule = {}
local espCache = {
    skeletonLines = {},
    healthBars = {},
    distLabels = {},
    offArrows = {},
    trailPoints = {},
    ghostLabels = {},
    dangerCircles = {},
}

function ESPModule.getAlpha(p)
    if State.streamMode then return 0 end
    if not C.ESP.FadeDistance then return 1 end
    local dist = Utils.getDistance(p)
    return math.clamp(1 - dist/400, 0.1, 1)
end

function ESPModule.getPriorityColor(p)
    if not C.ESP.PriorityHighlight then return C.ESP.Color end
    local dist = Utils.getDistance(p)
    local threat = Brain.isThreat(p)
    if threat then return Color3.fromRGB(255, 50, 50) end
    if dist <= C.ESP.PriorityRange then return Color3.fromRGB(255, 150, 0) end
    if C.ESP.GradientHP then
        local hp = Utils.getHP(p)
        local maxHP = p.Character and p.Character:FindFirstChild("Humanoid") and
                      p.Character.Humanoid.MaxHealth or 100
        local pct = math.clamp(hp / maxHP, 0, 1)
        return Color3.fromRGB(255 * (1-pct), 255 * pct, 0)
    end
    return C.ESP.Color
end

function ESPModule.clearType(cacheKey)
    if espCache[cacheKey] then
        for _, d in pairs(espCache[cacheKey]) do
            if type(d) == "table" then
                for _, v in pairs(d) do if v then v.Visible = false end end
            else
                if d then d.Visible = false end
            end
        end
        espCache[cacheKey] = {}
    end
end

function ESPModule.clearAll()
    for key, _ in pairs(espCache) do
        ESPModule.clearType(key)
    end
end

function ESPModule.updateSkeleton()
    ESPModule.clearType("skeletonLines")
    if not C.ESP.Skeleton or not C.ESP.Visible or State.streamMode then return end
    for _, p in pairs(Players:GetPlayers()) do
        if p ~= LP and p.Character and Utils.isEnemy(p) then
            if C.ESP.VisibleOnly and not Utils.isVisible(p) then continue end
            local alpha = ESPModule.getAlpha(p)
            local color = ESPModule.getPriorityColor(p)
            -- Visible vs invisible coloring
            if C.ESP.VisibleOnly == false then
                color = Utils.isVisible(p) and color or Color3.fromRGB(150,150,150)
            end
            for _, bone in pairs(BONES_LIST) do
                local p0 = p.Character:FindFirstChild(bone[1])
                local p1 = p.Character:FindFirstChild(bone[2])
                if p0 and p1 then
                    local s0, v0 = Cam:WorldToViewportPoint(p0.Position)
                    local s1, v1 = Cam:WorldToViewportPoint(p1.Position)
                    if v0 and v1 then
                        local line = getFromPool("lines")
                        line.From = Vector2.new(s0.X, s0.Y)
                        line.To = Vector2.new(s1.X, s1.Y)
                        line.Color = C.ESP.SkeletonColor
                        line.Thickness = 1.5
                        line.Transparency = 1 - alpha
                        line.Visible = true
                        table.insert(espCache.skeletonLines, line)
                    end
                end
            end
        end
    end
end

function ESPModule.updateHealthBars()
    ESPModule.clearType("healthBars")
    if not C.ESP.HealthBar or not C.ESP.Visible or State.streamMode then return end
    for _, p in pairs(Players:GetPlayers()) do
        if p ~= LP and p.Character and Utils.isEnemy(p) then
            if C.ESP.VisibleOnly and not Utils.isVisible(p) then continue end
            local hum = p.Character:FindFirstChild("Humanoid")
            local hrp = p.Character:FindFirstChild("HumanoidRootPart")
            if hum and hrp then
                local pos, vis = Cam:WorldToViewportPoint(hrp.Position)
                if vis then
                    local hp = hum.Health / hum.MaxHealth
                    local alpha = ESPModule.getAlpha(p)
                    local bh, bw = 40, 5
                    local x, y = pos.X - 22, pos.Y - bh/2
                    local bg = getFromPool("squares")
                    bg.Size = Vector2.new(bw, bh)
                    bg.Position = Vector2.new(x, y)
                    bg.Color = Color3.fromRGB(0,0,0)
                    bg.Filled = true
                    bg.Transparency = 0.5
                    bg.Visible = true
                    local fill = getFromPool("squares")
                    fill.Size = Vector2.new(bw, bh * hp)
                    fill.Position = Vector2.new(x, y + bh*(1-hp))
                    fill.Color = Color3.fromRGB(255*(1-hp), 255*hp, 0)
                    fill.Filled = true
                    fill.Transparency = 1 - alpha
                    fill.Visible = true
                    table.insert(espCache.healthBars, {bg, fill})
                end
            end
        end
    end
end

function ESPModule.updateDistance()
    ESPModule.clearType("distLabels")
    if not C.ESP.Distance or not C.ESP.Visible or State.streamMode then return end
    local myHRP = LP.Character and LP.Character:FindFirstChild("HumanoidRootPart")
    if not myHRP then return end
    for _, p in pairs(Players:GetPlayers()) do
        if p ~= LP and p.Character and Utils.isEnemy(p) then
            if C.ESP.VisibleOnly and not Utils.isVisible(p) then continue end
            local hrp = p.Character:FindFirstChild("HumanoidRootPart")
            if hrp then
                local pos, vis = Cam:WorldToViewportPoint(hrp.Position)
                if vis then
                    local dist = math.floor((hrp.Position-myHRP.Position).Magnitude)
                    local t = getFromPool("texts")
                    t.Text = dist .. "m"
                    t.Size = 13
                    t.Color = ESPModule.getPriorityColor(p)
                    t.Outline = true
                    t.Transparency = 1 - ESPModule.getAlpha(p)
                    t.Position = Vector2.new(pos.X+10, pos.Y)
                    t.Visible = true
                    table.insert(espCache.distLabels, t)
                end
            end
        end
    end
end

function ESPModule.updateOffscreen()
    ESPModule.clearType("offArrows")
    if not C.ESP.Offscreen or not C.ESP.Visible or State.streamMode then return end
    local center = Vector2.new(Cam.ViewportSize.X/2, Cam.ViewportSize.Y/2)
    for _, p in pairs(Players:GetPlayers()) do
        if p ~= LP and p.Character and Utils.isEnemy(p) then
            local hrp = p.Character:FindFirstChild("HumanoidRootPart")
            if hrp then
                local pos, vis = Cam:WorldToViewportPoint(hrp.Position)
                if not vis or pos.Z < 0 then
                    local dir = (Vector2.new(pos.X,pos.Y)-center)
                    if dir.Magnitude == 0 then continue end
                    dir = dir.Unit
                    local angle = math.atan2(dir.Y, dir.X)
                    local radius = math.min(center.X, center.Y) - 30
                    local ap = center + Vector2.new(math.cos(angle), math.sin(angle)) * radius
                    local arrow = getFromPool("triangles")
                    arrow.PointA = ap + Vector2.new(math.cos(angle)*10, math.sin(angle)*10)
                    arrow.PointB = ap + Vector2.new(math.cos(angle+2.5)*8, math.sin(angle+2.5)*8)
                    arrow.PointC = ap + Vector2.new(math.cos(angle-2.5)*8, math.sin(angle-2.5)*8)
                    arrow.Color = ESPModule.getPriorityColor(p)
                    arrow.Filled = true
                    arrow.Visible = true
                    table.insert(espCache.offArrows, arrow)
                end
            end
        end
    end
end

function ESPModule.updateChams()
    if not C.ESP.Chams or State.streamMode then return end
    for _, p in pairs(Players:GetPlayers()) do
        if p ~= LP and p.Character and Utils.isEnemy(p) then
            for _, part in pairs(p.Character:GetDescendants()) do
                if part:IsA("BasePart") and part.Name ~= "HumanoidRootPart" then
                    part.Material = Enum.Material.Neon
                    part.Color = ESPModule.getPriorityColor(p)
                end
            end
        end
    end
end

function ESPModule.updateTrails()
    if not C.ESP.TrailESP or State.streamMode then return end
    for _, p in pairs(Players:GetPlayers()) do
        if p ~= LP and p.Character and Utils.isEnemy(p) then
            local hrp = p.Character:FindFirstChild("HumanoidRootPart")
            if hrp then
                if not State.enemyTrails[p.Name] then State.enemyTrails[p.Name] = {} end
                local trail = State.enemyTrails[p.Name]
                table.insert(trail, hrp.Position)
                if #trail > 20 then table.remove(trail, 1) end
                for i = 2, #trail do
                    local s0, v0 = Cam:WorldToViewportPoint(trail[i-1])
                    local s1, v1 = Cam:WorldToViewportPoint(trail[i])
                    if v0 and v1 then
                        local line = Drawing.new("Line")
                        line.From = Vector2.new(s0.X, s0.Y)
                        line.To = Vector2.new(s1.X, s1.Y)
                        line.Color = Color3.fromRGB(100, 200, 255)
                        line.Thickness = 1
                        line.Transparency = 0.3
                        line.Visible = true
                        task.delay(0.5, function() line:Remove() end)
                    end
                end
            end
        end
    end
end

function ESPModule.updateLastPosition()
    if not C.ESP.LastPosition or State.streamMode then return end
    for _, p in pairs(Players:GetPlayers()) do
        if p ~= LP and Utils.isEnemy(p) then
            local data = State.lastSeenPos[p.Name]
            if data and not Utils.isVisible(p) then
                local pos, vis = Cam:WorldToViewportPoint(data.pos)
                if vis then
                    local ghost = Drawing.new("Text")
                    ghost.Text = "? " .. p.Name
                    ghost.Size = 14
                    ghost.Color = Color3.fromRGB(150, 150, 255)
                    ghost.Outline = true
                    ghost.Transparency = 0.3
                    ghost.Position = Vector2.new(pos.X, pos.Y)
                    ghost.Visible = true
                    task.delay(0.08, function() ghost:Remove() end)
                end
            end
        end
    end
end

function ESPModule.updateDangerZone()
    if not C.ESP.DangerZone or State.streamMode then return end
    local myHRP = LP.Character and LP.Character:FindFirstChild("HumanoidRootPart")
    if not myHRP then return end
    for _, p in pairs(Players:GetPlayers()) do
        if p ~= LP and p.Character and Utils.isEnemy(p) then
            local dist = Utils.getDistance(p)
            if dist < C.ESP.PriorityRange then
                local hrp = p.Character:FindFirstChild("HumanoidRootPart")
                if hrp then
                    local pos, vis = Cam:WorldToViewportPoint(hrp.Position)
                    if vis then
                        local c = Drawing.new("Circle")
                        c.Position = Vector2.new(pos.X, pos.Y)
                        c.Radius = math.clamp((C.ESP.PriorityRange - dist) * 2, 10, 60)
                        c.Color = Color3.fromRGB(255, 0, 0)
                        c.Transparency = 0.6
                        c.Filled = true
                        c.Visible = true
                        task.delay(0.05, function() c:Remove() end)
                    end
                end
            end
        end
    end
end

-- ========================
-- PLAYER MODULE
-- ========================
local PlayerModule = {}

local originalBrightness = Lighting.Brightness
local originalAmbient = Lighting.Ambient
local originalOutdoor = Lighting.OutdoorAmbient

function PlayerModule.enableFullbright()
    Lighting.Brightness = 10
    Lighting.Ambient = Color3.fromRGB(255,255,255)
    Lighting.OutdoorAmbient = Color3.fromRGB(255,255,255)
end

function PlayerModule.disableFullbright()
    Lighting.Brightness = originalBrightness
    Lighting.Ambient = originalAmbient
    Lighting.OutdoorAmbient = originalOutdoor
end

function PlayerModule.stopFly()
    State.flyEnabled = false
    if State.flyConn then State.flyConn:Disconnect() State.flyConn = nil end
    local char = LP.Character
    if char then
        local hrp = char:FindFirstChild("HumanoidRootPart")
        local hum = char:FindFirstChild("Humanoid")
        if hrp then
            local bv = hrp:FindFirstChild("FlyBodyVelocity")
            local bg = hrp:FindFirstChild("FlyBodyGyro")
            if bv then bv:Destroy() end
            if bg then bg:Destroy() end
            hrp.AssemblyLinearVelocity = Vector3.new(0,0,0)
        end
        if hum then hum.PlatformStand = false end
    end
end

function PlayerModule.startFly(mobile)
    local char = LP.Character
    if not char then return end
    local hrp = char:FindFirstChild("HumanoidRootPart")
    local hum = char:FindFirstChild("Humanoid")
    if not hrp or not hum then return end
    hum.PlatformStand = true
    local bg = Instance.new("BodyGyro")
    bg.Name = "FlyBodyGyro"
    bg.MaxTorque = Vector3.new(9e9,9e9,9e9)
    bg.D = 100
    bg.CFrame = hrp.CFrame
    bg.Parent = hrp
    local bv = Instance.new("BodyVelocity")
    bv.Name = "FlyBodyVelocity"
    bv.MaxForce = Vector3.new(9e9,9e9,9e9)
    bv.P = 1000
    bv.Velocity = Vector3.new(0,0,0)
    bv.Parent = hrp
    State.flyEnabled = true
    State.flyConn = RunService.RenderStepped:Connect(function()
        if not State.flyEnabled then return end
        local c = LP.Character
        if not c then return end
        local h = c:FindFirstChild("HumanoidRootPart")
        local b = h and h:FindFirstChild("FlyBodyGyro")
        local v = h and h:FindFirstChild("FlyBodyVelocity")
        if not h or not b or not v then return end
        local move = Vector3.new(0,0,0)
        local cf = Cam.CFrame
        if mobile then
            local hu = c:FindFirstChild("Humanoid")
            if hu and hu.MoveDirection.Magnitude > 0 then
                move = move + hu.MoveDirection * C.Player.FlySpeed
            end
            if State.mobileFlyUp then move = move + Vector3.new(0,1,0) end
            if State.mobileFlyDown then move = move - Vector3.new(0,1,0) end
        else
            if UIS:IsKeyDown(Enum.KeyCode.W) then move = move + cf.LookVector end
            if UIS:IsKeyDown(Enum.KeyCode.S) then move = move - cf.LookVector end
            if UIS:IsKeyDown(Enum.KeyCode.A) then move = move - cf.RightVector end
            if UIS:IsKeyDown(Enum.KeyCode.D) then move = move + cf.RightVector end
            if UIS:IsKeyDown(Enum.KeyCode.Space) then move = move + Vector3.new(0,1,0) end
            if UIS:IsKeyDown(Enum.KeyCode.LeftShift) then move = move - Vector3.new(0,1,0) end
        end
        v.Velocity = move.Magnitude > 0 and move.Unit * C.Player.FlySpeed or Vector3.new(0,0,0)
        b.CFrame = CFrame.new(h.Position, h.Position + cf.LookVector)
    end)
end

-- ========================
-- COMBAT MODULE
-- ========================
local CombatModule = {}
local originalSizes = {}

function CombatModule.applyHitbox()
    for _, p in pairs(Players:GetPlayers()) do
        if p ~= LP and p.Character then
            if C.Combat.HitboxTeamCheck and not Utils.isEnemy(p) then continue end
            local parts = {"RightUpperLeg","LeftUpperLeg","HeadHB","HumanoidRootPart"}
            for _, pn in pairs(parts) do
                local part = p.Character:FindFirstChild(pn)
                if part then
                    if not originalSizes[p.Name] then originalSizes[p.Name] = {} end
                    if not originalSizes[p.Name][pn] then
                        originalSizes[p.Name][pn] = part.Size
                    end
                    part.CanCollide = false
                    part.Transparency = 0.75
                    part.Size = Vector3.new(21,21,21)
                end
            end
        end
    end
end

function CombatModule.removeHitbox()
    for _, p in pairs(Players:GetPlayers()) do
        if p.Character and originalSizes[p.Name] then
            for pn, sz in pairs(originalSizes[p.Name]) do
                local part = p.Character:FindFirstChild(pn)
                if part then part.Size = sz part.Transparency = 0 end
            end
        end
    end
    originalSizes = {}
end

function CombatModule.drawHitmarker()
    if not C.Combat.Hitmarker or State.streamMode then return end
    local cx = Cam.ViewportSize.X/2
    local cy = Cam.ViewportSize.Y/2
    local size = 8
    local lines = {
        {Vector2.new(cx-size,cy-size), Vector2.new(cx-3,cy-3)},
        {Vector2.new(cx+3,cy-3), Vector2.new(cx+size,cy-size)},
        {Vector2.new(cx-size,cy+size), Vector2.new(cx-3,cy+3)},
        {Vector2.new(cx+3,cy+3), Vector2.new(cx+size,cy+size)},
    }
    for _, l in pairs(lines) do
        local line = Drawing.new("Line")
        line.From = l[1]
        line.To = l[2]
        line.Color = Color3.fromRGB(255,255,255)
        line.Thickness = 2
        line.Visible = true
        task.delay(0.1, function() line:Remove() end)
    end
end

-- ========================
-- VISUAL MODULE
-- ========================
local VisualModule = {}
local FOVring = Drawing.new("Circle")
FOVring.Visible = false
FOVring.Thickness = 2
FOVring.Color = Color3.fromRGB(255,0,0)
FOVring.Filled = false
FOVring.Radius = 100

local FOVring2 = Drawing.new("Circle")
FOVring2.Visible = false
FOVring2.Thickness = 2
FOVring2.Color = Color3.fromRGB(0,255,0)
FOVring2.Filled = false
FOVring2.Radius = 100

local fpsLabel = Drawing.new("Text")
fpsLabel.Visible = false
fpsLabel.Size = 16
fpsLabel.Color = Color3.fromRGB(255,255,255)
fpsLabel.Outline = true
fpsLabel.Position = Vector2.new(10,10)

local timerLabel = Drawing.new("Text")
timerLabel.Visible = false
timerLabel.Size = 16
timerLabel.Color = Color3.fromRGB(255,255,255)
timerLabel.Outline = true
timerLabel.Position = Vector2.new(10,30)

local warningLabel = Drawing.new("Text")
warningLabel.Visible = false
warningLabel.Size = 20
warningLabel.Color = Color3.fromRGB(255,80,80)
warningLabel.Outline = true
warningLabel.Center = true

local debugLabel = Drawing.new("Text")
debugLabel.Visible = false
debugLabel.Size = 14
debugLabel.Color = Color3.fromRGB(100,255,100)
debugLabel.Outline = true
debugLabel.Position = Vector2.new(10,50)

local sessionStart = os.time()
local crosshairLines = {}
local crosshairEnabled = false
local crosshairColor = Color3.fromRGB(255,255,255)
local crosshairSize = 10
local crosshairGap = 5

function VisualModule.updateCrosshair()
    for _, l in pairs(crosshairLines) do l.Visible = false end
    crosshairLines = {}
    if not crosshairEnabled or State.streamMode then return end
    local cx = Cam.ViewportSize.X/2
    local cy = Cam.ViewportSize.Y/2
    local lines = {
        {Vector2.new(cx-crosshairSize-crosshairGap,cy), Vector2.new(cx-crosshairGap,cy)},
        {Vector2.new(cx+crosshairGap,cy), Vector2.new(cx+crosshairSize+crosshairGap,cy)},
        {Vector2.new(cx,cy-crosshairSize-crosshairGap), Vector2.new(cx,cy-crosshairGap)},
        {Vector2.new(cx,cy+crosshairGap), Vector2.new(cx,cy+crosshairSize+crosshairGap)},
    }
    for _, l in pairs(lines) do
        local line = Drawing.new("Line")
        line.From = l[1]
        line.To = l[2]
        line.Color = crosshairColor
        line.Thickness = 2
        line.Visible = true
        table.insert(crosshairLines, line)
    end
end

function VisualModule.updateWarning()
    if not C.Misc.EnemyWarning or State.streamMode then
        warningLabel.Visible = false
        return
    end
    local nearest, nearestDist = nil, math.huge
    for _, p in pairs(Players:GetPlayers()) do
        if p ~= LP and p.Character and Utils.isEnemy(p) then
            local d = Utils.getDistance(p)
            if d < nearestDist then nearestDist = d nearest = p end
        end
    end
    if nearest and nearestDist <= C.Misc.EnemyWarningRange then
        warningLabel.Text = "ENEMY NEARBY! [" .. math.floor(nearestDist) .. "m] " .. nearest.Name
        warningLabel.Position = Vector2.new(Cam.ViewportSize.X/2, Cam.ViewportSize.Y * 0.15)
        warningLabel.Visible = true
    else
        warningLabel.Visible = false
    end
end

function VisualModule.updateFOV()
    if State.streamMode then
        FOVring.Visible = false
        FOVring2.Visible = false
        return
    end
    FOVring.Position = Cam.ViewportSize / 2
    FOVring2.Position = Cam.ViewportSize / 2
    local t = AimModule.getTarget()
    local hasTarget = t ~= nil
    if FOVring.Visible then
        FOVring.Color = hasTarget and Color3.fromRGB(255,255,0) or Color3.fromRGB(255,0,0)
    end
    if FOVring2.Visible then
        FOVring2.Color = hasTarget and Color3.fromRGB(255,255,0) or Color3.fromRGB(0,255,0)
    end
end

function VisualModule.updateDebug()
    if not C.Misc.DebugMode or State.streamMode then
        debugLabel.Visible = false
        return
    end
    debugLabel.Visible = true
    local t = State.currentTarget
    local targetName = t and t.Name or "None"
    local targetDist = t and math.floor(Utils.getDistance(t)) or 0
    local targetHP = t and math.floor(Utils.getHP(t)) or 0
    local locked = State.lockActive and "YES" or "NO"
    local spec = #State.spectators
    local stress = math.floor(Brain.getStressLevel() * 100)
    debugLabel.Text = string.format(
        "[DEBUG v4.0]\nTarget: %s\nDist: %dm | HP: %d\nLocked: %s | FPS: %d\nPing: %dms | Stress: %d%%\nSpectators: %d | Mode: %s\nStream: %s",
        targetName, targetDist, targetHP, locked, State.fps,
        math.floor(State.ping), stress, spec, C.Mode,
        State.streamMode and "ON" or "OFF"
    )
end

function VisualModule.updateFPS()
    if not fpsLabel.Visible then return end
    fpsLabel.Text = "FPS: " .. State.fps
end

function VisualModule.updateTimer()
    if not timerLabel.Visible then return end
    local e = os.time() - sessionStart
    timerLabel.Text = string.format("Session: %02d:%02d", math.floor(e/60), e%60)
end

-- Radar
local radarEnabled = false
local radarSize = 150
local radarRange = 100
local radarDots = {}

function VisualModule.updateRadar()
    for _, d in pairs(radarDots) do d:Remove() end
    radarDots = {}
    if not radarEnabled or State.streamMode then return end
    local cx = Cam.ViewportSize.X - radarSize/2 - 10
    local cy = radarSize/2 + 10
    local bg = Drawing.new("Circle")
    bg.Position = Vector2.new(cx,cy)
    bg.Radius = radarSize/2
    bg.Color = Color3.fromRGB(0,0,0)
    bg.Transparency = 0.5
    bg.Filled = true
    bg.Visible = true
    table.insert(radarDots, bg)
    local border = Drawing.new("Circle")
    border.Position = Vector2.new(cx,cy)
    border.Radius = radarSize/2
    border.Color = Color3.fromRGB(255,255,255)
    border.Thickness = 1
    border.Filled = false
    border.Visible = true
    table.insert(radarDots, border)
    local myHRP = LP.Character and LP.Character:FindFirstChild("HumanoidRootPart")
    if not myHRP then return end
    for _, p in pairs(Players:GetPlayers()) do
        if p ~= LP and p.Character and Utils.isEnemy(p) then
            local hrp = p.Character:FindFirstChild("HumanoidRootPart")
            if hrp then
                local delta = hrp.Position - myHRP.Position
                if delta.Magnitude <= radarRange then
                    local angle = math.atan2(delta.Z, delta.X)
                    local camAngle = math.atan2(Cam.CFrame.LookVector.Z, Cam.CFrame.LookVector.X)
                    local relAngle = angle - camAngle
                    local scale = (delta.Magnitude/radarRange) * (radarSize/2)
                    local dot = Drawing.new("Circle")
                    dot.Position = Vector2.new(cx+math.cos(relAngle)*scale, cy+math.sin(relAngle)*scale)
                    dot.Radius = 4
                    dot.Color = ESPModule.getPriorityColor(p)
                    dot.Filled = true
                    dot.Visible = true
                    table.insert(radarDots, dot)
                end
            end
        end
    end
end

-- Keybind Overlay
local keybindGui = nil

function VisualModule.createKeybindOverlay()
    if keybindGui then keybindGui:Destroy() end
    keybindGui = Instance.new("ScreenGui")
    keybindGui.Name = "KeybindOverlay"
    keybindGui.ResetOnSpawn = false
    keybindGui.Parent = LP.PlayerGui
    local frame = Instance.new("Frame")
    frame.Size = UDim2.new(0,160,0,200)
    frame.Position = UDim2.new(0,10,0.5,-100)
    frame.BackgroundColor3 = Color3.fromRGB(15,15,15)
    frame.BackgroundTransparency = 0.3
    frame.BorderSizePixel = 0
    frame.Parent = keybindGui
    Instance.new("UICorner", frame).CornerRadius = UDim.new(0,8)
    local title = Instance.new("TextLabel", frame)
    title.Size = UDim2.new(1,0,0,25)
    title.BackgroundTransparency = 1
    title.Text = "KEYBINDS"
    title.TextColor3 = Color3.fromRGB(255,200,50)
    title.TextSize = 13
    title.Font = Enum.Font.GothamBold
    local binds = {
        {"Q","Dash"},{"E","Target Lock"},{"Z","ESP Toggle"},
        {"RMB","Aimbot"},{"Space","BHop/Fly Up"},{"Shift","Fly Down"},
        {"F8","Stream Mode"},{"F9","Panic Key"},
    }
    for i, bind in pairs(binds) do
        local label = Instance.new("TextLabel", frame)
        label.Size = UDim2.new(1,-10,0,20)
        label.Position = UDim2.new(0,5,0,22+(i-1)*22)
        label.BackgroundTransparency = 1
        label.Text = "[" .. bind[1] .. "] " .. bind[2]
        label.TextColor3 = Color3.fromRGB(200,200,200)
        label.TextSize = 12
        label.Font = Enum.Font.Gotham
        label.TextXAlignment = Enum.TextXAlignment.Left
    end
end

-- Stream Mode
function VisualModule.setStreamMode(enabled)
    State.streamMode = enabled
    if enabled then
        -- Hide all drawings
        FOVring.Visible = false
        FOVring2.Visible = false
        fpsLabel.Visible = false
        timerLabel.Visible = false
        warningLabel.Visible = false
        debugLabel.Visible = false
        for _, l in pairs(crosshairLines) do l.Visible = false end
        ESPModule.clearAll()
        if keybindGui then keybindGui.Enabled = false end
        AudioModule.play("stream")
        task.delay(0.2, function()
            local notif = Drawing.new("Text")
            notif.Text = "Stream Mode ON"
            notif.Size = 16
            notif.Color = Color3.fromRGB(100, 255, 100)
            notif.Outline = true
            notif.Center = true
            notif.Position = Vector2.new(Cam.ViewportSize.X/2, Cam.ViewportSize.Y * 0.9)
            notif.Visible = true
            task.delay(2, function() notif:Remove() end)
        end)
    else
        if keybindGui then keybindGui.Enabled = true end
        AudioModule.play("stream")
    end
end

-- ========================
-- DEV MODULE
-- ========================
local DevModule = {}
local devPlayerSelector = nil
local devTarget = nil

function DevModule.drawHitboxes()
    if not State.devAccess then return end
    for _, p in pairs(Players:GetPlayers()) do
        if p ~= LP and p.Character then
            local hrp = p.Character:FindFirstChild("HumanoidRootPart")
            if hrp then
                local pos, vis = Cam:WorldToViewportPoint(hrp.Position)
                if vis then
                    local box = Drawing.new("Square")
                    box.Position = Vector2.new(pos.X-10, pos.Y-10)
                    box.Size = Vector2.new(20,20)
                    box.Color = Color3.fromRGB(255,255,0)
                    box.Filled = false
                    box.Thickness = 1
                    box.Visible = true
                    task.delay(0.05, function() box:Remove() end)
                end
            end
        end
    end
end

function DevModule.drawPredictionLines()
    if not State.devAccess then return end
    for _, p in pairs(Players:GetPlayers()) do
        if p ~= LP and p.Character then
            local hrp = p.Character:FindFirstChild("HumanoidRootPart")
            if hrp then
                local predPos = AimModule.getPredicted(p, C.Aim.Bone)
                if predPos then
                    local s0, v0 = Cam:WorldToViewportPoint(hrp.Position)
                    local s1, v1 = Cam:WorldToViewportPoint(predPos)
                    if v0 and v1 then
                        local line = Drawing.new("Line")
                        line.From = Vector2.new(s0.X,s0.Y)
                        line.To = Vector2.new(s1.X,s1.Y)
                        line.Color = Color3.fromRGB(0,255,255)
                        line.Thickness = 1
                        line.Visible = true
                        task.delay(0.05, function() line:Remove() end)
                    end
                end
            end
        end
    end
end

-- ========================
-- MOBILE BUTTONS
-- ========================
local mobileGui = nil

local function createMobileButtons()
    if mobileGui then mobileGui:Destroy() end
    mobileGui = Instance.new("ScreenGui")
    mobileGui.Name = "ArsenalMobileGui"
    mobileGui.ResetOnSpawn = false
    mobileGui.Parent = LP.PlayerGui

    local function makeBtn(text, pos, size, color, cb)
        local btn = Instance.new("TextButton")
        btn.Size = size or UDim2.new(0,80,0,48)
        btn.Position = pos
        btn.BackgroundColor3 = color or Color3.fromRGB(25,25,25)
        btn.BackgroundTransparency = 0.25
        btn.TextColor3 = Color3.fromRGB(255,255,255)
        btn.Text = text
        btn.TextSize = 12
        btn.Font = Enum.Font.GothamBold
        btn.BorderSizePixel = 0
        btn.Parent = mobileGui
        Instance.new("UICorner", btn).CornerRadius = UDim.new(0,8)
        btn.MouseButton1Click:Connect(cb)
        return btn
    end

    local function toggleBtn(btn, state, onColor, offColor)
        btn.BackgroundColor3 = state and onColor or offColor
    end

    makeBtn("UP", UDim2.new(1,-90,0.65,0), nil, Color3.fromRGB(0,100,220), function()
        State.mobileFlyUp = true task.wait(0.15) State.mobileFlyUp = false
    end)
    makeBtn("DOWN", UDim2.new(1,-90,0.75,0), nil, Color3.fromRGB(0,60,180), function()
        State.mobileFlyDown = true task.wait(0.15) State.mobileFlyDown = false
    end)

    local flyBtn = makeBtn("FLY: OFF", UDim2.new(1,-90,0.55,0))
    flyBtn.MouseButton1Click:Connect(function()
        State.flyEnabled = not State.flyEnabled
        if State.flyEnabled then PlayerModule.startFly(true) else PlayerModule.stopFly() end
        flyBtn.Text = State.flyEnabled and "FLY: ON" or "FLY: OFF"
        toggleBtn(flyBtn, State.flyEnabled, Color3.fromRGB(0,170,70), Color3.fromRGB(25,25,25))
    end)

    local aimBtn = makeBtn("AIM: OFF", UDim2.new(1,-90,0.45,0))
    aimBtn.MouseButton1Click:Connect(function()
        State.mobileAim = not State.mobileAim
        C.Aim.Enabled = State.mobileAim
        aimBtn.Text = State.mobileAim and "AIM: ON" or "AIM: OFF"
        toggleBtn(aimBtn, State.mobileAim, Color3.fromRGB(200,40,40), Color3.fromRGB(25,25,25))
    end)

    local espBtn = makeBtn("ESP: OFF", UDim2.new(1,-90,0.35,0))
    espBtn.MouseButton1Click:Connect(function()
        C.ESP.Visible = not C.ESP.Visible
        espBtn.Text = C.ESP.Visible and "ESP: ON" or "ESP: OFF"
        toggleBtn(espBtn, C.ESP.Visible, Color3.fromRGB(180,120,0), Color3.fromRGB(25,25,25))
    end)

    local spdBtn = makeBtn("SPD: OFF", UDim2.new(1,-90,0.25,0))
    spdBtn.MouseButton1Click:Connect(function()
        C.Player.WSEnabled = not C.Player.WSEnabled
        spdBtn.Text = C.Player.WSEnabled and "SPD: ON" or "SPD: OFF"
        toggleBtn(spdBtn, C.Player.WSEnabled, Color3.fromRGB(0,150,150), Color3.fromRGB(25,25,25))
        if not C.Player.WSEnabled then
            local char = LP.Character
            if char and char:FindFirstChild("Humanoid") then char.Humanoid.WalkSpeed = 16 end
        end
    end)

    local hitBtn = makeBtn("HIT: OFF", UDim2.new(1,-90,0.15,0))
    hitBtn.MouseButton1Click:Connect(function()
        C.Combat.Hitbox = not C.Combat.Hitbox
        hitBtn.Text = C.Combat.Hitbox and "HIT: ON" or "HIT: OFF"
        toggleBtn(hitBtn, C.Combat.Hitbox, Color3.fromRGB(160,0,160), Color3.fromRGB(25,25,25))
        if not C.Combat.Hitbox then CombatModule.removeHitbox() end
    end)
end

-- ========================
-- INPUT SYSTEM
-- ========================
UIS.InputBegan:Connect(function(input, gpe)
    if gpe then return end

    -- Panic Key
    if input.KeyCode == C.Misc.PanicKey then
        C.Aim.Enabled = false
        C.ESP.Enabled = false
        C.Combat.Hitbox = false
        C.Player.WSEnabled = false
        State.flyEnabled = false
        PlayerModule.stopFly()
        CombatModule.removeHitbox()
        ESPModule.clearAll()
        FOVring.Visible = false
        FOVring2.Visible = false
        return
    end

    -- Stream Mode
    if input.KeyCode == C.Misc.StreamKey then
        C.Misc.StreamMode = not C.Misc.StreamMode
        VisualModule.setStreamMode(C.Misc.StreamMode)
        return
    end

    -- Target Lock
    if input.KeyCode == C.Aim.TargetLockKey and C.Aim.TargetLock then
        if not State.lockActive then
            local t = AimModule.getTarget()
            if t then
                State.lockedTarget = t
                State.lockActive = true
            end
        else
            State.lockActive = false
            State.lockedTarget = nil
        end
    end

    -- ESP Toggle
    if C.ESP.KeyToggle and input.KeyCode == C.ESP.KeyBind then
        C.ESP.Visible = not C.ESP.Visible
    end

    -- Dash
    if input.KeyCode == Enum.KeyCode.Q and not State.dashCD then
        local char = LP.Character
        local hrp = char and char:FindFirstChild("HumanoidRootPart")
        if hrp then
            State.dashCD = true
            hrp.Velocity = hrp.CFrame.LookVector * 100
            task.wait(0.5)
            State.dashCD = false
        end
    end
end)

-- ========================
-- REGISTER SCHEDULERS
-- ========================
PerformanceManager.registerScheduler("Aim", 0, function()
    if not C.Aim.Enabled then return end
    local isKeybindPressed = false
    if C.Aim.Keybind == Enum.UserInputType.MouseButton2 then
        isKeybindPressed = UIS:IsMouseButtonPressed(Enum.UserInputType.MouseButton2)
    elseif C.Aim.Keybind == Enum.UserInputType.MouseButton1 then
        isKeybindPressed = UIS:IsMouseButtonPressed(Enum.UserInputType.MouseButton1)
    else
        isKeybindPressed = UIS:IsKeyDown(C.Aim.Keybind)
    end
    if isKeybindPressed or State.mobileAim then
        local target = AimModule.getTarget()
        if target then
            if C.Aim.AimDelay > 0 then
                task.wait(C.Aim.AimDelay / 1000)
            end
            AimModule.doAim(target)
        end
    end
end)

PerformanceManager.registerScheduler("ESP_Skeleton", 0.02, function()
    if C.ESP.Skeleton then ESPModule.updateSkeleton() end
end)

PerformanceManager.registerScheduler("ESP_HealthBar", 0.05, function()
    if C.ESP.HealthBar then ESPModule.updateHealthBars() end
end)

PerformanceManager.registerScheduler("ESP_Distance", 0.1, function()
    if C.ESP.Distance then ESPModule.updateDistance() end
end)

PerformanceManager.registerScheduler("ESP_Offscreen", 0.05, function()
    if C.ESP.Offscreen then ESPModule.updateOffscreen() end
end)

PerformanceManager.registerScheduler("ESP_Chams", 0.1, function()
    if C.ESP.Chams then ESPModule.updateChams() end
end)

PerformanceManager.registerScheduler("ESP_Trails", 0.05, function()
    if C.ESP.TrailESP then ESPModule.updateTrails() end
end)

PerformanceManager.registerScheduler("ESP_LastPos", 0.1, function()
    if C.ESP.LastPosition then ESPModule.updateLastPosition() end
end)

PerformanceManager.registerScheduler("ESP_DangerZone", 0.05, function()
    if C.ESP.DangerZone then ESPModule.updateDangerZone() end
end)

PerformanceManager.registerScheduler("Brain_Threats", 0.5, function()
    Brain.updateThreats()
    State.stressLevel = Brain.getStressLevel()
end)

PerformanceManager.registerScheduler("Spectators", 1.0, function()
    if not C.Misc.SpectatorDetection then return end
    State.spectators = {}
    for _, p in pairs(Players:GetPlayers()) do
        if p ~= LP then
            if not p.Character or not p.Character:FindFirstChild("HumanoidRootPart") then
                table.insert(State.spectators, p.Name)
            end
        end
    end
    -- Anti-Spectator: auto legit se tiver espectadores
    if C.Misc.AntiSpectator and #State.spectators > 0 then
        if not Brain.shouldReduceAggression() then
            C.Aim.Smooth = math.max(C.Aim.Smooth, 0.05)
        end
    end
end)

PerformanceManager.registerScheduler("Radar", 0.05, function()
    VisualModule.updateRadar()
end)

PerformanceManager.registerScheduler("Warning", 0.2, function()
    VisualModule.updateWarning()
end)

PerformanceManager.registerScheduler("DevHitboxes", 0.05, function()
    if State.devAccess and C.Misc.DebugMode then
        DevModule.drawHitboxes()
        DevModule.drawPredictionLines()
    end
end)

PerformanceManager.registerScheduler("AntiLock", 0.02, function()
    if not C.Player.AntiLock then return end
    local char = LP.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    if hrp then
        local t = tick()
        local off = Vector3.new(
            math.sin(t*7.3+State.behaviorSeed)*0.3,
            0,
            math.cos(t*5.1+State.behaviorSeed)*0.3
        )
        hrp.CFrame = hrp.CFrame * CFrame.new(off)
    end
end)

-- ========================
-- MAIN RUNSERVICE LOOP
-- ========================
RunService.RenderStepped:Connect(function()
    PerformanceManager.tick()
    VisualModule.updateFOV()
    VisualModule.updateCrosshair()
    VisualModule.updateFPS()
    VisualModule.updateTimer()
    VisualModule.updateDebug()
end)

RunService.Heartbeat:Connect(function()
    local char = LP.Character
    local hum = char and char:FindFirstChild("Humanoid")
    if hum then
        if C.Player.WSEnabled then hum.WalkSpeed = C.Player.WalkSpeed end
        if C.Player.JPEnabled then hum.JumpPower = C.Player.JumpPower end
    end

    if C.Player.BunnyHop and char then
        local h = char:FindFirstChild("Humanoid")
        if h and h.FloorMaterial ~= Enum.Material.Air then
            if UIS:IsKeyDown(Enum.KeyCode.Space) then
                h:ChangeState(Enum.HumanoidStateType.Jumping)
            end
        end
    end

    if C.Player.Noclip and char then
        for _, part in pairs(char:GetDescendants()) do
            if part:IsA("BasePart") then part.CanCollide = false end
        end
    end

    if C.Player.AntiRagdoll and char then
        local h = char:FindFirstChild("Humanoid")
        if h then
            h:SetStateEnabled(Enum.HumanoidStateType.Ragdoll, false)
            h:SetStateEnabled(Enum.HumanoidStateType.FallingDown, false)
        end
    end

    if C.Player.AntiFall and char then
        local h = char:FindFirstChild("Humanoid")
        if h then h:SetStateEnabled(Enum.HumanoidStateType.Freefall, false) end
    end

    if C.Combat.Hitbox then CombatModule.applyHitbox() end

    if C.Player.VelocityControl and char then
        local hrp = char:FindFirstChild("HumanoidRootPart")
        local h = char:FindFirstChild("Humanoid")
        if hrp and h and h.FloorMaterial == Enum.Material.Air then
            local vel = hrp.Velocity
            if vel.Magnitude > 1 then
                local dir = vel.Unit
                hrp.Velocity = Vector3.new(dir.X*(vel.Magnitude*C.Player.VelocityAmount), vel.Y, dir.Z*(vel.Magnitude*C.Player.VelocityAmount))
            end
        end
    end

    if C.Player.QuickStop and char then
        local hrp = char:FindFirstChild("HumanoidRootPart")
        local hum = char:FindFirstChild("Humanoid")
        if hrp and hum and hum.MoveDirection.Magnitude == 0 then
            local vel = hrp.Velocity
            hrp.Velocity = Vector3.new(vel.X * 0.7, vel.Y, vel.Z * 0.7)
        end
    end
end)

LP.CharacterAdded:Connect(function(char)
    local hum = char:WaitForChild("Humanoid")
    task.wait(0.5)
    if C.Player.WSEnabled then hum.WalkSpeed = C.Player.WalkSpeed end
    if C.Player.JPEnabled then hum.JumpPower = C.Player.JumpPower end
    if State.flyEnabled then task.wait(0.5) PlayerModule.startFly(isMobile) end
end)

-- Weapon system
local weaponConfigs = {}
local lastWeapon = nil

RunService.Heartbeat:Connect(function()
    local char = LP.Character
    if not char then return end
    local weapon = nil
    for _, t in pairs(char:GetChildren()) do
        if t:IsA("Tool") then weapon = t.Name break end
    end
    if weapon and weapon ~= lastWeapon then
        lastWeapon = weapon
        if weaponConfigs[weapon] then
            local wc = weaponConfigs[weapon]
            if wc.FOV then C.Aim.FOV = wc.FOV end
            if wc.Smooth then C.Aim.Smooth = wc.Smooth end
        end
    end
end)

-- Hit detection for sounds/hitmarker
Players.PlayerAdded:Connect(function(p)
    p.CharacterAdded:Connect(function(char)
        local hum = char:WaitForChild("Humanoid")
        hum.HealthChanged:Connect(function(hp)
            if hp < hum.MaxHealth and Utils.isEnemy(p) then
                if C.Combat.HitSound then AudioModule.play("hit") end
                if C.Combat.Hitmarker then CombatModule.drawHitmarker() end
            end
        end)
    end)
end)

-- ========================
-- LOAD RAYFIELD
-- ========================
local Rayfield = loadstring(game:HttpGet("https://sirius.menu/rayfield"))()

local Window = Rayfield:CreateWindow({
    Name = "Arsenal Script By Toddyx",
    LoadingTitle = "Arsenal Script",
    LoadingSubtitle = "v4.0 ULTIMATE",
    Theme = "Default",
    DisableRayfieldPrompts = true,
    DisableBuildWarnings = true,
    ConfigurationSaving = {
        Enabled = true,
        FolderName = "ArsenalScript",
        FileName = "Config"
    },
    KeySystem = false,
})

-- ========================
-- ABA: MAIN
-- ========================
local MainTab = Window:CreateTab("Main", "home")
MainTab:CreateSection("Arsenal Script v4.0 ULTIMATE")
MainTab:CreateLabel("By Toddyx | " .. (isMobile and "Mobile" or "PC"))
MainTab:CreateLabel("F8 = Stream Mode | F9 = Panic Key | E = Lock | Q = Dash | Z = ESP")

MainTab:CreateButton({
    Name = "Discord",
    Callback = function()
        setclipboard("discord.gg/M2dHpEQy")
        Rayfield:Notify({ Title = "Discord", Content = "Copiado!", Duration = 3 })
    end,
})

MainTab:CreateSection("Profiles")

MainTab:CreateButton({
    Name = "Legit Mode",
    Callback = function()
        C.Mode = "Legit"
        C.Aim.Smooth = 0.04
        C.Aim.FOV = 80
        C.Aim.DynamicSmooth = true
        C.Aim.AntiSwitch = true
        C.Aim.Humanizer = true
        C.Aim.TremorStrength = 0.15
        C.Aim.HitChance = 90
        C.Player.WalkSpeed = 18
        C.Player.FlySpeed = 30
        Rayfield:Notify({ Title = "Legit Mode", Content = "Natural and clean.", Duration = 3 })
    end,
})

MainTab:CreateButton({
    Name = "Rage Mode",
    Callback = function()
        C.Mode = "Rage"
        C.Aim.Smooth = 0.9
        C.Aim.FOV = 350
        C.Aim.DynamicSmooth = false
        C.Aim.AntiSwitch = false
        C.Aim.Humanizer = false
        C.Aim.HitChance = 100
        C.Player.WalkSpeed = 120
        C.Player.FlySpeed = 250
        Rayfield:Notify({ Title = "Rage Mode", Content = "Full power!", Duration = 3 })
    end,
})

MainTab:CreateButton({
    Name = "Legit Assist",
    Callback = function()
        C.Mode = "LegitAssist"
        C.Aim.Enabled = true
        C.Aim.Smooth = 0.03
        C.Aim.FOV = 65
        C.Aim.VisibleCheck = true
        C.Aim.Prediction = true
        C.Aim.DynamicSmooth = true
        C.Aim.AntiSwitch = true
        C.Aim.Humanizer = true
        C.Aim.TremorStrength = 0.1
        C.Aim.Priority = "Closest to Crosshair"
        C.Aim.HitChance = 85
        C.Player.WalkSpeed = 16
        Rayfield:Notify({ Title = "Legit Assist", Content = "Looks like a real player!", Duration = 4 })
    end,
})

-- ========================
-- ABA: AIM
-- ========================
local AimTab = Window:CreateTab("Aim", "crosshair")

AimTab:CreateSection("Aimbot")

AimTab:CreateToggle({
    Name = "Aimbot",
    CurrentValue = false,
    Flag = "AimbotEnabled",
    Callback = function(v) C.Aim.Enabled = v end,
})

AimTab:CreateSlider({
    Name = "FOV",
    Range = {10, 400},
    Increment = 5,
    Suffix = "px",
    CurrentValue = 100,
    Flag = "AimFOV",
    Callback = function(v)
        C.Aim.FOV = v
        FOVring.Radius = v
        FOVring2.Radius = v
    end,
})

AimTab:CreateSlider({
    Name = "Smooth",
    Range = {1, 20},
    Increment = 1,
    Suffix = "x",
    CurrentValue = 2,
    Flag = "AimSmooth",
    Callback = function(v) C.Aim.Smooth = v / 20 end,
})

AimTab:CreateDropdown({
    Name = "Aim Bone",
    Options = {"Head", "UpperTorso", "LowerTorso", "Random"},
    CurrentOption = {"Head"},
    Flag = "AimBone",
    Callback = function(v) C.Aim.Bone = v[1] end,
})

AimTab:CreateDropdown({
    Name = "Target Priority",
    Options = {"Closest to Crosshair", "Lowest HP", "Closest"},
    CurrentOption = {"Closest to Crosshair"},
    Flag = "AimPriority",
    Callback = function(v) C.Aim.Priority = v[1] end,
})

AimTab:CreateDropdown({
    Name = "Keybind",
    Options = {"Mouse2", "Mouse1", "LeftAlt", "CapsLock", "V", "F", "X"},
    CurrentOption = {"Mouse2"},
    Flag = "AimKeybind",
    Callback = function(v)
        local b = {
            ["Mouse2"] = Enum.UserInputType.MouseButton2,
            ["Mouse1"] = Enum.UserInputType.MouseButton1,
            ["LeftAlt"] = Enum.KeyCode.LeftAlt,
            ["CapsLock"] = Enum.KeyCode.CapsLock,
            ["V"] = Enum.KeyCode.V,
            ["F"] = Enum.KeyCode.F,
            ["X"] = Enum.KeyCode.X,
        }
        C.Aim.Keybind = b[v[1]] or Enum.UserInputType.MouseButton2
    end,
})

AimTab:CreateToggle({
    Name = "Aim Prediction",
    CurrentValue = false,
    Flag = "AimPrediction",
    Callback = function(v) C.Aim.Prediction = v end,
})

AimTab:CreateToggle({
    Name = "Visible Check",
    CurrentValue = false,
    Flag = "AimVisible",
    Callback = function(v) C.Aim.VisibleCheck = v end,
})

AimTab:CreateToggle({
    Name = "Dynamic Smooth",
    CurrentValue = false,
    Flag = "DynSmooth",
    Callback = function(v) C.Aim.DynamicSmooth = v end,
})

AimTab:CreateToggle({
    Name = "Multi Bone Scan",
    CurrentValue = false,
    Flag = "MultiBone",
    Callback = function(v) C.Aim.MultiBoneScan = v end,
})

AimTab:CreateSection("Target System")

AimTab:CreateToggle({
    Name = "Target Lock (Tecla E)",
    CurrentValue = false,
    Flag = "TargetLock",
    Callback = function(v)
        C.Aim.TargetLock = v
        if not v then State.lockActive = false State.lockedTarget = nil end
    end,
})

AimTab:CreateToggle({
    Name = "Anti Switch",
    CurrentValue = true,
    Flag = "AntiSwitch",
    Callback = function(v) C.Aim.AntiSwitch = v end,
})

AimTab:CreateSlider({
    Name = "Anti Switch Delay",
    Range = {5, 30},
    Increment = 1,
    Suffix = "x0.1s",
    CurrentValue = 15,
    Flag = "AntiSwitchDelay",
    Callback = function(v) C.Aim.AntiSwitchTime = v / 10 end,
})

AimTab:CreateSection("Humanizer Engine")

AimTab:CreateToggle({
    Name = "Humanizer",
    CurrentValue = false,
    Flag = "Humanizer",
    Callback = function(v) C.Aim.Humanizer = v end,
})

AimTab:CreateSlider({
    Name = "Tremor Strength",
    Range = {1, 20},
    Increment = 1,
    Suffix = "x0.1",
    CurrentValue = 2,
    Flag = "TremorStr",
    Callback = function(v) C.Aim.TremorStrength = v / 10 end,
})

AimTab:CreateSlider({
    Name = "Hit Chance",
    Range = {10, 100},
    Increment = 5,
    Suffix = "%",
    CurrentValue = 100,
    Flag = "HitChance",
    Callback = function(v) C.Aim.HitChance = v end,
})

AimTab:CreateSlider({
    Name = "Aim Delay",
    Range = {0, 300},
    Increment = 10,
    Suffix = "ms",
    CurrentValue = 0,
    Flag = "AimDelay",
    Callback = function(v) C.Aim.AimDelay = v end,
})

AimTab:CreateSlider({
    Name = "Random Offset",
    Range = {0, 5},
    Increment = 1,
    Suffix = "units",
    CurrentValue = 0,
    Flag = "RandomOffset",
    Callback = function(v) C.Aim.RandomOffset = v end,
})

AimTab:CreateSlider({
    Name = "Reaction Min",
    Range = {50, 500},
    Increment = 10,
    Suffix = "ms",
    CurrentValue = 50,
    Flag = "ReactionMin",
    Callback = function(v) C.Aim.ReactionMin = v end,
})

AimTab:CreateSlider({
    Name = "Reaction Max",
    Range = {50, 500},
    Increment = 10,
    Suffix = "ms",
    CurrentValue = 150,
    Flag = "ReactionMax",
    Callback = function(v) C.Aim.ReactionMax = v end,
})

AimTab:CreateToggle({
    Name = "Clutch Mode (Low HP)",
    CurrentValue = false,
    Flag = "ClutchMode",
    Callback = function(v) C.Aim.ClutchMode = v end,
})

AimTab:CreateSlider({
    Name = "Clutch HP Threshold",
    Range = {10, 60},
    Increment = 5,
    Suffix = "HP",
    CurrentValue = 30,
    Flag = "ClutchHP",
    Callback = function(v) C.Aim.ClutchHP = v end,
})

AimTab:CreateToggle({
    Name = "Fake Legit (Fake Miss)",
    CurrentValue = false,
    Flag = "FakeLegit",
    Callback = function(v) C.Misc.FakeLegit = v end,
})

AimTab:CreateSection("FOV Visual")

AimTab:CreateToggle({
    Name = "FOV V1",
    CurrentValue = false,
    Flag = "FOV1",
    Callback = function(v) FOVring.Visible = v end,
})

AimTab:CreateToggle({
    Name = "FOV V2",
    CurrentValue = false,
    Flag = "FOV2",
    Callback = function(v) FOVring2.Visible = v end,
})

AimTab:CreateColorPicker({
    Name = "FOV V1 Color",
    Color = Color3.fromRGB(255,0,0),
    Flag = "FOV1Color",
    Callback = function(v) FOVring.Color = v end,
})

AimTab:CreateColorPicker({
    Name = "FOV V2 Color",
    Color = Color3.fromRGB(0,255,0),
    Flag = "FOV2Color",
    Callback = function(v) FOVring2.Color = v end,
})

-- ========================
-- ABA: ESP
-- ========================
local ESPTab = Window:CreateTab("ESP", "eye")

local ESPLib = loadstring(game:HttpGet("https://kiriot22.com/releases/ESP.lua"))()
ESPLib:Toggle(true)
ESPLib.Players = false
ESPLib.Tracers = false
ESPLib.Boxes = false
ESPLib.Names = false
ESPLib.TeamColor = false
ESPLib.TeamMates = false

ESPTab:CreateSection("ESP Base")

ESPTab:CreateToggle({
    Name = "Enable ESP",
    CurrentValue = false,
    Flag = "ESPEnabled",
    Callback = function(v)
        C.ESP.Enabled = v
        ESPLib.Players = v
        ESPLib:Toggle(v)
    end,
})

ESPTab:CreateToggle({
    Name = "Boxes",
    CurrentValue = false,
    Flag = "ESPBoxes",
    Callback = function(v) C.ESP.Boxes = v ESPLib.Boxes = v end,
})

ESPTab:CreateToggle({
    Name = "Tracers",
    CurrentValue = false,
    Flag = "ESPTracers",
    Callback = function(v) C.ESP.Tracers = v ESPLib.Tracers = v end,
})

ESPTab:CreateToggle({
    Name = "Names",
    CurrentValue = false,
    Flag = "ESPNames",
    Callback = function(v) C.ESP.Names = v ESPLib.Names = v end,
})

ESPTab:CreateToggle({
    Name = "Skeleton",
    CurrentValue = false,
    Flag = "ESPSkeleton",
    Callback = function(v) C.ESP.Skeleton = v end,
})

ESPTab:CreateToggle({
    Name = "Health Bar",
    CurrentValue = false,
    Flag = "ESPHealthBar",
    Callback = function(v) C.ESP.HealthBar = v end,
})

ESPTab:CreateToggle({
    Name = "Distance",
    CurrentValue = false,
    Flag = "ESPDist",
    Callback = function(v) C.ESP.Distance = v end,
})

ESPTab:CreateToggle({
    Name = "Off Screen Arrows",
    CurrentValue = false,
    Flag = "ESPOffscreen",
    Callback = function(v) C.ESP.Offscreen = v end,
})

ESPTab:CreateToggle({
    Name = "Chams",
    CurrentValue = false,
    Flag = "ESPChams",
    Callback = function(v) C.ESP.Chams = v end,
})

ESPTab:CreateToggle({
    Name = "Trail ESP",
    CurrentValue = false,
    Flag = "ESPTrail",
    Callback = function(v) C.ESP.TrailESP = v end,
})

ESPTab:CreateToggle({
    Name = "Last Position Ghost",
    CurrentValue = false,
    Flag = "ESPLastPos",
    Callback = function(v) C.ESP.LastPosition = v end,
})

ESPTab:CreateToggle({
    Name = "Danger Zone",
    CurrentValue = false,
    Flag = "ESPDanger",
    Callback = function(v) C.ESP.DangerZone = v end,
})

ESPTab:CreateToggle({
    Name = "Gradient by HP",
    CurrentValue = false,
    Flag = "ESPGradient",
    Callback = function(v) C.ESP.GradientHP = v end,
})

ESPTab:CreateSection("ESP Intelligence")

ESPTab:CreateToggle({
    Name = "Visible Only",
    CurrentValue = false,
    Flag = "ESPVisOnly",
    Callback = function(v) C.ESP.VisibleOnly = v end,
})

ESPTab:CreateToggle({
    Name = "Fade by Distance",
    CurrentValue = false,
    Flag = "ESPFade",
    Callback = function(v) C.ESP.FadeDistance = v end,
})

ESPTab:CreateToggle({
    Name = "Priority Highlight",
    CurrentValue = false,
    Flag = "ESPPriority",
    Callback = function(v) C.ESP.PriorityHighlight = v end,
})

ESPTab:CreateSlider({
    Name = "Priority Range",
    Range = {10, 150},
    Increment = 5,
    Suffix = "m",
    CurrentValue = 30,
    Flag = "ESPPriorityRange",
    Callback = function(v) C.ESP.PriorityRange = v end,
})

ESPTab:CreateToggle({
    Name = "Team Check",
    CurrentValue = true,
    Flag = "ESPTeam",
    Callback = function(v)
        C.ESP.TeamCheck = v
        ESPLib.TeamMates = not v
        ESPLib.TeamColor = not v
    end,
})

ESPTab:CreateToggle({
    Name = "ESP Key Toggle (Z)",
    CurrentValue = false,
    Flag = "ESPKeyToggle",
    Callback = function(v) C.ESP.KeyToggle = v end,
})

ESPTab:CreateColorPicker({
    Name = "ESP Color",
    Color = Color3.fromRGB(255,0,0),
    Flag = "ESPColor",
    Callback = function(v) C.ESP.Color = v ESPLib.Color = v end,
})

ESPTab:CreateColorPicker({
    Name = "Skeleton Color",
    Color = Color3.fromRGB(255,255,255),
    Flag = "SkeletonColor",
    Callback = function(v) C.ESP.SkeletonColor = v end,
})

ESPTab:CreateSection("Radar")

ESPTab:CreateToggle({
    Name = "Radar",
    CurrentValue = false,
    Flag = "Radar",
    Callback = function(v) radarEnabled = v end,
})

ESPTab:CreateSlider({
    Name = "Radar Range",
    Range = {50, 500},
    Increment = 10,
    Suffix = "studs",
    CurrentValue = 100,
    Flag = "RadarRange",
    Callback = function(v) radarRange = v end,
})

-- ========================
-- ABA: PLAYER
-- ========================
local PlayerTab = Window:CreateTab("Player", "user")

PlayerTab:CreateSection("Movement")

PlayerTab:CreateToggle({
    Name = "Fly",
    CurrentValue = false,
    Flag = "Fly",
    Callback = function(v)
        if v then PlayerModule.startFly(isMobile) else PlayerModule.stopFly() end
    end,
})

PlayerTab:CreateSlider({
    Name = "Fly Speed",
    Range = {10, 400},
    Increment = 5,
    Suffix = "Speed",
    CurrentValue = 50,
    Flag = "FlySpeed",
    Callback = function(v) C.Player.FlySpeed = v end,
})

PlayerTab:CreateToggle({
    Name = "Walk Speed",
    CurrentValue = false,
    Flag = "WS",
    Callback = function(v)
        C.Player.WSEnabled = v
        if not v then
            local char = LP.Character
            if char and char:FindFirstChild("Humanoid") then char.Humanoid.WalkSpeed = 16 end
        end
    end,
})

PlayerTab:CreateSlider({
    Name = "Walk Speed Value",
    Range = {16, 500},
    Increment = 1,
    Suffix = "Speed",
    CurrentValue = 16,
    Flag = "WSVal",
    Callback = function(v) C.Player.WalkSpeed = v end,
})

PlayerTab:CreateToggle({
    Name = "Jump Power",
    CurrentValue = false,
    Flag = "JP",
    Callback = function(v)
        C.Player.JPEnabled = v
        if not v then
            local char = LP.Character
            if char and char:FindFirstChild("Humanoid") then char.Humanoid.JumpPower = 50 end
        end
    end,
})

PlayerTab:CreateSlider({
    Name = "Jump Power Value",
    Range = {50, 500},
    Increment = 1,
    Suffix = "Power",
    CurrentValue = 50,
    Flag = "JPVal",
    Callback = function(v) C.Player.JumpPower = v end,
})

PlayerTab:CreateToggle({
    Name = "Noclip",
    CurrentValue = false,
    Flag = "Noclip",
    Callback = function(v) C.Player.Noclip = v end,
})

PlayerTab:CreateToggle({
    Name = "Anti Ragdoll",
    CurrentValue = false,
    Flag = "AntiRagdoll",
    Callback = function(v) C.Player.AntiRagdoll = v end,
})

PlayerTab:CreateToggle({
    Name = "Anti Fall Damage",
    CurrentValue = false,
    Flag = "AntiFall",
    Callback = function(v) C.Player.AntiFall = v end,
})

PlayerTab:CreateToggle({
    Name = "Bunny Hop",
    CurrentValue = false,
    Flag = "BHop",
    Callback = function(v) C.Player.BunnyHop = v end,
})

PlayerTab:CreateToggle({
    Name = "Strafe Assist",
    CurrentValue = false,
    Flag = "Strafe",
    Callback = function(v) C.Player.Strafe = v end,
})

PlayerTab:CreateToggle({
    Name = "Velocity Control",
    CurrentValue = false,
    Flag = "VelCtrl",
    Callback = function(v) C.Player.VelocityControl = v end,
})

PlayerTab:CreateSlider({
    Name = "Velocity Amount",
    Range = {10, 20},
    Increment = 1,
    Suffix = "x0.1",
    CurrentValue = 10,
    Flag = "VelAmt",
    Callback = function(v) C.Player.VelocityAmount = v / 10 end,
})

PlayerTab:CreateToggle({
    Name = "Quick Stop",
    CurrentValue = false,
    Flag = "QuickStop",
    Callback = function(v) C.Player.QuickStop = v end,
})

PlayerTab:CreateToggle({
    Name = "Anti Lock",
    CurrentValue = false,
    Flag = "AntiLock",
    Callback = function(v) C.Player.AntiLock = v end,
})

PlayerTab:CreateToggle({
    Name = "Movement Randomizer",
    CurrentValue = false,
    Flag = "MovRand",
    Callback = function(v) C.Player.MovementRandomizer = v end,
})

PlayerTab:CreateLabel("Dash: Pressione Q")

PlayerTab:CreateSection("Teleport")

PlayerTab:CreateToggle({
    Name = "Click TP",
    CurrentValue = false,
    Flag = "ClickTP",
    Callback = function(v)
        State.tpEnabled = v
        if v then
            State.tpConn = UIS.InputBegan:Connect(function(input, gpe)
                if gpe then return end
                if input.UserInputType == Enum.UserInputType.MouseButton1 and State.tpEnabled then
                    local unitRay = Cam:ScreenPointToRay(input.Position.X, input.Position.Y)
                    local ray = Ray.new(unitRay.Origin, unitRay.Direction * 500)
                    local hit, pos = workspace:FindPartOnRay(ray, LP.Character)
                    if hit then
                        local hrp = LP.Character and LP.Character:FindFirstChild("HumanoidRootPart")
                        if hrp then hrp.CFrame = CFrame.new(pos + Vector3.new(0,3,0)) end
                    end
                end
            end)
        else
            if State.tpConn then State.tpConn:Disconnect() end
        end
    end,
})

PlayerTab:CreateDropdown({
    Name = "TP to Player",
    Options = (function()
        local names = {}
        for _, p in pairs(Players:GetPlayers()) do
            if p ~= LP then table.insert(names, p.Name) end
        end
        if #names == 0 then names = {"None"} end
        return names
    end)(),
    CurrentOption = {},
    Flag = "TPPlayer",
    Callback = function(v)
        local t = Players:FindFirstChild(v[1])
        if t and t.Character then
            local hrp = t.Character:FindFirstChild("HumanoidRootPart")
            local myHRP = LP.Character and LP.Character:FindFirstChild("HumanoidRootPart")
            if hrp and myHRP then
                myHRP.CFrame = hrp.CFrame + Vector3.new(0,3,0)
                Rayfield:Notify({ Title = "TP", Content = "Teleported to " .. v[1], Duration = 3 })
            end
        end
    end,
})

-- ========================
-- ABA: COMBAT
-- ========================
local CombatTab = Window:CreateTab("Combat", "sword")

CombatTab:CreateSection("Hitbox")

CombatTab:CreateToggle({
    Name = "Hitbox",
    CurrentValue = false,
    Flag = "Hitbox",
    Callback = function(v)
        C.Combat.Hitbox = v
        if not v then CombatModule.removeHitbox() end
    end,
})

CombatTab:CreateToggle({
    Name = "Team Check Hitbox",
    CurrentValue = true,
    Flag = "HitboxTeam",
    Callback = function(v) C.Combat.HitboxTeamCheck = v end,
})

CombatTab:CreateSection("Gun Mods")

CombatTab:CreateButton({
    Name = "Inf Ammo",
    Callback = function()
        task.spawn(function()
            while task.wait() do
                local gui = LP.PlayerGui
                local g = gui:FindFirstChild("GUI")
                if g then
                    local c = g:FindFirstChild("Client")
                    local vars = c and c:FindFirstChild("Variables")
                    if vars then
                        if vars:FindFirstChild("ammocount") then vars.ammocount.Value = 999 end
                        if vars:FindFirstChild("ammocount2") then vars.ammocount2.Value = 999 end
                    end
                end
            end
        end)
        Rayfield:Notify({ Title = "Inf Ammo", Content = "Active!", Duration = 3 })
    end,
})

CombatTab:CreateButton({
    Name = "Rapid Fire",
    Callback = function()
        local rs = game.ReplicatedStorage
        if rs:FindFirstChild("Weapons") then
            for _, v in pairs(rs.Weapons:GetDescendants()) do
                if v.Name == "FireRate" then v.Value = 0.01 end
            end
        end
        Rayfield:Notify({ Title = "Rapid Fire", Content = "Active!", Duration = 3 })
    end,
})

CombatTab:CreateToggle({
    Name = "No Recoil",
    CurrentValue = false,
    Flag = "NoRecoil",
    Callback = function(v)
        C.Combat.NoRecoil = v
        if v then
            local rs = game.ReplicatedStorage
            if rs:FindFirstChild("Weapons") then
                for _, obj in pairs(rs.Weapons:GetDescendants()) do
                    if obj.Name == "Recoil" or obj.Name == "VerticalRecoil" or obj.Name == "HorizontalRecoil" then
                        obj.Value = 0
                    end
                end
            end
        end
    end,
})

CombatTab:CreateToggle({
    Name = "No Spread",
    CurrentValue = false,
    Flag = "NoSpread",
    Callback = function(v)
        C.Combat.NoSpread = v
        if v then
            local rs = game.ReplicatedStorage
            if rs:FindFirstChild("Weapons") then
                for _, obj in pairs(rs.Weapons:GetDescendants()) do
                    if obj.Name == "Spread" or obj.Name == "SpreadAngle" then
                        obj.Value = 0
                    end
                end
            end
        end
    end,
})

CombatTab:CreateToggle({
    Name = "Hit Sound",
    CurrentValue = false,
    Flag = "HitSound",
    Callback = function(v) C.Combat.HitSound = v end,
})

CombatTab:CreateToggle({
    Name = "Hitmarker",
    CurrentValue = false,
    Flag = "Hitmarker",
    Callback = function(v) C.Combat.Hitmarker = v end,
})

CombatTab:CreateSection("Weapon Config")

CombatTab:CreateButton({
    Name = "Save Current Weapon Config",
    Callback = function()
        if lastWeapon then
            weaponConfigs[lastWeapon] = { FOV = C.Aim.FOV, Smooth = C.Aim.Smooth }
            Rayfield:Notify({ Title = "Weapon Config", Content = "Saved: " .. lastWeapon, Duration = 3 })
        else
            Rayfield:Notify({ Title = "Weapon Config", Content = "No weapon equipped!", Duration = 3 })
        end
    end,
})

-- ========================
-- ABA: VISUALS
-- ========================
local VisualTab = Window:CreateTab("Visuals", "star")

VisualTab:CreateSection("Misc Visuals")

VisualTab:CreateToggle({
    Name = "Crosshair",
    CurrentValue = false,
    Flag = "Crosshair",
    Callback = function(v)
        crosshairEnabled = v
        if not v then
            for _, l in pairs(crosshairLines) do l.Visible = false end
            crosshairLines = {}
        end
    end,
})

VisualTab:CreateSlider({
    Name = "Crosshair Size",
    Range = {5, 50},
    Increment = 1,
    Suffix = "px",
    CurrentValue = 10,
    Flag = "CrosshairSize",
    Callback = function(v) crosshairSize = v end,
})

VisualTab:CreateSlider({
    Name = "Crosshair Gap",
    Range = {0, 20},
    Increment = 1,
    Suffix = "px",
    CurrentValue = 5,
    Flag = "CrosshairGap",
    Callback = function(v) crosshairGap = v end,
})

VisualTab:CreateColorPicker({
    Name = "Crosshair Color",
    Color = Color3.fromRGB(255,255,255),
    Flag = "CrosshairColor",
    Callback = function(v) crosshairColor = v end,
})

VisualTab:CreateToggle({
    Name = "Full Bright",
    CurrentValue = false,
    Flag = "FullBright",
    Callback = function(v)
        if v then PlayerModule.enableFullbright() else PlayerModule.disableFullbright() end
    end,
})

VisualTab:CreateToggle({
    Name = "FPS Counter",
    CurrentValue = false,
    Flag = "FPSCount",
    Callback = function(v) fpsLabel.Visible = v end,
})

VisualTab:CreateToggle({
    Name = "Session Timer",
    CurrentValue = false,
    Flag = "Timer",
    Callback = function(v) timerLabel.Visible = v end,
})

-- ========================
-- ABA: MOBILE
-- ========================
local MobileTab = Window:CreateTab("Mobile", "smartphone")
MobileTab:CreateSection("Mobile Mode")
MobileTab:CreateLabel("Detected: " .. (isMobile and "Mobile" or "PC"))

MobileTab:CreateToggle({
    Name = "Mobile Buttons",
    CurrentValue = isMobile,
    Flag = "MobileButtons",
    Callback = function(v)
        if v then
            createMobileButtons()
            Rayfield:Notify({ Title = "Mobile", Content = "Buttons active!", Duration = 3 })
        else
            if mobileGui then mobileGui:Destroy() mobileGui = nil end
        end
    end,
})

MobileTab:CreateToggle({
    Name = "Auto Aim Mobile",
    CurrentValue = false,
    Flag = "MobileAim",
    Callback = function(v)
        State.mobileAim = v
        C.Aim.Enabled = v
    end,
})

MobileTab:CreateSlider({
    Name = "Mobile FOV",
    Range = {10, 400},
    Increment = 5,
    Suffix = "px",
    CurrentValue = 150,
    Flag = "MobileFOV",
    Callback = function(v) C.Aim.FOV = v end,
})

MobileTab:CreateToggle({
    Name = "FPS Boost Mobile",
    CurrentValue = false,
    Flag = "MobileFPSBoost",
    Callback = function(v)
        if v then PerformanceManager.enableFPSBoost() else PerformanceManager.disableFPSBoost() end
    end,
})

-- ========================
-- ABA: PC
-- ========================
local PCTab = Window:CreateTab("PC", "monitor")
PCTab:CreateSection("PC Mode")
PCTab:CreateLabel("Detected: " .. (not isMobile and "PC" or "Mobile"))

PCTab:CreateToggle({
    Name = "Keybind Overlay",
    CurrentValue = false,
    Flag = "KeybindOverlay",
    Callback = function(v)
        C.Misc.KeybindOverlay = v
        if v then VisualModule.createKeybindOverlay()
        else if keybindGui then keybindGui:Destroy() keybindGui = nil end end
    end,
})

PCTab:CreateToggle({
    Name = "FPS Boost PC",
    CurrentValue = false,
    Flag = "FPSBoostPC",
    Callback = function(v)
        if v then PerformanceManager.enableFPSBoost() else PerformanceManager.disableFPSBoost() end
    end,
})

PCTab:CreateToggle({
    Name = "Adaptive FPS Boost",
    CurrentValue = false,
    Flag = "AdaptiveFPS",
    Callback = function(v) C.Performance.AdaptiveFPS = v end,
})

PCTab:CreateSlider({
    Name = "FPS Limiter",
    Range = {0, 144},
    Increment = 5,
    Suffix = "FPS",
    CurrentValue = 0,
    Flag = "FPSLimit",
    Callback = function(v) C.Performance.FPSLimit = v end,
})

-- ========================
-- ABA: MISC
-- ========================
local MiscTab = Window:CreateTab("Misc", "settings")

MiscTab:CreateSection("Utilities")

MiscTab:CreateToggle({
    Name = "Enemy Warning",
    CurrentValue = false,
    Flag = "EnemyWarn",
    Callback = function(v) C.Misc.EnemyWarning = v end,
})

MiscTab:CreateSlider({
    Name = "Warning Range",
    Range = {10, 200},
    Increment = 5,
    Suffix = "m",
    CurrentValue = 50,
    Flag = "WarnRange",
    Callback = function(v) C.Misc.EnemyWarningRange = v end,
})

MiscTab:CreateToggle({
    Name = "Spectator Detection",
    CurrentValue = false,
    Flag = "SpectDetect",
    Callback = function(v) C.Misc.SpectatorDetection = v end,
})

MiscTab:CreateToggle({
    Name = "Anti Spectator (Auto Legit)",
    CurrentValue = false,
    Flag = "AntiSpect",
    Callback = function(v) C.Misc.AntiSpectator = v end,
})

MiscTab:CreateToggle({
    Name = "Risk System",
    CurrentValue = false,
    Flag = "RiskSys",
    Callback = function(v) C.Misc.RiskSystem = v end,
})

MiscTab:CreateToggle({
    Name = "Stream Mode",
    CurrentValue = false,
    Flag = "StreamMode",
    Callback = function(v)
        C.Misc.StreamMode = v
        VisualModule.setStreamMode(v)
    end,
})

MiscTab:CreateToggle({
    Name = "Anti AFK",
    CurrentValue = false,
    Flag = "AntiAFK",
    Callback = function(v)
        C.Misc.AntiAFK = v
        if v then
            task.spawn(function()
                while C.Misc.AntiAFK do
                    task.wait(55)
                    local VU = game:GetService("VirtualUser")
                    VU:CaptureController()
                    VU:ClickButton2(Vector2.new())
                end
            end)
        end
    end,
})

MiscTab:CreateSection("Themes")

local themes = {"Default", "Ocean", "Amethyst", "Green", "Light", "Dark"}

local themeDropdown = MiscTab:CreateDropdown({
    Name = "Select Theme",
    Options = themes,
    CurrentOption = {"Default"},
    Flag = "Theme",
    Callback = function(v)
        local theme = v[1]
        local ok, err = pcall(function()
            Rayfield:SetTheme(theme)
        end)
        if ok then
            Rayfield:Notify({ Title = "Theme", Content = theme .. " applied!", Duration = 3 })
        else
            -- Fallback
            pcall(function() Window:ChangeTheme(theme) end)
        end
    end,
})

-- ========================
-- ABA: CONFIG
-- ========================
local ConfigTab = Window:CreateTab("Config", "settings")
ConfigTab:CreateLabel("Arsenal Script v4.0 ULTIMATE | By Toddyx")

ConfigTab:CreateButton({
    Name = "Export Config",
    Callback = function()
        local result = ConfigManager:export()
        if result then
            Rayfield:Notify({ Title = "Config", Content = "Exported to clipboard!", Duration = 3 })
        end
    end,
})

ConfigTab:CreateButton({
    Name = "Hot Reload",
    Callback = function()
        Rayfield:LoadConfiguration()
        Rayfield:Notify({ Title = "Config", Content = "Reloaded!", Duration = 3 })
    end,
})

ConfigTab:CreateButton({
    Name = "Destroy UI",
    Callback = function()
        PlayerModule.stopFly()
        PerformanceManager.disableFPSBoost()
        PlayerModule.disableFullbright()
        CombatModule.removeHitbox()
        ESPModule.clearAll()
        for _, d in pairs(radarDots) do d:Remove() end
        for _, l in pairs(crosshairLines) do l:Remove() end
        if mobileGui then mobileGui:Destroy() end
        if keybindGui then keybindGui:Destroy() end
        warningLabel:Remove()
        debugLabel:Remove()
        fpsLabel:Remove()
        timerLabel:Remove()
        FOVring:Remove()
        FOVring2:Remove()
        if State.tpConn then State.tpConn:Disconnect() end
        RunService:UnbindFromRenderStep("FOVUpdate")
        Rayfield:Destroy()
    end,
})

-- ========================
-- ABA: DEV (ACESSO RESTRITO)
-- ========================
local DevTab = Window:CreateTab("DEV", "code")
DevTab:CreateSection("Developer Access")
DevTab:CreateLabel("Restricted Area - Dev Only")

local devInput = DevTab:CreateInput({
    Name = "Enter your username",
    PlaceholderText = "Username...",
    RemoveTextAfterFocusLost = false,
    Flag = "DevInput",
    Callback = function(v)
        if v == LP.Name and LP.Name == "zoompro177" then
            State.devAccess = true
            C.Misc.DebugMode = true
            debugLabel.Visible = true
            Rayfield:Notify({
                Title = "DEV ACCESS GRANTED",
                Content = "Welcome, " .. LP.Name .. "! Dev mode enabled.",
                Duration = 5,
            })
        else
            Rayfield:Notify({
                Title = "Access Denied",
                Content = "Invalid credentials.",
                Duration = 3,
            })
        end
    end,
})

DevTab:CreateSection("Dev Tools (Requires Access)")

DevTab:CreateToggle({
    Name = "Debug Mode",
    CurrentValue = false,
    Flag = "DebugMode",
    Callback = function(v)
        if not State.devAccess then
            Rayfield:Notify({ Title = "Access Denied", Content = "Enter dev credentials first!", Duration = 3 })
            return
        end
        C.Misc.DebugMode = v
        debugLabel.Visible = v
    end,
})

DevTab:CreateToggle({
    Name = "Draw Hitboxes",
    CurrentValue = false,
    Flag = "DevHitboxes",
    Callback = function(v)
        if not State.devAccess then return end
        C.Misc.DebugMode = v
    end,
})

DevTab:CreateToggle({
    Name = "Draw Prediction Lines",
    CurrentValue = false,
    Flag = "DevPredLines",
    Callback = function(v)
        if not State.devAccess then return end
        C.Aim.Prediction = v
    end,
})

DevTab:CreateButton({
    Name = "Print Spectators",
    Callback = function()
        if not State.devAccess then return end
        local spec = table.concat(State.spectators, ", ")
        Rayfield:Notify({ Title = "Spectators", Content = #State.spectators > 0 and spec or "None", Duration = 5 })
    end,
})

DevTab:CreateButton({
    Name = "Print Target Info",
    Callback = function()
        if not State.devAccess then return end
        local t = State.currentTarget
        if t then
            Rayfield:Notify({
                Title = "Target: " .. t.Name,
                Content = string.format("HP: %d | Dist: %dm | Threat: %s",
                    math.floor(Utils.getHP(t)),
                    math.floor(Utils.getDistance(t)),
                    Brain.isThreat(t) and "YES" or "NO"
                ),
                Duration = 5,
            })
        else
            Rayfield:Notify({ Title = "No Target", Content = "No target in FOV", Duration = 3 })
        end
    end,
})

-- ========================
-- INIT
-- ========================
Rayfield:LoadConfiguration()

if isMobile then
    task.wait(2)
    createMobileButtons()
    Rayfield:Notify({
        Title = "Mobile Detected!",
        Content = "Buttons and auto-aim configured!",
        Duration = 5,
    })
end

Rayfield:Notify({
    Title = "Arsenal Script v4.0",
    Content = "Loaded! F8=Stream | F9=Panic | E=Lock",
    Duration = 5,
})
