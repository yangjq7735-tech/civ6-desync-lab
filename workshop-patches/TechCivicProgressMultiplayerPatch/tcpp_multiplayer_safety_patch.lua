-- Copyright (c) 2026 civ6-desync-lab contributors.
-- This compatibility patch contains no Tech Civic Progress Plus source/assets.

ExposedMembers.TechCivicProgress = ExposedMembers.TechCivicProgress or {};

local function ReadOnlyTechOverflow()
    ExposedMembers.TechCivicProgress.overflow_tech = 0;
end

local function ReadOnlyCivicOverflow()
    ExposedMembers.TechCivicProgress.overflow_civic = 0;
end

ExposedMembers.TechCivicProgress.overflow_tech = 0;
ExposedMembers.TechCivicProgress.overflow_civic = 0;
ExposedMembers.TechCivicProgress.GetTechOverflow = ReadOnlyTechOverflow;
ExposedMembers.TechCivicProgress.GetCivicOverflow = ReadOnlyCivicOverflow;

print("Tech Civic Progress Plus Multiplayer Safety Patch: mutation-based overflow probing disabled");
