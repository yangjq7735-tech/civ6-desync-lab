-- Copyright (c) 2026 civ6-desync-lab contributors.
-- This compatibility patch contains no Quick Deals source or assets.

local sellableDeals = {};
local buyableDeals = {};
local SafeCacheManager = {};

SafeCacheManager.GetCachedDeals = function(isSell:boolean)
    if isSell then
        return sellableDeals;
    end
    return buyableDeals;
end

SafeCacheManager.SetCachedDeals = function(deals:table, isSell:boolean)
    if isSell then
        sellableDeals = deals or {};
    else
        buyableDeals = deals or {};
    end
end

ExposedMembers.QD = ExposedMembers.QD or {};
ExposedMembers.QD.CacheManager = SafeCacheManager;

print("Quick Deals Multiplayer Safety Patch: process-local cache installed");
