-- Persistent player data. Versioned schema + migrations, dirty-flag autosave (no write spam),
-- graceful fallback to memory-only when DataStores are unavailable (e.g. unpublished place in Studio).
local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Util = require(ReplicatedStorage.Shared.Util)

local DataService = {}

local function defaultData()
	return {
		Version = Config.Data.CurrentVersion,
		Cash = Config.Starting.Cash,
		Reputation = 0,
		Equipment = { ToolId = Config.Starting.ToolId, BackpackId = Config.Starting.BackpackId },
		OwnedTools = { [Config.Starting.ToolId] = true },
		OwnedBackpacks = { [Config.Starting.BackpackId] = true },
		BackpackItems = {}, -- [treasureId] = count (persisted so a reset/rejoin never eats your haul)
		Research = {},
		UnlockedSites = {},
		Collection = {}, -- [treasureId] = { Count, FirstFound }
		Stats = {
			BlocksDug = 0, TreasureFound = 0, CashEarned = 0,
			RelicsDiscovered = 0, RelicsExtracted = 0, RelicsStolen = 0, DeepestDepth = 0,
		},
		Cosmetics = {},
		EquippedCosmetics = {},
		Settings = {},
	}
end

-- Migrations: [n] upgrades data from version n to n+1.
local Migrations: { [number]: (any) -> () } = {
	-- [1] = function(data) ... end,
}

local function migrate(data)
	local v = data.Version or 0
	while v < Config.Data.CurrentVersion do
		local step = Migrations[v]
		if step then
			step(data)
		end
		v += 1
		data.Version = v
	end
	Util.Reconcile(data, defaultData())
end

local store
if Config.Data.Enabled then
	store = DataStoreService:GetDataStore(Config.Data.StoreName)
end

local profiles: { [Player]: { Data: any, Dirty: boolean, NoSave: boolean } } = {}
local loadedCallbacks: { (Player, any) -> () } = {}
local warnedUnavailable = false

local function key(player: Player)
	return "Player_" .. player.UserId
end

local function attempt(fn: () -> any, tries: number)
	local ok, result
	for i = 1, tries do
		ok, result = pcall(fn)
		if ok then
			return true, result
		end
		task.wait(i)
	end
	return false, result
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

function DataService.Save(player: Player, force: boolean?)
	local p = profiles[player]
	if not p or not store or p.NoSave then
		return
	end
	if not p.Dirty and not force then
		return
	end
	p.Dirty = false
	local ok, err = attempt(function()
		store:SetAsync(key(player), p.Data)
	end, 3)
	if not ok then
		p.Dirty = true
		if not warnedUnavailable then
			warnedUnavailable = true
			warn("[DataService] Save failed (is Studio API access enabled for this place?): " .. tostring(err))
		end
	end
end

local function load(player: Player)
	local data
	local noSave = false
	if store then
		local ok, result = attempt(function()
			return store:GetAsync(key(player))
		end, 3)
		if ok then
			data = result
		else
			-- Could not read. Do NOT risk overwriting real data with defaults later.
			noSave = true
			if RunService:IsStudio() then
				warn("[DataService] DataStore unavailable in Studio - progress this session will not persist. (" .. tostring(result) .. ")")
			else
				warn("[DataService] Load failed for " .. player.Name .. ": " .. tostring(result))
			end
		end
	end
	if type(data) ~= "table" then
		data = defaultData()
	else
		migrate(data)
	end
	if not player.Parent then
		return
	end
	profiles[player] = { Data = data, Dirty = noSave == false and false, NoSave = noSave }
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
		DataService.Save(player, true)
		profiles[player] = nil
	end)

	task.spawn(function()
		while true do
			task.wait(Config.Data.AutosaveInterval)
			for player in pairs(profiles) do
				task.spawn(DataService.Save, player)
			end
		end
	end)

	game:BindToClose(function()
		for player in pairs(profiles) do
			task.spawn(DataService.Save, player, true)
		end
		if not RunService:IsStudio() then
			task.wait(3)
		end
	end)
end

return DataService
