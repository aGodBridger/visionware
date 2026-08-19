-- https://discord.gg/tUEJZYvF9d  (wapus)  -- adapted for aGodBridger/visionware
-- Runs the full Phantom Forces cheat (source.lua) EXACTLY like wapus does.
-- source.lua contains ESP, aimbot, silent aim, triggerbot, speed, movement,
-- visuals, etc. NOTE: this requires an executor with getgc / run_on_actor /
-- getactorthreads (internal-style executor). Low-UNC executors (Xeno) can't run it.
local executor = string.lower(identifyexecutor and identifyexecutor() or "")
local source = game:HttpGet("https://raw.githubusercontent.com/aGodBridger/visionware/refs/heads/main/source.lua")
local threadSource = [[
    for _, func in getgc(false) do
        if type(func) == "function" and islclosure(func) and debug.getinfo(func).name == "require" and string.find(debug.getinfo(func).source, "ClientLoader") then
            ]] .. source .. [[
            break
        end
    end
]]

local function runSource(runner, getAll)
    for _, actor in getAll() do
        pcall(runner, actor, threadSource)
    end
end

if string.find(executor, "choco") and (not getgenv().executed) then
    runSource(run_on_actor, get_deleted_actors)
elseif string.find(executor, "volt") and (not getgenv().executed) then
    runSource(run_on_actor, getactors)
elseif string.find(executor, "potassium") and (not getgenv().executed) then
    runSource(run_on_thread, getactorthreads)
elseif string.find(executor, "nihon") and (not getgenv().executed) then
    runSource(run_on_actor, getdeletedactors)
elseif string.find(executor, "synapse z") and (not getgenv().executed) then
    runSource(run_on_actor, getdeletedactors)
elseif string.find(executor, "yubx") and (not getgenv().executed) then
    runSource(run_on_actor, getdeletedactors)
elseif string.find(executor, "cosmic") and (not getgenv().executed) then
    runSource(run_on_actor, getdeletedactors)
elseif getfflag and (string.lower(tostring(getfflag("DebugRunParallelLuaOnMainThread"))) == "true") then
    loadstring(source)()
elseif setfflag then
    pcall(function()
        setfflag("DebugRunParallelLuaOnMainThread", "True")
        if queue_on_teleport then queue_on_teleport(source) end
        game:GetService("TeleportService"):Teleport(game.PlaceId)
    end)
else
    -- fallback: try to run on the main thread
    pcall(loadstring, source)
end

getgenv().executed = true