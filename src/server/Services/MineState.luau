-- Tiny shared holder of the mine's lifecycle state, so DigService / ArtifactService / DynamiteService can ask
-- "is the mine accepting requests?" and "is this the current generation?" without depending on MineShiftService (no cycles).
-- MineShiftService owns the values; everyone else only reads.
local Workspace = game:GetService("Workspace")

local MineState = {}

local state = "Active"
local generation = 1

function MineState.Set(newState: string, newGeneration: number)
	state = newState
	generation = newGeneration
end

function MineState.State(): string
	return state
end

function MineState.Generation(): number
	return generation
end

function MineState.Accepting(): boolean
	return state == "Active" or state == "Warning"
end

function MineState.IsCurrent(gen: any): boolean
	return type(gen) == "number" and gen == generation
end

-- Replicates what clients need (late joiners get the current values automatically with the Workspace attributes).
-- `endsAt` is a Workspace:GetServerTimeNow() timestamp; `resetAt` the predicted scheduled reset (also server time) or 0.
function MineState.Publish(info)
	Workspace:SetAttribute("MineState", state)
	Workspace:SetAttribute("MineGeneration", generation)
	Workspace:SetAttribute("MineEndsAt", info.EndsAt or 0)
	Workspace:SetAttribute("MineResetAt", info.ResetAt or 0)
	Workspace:SetAttribute("MineReason", info.Reason or "")
	Workspace:SetAttribute("MineDug", info.DugPercent or 0)
end

return MineState
