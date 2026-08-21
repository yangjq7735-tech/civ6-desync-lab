-- Quick Deals Desync Probe
--
-- This deliberately exercises Quick Deals' existing UI-to-gameplay cache bridge.
-- It contains no debugger, tuner, native hook, network API, or repeated update loop.

local PROBE_VERSION = 1
local m_hasTriggered = false

local function Log(status, details)
    print("QD_DESYNC_PROBE version=" .. tostring(PROBE_VERSION)
        .. " status=" .. tostring(status)
        .. " " .. tostring(details or ""))
end

local function OnLoadGameViewStateDone()
    if m_hasTriggered then
        return
    end

    if not GameConfiguration.IsAnyMultiplayer() then
        Log("SKIP", "reason=not-multiplayer")
        return
    end

    local localPlayerID = Game.GetLocalPlayer()
    if localPlayerID == nil or localPlayerID < 0 then
        Log("SKIP", "reason=no-local-player")
        return
    end

    local qd = ExposedMembers.QD
    local cacheManager = qd and qd.CacheManager
    if cacheManager == nil or cacheManager.SetCachedDeals == nil or cacheManager.GetCachedDeals == nil then
        Log("ERROR", "reason=quick-deals-cache-manager-unavailable localPlayer=" .. tostring(localPlayerID))
        return
    end

    m_hasTriggered = true

    -- Both the target Player object inside Quick Deals and this value differ by
    -- client. This makes the unsafe local-client write unambiguous.
    local marker = {
        Probe = "QD_DESYNC_PROBE",
        Version = PROBE_VERSION,
        LocalPlayer = localPlayerID,
        MarkerValue = 100000 + localPlayerID
    }

    cacheManager.SetCachedDeals(marker, true)

    local readback = cacheManager.GetCachedDeals(true) or {}
    Log("WRITE",
        "localPlayer=" .. tostring(localPlayerID)
        .. " markerValue=" .. tostring(marker.MarkerValue)
        .. " readbackLocalPlayer=" .. tostring(readback.LocalPlayer)
        .. " readbackMarkerValue=" .. tostring(readback.MarkerValue))
end

Events.LoadGameViewStateDone.Add(OnLoadGameViewStateDone)
Log("ARMED", "event=LoadGameViewStateDone")
