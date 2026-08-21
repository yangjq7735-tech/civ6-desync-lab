-- Copyright (c) 2026 civ6-desync-lab contributors.
-- This compatibility patch contains no Multiplayer Helper source or assets.
-- It detaches known unsafe callbacks after the dependency initializes.

local function RemoveCallback(eventObject, callback, label)
    if eventObject ~= nil and callback ~= nil then
        eventObject.Remove(callback);
        print("Multiplayer Helper Safety Patch: detached " .. label);
    end
end

RemoveCallback(GameEvents.OnGameTurnStarted, OnGameTurnStarted, "diagnostic RNG callback");
RemoveCallback(GameEvents.OnGameTurnStarted, NoMoreStack, "automatic research/civic callback");
RemoveCallback(LuaEvents.UICPLPlayerDrop, OnDrop, "drop freeze callback");
RemoveCallback(LuaEvents.UICPLPlayerConnect, OnConnect, "reconnect restore callback");
RemoveCallback(LuaEvents.UISuddenDeathTimeExpireAI, OnTimerExpires, "sudden-death destruction callback");
RemoveCallback(LuaEvents.UISuddenDeathSavetime, OnTimeSaved, "timer property callback");

print("Multiplayer Helper Multiplayer Safety Patch initialized");
