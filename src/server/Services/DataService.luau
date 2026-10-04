-- Persistent player data. Versioned schema + migrations, dirty-flag autosave (no write spam),
-- graceful fallback to memory-only when DataStores are unavailable (e.g. unpublished place in Studio).
local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Util = require(ReplicatedStorage.Shared.Util)
local Defs = require(ReplicatedStorage.Shared.Defs)
local DataMigrations = require(script.Parent.DataMigrations)
local SaveMode = require(script.Parent.SaveMode)
local ProfileStore = require(script.Parent.ProfileStore)
local SessionLock = require(script.Parent.SessionLock)
local SettingsSpec = require(ReplicatedStorage.Shared.SettingsSpec)
local CollectionSpec = require(ReplicatedStorage.Shared.CollectionSpec)

local DataService = {}

local function defaultData()
	return {
		Version = Config.Data.CurrentVersion,
		Cash = Config.Starting.Cash,
		Reputation = 0,
		Equipment = { ToolId = Config.Starting.ToolId, BackpackId = Config.Starting.BackpackId },
		OwnedTools = { [Config.Starting.ToolId] = true },
		OwnedBackpacks = { [Config.Starting.BackpackId] = true },
		Consumables = {}, -- [consumableId] = count (e.g. dynamite)
		BackpackItems = {}, -- [treasureId] = count (persisted so a reset/rejoin never eats your haul)
		Research = {},
		UnlockedSites = {},
		Collection = {}, -- [treasureId] = { Count, FirstFound }
		Display = {}, -- treasure ids shown on the player's camp shelf (subset of Collection)
		Guide = {}, -- [hintId] = true once a first-time hint is finished; Guide.skipped = true after "Skip tutorial"
		GuideBase = {}, -- lifetime counters at the last tutorial restart (GuideSpec.Baseline); {} = never restarted
		Stats = {
			BlocksDug = 0, TreasureFound = 0, CashEarned = 0,
			RelicsDiscovered = 0, RelicsExtracted = 0, RelicsStolen = 0, DeepestDepth = 0,
		},
		Cosmetics = {},
		EquippedCosmetics = {},
		Settings = SettingsSpec.Defaults(),
	}
end

local function migrate(data)
	-- fields that must be tables are replaced by their defaults if a corrupted save holds something else
	local template = defaultData()
	for k, v in pairs(template) do
		if type(v) == "table" and type(data[k]) ~= "table" and data[k] ~= nil then
			data[k] = Util.DeepCopy(v)
		end
	end
	DataMigrations.Migrate(data, Config.Data.CurrentVersion, Defs)
	Util.Reconcile(data, template)
	DataMigrations.Sanitize(data, Defs, Config.Starting.ToolId, Config.Starting.BackpackId)
	data.Settings = SettingsSpec.Sanitize(data.Settings) -- clamp whatever was saved
	DataMigrations.SanitizeCollection(data, Defs)
	data.Display = CollectionSpec.SanitizeDisplay(data.Display, data.Collection)
end

-- GetDataStore throws in an unpublished place, so it must never run unprotected.
local store
if Config.Data.Enabled then
	local ok, result = pcall(function()
		-- Studio sessions NEVER touch the production store, even if Studio API access is on for the production place.
		return DataStoreService:GetDataStore(RunService:IsStudio() and Config.Data.StudioStoreName or Config.Data.StoreName)
	end)
	if ok then
		store = result
	else
		warn("[DataService] DataStore unavailable (publish the place to enable saving). Running without saving. " .. tostring(result))
	end
end

local storeName = RunService:IsStudio() and Config.Data.StudioStoreName or Config.Data.StoreName
-- What kind of storage this server session has (never personal data): used for logs and the player-facing test-session notice.
local storageMode: string
if not Config.Data.Enabled then
	storageMode = "disabled"
elseif not store then
	storageMode = "no-datastore"
elseif RunService:IsStudio() then
	storageMode = "studio-test-store"
else
	storageMode = "production-store"
end
print(("[DataService] storage mode: %s (store '%s', Studio=%s, JobId='%s')"):format(storageMode, store and storeName or "-", tostring(RunService:IsStudio()), game.JobId))
if storageMode == "no-datastore" or storageMode == "disabled" then
	warn("[DataService] NO DataStore: every session is memory-only and nothing will be saved. (Publish the place and, for Studio testing, enable Studio Access to API Services on an isolated TEST place: docs/ISOLATED_TEST_EXPERIENCE.md)")
end

local diagnostics = { LoadsOk = 0, LoadsFailed = 0, LockRefusals = 0, SavesOk = 0, SavesFailed = 0, MemoryOnlyProfiles = 0, Kicks = 0 }

local LOCK_TIMEOUT = 120 -- seconds after which another server's lock is treated as dead (crash / lost release)
local LOCK_REFRESH = 45 -- rewrite at least this often so a live session's lock never goes stale
local profiles: { [Player]: { Data: any, Dirty: boolean, NoSave: boolean, SaveReason: string, LastWrite: number, Saving: boolean } } = {}
local loadedCallbacks: { (Player, any) -> () } = {}
local lastSaveWarn: { [Player]: number } = {}
local lastSaveLog: { [Player]: number } = {}
local inFlightFinalSaves = 0

local function key(player: Player)
	return "Player_" .. player.UserId
end

local function isStudio()
	return RunService:IsStudio()
end

local function attempt(fn: () -> any, tries: number)
	local ok, result
	if isStudio() then
		tries = math.min(tries, 2) -- fail fast in Studio so a missing API permission doesn't delay loading
	end
	for i = 1, tries do
		ok, result = pcall(fn)
		if ok then
			return true, result
		end
		if i < tries then
			task.wait(i * 2)
		end
	end
	return false, result
end

local storeCtx = { JobId = game.JobId, Lock = SessionLock, Now = os.time, LockTimeout = LOCK_TIMEOUT, Attempt = attempt }

function DataService.OnLoaded(cb: (Player, any) -> ())
	table.insert(loadedCallbacks, cb)
end

function DataService.Get(player: Player)
	local p = profiles[player]
	return p and p.Data
end

function DataService.MarkDirty(player: Player)
	local p = profiles[player]
	if p then
		p.Dirty = true
	end
end

-- Writes the profile. `release` also drops the session lock (player leaving / server closing).
-- Returns true when nothing needed writing or the write succeeded.
function DataService.Save(player: Player, force: boolean?, release: boolean?): boolean
	local p = profiles[player]
	if not p or not store or p.NoSave then
		return true
	end
	local stale = os.clock() - p.LastWrite >= LOCK_REFRESH
	if not p.Dirty and not force and not stale then
		return true
	end
	if p.Saving then
		if not (force or release) then
			return true -- an autosave is already in flight; the next one picks up newer changes
		end
		while p.Saving do -- a final save must not be skipped: wait for the in-flight write, then write again
			task.wait(0.1)
		end
	end
	p.Saving = true
	p.Dirty = false
	local snapshot = Util.DeepCopy(p.Data)
	local result = ProfileStore.Save(store, key(player), snapshot, release == true, storeCtx, 3)
	local ok, lostLock, err = result.Ok, result.LostLock, result.Err
	p.Saving = false
	if ok then
		p.LastWrite = os.clock()
		diagnostics.SavesOk += 1
		if os.clock() - (lastSaveLog[player] or -1e9) > 300 or release then
			lastSaveLog[player] = os.clock()
			print(("[DataService] saved %s (%s%s)"):format(player.Name, release and "final, lock released" or "autosave", force and ", forced" or ""))
		end
		return true
	end
	diagnostics.SavesFailed += 1
	p.Dirty = true
	if lostLock then
		p.NoSave = true -- never write again from this server
		diagnostics.LockRefusals += 1
		warn(("[DataService] SESSION LOCK lost: %s's profile is now owned by another server; saving from this one is disabled."):format(player.Name))
	elseif os.clock() - (lastSaveWarn[player] or 0) > 30 then
		lastSaveWarn[player] = os.clock()
		warn(("[DataService] Save failed for %s (will retry): %s"):format(player.Name, tostring(err)))
	end
	return false
end

local function load(player: Player)
	local data
	local readOk, locked = true, false
	if store then
		local r = ProfileStore.Load(store, key(player), storeCtx, 4)
		readOk, locked, data = r.Ok, r.Locked, r.Data
		if locked then
			diagnostics.LockRefusals += 1
			warn(("[DataService] SESSION LOCK: %s's profile is held by another live server; refusing to load it here."):format(player.Name))
		elseif not r.Ok then
			warn(("[DataService] LOAD FAILED for %s: %s"):format(player.Name, tostring(r.Err)))
		end
	end

	local hasData = type(data) == "table"
	local migrateOk = true
	if hasData then
		data.SessionLock = nil
		local okMigrate, errMigrate = pcall(migrate, data)
		migrateOk = okMigrate
		if not okMigrate then
			warn("[DataService] Could not migrate " .. player.Name .. "'s save: " .. tostring(errMigrate))
		end
	end

	-- One decision for every outcome (SaveMode, unit-tested): anything we could not use is NEVER saved over.
	local mode = SaveMode.Decide({ StoreAvailable = store ~= nil, ReadOk = readOk and not locked, Locked = locked, HasData = hasData,
		MigrateOk = migrateOk, IsStudio = isStudio() })
	if mode.Kick then
		diagnostics.LoadsFailed += 1
		diagnostics.Kicks += 1
		warn(("[DataService] %s refused (%s): nothing was written."):format(player.Name, mode.Reason))
		-- we may hold the lock from a successful read: let go of it, then refuse the join
		if store and readOk and not locked then
			ProfileStore.Release(store, key(player), storeCtx)
		end
		if player.Parent then
			player:Kick(SaveMode.KickMessages[mode.Reason] or "Your saved progress could not be loaded.")
		end
		return
	end
	if mode.UseDefaults then
		data = defaultData()
	end
	local noSave = not mode.Persist
	if not player.Parent then
		if store and readOk and not locked then
			ProfileStore.Release(store, key(player), storeCtx) -- joined and left before the profile was kept: release the lock we took
		end
		return
	end
	if noSave then
		diagnostics.MemoryOnlyProfiles += 1
		warn(("[DataService] %s plays on a MEMORY-ONLY profile (%s): nothing will be saved this session."):format(player.Name, mode.Reason))
	elseif isStudio() then
		print(("[DataService] Studio session saving to the TEST store '%s' (%s)."):format(Config.Data.StudioStoreName, mode.Reason))
	end
	if not noSave then
		diagnostics.LoadsOk += 1
	end
	profiles[player] = { Data = data, Dirty = false, NoSave = noSave, SaveReason = mode.Reason, LastWrite = os.clock(), Saving = false }
	for _, cb in ipairs(loadedCallbacks) do
		task.spawn(cb, player, data)
	end
end

-- "loaded" / "new-player" (saving) or the reason this profile is memory-only (no-datastore, locked, read-failed, migration-failed).
function DataService.SaveStatus(player: Player): string?
	local p = profiles[player]
	return p and ((p.NoSave and "memory-only: " or "saving: ") .. p.SaveReason) or nil
end

function DataService.IsPersistent(player: Player): boolean
	local p = profiles[player]
	return p ~= nil and not p.NoSave and store ~= nil
end

function DataService.Init()
	Players.PlayerAdded:Connect(load)
	for _, p in ipairs(Players:GetPlayers()) do
		task.spawn(load, p)
	end

	Players.PlayerRemoving:Connect(function(player)
		inFlightFinalSaves += 1
		DataService.Save(player, true, true)
		inFlightFinalSaves -= 1
		profiles[player] = nil
		lastSaveWarn[player] = nil
	end)

	task.spawn(function()
		while true do
			task.wait(Config.Data.AutosaveInterval)
			for player in pairs(profiles) do
				task.spawn(DataService.Save, player)
			end
		end
	end)

	-- Shutdown: flush every profile and wait for it (Roblox allows ~30 s). This ALSO runs in Studio: stopping a Studio test closes the server
	-- immediately, and without waiting here a short test session's progress (autosave is every 60 s) would be lost.
	-- Players already leaving have their own final save in flight (inFlightFinalSaves); wait for those too.
	game:BindToClose(function()
		local pending = 0
		for player in pairs(profiles) do
			pending += 1
			task.spawn(function()
				DataService.Save(player, true, true)
				pending -= 1
			end)
		end
		local deadline = os.clock() + 25
		while (pending > 0 or inFlightFinalSaves > 0) and os.clock() < deadline do
			task.wait(0.1)
		end
		if pending > 0 or inFlightFinalSaves > 0 then
			warn(("[DataService] Shutdown: %d profile save(s) did not finish in time."):format(pending + inFlightFinalSaves))
		end
		print(("[DataService] shutdown summary: loadsOk=%d loadsFailed=%d lockRefusals=%d savesOk=%d savesFailed=%d memoryOnly=%d kicks=%d"):format(
			diagnostics.LoadsOk, diagnostics.LoadsFailed, diagnostics.LockRefusals, diagnostics.SavesOk, diagnostics.SavesFailed,
			diagnostics.MemoryOnlyProfiles, diagnostics.Kicks))
	end)
end

-- Counters for the server Output / tests; contains no profile contents.
function DataService.Diagnostics()
	return table.clone(diagnostics)
end

function DataService.StorageMode(): string
	return storageMode
end

-- What the player may be told about their own session (no profile contents): whether progress is being saved and why not.
function DataService.SaveInfo(player: Player)
	local p = profiles[player]
	if not p then
		return nil
	end
	return { Saving = not p.NoSave, Reason = p.SaveReason, Mode = storageMode }
end

return DataService
