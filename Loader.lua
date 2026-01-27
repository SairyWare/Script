--[[
    SairyWare Private Loader

    Developed by SairyWare Team
    Lead Developer: alert3z

    ⚠ This software is private.
    Any modification, redistribution, or cracking is prohibited.

    © 2026 SairyWare Private. All rights reserved.
]]--

print("Welcome to SairyWare Private")

if not game:IsLoaded() then
    game.Loaded:Wait()
end

task.wait(3)

local Game = {
    [game.PlaceId] = "url"
}

local Modules = {
    Executor = ((identifyexecutor and identifyexecutor()) or (getexecutorname and getexecutorname()) or "Unknown"),
    Load = function()
        local _Src = Game[game.PlaceId]
        if not _Src then
            return warn("❌ Unsupported game ->", game.PlaceId)
        end
    
        local _Success, _Err = pcall(function()
            loadstring(game:HttpGet(_Src))()
        end)
    
        if not _Success then
            warn("❌ Failed to load script:", _Err)
        end
    end
}

local BlockedExecutors = { "xeno", "solara", "jjsploit" }

local function NotSupport()
    local _Exec = Modules.Executor:lower()
    for _, v in ipairs(BlockedExecutors) do
        if _Exec:find(v) then
            return true
        end
    end
    return false
end

print("Execute On ->", Modules.Executor)

if NotSupport() then
    game.Players.LocalPlayer:Kick(
        "⚠️ Executor "..Modules.Executor.." not supported ⚠️"
    )
    return
end;

Modules.Load()