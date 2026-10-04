-- Who may use developer test mode, and which requests are well-formed. Pure (tests/dev_mode_test.luau). The inputs come from the SERVER
-- (RunService:IsStudio(), game.PlaceId, player.UserId, Config.Dev); nothing here ever reads a value supplied by a client except the
-- request itself, which is validated against a fixed whitelist.
local DevAccess = {}

-- action -> { World = changes the shared world (needs World access and Test Mode), Needs = "Test" (personal overlay must be active) }
DevAccess.Actions = {
	Enter = { },
	Exit = { },
	UnlockAll = { Needs = "Test" },
	Equip = { Needs = "Test" },
	GrantCash = { Needs = "Test" },
	UnlockCollection = { Needs = "Test" },
	Reveal = { Needs = "Test" }, -- cosmetic reveal only
	FreshProfile = { Needs = "Test" },
	Teleport = { Needs = "Test" }, -- moves only the requesting player, via existing landing positions
	SpawnArtifact = { Needs = "Test", World = true }, -- personal / relic artifacts exist in the shared world
	StartRelic = { Needs = "Test", World = true },
	ResetMine = { Needs = "Test", World = true },
}

local function isId(n: any): boolean
	return type(n) == "number" and n == math.floor(n) and n > 0 and n < 2 ^ 53
end

local function contains(list: any, value: any): boolean
	if type(list) ~= "table" or not isId(value) then
		return false
	end
	for _, v in ipairs(list) do
		if v == value then
			return true
		end
	end
	return false
end

-- ctx = { IsStudio, PlaceId, UserId, AllowedUserIds, TestPlaceIds }
-- returns { Allowed, World, Env = "studio" | "test-place" | "production", Reason }
function DevAccess.Resolve(ctx)
	if ctx.IsStudio == true then
		return { Allowed = true, World = true, Env = "studio", Reason = "studio" }
	end
	local placeOk = contains(ctx.TestPlaceIds, ctx.PlaceId)
	local userOk = contains(ctx.AllowedUserIds, ctx.UserId)
	if placeOk and userOk then
		return { Allowed = true, World = true, Env = "test-place", Reason = "allowlisted" }
	end
	return { Allowed = false, World = false, Env = placeOk and "test-place" or "production",
		Reason = placeOk and "not-allowlisted" or "not-a-test-place" }
end

-- Validates (action, arg) from a remote. Returns (true, cleanArg) or (false, reason). `defs` = { Tools, Backpacks, Treasure, StopCount, MaxCash }.
function DevAccess.Validate(action: any, arg: any, defs)
	if type(action) ~= "string" or DevAccess.Actions[action] == nil then
		return false, "unknown-action"
	end
	if action == "Equip" then
		if type(arg) ~= "table" or type(arg.Kind) ~= "string" or type(arg.Id) ~= "string" then
			return false, "bad-argument"
		end
		if arg.Kind == "Tool" and defs.Tools[arg.Id] then
			return true, { Kind = "Tool", Id = arg.Id }
		elseif arg.Kind == "Backpack" and defs.Backpacks[arg.Id] then
			return true, { Kind = "Backpack", Id = arg.Id }
		end
		return false, "unknown-item"
	elseif action == "GrantCash" then
		if type(arg) ~= "number" or arg ~= arg or arg < 1 or arg == math.huge then
			return false, "bad-argument"
		end
		return true, math.floor(math.min(arg, defs.MaxCash))
	elseif action == "SpawnArtifact" or action == "Reveal" then
		if type(arg) ~= "string" or not defs.Treasure[arg] then
			return false, "unknown-item"
		end
		return true, arg
	elseif action == "Teleport" then
		if type(arg) ~= "number" or arg ~= math.floor(arg) or arg < 1 or arg > defs.StopCount then
			return false, "bad-argument"
		end
		return true, arg
	end
	return true, nil -- every other action takes no argument; anything sent is ignored
end

-- Whether a validated action may run given the player's access and mode. Returns (true) or (false, reason).
function DevAccess.Permit(action: string, access, inTestMode: boolean)
	local def = DevAccess.Actions[action]
	if not def then
		return false, "unknown-action"
	end
	if not access or not access.Allowed then
		return false, "not-allowed"
	end
	if def.Needs == "Test" and not inTestMode then
		return false, "test-mode-required"
	end
	if def.World and not access.World then
		return false, "world-actions-not-allowed"
	end
	return true
end

-- One line telling the developer what kind of session this is (shown in the panel). `save` = DataService.SaveInfo (no profile contents).
function DevAccess.SessionLabel(save): string
	if type(save) ~= "table" then
		return "Loading"
	end
	if save.Saving == false then
		return "Temporary session - progress will not save"
	elseif save.Mode == "studio-test-store" then
		return "Isolated test store - progress saves to the TEST store"
	end
	return "Normal play - production store"
end

return DevAccess
