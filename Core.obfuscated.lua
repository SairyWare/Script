-- language: Luau, file: Core.lua, runtime: Roblox Luau, target: SairyWare Core Client Authority
--[[
    SairyWare — Core Authentication Authority & Runtime Guard
    Author: Alert3z / SairyWare Team
    Architecture: Modern Obsidian Glass UI / CanvasGroup / Toast Engine / Server Authority
]]

local TaskWait = task.wait

if not game:IsLoaded() then
    game.Loaded:Wait()
end

--// Services
local Services = setmetatable({}, {
    __index = function(Self, Name)
        local Service = cloneref and cloneref(game:GetService(Name)) or game:GetService(Name)
        rawset(Self, Name, Service)
        return Service
    end
})

local TweenService       = Services.TweenService
local UserInputService   = Services.UserInputService
local RunService         = Services.RunService
local Players            = Services.Players
local HttpService        = Services.HttpService
local RbxAnalyticsService= Services.RbxAnalyticsService

local LocalPlayer        = Players.LocalPlayer
local PlayerGui          = LocalPlayer:WaitForChild("PlayerGui")

--// Environment Helpers
local function GetGuiParent()
    if gethui then return gethui() end
    local CoreGui = Services.CoreGui
    if CoreGui then
        local Success = pcall(function() local _ = CoreGui.Name end)
        if Success then return CoreGui end
    end
    return PlayerGui
end

local function GetRequest()
    return (syn and syn.request) or (http and http.request) or http_request or request
end

local function GetHwid()
    local ExecutorHwid = gethwid and gethwid() or get_hwid and get_hwid()
    if ExecutorHwid and #ExecutorHwid > 0 then
        return tostring(ExecutorHwid)
    end
    local Success, ClientId = pcall(function()
        return RbxAnalyticsService:GetClientId()
    end)
    if Success and ClientId and #ClientId > 0 then
        return "RBX-" .. tostring(ClientId)
    end
    return "RBX-UNKNOWN-CLIENT"
end

local FolderName  = "SairyWare"
local KeyFileName = FolderName .. "/Key.txt"

local function LoadSavedKey()
    if isfile and isfile(KeyFileName) then
        local Saved = readfile(KeyFileName)
        if Saved and #Saved > 0 then
            return Saved:gsub("%s+", "")
        end
    end
    return ""
end

local function SaveKey(Key)
    if not (makefolder and writefile) then return end
    if not isfolder(FolderName) then
        makefolder(FolderName)
    end
    writefile(KeyFileName, Key)
end

local function SetClipboardText(Text)
    if setclipboard then
        setclipboard(Text)
        return true
    end
    return false
end

local function GetClipboardText()
    if getclipboard then
        local Success, Result = pcall(getclipboard)
        if Success and type(Result) == "string" and #Result > 0 then
            return Result
        end
    end
    return nil
end

--// Configuration
local ApiUrl     = "https://sairy-ware.alert-3zyt.workers.dev"
local DiscordUrl = "https://discord.gg/AEYZepuvvK"

--// 3. Color & Typography Specifications
local PALETTE = {
    BackgroundObsidian = Color3.fromRGB(7, 9, 13),      -- #07090D (Base Canvas)
    CardSurface        = Color3.fromRGB(15, 18, 26),    -- #0F121A (Surface Low)
    SurfaceElevated    = Color3.fromRGB(20, 24, 35),    -- #141823 (Card/Input Fill)
    SurfaceBorder      = Color3.fromRGB(255, 255, 255), -- Transparency: 0.92
    
    CyanElectric       = Color3.fromRGB(0, 240, 255),   -- #00F0FF (Primary Active)
    IrisRoyal          = Color3.fromRGB(99, 102, 241),  -- #6366F1 (Secondary Accent)
    AccentGlowCyan     = Color3.fromRGB(0, 240, 255),   -- Transparency: 0.75
    
    SuccessGreen       = Color3.fromRGB(34, 197, 94),   -- #22C55E (Accepted / Online)
    ErrorRed           = Color3.fromRGB(239, 68, 68),   -- #EF4444 (Invalid / Denied)
    WarningAmber       = Color3.fromRGB(245, 158, 11),  -- #F59E0B (Expired / Notice)
    
    TextPrimary        = Color3.fromRGB(255, 255, 255), -- #FFFFFF (Titles, Input)
    TextSecondary      = Color3.fromRGB(148, 163, 184), -- #94A3B8 (Labels, Subtitles)
    TextMuted          = Color3.fromRGB(71, 85, 105),   -- #475569 (Placeholders, Borders)
}

--// Status Mapping Specification
local STATUS_CONFIG = {
    VALID = { Message = "Key Verified Successfully", Color = PALETTE.SuccessGreen },
    INVALID_KEY = { Message = "Invalid Key", Color = PALETTE.ErrorRed },
    DEVICE_MISMATCH = { Message = "This Key Is Already Bound To Another Device", Color = PALETTE.WarningAmber },
    EXPIRED = { Message = "This Key Has Expired", Color = PALETTE.WarningAmber },
    SUSPENDED = { Message = "This Key Has Been Suspended", Color = PALETTE.ErrorRed },
    REVOKED = { Message = "This Key Has Been Revoked", Color = PALETTE.ErrorRed },
    EXHAUSTED = { Message = "Maximum Allowed Uses Reached", Color = PALETTE.WarningAmber },
    NOT_ACTIVATED = { Message = "This Key Has Not Been Activated", Color = PALETTE.WarningAmber },
    RATE_LIMITED = { Message = "Too Many Requests. Please wait.", Color = PALETTE.WarningAmber },
    SERVER_ERROR = { Message = "Unable To Verify Key", Color = PALETTE.ErrorRed },
    AUTH_FAILED = { Message = "Authentication Failed", Color = PALETTE.ErrorRed },
}

--// Local Closure-Scoped Runtime Security State (DO NOT expose raw authority in getgenv)
local RuntimeState = {
    IsAuthenticated = false,
    SessionToken = nil,
    Key = nil,
    Hwid = nil,
    GameId = tostring(game.GameId),
    PlaceId = tostring(game.PlaceId),
    HeartbeatInterval = 60, -- 60s responsive heartbeat
    HeartbeatTask = nil,
    LastVerified = 0,
    Vars = {},
}

local CurrentActiveGui = nil

local function EnforceViolation(Reason, Status)
    RuntimeState.IsAuthenticated = false
    RuntimeState.SessionToken = nil
    RuntimeState.Key = nil

    if RuntimeState.HeartbeatTask then
        task.cancel(RuntimeState.HeartbeatTask)
        RuntimeState.HeartbeatTask = nil
    end

    if CurrentActiveGui then
        pcall(function() CurrentActiveGui:Destroy() end)
        CurrentActiveGui = nil
    end

    -- Clear fallback globals
    getgenv().SairyKey = nil
    getgenv().SairyHwid = nil
    getgenv().SairySession = nil
    getgenv().SairySignature = nil
    getgenv().Session = nil
    getgenv().SairyVars = nil
    _G.SairyKey = nil

    local ViolationText = string.format("[SAIRYWARE CORE GUARD]\nAccess Denied: %s\nStatus: %s", tostring(Reason or "Authentication Required"), tostring(Status or "AUTH_FAILED"))
    warn(ViolationText)

    pcall(function()
        if LocalPlayer and LocalPlayer.Kick then
            LocalPlayer:Kick(ViolationText)
        end
    end)

    error(ViolationText, 0)
end

local function VerifySessionWithServer()
    if not RuntimeState.SessionToken or not RuntimeState.Key then
        EnforceViolation("No active session token to verify.", "AUTH_FAILED")
        return false
    end

    local RequestFunc = GetRequest()
    if not RequestFunc then
        EnforceViolation("HTTP request capability missing during session verification.", "SERVER_ERROR")
        return false
    end

    local Success, Response = pcall(function()
        return RequestFunc({
            Url = ApiUrl .. "/session-check",
            Method = "POST",
            Headers = { ["Content-Type"] = "application/json" },
            Body = HttpService:JSONEncode({
                key = RuntimeState.Key,
                hwid = RuntimeState.Hwid or GetHwid(),
                session_token = RuntimeState.SessionToken,
                signature = RuntimeState.SessionToken,
                game_id = RuntimeState.GameId,
                place_id = RuntimeState.PlaceId,
            }),
        })
    end)

    if not Success or not Response or Response.StatusCode ~= 200 then
        local ServerStatus = "SERVER_ERROR"
        local ServerMsg = "Session verification failed"
        pcall(function()
            local Decoded = HttpService:JSONDecode(Response.Body)
            if Decoded then
                if Decoded.status then ServerStatus = Decoded.status end
                if Decoded.message then ServerMsg = Decoded.message end
            end
        end)
        EnforceViolation(ServerMsg, ServerStatus)
        return false
    end

    local Decoded
    local DecodeOk = pcall(function() Decoded = HttpService:JSONDecode(Response.Body) end)
    if not DecodeOk or not Decoded or not Decoded.success or Decoded.status ~= "VALID" then
        local Status = (Decoded and Decoded.status) or "AUTH_FAILED"
        local Msg = (Decoded and Decoded.message) or "Session revoked by server authority."
        EnforceViolation(Msg, Status)
        return false
    end

    RuntimeState.LastVerified = os.time()
    return true
end

--// Factory for Secure AuthContext (passed directly to game scripts)
local function CreateAuthContext()
    local AuthContext = {}
    AuthContext.IsCoreAuthority = true
    AuthContext.GameId = RuntimeState.GameId
    AuthContext.PlaceId = RuntimeState.PlaceId

    function AuthContext:ValidateRuntime()
        return RuntimeState.IsAuthenticated and (RuntimeState.SessionToken ~= nil) and (#RuntimeState.SessionToken > 10)
    end

    function AuthContext:GetToken()
        return RuntimeState.SessionToken
    end

    function AuthContext:GetKey()
        return RuntimeState.Key
    end

    function AuthContext:GetVars()
        return RuntimeState.Vars
    end

    function AuthContext:VerifyServerSession()
        return VerifySessionWithServer()
    end

    function AuthContext:ProtectFunction(ActionName, OriginalFunc)
        return function(...)
            if not RuntimeState.IsAuthenticated or not RuntimeState.SessionToken then
                EnforceViolation("Protected function '" .. tostring(ActionName) .. "' called without authenticated session.", "AUTH_FAILED")
                return
            end
            if (os.time() - RuntimeState.LastVerified) > RuntimeState.HeartbeatInterval then
                local IsValid = VerifySessionWithServer()
                if not IsValid then return end
            end
            return OriginalFunc(...)
        end
    end

    return AuthContext
end

--// Authenticate with Cloudflare Worker
local function AuthenticateKey(UserKey)
    local RequestFunc = GetRequest()
    if not RequestFunc then
        return false, "SERVER_ERROR", "Executor does not support HTTP requests", nil
    end

    local Hwid = GetHwid()
    local Timestamp = os.time()
    local GameId = tostring(game.GameId)
    local PlaceId = tostring(game.PlaceId)

    local MarketplaceService = Services.MarketplaceService
    local GameName = "Unknown Game"
    pcall(function()
        local Info = MarketplaceService:GetProductInfo(game.PlaceId)
        if Info and Info.Name then GameName = tostring(Info.Name) end
    end)

    local Success, Response = pcall(function()
        return RequestFunc({
            Url = ApiUrl .. "/auth",
            Method = "POST",
            Headers = { ["Content-Type"] = "application/json" },
            Body = HttpService:JSONEncode({
                key = UserKey,
                hwid = Hwid,
                game_id = GameId,
                place_id = PlaceId,
                game_name = GameName,
                GameName = GameName,
                PlaceId = PlaceId,
                GameId = GameId,
                script_uid = "SairyWareCore",
                timestamp = Timestamp,
            }),
        })
    end)

    if not Success or not Response then
        return false, "SERVER_ERROR", STATUS_CONFIG.SERVER_ERROR.Message .. " (Connection Failed)", nil
    end

    local Data = nil
    pcall(function()
        Data = HttpService:JSONDecode(Response.Body)
    end)

    if not Data or type(Data) ~= "table" then
        local FallbackStatus = Response.StatusCode == 429 and "RATE_LIMITED" or (Response.StatusCode == 403 and "INVALID_KEY" or "SERVER_ERROR")
        return false, FallbackStatus, STATUS_CONFIG[FallbackStatus].Message, nil
    end

    if not Data.success or Response.StatusCode ~= 200 or Data.status ~= "VALID" then
        local Status = Data.status or "AUTH_FAILED"
        local Msg = STATUS_CONFIG[Status] and STATUS_CONFIG[Status].Message or (Data.message or "Authentication Failed")
        if Status == "DEVICE_MISMATCH" and Data.data and Data.data.device_reference then
            Msg = string.format("This Key Is Bound To Another Device (%s)", tostring(Data.data.device_reference))
        end
        return false, Status, Msg, Data
    end

    return true, "VALID", STATUS_CONFIG.VALID.Message, Data
end

--// Start Heartbeat & Runtime Security
local function StartSessionGuard(UserKey, Hwid, SessionToken, Vars)
    RuntimeState.IsAuthenticated = true
    RuntimeState.Key = UserKey
    RuntimeState.Hwid = Hwid
    RuntimeState.SessionToken = SessionToken
    RuntimeState.Vars = Vars or {}
    RuntimeState.LastVerified = os.time()

    -- Compatibility fallback (for external inspection without granting authority)
    getgenv().SairySession = SessionToken
    getgenv().SairyKey = UserKey
    getgenv().SairyHwid = Hwid
    getgenv().SairyVars = RuntimeState.Vars

    if RuntimeState.HeartbeatTask then
        task.cancel(RuntimeState.HeartbeatTask)
    end

    RuntimeState.HeartbeatTask = task.spawn(function()
        while RuntimeState.IsAuthenticated do
            task.wait(RuntimeState.HeartbeatInterval)
            if RuntimeState.IsAuthenticated then
                VerifySessionWithServer()
            end
        end
    end)
end

--// Execute Game Script with AuthContext
local function LaunchGamePayload(PayloadString)
    task.spawn(function()
        TaskWait(0.4)
        local ScriptFunction, CompileErr = loadstring(PayloadString)
        if not ScriptFunction then
            warn("[SAIRYWARE CORE] Failed to compile payload: " .. tostring(CompileErr))
            return
        end

        local AuthContext = CreateAuthContext()
        local ExecOk, ExecErr = pcall(function()
            ScriptFunction(AuthContext)
        end)

        if not ExecOk then
            warn("[SAIRYWARE CORE] Execution error: " .. tostring(ExecErr))
        end
    end)
end

--// Render KeySystem UI (Modern Obsidian Glass UI)
local function RenderKeySystemUi(InitialStatusText, InitialStatus)
    -- Clean previous instances
    local ParentGui = GetGuiParent()
    for _, GuiName in ipairs({"SairyWare_KeySystem", "SairyAuthentication"}) do
        local Existing = ParentGui:FindFirstChild(GuiName)
        if Existing then Existing:Destroy() end
    end

    local StoredKey = LoadSavedKey()
    local IsMasked = false
    local IsVerifying = false

    local ScreenGui = Instance.new("ScreenGui")
    ScreenGui.Name = "SairyWare_KeySystem"
    ScreenGui.ResetOnSpawn = false
    ScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    ScreenGui.IgnoreGuiInset = true
    ScreenGui.DisplayOrder = 999
    ScreenGui.Parent = ParentGui
    CurrentActiveGui = ScreenGui

    local BackgroundDim = Instance.new("Frame")
    BackgroundDim.Name = "BackgroundDim"
    BackgroundDim.Size = UDim2.fromScale(1, 1)
    BackgroundDim.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
    BackgroundDim.BackgroundTransparency = 1
    BackgroundDim.BorderSizePixel = 0
    BackgroundDim.Parent = ScreenGui

    local MainModal = Instance.new("CanvasGroup")
    MainModal.Name = "MainModal"
    MainModal.Size = UDim2.fromOffset(480, 430)
    MainModal.Position = UDim2.fromScale(0.5, 0.5)
    MainModal.AnchorPoint = Vector2.new(0.5, 0.5)
    MainModal.BackgroundColor3 = PALETTE.BackgroundObsidian
    MainModal.BorderSizePixel = 0
    MainModal.GroupTransparency = 1
    MainModal.Parent = ScreenGui

    local ModalCorner = Instance.new("UICorner")
    ModalCorner.CornerRadius = UDim.new(0, 16)
    ModalCorner.Parent = MainModal

    local ModalStroke = Instance.new("UIStroke")
    ModalStroke.Name = "ModalStroke"
    ModalStroke.Color = PALETTE.SurfaceBorder
    ModalStroke.Thickness = 1
    ModalStroke.Transparency = 0.92
    ModalStroke.Parent = MainModal

    -- Draggable modal
    local Dragging, DragInput, DragStart, StartPos
    MainModal.InputBegan:Connect(function(Input)
        if Input.UserInputType == Enum.UserInputType.MouseButton1 or Input.UserInputType == Enum.UserInputType.Touch then
            Dragging = true
            DragStart = Input.Position
            StartPos = MainModal.Position
            Input.Changed:Connect(function()
                if Input.UserInputState == Enum.UserInputState.End then Dragging = false end
            end)
        end
    end)
    MainModal.InputChanged:Connect(function(Input)
        if Input.UserInputType == Enum.UserInputType.MouseMovement or Input.UserInputType == Enum.UserInputType.Touch then
            if Dragging and DragStart and StartPos then
                local Delta = Input.Position - DragStart
                MainModal.Position = UDim2.new(StartPos.X.Scale, StartPos.X.Offset + Delta.X, StartPos.Y.Scale, StartPos.Y.Offset + Delta.Y)
            end
        end
    end)

    -- Toast Notification Engine
    local ToastContainer = Instance.new("Frame")
    ToastContainer.Name = "ToastContainer"
    ToastContainer.Size = UDim2.new(1, -48, 0, 48)
    ToastContainer.Position = UDim2.new(0, 24, 1, -64)
    ToastContainer.BackgroundTransparency = 1
    ToastContainer.ZIndex = 10
    ToastContainer.Parent = MainModal

    local ToastCard = Instance.new("Frame")
    ToastCard.Name = "ToastCard"
    ToastCard.Size = UDim2.new(1, 0, 1, 0)
    ToastCard.Position = UDim2.fromOffset(0, 70)
    ToastCard.BackgroundColor3 = PALETTE.SurfaceElevated
    ToastCard.BorderSizePixel = 0
    ToastCard.Parent = ToastContainer

    local ToastCorner = Instance.new("UICorner")
    ToastCorner.CornerRadius = UDim.new(0, 8)
    ToastCorner.Parent = ToastCard

    local ToastAccentBar = Instance.new("Frame")
    ToastAccentBar.Name = "ToastAccentBar"
    ToastAccentBar.Size = UDim2.new(0, 4, 1, 0)
    ToastAccentBar.BackgroundColor3 = PALETTE.CyanElectric
    ToastAccentBar.BorderSizePixel = 0
    ToastAccentBar.Parent = ToastCard

    local ToastTitle = Instance.new("TextLabel")
    ToastTitle.Name = "ToastTitle"
    ToastTitle.Size = UDim2.new(1, -20, 0, 16)
    ToastTitle.Position = UDim2.fromOffset(14, 6)
    ToastTitle.BackgroundTransparency = 1
    ToastTitle.Text = "SYSTEM NOTICE"
    ToastTitle.TextColor3 = PALETTE.TextPrimary
    ToastTitle.TextSize = 11
    ToastTitle.Font = Enum.Font.GothamBold
    ToastTitle.TextXAlignment = Enum.TextXAlignment.Left
    ToastTitle.Parent = ToastCard

    local ToastDesc = Instance.new("TextLabel")
    ToastDesc.Name = "ToastDesc"
    ToastDesc.Size = UDim2.new(1, -20, 0, 18)
    ToastDesc.Position = UDim2.fromOffset(14, 22)
    ToastDesc.BackgroundTransparency = 1
    ToastDesc.Text = "Toast message"
    ToastDesc.TextColor3 = PALETTE.TextSecondary
    ToastDesc.TextSize = 10
    ToastDesc.Font = Enum.Font.GothamMedium
    ToastDesc.TextXAlignment = Enum.TextXAlignment.Left
    ToastDesc.Parent = ToastCard

    local CurrentToastThread = nil
    local function ShowToast(Type, Title, Desc)
        if CurrentToastThread then task.cancel(CurrentToastThread) end
        local AccentColor = PALETTE.CyanElectric
        if Type == "SUCCESS" then AccentColor = PALETTE.SuccessGreen
        elseif Type == "ERROR" then AccentColor = PALETTE.ErrorRed
        elseif Type == "WARNING" then AccentColor = PALETTE.WarningAmber end

        ToastAccentBar.BackgroundColor3 = AccentColor
        ToastTitle.Text = Title:upper()
        ToastTitle.TextColor3 = AccentColor
        ToastDesc.Text = Desc

        TweenService:Create(ToastCard, TweenInfo.new(0.3, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {
            Position = UDim2.fromOffset(0, 0)
        }):Play()

        CurrentToastThread = task.delay(3.5, function()
            TweenService:Create(ToastCard, TweenInfo.new(0.3, Enum.EasingStyle.Quart, Enum.EasingDirection.In), {
                Position = UDim2.fromOffset(0, 70)
            }):Play()
        end)
    end

    -- Header
    local Header = Instance.new("Frame")
    Header.Name = "Header"
    Header.Size = UDim2.new(1, 0, 0, 56)
    Header.BackgroundTransparency = 1
    Header.Parent = MainModal

    local HeaderPadding = Instance.new("UIPadding")
    HeaderPadding.PaddingLeft = UDim.new(0, 24)
    HeaderPadding.PaddingRight = UDim.new(0, 24)
    HeaderPadding.Parent = Header

    local TitleLabel = Instance.new("TextLabel")
    TitleLabel.Name = "TitleLabel"
    TitleLabel.Size = UDim2.new(0.7, 0, 1, 0)
    TitleLabel.BackgroundTransparency = 1
    TitleLabel.Text = "SAIRYWARE  //  KEY AUTHENTICATION"
    TitleLabel.TextColor3 = PALETTE.TextPrimary
    TitleLabel.TextSize = 13
    TitleLabel.Font = Enum.Font.GothamBold
    TitleLabel.TextXAlignment = Enum.TextXAlignment.Left
    TitleLabel.Parent = Header

    local CloseBtn = Instance.new("TextButton")
    CloseBtn.Name = "CloseBtn"
    CloseBtn.Size = UDim2.fromOffset(28, 28)
    CloseBtn.Position = UDim2.new(1, -28, 0.5, 0)
    CloseBtn.AnchorPoint = Vector2.new(0, 0.5)
    CloseBtn.BackgroundColor3 = PALETTE.CardSurface
    CloseBtn.BorderSizePixel = 0
    CloseBtn.Text = "✕"
    CloseBtn.TextColor3 = PALETTE.TextSecondary
    CloseBtn.TextSize = 12
    CloseBtn.Font = Enum.Font.GothamBold
    CloseBtn.Parent = Header

    local CloseCorner = Instance.new("UICorner")
    CloseCorner.CornerRadius = UDim.new(0, 6)
    CloseCorner.Parent = CloseBtn

    CloseBtn.MouseButton1Click:Connect(function()
        TweenService:Create(MainModal, TweenInfo.new(0.25, Enum.EasingStyle.Quart, Enum.EasingDirection.In), {
            GroupTransparency = 1,
            Size = UDim2.fromOffset(450, 400),
        }):Play()
        TweenService:Create(BackgroundDim, TweenInfo.new(0.25), { BackgroundTransparency = 1 }):Play()
        task.wait(0.3)
        ScreenGui:Destroy()
    end)

    -- Body
    local Body = Instance.new("Frame")
    Body.Name = "Body"
    Body.Size = UDim2.new(1, -48, 1, -114)
    Body.Position = UDim2.fromOffset(24, 60)
    Body.BackgroundTransparency = 1
    Body.Parent = MainModal

    local SubtitleLabel = Instance.new("TextLabel")
    SubtitleLabel.Name = "SubtitleLabel"
    SubtitleLabel.Size = UDim2.new(1, 0, 0, 20)
    SubtitleLabel.BackgroundTransparency = 1
    SubtitleLabel.Text = "ENTER YOUR LICENSE KEY TO PROCEED"
    SubtitleLabel.TextColor3 = PALETTE.TextSecondary
    SubtitleLabel.TextSize = 10
    SubtitleLabel.Font = Enum.Font.GothamBold
    SubtitleLabel.TextXAlignment = Enum.TextXAlignment.Left
    SubtitleLabel.Parent = Body

    -- Input Card
    local InputCard = Instance.new("Frame")
    InputCard.Name = "InputCard"
    InputCard.Size = UDim2.new(1, 0, 0, 46)
    InputCard.Position = UDim2.fromOffset(0, 26)
    InputCard.BackgroundColor3 = PALETTE.SurfaceElevated
    InputCard.BorderSizePixel = 0
    InputCard.Parent = Body

    local InputCorner = Instance.new("UICorner")
    InputCorner.CornerRadius = UDim.new(0, 8)
    InputCorner.Parent = InputCard

    local InputStroke = Instance.new("UIStroke")
    InputStroke.Color = PALETTE.SurfaceBorder
    InputStroke.Thickness = 1
    InputStroke.Transparency = 0.92
    InputStroke.Parent = InputCard

    local KeyInputBox = Instance.new("TextBox")
    KeyInputBox.Name = "KeyInputBox"
    KeyInputBox.Size = UDim2.new(1, -85, 1, 0)
    KeyInputBox.Position = UDim2.fromOffset(12, 0)
    KeyInputBox.BackgroundTransparency = 1
    KeyInputBox.Text = StoredKey
    KeyInputBox.PlaceholderText = "SAIRY-XXXX-XXXX-XXXX-XXXX"
    KeyInputBox.PlaceholderColor3 = PALETTE.TextMuted
    KeyInputBox.TextColor3 = PALETTE.TextPrimary
    KeyInputBox.TextSize = 12
    KeyInputBox.Font = Enum.Font.RobotoMono
    KeyInputBox.TextXAlignment = Enum.TextXAlignment.Left
    KeyInputBox.ClearTextOnFocus = false
    KeyInputBox.Parent = InputCard

    local PasteBtn = Instance.new("TextButton")
    PasteBtn.Name = "PasteBtn"
    PasteBtn.Size = UDim2.fromOffset(60, 28)
    PasteBtn.Position = UDim2.new(1, -68, 0.5, 0)
    PasteBtn.AnchorPoint = Vector2.new(0, 0.5)
    PasteBtn.BackgroundColor3 = PALETTE.CardSurface
    PasteBtn.BorderSizePixel = 0
    PasteBtn.Text = "PASTE"
    PasteBtn.TextColor3 = PALETTE.CyanElectric
    PasteBtn.TextSize = 10
    PasteBtn.Font = Enum.Font.GothamBold
    PasteBtn.Parent = InputCard

    local PasteCorner = Instance.new("UICorner")
    PasteCorner.CornerRadius = UDim.new(0, 6)
    PasteCorner.Parent = PasteBtn

    PasteBtn.MouseButton1Click:Connect(function()
        local Clip = GetClipboardText()
        if Clip and #Clip > 0 then
            local Clean = Clip:gsub("%s+", "")
            KeyInputBox.Text = Clean
            StoredKey = Clean
            ShowToast("INFO", "Clipboard Attached", "Key populated from clipboard.")
        end
    end)

    -- Action Buttons Rack
    local ActionRack = Instance.new("Frame")
    ActionRack.Name = "ActionRack"
    ActionRack.Size = UDim2.new(1, 0, 0, 40)
    ActionRack.Position = UDim2.fromOffset(0, 82)
    ActionRack.BackgroundTransparency = 1
    ActionRack.Parent = Body

    local VerifyBtn = Instance.new("TextButton")
    VerifyBtn.Name = "VerifyBtn"
    VerifyBtn.Size = UDim2.new(0.58, -6, 1, 0)
    VerifyBtn.BackgroundColor3 = PALETTE.IrisRoyal
    VerifyBtn.BorderSizePixel = 0
    VerifyBtn.Text = "✔  Verify License"
    VerifyBtn.TextColor3 = PALETTE.TextPrimary
    VerifyBtn.TextSize = 12
    VerifyBtn.Font = Enum.Font.GothamBold
    VerifyBtn.Parent = ActionRack

    local VerifyCorner = Instance.new("UICorner")
    VerifyCorner.CornerRadius = UDim.new(0, 8)
    VerifyCorner.Parent = VerifyBtn

    local GetKeyBtn = Instance.new("TextButton")
    GetKeyBtn.Name = "GetKeyBtn"
    GetKeyBtn.Size = UDim2.new(0.42, -6, 1, 0)
    GetKeyBtn.Position = UDim2.new(0.58, 6, 0, 0)
    GetKeyBtn.BackgroundColor3 = PALETTE.CardSurface
    GetKeyBtn.BorderSizePixel = 0
    GetKeyBtn.Text = "🔑  Get Key"
    GetKeyBtn.TextColor3 = PALETTE.CyanElectric
    GetKeyBtn.TextSize = 12
    GetKeyBtn.Font = Enum.Font.GothamBold
    GetKeyBtn.Parent = ActionRack

    local GetKeyCorner = Instance.new("UICorner")
    GetKeyCorner.CornerRadius = UDim.new(0, 8)
    GetKeyCorner.Parent = GetKeyBtn

    GetKeyBtn.MouseButton1Click:Connect(function()
        local Url = ApiUrl .. "/getkey"
        if SetClipboardText(Url) then
            ShowToast("INFO", "Get Key Copied", "Get-Key link copied to clipboard!")
        end
    end)

    -- Status & Info Cards Rack (2x2 Grid)
    local InfoCardsRack = Instance.new("Frame")
    InfoCardsRack.Name = "InfoCardsRack"
    InfoCardsRack.Size = UDim2.new(1, 0, 0, 110)
    InfoCardsRack.Position = UDim2.fromOffset(0, 134)
    InfoCardsRack.BackgroundTransparency = 1
    InfoCardsRack.Parent = Body

    local InfoLayout = Instance.new("UIGridLayout")
    InfoLayout.CellSize = UDim2.new(0.5, -4, 0, 50)
    InfoLayout.CellPadding = UDim2.new(0, 8, 0, 8)
    InfoLayout.Parent = InfoCardsRack

    local function CreateInfoCard(Title, Val)
        local Card = Instance.new("Frame")
        Card.BackgroundColor3 = PALETTE.CardSurface
        Card.BorderSizePixel = 0
        Card.Parent = InfoCardsRack

        local C = Instance.new("UICorner")
        C.CornerRadius = UDim.new(0, 8)
        C.Parent = Card

        local S = Instance.new("UIStroke")
        S.Color = PALETTE.SurfaceBorder
        S.Thickness = 1
        S.Transparency = 0.92
        S.Parent = Card

        local L = Instance.new("TextLabel")
        L.Size = UDim2.new(1, -16, 0, 14)
        L.Position = UDim2.fromOffset(8, 6)
        L.BackgroundTransparency = 1
        L.Text = Title
        L.TextColor3 = PALETTE.TextMuted
        L.TextSize = 9
        L.Font = Enum.Font.GothamBold
        L.TextXAlignment = Enum.TextXAlignment.Left
        L.Parent = Card

        local V = Instance.new("TextLabel")
        V.Size = UDim2.new(1, -16, 0, 18)
        V.Position = UDim2.fromOffset(8, 22)
        V.BackgroundTransparency = 1
        V.Text = Val
        V.TextColor3 = PALETTE.TextSecondary
        V.TextSize = 11
        V.Font = Enum.Font.GothamMedium
        V.TextXAlignment = Enum.TextXAlignment.Left
        V.Parent = Card

        return V
    end

    local ValStatus = CreateInfoCard("KEY STATUS", InitialStatusText or "● Ready for Input")
    local ValExpires = CreateInfoCard("EXPIRATION", "--")
    local ValHwid = CreateInfoCard("SECURITY CHECK", "✔ HWID Ready")
    local ValNode = CreateInfoCard("AUTHORITY NODE", "CF-Edge Sentinel")

    if InitialStatus and STATUS_CONFIG[InitialStatus] then
        ValStatus.TextColor3 = STATUS_CONFIG[InitialStatus].Color
    end

    -- Footer
    local Footer = Instance.new("Frame")
    Footer.Name = "Footer"
    Footer.Size = UDim2.new(1, 0, 0, 44)
    Footer.Position = UDim2.new(0, 0, 1, -44)
    Footer.BackgroundTransparency = 1
    Footer.Parent = MainModal

    local FooterPadding = Instance.new("UIPadding")
    FooterPadding.PaddingLeft = UDim.new(0, 24)
    FooterPadding.PaddingRight = UDim.new(0, 24)
    FooterPadding.Parent = Footer

    local CreditLabel = Instance.new("TextLabel")
    CreditLabel.Size = UDim2.new(0.65, 0, 1, 0)
    CreditLabel.BackgroundTransparency = 1
    CreditLabel.Text = "SairyWare Core Authority v3.0"
    CreditLabel.TextColor3 = PALETTE.TextMuted
    CreditLabel.TextSize = 11
    CreditLabel.Font = Enum.Font.GothamMedium
    CreditLabel.TextXAlignment = Enum.TextXAlignment.Left
    CreditLabel.Parent = Footer

    local DiscordBtn = Instance.new("TextButton")
    DiscordBtn.Size = UDim2.fromOffset(90, 26)
    DiscordBtn.Position = UDim2.new(1, -90, 0.5, 0)
    DiscordBtn.AnchorPoint = Vector2.new(0, 0.5)
    DiscordBtn.BackgroundColor3 = PALETTE.CardSurface
    DiscordBtn.BorderSizePixel = 0
    DiscordBtn.Text = "💬 Discord"
    DiscordBtn.TextColor3 = PALETTE.TextSecondary
    DiscordBtn.TextSize = 10.5
    DiscordBtn.Font = Enum.Font.GothamMedium
    DiscordBtn.Parent = Footer

    local DiscordCorner = Instance.new("UICorner")
    DiscordCorner.CornerRadius = UDim.new(0, 6)
    DiscordCorner.Parent = DiscordBtn

    DiscordBtn.MouseButton1Click:Connect(function()
        if SetClipboardText(DiscordUrl) then
            ShowToast("INFO", "Discord Link Copied", "Discord invitation link copied!")
        end
    end)

    -- Animate Modal In
    TweenService:Create(BackgroundDim, TweenInfo.new(0.3), { BackgroundTransparency = 0.5 }):Play()
    TweenService:Create(MainModal, TweenInfo.new(0.4, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {
        GroupTransparency = 0
    }):Play()

    -- Verification Action
    VerifyBtn.MouseButton1Click:Connect(function()
        if IsVerifying then return end
        local InputKey = KeyInputBox.Text:gsub("%s+", "")
        if #InputKey == 0 then
            ValStatus.Text = "● Empty Key"
            ValStatus.TextColor3 = PALETTE.ErrorRed
            ShowToast("ERROR", "Input Required", "Please enter your license key.")
            return
        end

        IsVerifying = true
        VerifyBtn.Text = "Verifying..."
        ValStatus.Text = "● Contacting Server..."
        ValStatus.TextColor3 = PALETTE.WarningAmber

        task.spawn(function()
            local Ok, Status, Msg, Data = AuthenticateKey(InputKey)
            VerifyBtn.Text = "✔  Verify License"
            IsVerifying = false

            if Ok and Status == "VALID" and Data then
                SaveKey(InputKey)
                ValStatus.Text = "● Verified"
                ValStatus.TextColor3 = PALETTE.SuccessGreen
                ValExpires.Text = Data.expires_at and "Active" or "Lifetime"
                ValExpires.TextColor3 = PALETTE.SuccessGreen
                ShowToast("SUCCESS", "Access Granted", "Server authority granted access.")

                local SessionToken = Data.data and Data.data.session_token or Data.session_token or Data.signature
                StartSessionGuard(InputKey, GetHwid(), SessionToken, Data.vars or {})

                task.wait(0.7)
                TweenService:Create(MainModal, TweenInfo.new(0.3, Enum.EasingStyle.Quart, Enum.EasingDirection.In), {
                    GroupTransparency = 1,
                    Size = UDim2.fromOffset(450, 400),
                }):Play()
                TweenService:Create(BackgroundDim, TweenInfo.new(0.3), { BackgroundTransparency = 1 }):Play()
                task.wait(0.35)
                ScreenGui:Destroy()
                CurrentActiveGui = nil

                LaunchGamePayload(Data.payload)
            else
                local Color = STATUS_CONFIG[Status] and STATUS_CONFIG[Status].Color or PALETTE.ErrorRed
                ValStatus.Text = "● " .. (STATUS_CONFIG[Status] and STATUS_CONFIG[Status].Message or "Denied")
                ValStatus.TextColor3 = Color
                ShowToast("ERROR", "Access Denied", Msg or "Verification failed.")
            end
        end)
    end)
end

--// Entry Point for SairyWare Core
local function InitializeCore(LaunchOptions)
    LaunchOptions = LaunchOptions or {}
    local SavedKey = _G.SairyKey or LoadSavedKey()

    if SavedKey and #SavedKey > 5 then
        -- Background Verification
        task.spawn(function()
            local Ok, Status, Msg, Data = AuthenticateKey(SavedKey)
            if Ok and Status == "VALID" and Data then
                local SessionToken = Data.data and Data.data.session_token or Data.session_token or Data.signature
                StartSessionGuard(SavedKey, GetHwid(), SessionToken, Data.vars or {})
                LaunchGamePayload(Data.payload)
            else
                RenderKeySystemUi(Msg, Status)
            end
        end)
    else
        RenderKeySystemUi("Please enter your key to continue.", "PROMPT")
    end
end

InitializeCore()

return {
    Version = "3.0.0",
    Initialize = InitializeCore,
}

