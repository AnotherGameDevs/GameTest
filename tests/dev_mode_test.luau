-- Run via tests/run_all.sh. Developer test mode, offline: access rules, request validation, the isolated test overlay against a fake DataStore,
-- and the guards that stop test rewards reaching a normal profile. NOT proof of anything in the engine (the panel, remotes and world actions
-- are listed as "not run" in docs/DEVELOPER_MODE.md).
local DevAccess = require("../src/server/Services/DevAccess")
local DevProfile = require("../src/server/Services/DevProfile")
local DevScenario = require("../src/server/Services/DevScenario")
local ProfileOverlay = require("../src/server/Services/ProfileOverlay")
local ProfileStore = require("../src/server/Services/ProfileStore")
local SessionLock = require("../src/server/Services/SessionLock")
local MineLifecycle = require("../src/server/Services/MineLifecycle")
local Defs = require("./_build/shared/Defs")
local Config = require("./_build/shared/Config")
local CollectionSpec = require("./_build/shared/CollectionSpec")

local passed, failed = 0, 0
local function check(name, cond, detail) if cond then passed += 1 else failed += 1; print("FAIL: " .. name .. (detail and ("  -> " .. tostring(detail)) or "")) end end

-- 1. access ---------------------------------------------------------------------------------------------------------------------------------
local function ctx(over)
	local c = { IsStudio = false, PlaceId = 111, UserId = 42, AllowedUserIds = {}, TestPlaceIds = {} }
	for k, v in pairs(over or {}) do c[k] = v end
	return c
end
check("shipped config: nobody is allowlisted and no test place is set", #Config.Dev.AllowedUserIds == 0 and #Config.Dev.TestPlaceIds == 0)
check("published server with the shipped (empty) config denies everyone", not DevAccess.Resolve(ctx({ AllowedUserIds = Config.Dev.AllowedUserIds, TestPlaceIds = Config.Dev.TestPlaceIds })).Allowed)
check("Studio allows (private server)", DevAccess.Resolve(ctx({ IsStudio = true })).Allowed and DevAccess.Resolve(ctx({ IsStudio = true })).World)
check("allowlisted user on a listed test place is allowed", DevAccess.Resolve(ctx({ AllowedUserIds = { 42 }, TestPlaceIds = { 111 } })).Allowed)
check("allowlisted user on a production place is DENIED (cannot reset a public mine)", not DevAccess.Resolve(ctx({ AllowedUserIds = { 42 }, TestPlaceIds = { 999 } })).Allowed)
check("non-allowlisted user on the test place is denied", not DevAccess.Resolve(ctx({ AllowedUserIds = { 7 }, TestPlaceIds = { 111 } })).Allowed)
check("no world access without access", not DevAccess.Resolve(ctx({ AllowedUserIds = { 7 }, TestPlaceIds = { 111 } })).World)
for _, bad in ipairs({ "42", 0, -5, 4.5, 1 / 0, 0 / 0, true }) do
	check("malformed UserId never matches: " .. tostring(bad), not DevAccess.Resolve(ctx({ UserId = bad, AllowedUserIds = { 42, "42", 0, -5 }, TestPlaceIds = { 111 } })).Allowed)
end
check("malformed lists are ignored", not DevAccess.Resolve(ctx({ AllowedUserIds = "42", TestPlaceIds = 111 })).Allowed and not DevAccess.Resolve(ctx({ AllowedUserIds = nil, TestPlaceIds = nil })).Allowed)
check("a client claim is not an input: Resolve ignores unknown fields", not DevAccess.Resolve(ctx({ ClaimsDeveloper = true, IsDeveloper = true })).Allowed)

-- 2. request validation -----------------------------------------------------------------------------------------------------------------------
local defs = { Tools = Defs.Tools, Backpacks = Defs.Backpacks, Treasure = Defs.Treasure, StopCount = 5, MaxCash = Config.Dev.MaxCash }
local function v(a, x) return DevAccess.Validate(a, x, defs) end
for _, a in ipairs({ "Hack", "", 5, nil, {}, "enter", "__index", "Enter;Exit" }) do
	check("unknown action rejected: " .. tostring(a), not (v(a, nil)))
end
check("Equip tool ok", select(2, v("Equip", { Kind = "Tool", Id = "drill" })).Id == "drill")
check("Equip backpack ok", select(2, v("Equip", { Kind = "Backpack", Id = "pouch" })).Kind == "Backpack")
check("Equip unknown id rejected", not v("Equip", { Kind = "Tool", Id = "laser" }) and not v("Equip", { Kind = "Backpack", Id = "drill" }))
check("Equip junk rejected", not v("Equip", nil) and not v("Equip", "drill") and not v("Equip", { Kind = 1, Id = 2 }) and not v("Equip", { Kind = "Consumable", Id = "dynamite" }))
check("GrantCash clamps", select(2, v("GrantCash", 5e12)) == Config.Dev.MaxCash and select(2, v("GrantCash", 2500.9)) == 2500)
check("GrantCash rejects negatives, zero, NaN, inf, strings, tables", not v("GrantCash", -5) and not v("GrantCash", 0) and not v("GrantCash", 0 / 0) and not v("GrantCash", 1 / 0) and not v("GrantCash", "9") and not v("GrantCash", {}))
check("Teleport range", v("Teleport", 1) and v("Teleport", 5) and not v("Teleport", 0) and not v("Teleport", 6) and not v("Teleport", 1.5) and not v("Teleport", "2"))
check("Spawn / reveal need a real treasure id", v("SpawnArtifact", "sun_mask") and not v("SpawnArtifact", "nothing") and not v("Reveal", 5) and v("Reveal", "bronze_ring"))

-- 3. permission matrix -----------------------------------------------------------------------------------------------------------------------
local studio = DevAccess.Resolve(ctx({ IsStudio = true }))
local denied = DevAccess.Resolve(ctx())
for action, def in pairs(DevAccess.Actions) do
	check("denied account can do nothing: " .. action, not DevAccess.Permit(action, denied, true))
	check("nil access can do nothing: " .. action, not DevAccess.Permit(action, nil, true))
	if def.Needs == "Test" then
		check("needs test mode: " .. action, not DevAccess.Permit(action, studio, false) and DevAccess.Permit(action, studio, true))
	end
	if def.World then
		check("world action needs world access: " .. action, not DevAccess.Permit(action, { Allowed = true, World = false }, true))
	end
end
check("Enter / Exit are available outside test mode", DevAccess.Permit("Enter", studio, false) and DevAccess.Permit("Exit", studio, false))
check("every shared-world action is flagged as world", DevAccess.Actions.SpawnArtifact.World and DevAccess.Actions.StartRelic.World and DevAccess.Actions.ResetMine.World)
check("moving only yourself / editing only the overlay is not a world action", not DevAccess.Actions.Teleport.World and not DevAccess.Actions.UnlockAll.World and not DevAccess.Actions.GrantCash.World)
check("session label: temporary / isolated / normal",
	DevAccess.SessionLabel({ Saving = false }):find("Temporary") ~= nil
	and DevAccess.SessionLabel({ Saving = true, Mode = "studio-test-store" }):find("Isolated test store") ~= nil
	and DevAccess.SessionLabel({ Saving = true, Mode = "production-store" }):find("Normal play") ~= nil)

-- 4. profile operations on the overlay ------------------------------------------------------------------------------------------------------------
local function realProfile()
	return { Version = 3, Cash = 1234, Reputation = 0, Equipment = { ToolId = "digging_shovel", BackpackId = "satchel" },
		OwnedTools = { rusty_shovel = true, digging_shovel = true }, OwnedBackpacks = { pouch = true, satchel = true }, Consumables = {},
		BackpackItems = { old_coin = 3 }, Collection = { old_coin = { Count = 4, FirstFound = 99 } }, Display = { "old_coin" }, Guide = { mine = true },
		GuideBase = {}, Settings = { MasterVolume = 0.5 }, Stats = { BlocksDug = 77, TreasureFound = 5, CashEarned = 1500, RelicsExtracted = 0 } }
end
local function eq(a, b) if type(a) ~= type(b) then return false end if type(a) ~= "table" then return a == b end for k, x in pairs(a) do if not eq(x, b[k]) then return false end end for k in pairs(b) do if a[k] == nil then return false end end return true end

local d = realProfile()
DevProfile.UnlockAllEquipment(d, Defs)
local allTools, allPacks = true, true
for id in pairs(Defs.Tools) do allTools = allTools and d.OwnedTools[id] == true end
for id in pairs(Defs.Backpacks) do allPacks = allPacks and d.OwnedBackpacks[id] == true end
check("unlock all: every tool and backpack is owned", allTools and allPacks)
check("unlock all: dynamite filled to its carry limit", d.Consumables.dynamite == Defs.Consumables.dynamite.MaxCarry)
check("unlock all does not change what is equipped", d.Equipment.ToolId == "digging_shovel" and d.Equipment.BackpackId == "satchel")
check("equip any tool", DevProfile.Equip(d, "Tool", "industrial_drill", Defs) and d.Equipment.ToolId == "industrial_drill")
check("equip any backpack", DevProfile.Equip(d, "Backpack", "expedition_pack", Defs) and d.Equipment.BackpackId == "expedition_pack")
check("equip unknown id changes nothing", not DevProfile.Equip(d, "Tool", "laser", Defs) and d.Equipment.ToolId == "industrial_drill")
check("cash grant", DevProfile.GrantCash(d, 5000, Config.Dev.MaxCash) == 5000 and d.Cash == 6234)
DevProfile.UnlockCollection(d, CollectionSpec, Defs, 5, Config.Collection.DisplaySlots)
local allEntries = true
for id in pairs(Defs.Treasure) do allEntries = allEntries and d.Collection[id] ~= nil end
check("collection unlock: every entry exists", allEntries)
check("collection unlock: shelf is filled and valid", #d.Display > 0 and #d.Display <= Config.Collection.DisplaySlots and #CollectionSpec.SanitizeDisplay(d.Display, d.Collection) == #d.Display)
check("an existing entry keeps its real count", d.Collection.old_coin.Count == 4)

-- 5. isolation: the overlay never reaches the DataStore ------------------------------------------------------------------------------------------------
local function deepcopy(t) if type(t) ~= "table" then return t end local c = {} for k, x in pairs(t) do c[k] = deepcopy(x) end return c end
local function newStore()
	local st = { data = {}, writes = 0 }
	function st:UpdateAsync(key, fn) local new = fn(deepcopy(self.data[key])); if new ~= nil then self.data[key] = deepcopy(new); self.writes += 1 end end
	return st
end
local clock = 1000
local A = { JobId = "A", Lock = SessionLock, Now = function() return clock end, LockTimeout = 120,
	Attempt = function(fn, tries) local ok, res; for _ = 1, tries do ok, res = pcall(fn); if ok then return true, res end end return false, res end }
local K = "Player_42"

local original = realProfile()
local st = newStore()
local record = { Data = deepcopy(original), Dirty = false, Overlay = false, Normal = nil }
local live = record.Data -- the table every service holds
local function save(release) return ProfileStore.Save(st, K, deepcopy(ProfileOverlay.SaveSource(record)), release, A, 3) end
check("baseline save writes the real profile", save(false).Ok and eq(st.data[K].Equipment, original.Equipment))

check("enter test mode", ProfileOverlay.Enter(record) and ProfileOverlay.Active(record))
check("entering twice is refused", not ProfileOverlay.Enter(record))
check("the live table is the SAME table (services keep working)", record.Data == live)
check("overlay starts as a copy of the real profile", live.Cash == 1234)
DevProfile.UnlockAllEquipment(live, Defs); DevProfile.GrantCash(live, 900000, Config.Dev.MaxCash); DevProfile.Equip(live, "Tool", "industrial_drill", Defs)
DevProfile.UnlockCollection(live, CollectionSpec, Defs, 1, Config.Collection.DisplaySlots)
live.Guide.skipped = true; live.Settings.MasterVolume = 0; live.Stats.RelicsExtracted = 9
record.Dirty = false
ProfileOverlay.MarkDirty(record)
check("test actions never mark the real profile dirty", record.Dirty == false)
for _, release in ipairs({ false, true }) do
	save(release)
	check("autosave / leave save writes the REAL profile, not the overlay (release=" .. tostring(release) .. ")",
		st.data[K].Cash == 1234 and st.data[K].Equipment.ToolId == "digging_shovel" and st.data[K].OwnedTools.industrial_drill == nil
		and st.data[K].Collection.sun_mask == nil and st.data[K].Guide.skipped == nil and st.data[K].Settings.MasterVolume == 0.5 and st.data[K].Stats.RelicsExtracted == 0)
end
check("the stored profile still equals the original (ignoring lock)", (function() local s = deepcopy(st.data[K]); s.SessionLock = nil; return eq(s, original) end)())

check("fresh test profile replaces only the overlay", ProfileOverlay.Fresh(record, { Cash = 0, Equipment = { ToolId = "rusty_shovel" }, OwnedTools = { rusty_shovel = true }, Collection = {}, Guide = {}, Stats = {} }) and live.Cash == 0)
save(false)
check("a fresh test profile does not wipe the stored profile", st.data[K].Cash == 1234 and st.data[K].Collection.old_coin.Count == 4)

check("exit restores the real profile exactly", ProfileOverlay.Exit(record) and eq(live, original) and not ProfileOverlay.Active(record))
check("exit twice is refused", not ProfileOverlay.Exit(record))
check("after exit, real changes are saved again", (function() live.Cash += 10; ProfileOverlay.MarkDirty(record); save(true); return record.Dirty and st.data[K].Cash == 1244 end)())

-- failed-load stand-in: overlay on a memory-only profile still cannot create a stored profile
local st2 = newStore()
local rec2 = { Data = { Cash = 5 }, Overlay = false, NoSave = true }
ProfileOverlay.Enter(rec2); rec2.Data.Cash = 999
check("a memory-only profile with an overlay writes nothing (nothing to write, nothing stored)", st2.writes == 0)

-- 6. test rewards cannot reach a normal profile ---------------------------------------------------------------------------------------------------------
DevScenario.Mark("rec-1")
check("a marked artifact is a test artifact", DevScenario.IsTest("rec-1") and not DevScenario.IsTest("rec-2") and not DevScenario.IsTest(nil))
DevScenario.Clear("rec-1")
check("cleared after deposit", not DevScenario.IsTest("rec-1"))
DevScenario.Mark("a"); DevScenario.Mark("b"); DevScenario.Reset()
check("reset clears all", not DevScenario.IsTest("a") and not DevScenario.IsTest("b"))

-- 7. mine reset helper uses the existing state machine ---------------------------------------------------------------------------------------------------
local lc = MineLifecycle.new(Config.Reset, 0)
check("manual reset starts a Warning (the normal first step)", lc:RequestManual(10, 15) and lc:State() == "Warning" and lc:Reason() == "Manual" and lc:EndsAt() == 25)
check("manual reset cannot overlap a reset in flight", not lc:RequestManual(11, 15))
check("the normal path continues: Evacuate at the end of the warning", lc:Update(24, 0, 1) == nil and lc:Update(25, 0, 1) == "Evacuate" and lc:State() == "Evacuating")
check("manual reset refused while evacuating", not lc:RequestManual(26, 15))
check("regeneration then a NEW generation", lc:BeginRegeneration() and lc:FinishRegeneration(30) and lc:State() == "Active" and lc:Generation() == 2)
check("a second manual reset is allowed once Active again", lc:RequestManual(40, 10) and lc:EndsAt() == 50)
local lc2 = MineLifecycle.new(Config.Reset, 0)
check("warning countdown never below 1 s", lc2:RequestManual(0, -50) and lc2:EndsAt() == 1)
check("scheduled reset logic is unchanged", (function() local l = MineLifecycle.new(Config.Reset, 0); return l:Update(Config.Reset.IntervalMinutes * 60 + 1, 0, 1) == "Warn" and l:Reason() == "Scheduled" end)())

print(("dev_mode_test: %d passed, %d failed"):format(passed, failed))
if failed > 0 then error("dev_mode_test failed") end
