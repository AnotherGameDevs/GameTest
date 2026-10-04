-- The DataStore protocol for ONE player profile, separated from DataService so it can be exercised against a fake store
-- (tests/saving_test.luau). It is the SAME code DataService runs; DataService only adds Roblox glue (players, timers, logging).
-- A "store" is anything with :UpdateAsync(key, transform) (Roblox's DataStore, or the fake in the tests).
--   Load:   claim the session lock and read the profile in ONE UpdateAsync (so two servers can not both load it).
--   Save:   write the snapshot only if no OTHER live server holds the lock; `release` clears our lock (leaving / shutdown).
--   Release: drop our lock without writing data (used when a loaded profile is abandoned).
-- Nothing here ever writes defaults: a failed or refused read never leads to a write.
-- The lock rules (SessionLock) are passed in through ctx.Lock so this module has no Roblox-only requires and runs under the plain Luau CLI.

local ProfileStore = {}

-- ctx = { JobId, Lock = SessionLock, Now = function() number, LockTimeout, Attempt = function(fn, tries) -> ok, result }
-- returns { Ok, Locked, Data, Err }; Ok=false means "could not read" (Data nil).
function ProfileStore.Load(store, key: string, ctx, tries: number)
	local locked = false
	local ok, result = ctx.Attempt(function()
		local read
		store:UpdateAsync(key, function(old)
			locked = false
			if ctx.Lock.IsLockedByOther(old, ctx.JobId, ctx.Now(), ctx.LockTimeout) then
				locked = true
				return nil -- cancel: leave the other server's record untouched
			end
			read = old
			local new = old or {}
			new.SessionLock = ctx.Lock.Claim(ctx.JobId, ctx.Now())
			return new
		end)
		return read
	end, tries)
	if locked then
		return { Ok = false, Locked = true, Data = nil, Err = "locked by another server" }
	end
	if not ok then
		return { Ok = false, Locked = false, Data = nil, Err = result }
	end
	return { Ok = true, Locked = false, Data = result, Err = nil }
end

-- snapshot: a private deep copy of the profile (this function adds/removes SessionLock on it).
-- returns { Ok, LostLock, Err }
function ProfileStore.Save(store, key: string, snapshot, release: boolean, ctx, tries: number)
	local lostLock = false
	local ok, err = ctx.Attempt(function()
		store:UpdateAsync(key, function(old)
			lostLock = false
			if ctx.Lock.IsLockedByOther(old, ctx.JobId, ctx.Now(), ctx.LockTimeout) then
				lostLock = true
				return nil -- another live server owns this profile: do NOT overwrite it
			end
			snapshot.SessionLock = (not release) and ctx.Lock.Claim(ctx.JobId, ctx.Now()) or nil
			return snapshot
		end)
	end, tries)
	return { Ok = ok and not lostLock, LostLock = lostLock, Err = err }
end

-- Clears OUR lock (and only ours) while keeping the stored data exactly as it is.
function ProfileStore.Release(store, key: string, ctx)
	return pcall(function()
		store:UpdateAsync(key, function(old)
			if type(old) == "table" and old.SessionLock and old.SessionLock.JobId == ctx.JobId then
				old.SessionLock = nil
				return old
			end
			return nil
		end)
	end)
end

return ProfileStore
