-- Balance telemetry for tuning prices: per-player blocks cleared and cash earned per minute, printed to the
-- server Output every Config.Metrics.PrintInterval seconds (Studio playtests: View > Output).
--   blocks/min (wall)   = blocks cleared / window length         (includes walking, shopping, idling)
--   blocks/min (active) = blocks cleared / seconds with a swing  (comparable to economy_sim.py)
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)

local RunService = game:GetService("RunService")
local DataService = require(script.Parent.DataService)

local MetricsService = {}

-- Telemetry is a development tool: always on in Studio playtests, off in published servers unless Config enables it.
local function enabled(): boolean
	return Config.Metrics.Enabled or RunService:IsStudio()
end

type Window = { Blocks: number, Cash: number, Items: number, ActiveSeconds: { [number]: boolean }, Start: number }
local windows: { [Player]: Window } = {}
local totals: { [Player]: { Blocks: number, Cash: number, Start: number } } = {}

local function fresh(): Window
	return { Blocks = 0, Cash = 0, Items = 0, ActiveSeconds = {}, Start = os.clock() }
end

local function get(player: Player): Window
	local w = windows[player]
	if not w then
		w = fresh()
		windows[player] = w
		totals[player] = { Blocks = 0, Cash = 0, Start = os.clock() }
	end
	return w
end

function MetricsService.Hit(player: Player, blocksCleared: number)
	if not enabled() then
		return
	end
	local w = get(player)
	w.ActiveSeconds[math.floor(os.clock())] = true
	w.Blocks += blocksCleared
	totals[player].Blocks += blocksCleared
end

function MetricsService.Sold(player: Player, cash: number, items: number)
	if not enabled() then
		return
	end
	local w = get(player)
	w.Cash += cash
	w.Items += items
	totals[player].Cash += cash
end

local function report()
	for player, w in pairs(windows) do
		local data = DataService.Get(player)
		local mins = math.max((os.clock() - w.Start) / 60, 1 / 60)
		local active = 0
		for _ in pairs(w.ActiveSeconds) do
			active += 1
		end
		if w.Blocks > 0 or w.Cash > 0 then
			print(("[Metrics] %s tool=%s | last %.1f min: blocks=%d (%.1f/min wall, %.1f/min active) cash=%d (%.0f/min) items sold=%d | session: blocks=%d cash=%d"):format(
				player.Name, data and data.Equipment.ToolId or "?", mins, w.Blocks, w.Blocks / mins,
				active > 0 and w.Blocks / (active / 60) or 0, w.Cash, w.Cash / mins, w.Items,
				totals[player].Blocks, totals[player].Cash))
		end
		windows[player] = fresh()
	end
end

function MetricsService.Init()
	if not enabled() then
		return
	end
	Players.PlayerRemoving:Connect(function(p)
		windows[p] = nil
		totals[p] = nil
	end)
	task.spawn(function()
		while true do
			task.wait(Config.Metrics.PrintInterval)
			report()
		end
	end)
end

return MetricsService
