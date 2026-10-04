-- Pure decision: what DataService may do with a player's profile after trying to load it (tests/saving_test.luau).
-- The one rule that matters: a profile that exists in the DataStore but could not be read, was locked by another live server, or
-- could not be migrated is NEVER saved over. Stand-in default profiles are memory-only; in a published server the player is kicked instead.
local SaveMode = {}

-- ctx = { StoreAvailable, ReadOk, Locked, HasData, MigrateOk, IsStudio }
-- returns { Persist = may this profile ever be written?, UseDefaults = start from a default profile?, Kick = message or nil, Reason = string }
function SaveMode.Decide(ctx)
	if not ctx.StoreAvailable then
		return { Persist = false, UseDefaults = true, Kick = nil, Reason = "no-datastore" } -- memory only, nothing to overwrite
	end
	local problem
	if ctx.Locked then
		problem = "locked"
	elseif not ctx.ReadOk then
		problem = "read-failed"
	elseif ctx.HasData and not ctx.MigrateOk then
		problem = "migration-failed"
	end
	if problem then
		return {
			Persist = false, -- never write over what we could not use
			UseDefaults = true,
			Kick = (not ctx.IsStudio) and problem or nil, -- published servers kick; Studio plays on a memory-only stand-in
			Reason = problem,
		}
	end
	return { Persist = true, UseDefaults = not ctx.HasData, Kick = nil, Reason = ctx.HasData and "loaded" or "new-player" }
end

SaveMode.KickMessages = {
	locked = "Your saved progress is still open on another server. Please rejoin in about a minute.",
	["read-failed"] = "Your saved progress could not be loaded. Please rejoin in a moment - nothing was overwritten.",
	["migration-failed"] = "Your saved progress could not be read. Please rejoin - nothing was overwritten.",
}

return SaveMode
