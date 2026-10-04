-- Player-facing progress that is just saved flags: the camp-shelf selection and first-time hint progress. The server
-- validates every request against the saved collection / the hint list; the client only ever sends ids.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local CollectionSpec = require(ReplicatedStorage.Shared.CollectionSpec)
local GuideSpec = require(ReplicatedStorage.Shared.GuideSpec)

local DataService = require(script.Parent.DataService)
local StateService = require(script.Parent.StateService)
local RateLimiter = require(script.Parent.RateLimiter)

local CollectionService = {}

local notifyRemote = Remotes.Get("Notify")

local function setDisplay(player: Player, id: any)
	if not RateLimiter.Check(player, "SetDisplay") then
		return
	end
	local data = DataService.Get(player)
	if not data then
		return
	end
	local list, ok, reason = CollectionSpec.ToggleDisplay(data.Display, id, data.Collection)
	if not ok then
		if reason == "Full" then
			notifyRemote:FireClient(player, "Your shelf is full - remove one first.", "Danger")
		elseif reason == "NotDiscovered" then
			notifyRemote:FireClient(player, "You have not discovered that yet.", "Danger")
		end
		return
	end
	data.Display = list
	DataService.MarkDirty(player)
	StateService.Push(player)
end

local function guideDone(player: Player, id: any)
	if not RateLimiter.Check(player, "GuideDone") or not GuideSpec.IsValid(id) then
		return
	end
	local data = DataService.Get(player)
	if not data or data.Guide[id] then
		return
	end
	data.Guide[id] = true
	DataService.MarkDirty(player)
	StateService.Push(player)
end

-- "Skip tutorial" clears guidance and records completion; "restart" wipes the saved progress and stores a baseline so
-- old lifetime stats are not mistaken for new progress. Both are saved in the profile (no replay on respawn/rejoin).
local function guideControl(player: Player, action: any)
	if not RateLimiter.Check(player, "GuideControl") then
		return
	end
	local data = DataService.Get(player)
	if not data then
		return
	end
	if action == "skip" then
		for _, id in ipairs(GuideSpec.Order) do
			data.Guide[id] = true
		end
		data.Guide.skipped = true
	elseif action == "restart" then
		table.clear(data.Guide)
		data.GuideBase = GuideSpec.Baseline(data)
	else
		return
	end
	DataService.MarkDirty(player)
	StateService.Push(player)
end

function CollectionService.Init()
	Remotes.Get("SetDisplay").OnServerEvent:Connect(setDisplay)
	Remotes.Get("GuideDone").OnServerEvent:Connect(guideDone)
	Remotes.Get("GuideControl").OnServerEvent:Connect(guideControl)
end

return CollectionService
