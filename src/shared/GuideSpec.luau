-- First-time-player hints. Pure: given a state snapshot and the set of finished hints, returns the single hint that
-- should be showing (or nil). Hints disappear for good when their condition is met; progress is saved server-side.
-- Tested in tests/collection_test.luau.
--
-- `state` fields: Cash, Count, Capacity, Stats{BlocksDug, CashEarned, DeepestDepth}, OwnedToolCount, NextToolPrice,
--   NextToolName, Carrying (bool), HasDeposited (bool), CollectionFound (number), Touch (bool), depthMeters (number)
-- `names` = { Dig, Sell, Shop, Place, Journal } display strings for the CURRENT bindings.
local Defs = require(script.Parent.Defs)
local CollectionSpec = require(script.Parent.CollectionSpec)

local GuideSpec = {}

GuideSpec.Order = { "mine", "backpack", "sell", "upgrade", "elevator", "artifact", "collection" }
GuideSpec.Ids = {}
for _, id in ipairs(GuideSpec.Order) do
	GuideSpec.Ids[id] = true
end

-- Seconds a hint stays up before it is marked done on its own (hints without an entry stay until satisfied).
GuideSpec.Timeout = { backpack = 9, elevator = 12, collection = 14 }

function GuideSpec.IsValid(id: any): boolean
	return type(id) == "string" and GuideSpec.Ids[id] == true
end

-- A hint is "satisfied" (never shown again) when the player has clearly done the thing.
function GuideSpec.Satisfied(id: string, s): boolean
	if id == "mine" then
		return s.Stats.BlocksDug >= 4
	elseif id == "backpack" then
		return s.Stats.CashEarned > 0
	elseif id == "sell" then
		return s.Stats.CashEarned > 0
	elseif id == "upgrade" then
		return s.OwnedToolCount >= 2
	elseif id == "elevator" then
		return false -- dismissed by timeout / the player moving on (see GuideController)
	elseif id == "artifact" then
		return s.HasDeposited
	elseif id == "collection" then
		return false -- dismissed when the journal is opened or by timeout
	end
	return true
end

-- Is the hint's trigger condition met right now?
function GuideSpec.Triggered(id: string, s): boolean
	if id == "mine" then
		return true
	elseif id == "backpack" then
		return s.Count >= 1 and s.Stats.CashEarned == 0
	elseif id == "sell" then
		return s.Count >= 3 or (s.Count >= 1 and s.Count >= s.Capacity * 0.5)
	elseif id == "upgrade" then
		return s.Stats.CashEarned > 0 and s.OwnedToolCount < 2 and s.NextToolPrice ~= nil and s.Cash >= s.NextToolPrice
	elseif id == "elevator" then
		return s.depthMeters >= 8 and not s.Carrying
	elseif id == "artifact" then
		return s.Carrying
	elseif id == "collection" then
		return s.CollectionFound >= 1 and s.Stats.CashEarned > 0
	end
	return false
end

function GuideSpec.Text(id: string, s, names): (string, string)
	if id == "mine" then
		if s.Touch then
			return "DIG", "Tap the ground (or hold the DIG button) to dig. Walk up to a block first - it must be close."
		end
		return "DIG", ("Hold %s on the ground to dig. Move closer if the block is out of reach."):format(names.Dig)
	elseif id == "backpack" then
		return "BACKPACK", ("Treasure goes into your backpack (%d / %d). When it is full, you must sell."):format(s.Count, s.Capacity)
	elseif id == "sell" then
		return "SELL", ("Walk to the gold SELL ZONE at camp to sell your finds. %s teleports you to camp."):format(names.Sell)
	elseif id == "upgrade" then
		return "UPGRADE", ("You can afford the %s! Open the SHOP at camp (stand near it, press the prompt) to buy and equip it."):format(s.NextToolName or "next tool")
	elseif id == "elevator" then
		return "ELEVATOR", "Use the camp ELEVATOR (right of the pit) to ride between layers, or climb the ladder beside it."
	elseif id == "artifact" then
		return "IMPORTANT ARTIFACT", ("You can't dig or teleport while carrying it. Take it to the RECEIVING TABLE at camp - or press %s to put it down."):format(names.Place)
	elseif id == "collection" then
		return "COLLECTION", ("Press %s to open your Collection Journal and pick artifacts for your camp shelf."):format(names.Journal)
	end
	return "", ""
end

-- The single hint to show: the first in order that is triggered, not yet done and not satisfied.
function GuideSpec.Active(s, done: { [string]: boolean }): string?
	if done.skipped then
		return nil -- "Skip tutorial" was used: no guidance at all until the player restarts it from Settings
	end
	for _, id in ipairs(GuideSpec.Order) do
		if not done[id] and not GuideSpec.Satisfied(id, s) and GuideSpec.Triggered(id, s) then
			return id
		end
	end
	return nil
end

-- Ids that can be marked done because their condition is satisfied (so they are persisted and never reappear).
function GuideSpec.NewlySatisfied(s, done: { [string]: boolean }): { string }
	local out = {}
	if done.skipped then
		return out
	end
	for _, id in ipairs(GuideSpec.Order) do
		if not done[id] and GuideSpec.Satisfied(id, s) then
			table.insert(out, id)
		end
	end
	return out
end

-- Builds the snapshot GuideSpec works on from the server's player snapshot `d`, the saved restart baseline `base`
-- (lifetime counters at the moment the tutorial was last restarted; {} for a fresh profile) and client-only extras.
-- Everything is RELATIVE to the baseline, so restarting the tutorial for a veteran really starts from zero instead of
-- instantly counting old progress as done.
function GuideSpec.StateFrom(d, base, extras)
	base = base or {}
	local stats = d.Stats or {}
	local owned = 0
	for _ in pairs(d.OwnedTools or {}) do
		owned += 1
	end
	local nextTool
	for _, id in ipairs(Defs.ToolsByTier) do
		if not (d.OwnedTools or {})[id] then
			nextTool = Defs.Tools[id]
			break
		end
	end
	local found = CollectionSpec.Totals(d.Collection or {})
	return {
		Cash = d.Cash or 0, Count = d.Count or 0, Capacity = math.max(d.Capacity or 1, 1),
		Stats = {
			BlocksDug = math.max((stats.BlocksDug or 0) - (base.BlocksDug or 0), 0),
			CashEarned = math.max((stats.CashEarned or 0) - (base.CashEarned or 0), 0),
			DeepestDepth = stats.DeepestDepth or 0,
		},
		OwnedToolCount = math.max(owned - (base.Tools or 1), 0) + 1,
		NextToolPrice = nextTool and nextTool.Price or nil,
		NextToolName = nextTool and nextTool.DisplayName or nil,
		Carrying = d.Carrying ~= nil,
		HasDeposited = (stats.RelicsExtracted or 0) - (base.RelicsExtracted or 0) > 0,
		CollectionFound = math.max(found - (base.Found or 0), 0),
		Touch = extras.Touch == true,
		depthMeters = extras.depthMeters or 0,
	}
end

-- The baseline to save when the tutorial is restarted (computed on the server from the live profile).
function GuideSpec.Baseline(data)
	local owned = 0
	for _ in pairs(data.OwnedTools or {}) do
		owned += 1
	end
	local found = CollectionSpec.Totals(data.Collection or {})
	local stats = data.Stats or {}
	return { BlocksDug = stats.BlocksDug or 0, CashEarned = stats.CashEarned or 0, RelicsExtracted = stats.RelicsExtracted or 0,
		Tools = math.max(owned, 1), Found = found }
end

return GuideSpec
