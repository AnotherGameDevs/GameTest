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
		Guide = {}, -- [hintId] = true once a first-time hint is finished
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
	DataMigrations.Migrate(data, Config.Data.CurrentVersion, Defs)
	Util.Reconcile(data, defaultData())
	DataMigrations.Sanitize(data, Defs, Config.Starting.ToolId, Config.Starting.BackpackId)
	data.Settings = SettingsSpec.Sanitize(data.Settings) -- clamp whatever was saved
	DataMigrations.SanitizeCollection(data, Defs)
	data.Display = CollectionSpec.SanitizeDisplay(data.Display, data.Collection)
end

-- GetDataStore throws in an unpublished place, so it must never run unprotected.
local store
if Config.Data.Enabled then
	local ok, result = pcall(function()
		return DataStoreService:GetDataStore(Config.Data.StoreName)
	end)
	if ok then
		store = result
	else
		warn("[DataService] DataStore unavailable (publish the place to enable saving). Running without saving. " .. tostring(result))
	end
end

local LOCK_TIMEOUT = 120 -- seconds after which another server's lock is treated as dead (crash / lost release)
local LOCK_REFRESH = 45 -- rewrite at least this often so a live session's lock never goes stale
local profiles: { [Player]: { Data: any, Dirty: boolean, NoSave: boolean, LastWrite: number, Saving: boolean } } = {}
local loadedCallbacks: { (Player, any) -> () } = {}
local lastSaveWarn: { [Player]: number } = {}

local function key(player: Player)
	return "Player_" .. player.UserId
end

local function isStudio()
	return RunService:IsStudio()
end

local function attempt(fn: () -> any, tries: number)
	local ok, result
	if isStudio() then
		tries = 1 -- fail fast in Studio so a missing API permission doesn't delay loading
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

-- Session lock: a profile records which server (JobId) owns it. A second server refuses to load a profile that is
-- locked by a live session, so two servers can never both write one player's progress. Stale locks expire.
local function lockedByOther(old): boolean
	local lock = old and old.SessionLock
	return type(lock) == "table" and lock.JobId ~= game.JobId and (os.time() - (tonumber(lock.At) or 0)) < LOCK_TIMEOUT
end

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
	local lostLock = false
	local ok, err = attempt(function()
		store:UpdateAsync(key(player), function(old)
			lostLock = false
			if lockedByOther(old) then
				lostLock = true
				return nil -- another live server owns this profile: do NOT overwrite it
			end
			snapshot.SessionLock = (not release) and { JobId = game.JobId, At = os.time() } or nil
			return snapshot
		end)
	end, 3)
	p.Saving = false
	if ok and not lostLock then
		p.LastWrite = os.clock()
		return true
	end
	p.Dirty = true
	if lostLock then
		p.NoSave = true -- never write again from this server
		warn(("[DataService] %s's profile is now owned by another server; saving from this one is disabled."):format(player.Name))
	elseif os.clock() - (lastSaveWarn[player] or 0) > 30 then
		lastSaveWarn[player] = os.clock()
		warn(("[DataService] Save failed for %s (will retry): %s"):format(player.Name, tostring(err)))
	end
	return false
end

local function load(player: Player)
	local data
	local noSave = false
	local failReason: string? = nil
	if store then
		local locked = false
		local ok, result = attempt(function()
			local read
			store:UpdateAsync(key(player), function(old)
				locked = false
				if lockedByOther(old) then
					locked = true
					return nil
				end
				read = old
				local new = old or {}
				new.SessionLock = { JobId = game.JobId, At = os.time() }
				return new
			end)
			return read
		end, 4)
		if locked then
			failReason = "Your saved progress is still open on another server. Please rejoin in about a minute."
			warn("[DataService] Profile locked by another server for " .. player.Name)
		elseif ok then
			data = result
		else
			failReason = "Your saved progress could not be loaded. Please rejoin in a moment - nothing was overwritten."
			warn("[DataService] Load failed for " .. player.Name .. ": " .. tostring(result))
		end
		if failReason then
			noSave = true
		end
	end
	if failReason and not isStudio() then
		-- Production: never let someone play (and lose progress) on a stand-in profile.
		if player.Parent then
			player:Kick(failReason)
		end
		return
	end
	if type(data) ~= "table" then
		data = defaultData()
	else
		data.SessionLock = nil
		migrate(data)
	end
	if not player.Parent then
		if store and not noSave then
			-- joined and left before the profile was kept: release the lock we just took
			pcall(function()
				store:UpdateAsync(key(player), function(old)
					if old and old.SessionLock and old.SessionLock.JobId == game.JobId then
						old.SessionLock = nil
						return old
					end
					return nil
				end)
			end)
		end
		return
	end
	if noSave and isStudio() then
		warn("[DataService] DataStore unavailable in Studio - progress this session will not persist.")
	end
	profiles[player] = { Data = data, Dirty = false, NoSave = noSave, LastWrite = os.clock(), Saving = false }
	for _, cb in ipairs(loadedCallbacks) do
		task.spawn(cb, player, data)
	end
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
		DataService.Save(player, true, true)
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

	-- Shutdown: save every profile in parallel and wait for them (Roblox allows ~30 s), instead of a fixed sleep.
	game:BindToClose(function()
		if isStudio() then
			return
		end
		local pending = 0
		for player in pairs(profiles) do
			pending += 1
			task.spawn(function()
				DataService.Save(player, true, true)
				pending -= 1
			end)
		end
		local deadline = os.clock() + 25
		while pending > 0 and os.clock() < deadline do
			task.wait(0.2)
		end
		if pending > 0 then
			warn(("[DataService] Shutdown: %d profile(s) did not finish saving."):format(pending))
		end
	end)
end

return DataService
