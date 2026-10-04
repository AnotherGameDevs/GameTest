-- The developer test OVERLAY on a profile record, as pure functions (tests/dev_mode_test.luau runs them against a fake DataStore). DataService
-- uses exactly these. A profile record is { Data, Normal, Overlay, Dirty, ... }:
--   * Data    = the table every service reads/writes (DataService.Get). In test mode it holds TEST data; the table itself is never replaced.
--   * Normal  = the player's REAL profile, parked untouched while the overlay is active.
--   * Writes (autosave, leave, shutdown) take their snapshot from SaveSource(): always the real profile, never the overlay.
local ProfileOverlay = {}

local function deepCopy(t: any): any
	if type(t) ~= "table" then
		return t
	end
	local c = {}
	for k, v in pairs(t) do
		c[k] = deepCopy(v)
	end
	return c
end

-- Makes `dst` hold exactly the contents of `src` (deep copy) WITHOUT replacing the `dst` table, so every service that already holds a
-- reference to the profile table keeps seeing the current profile.
local function replaceInPlace(dst: any, src: any)
	for k in pairs(dst) do
		dst[k] = nil
	end
	for k, v in pairs(src) do
		dst[k] = deepCopy(v)
	end
end
ProfileOverlay.ReplaceInPlace = replaceInPlace

function ProfileOverlay.Active(p): boolean
	return p ~= nil and p.Overlay == true
end

-- Parks the real profile and starts the overlay (a copy of it, or a fresh default profile when `freshData` is given).
function ProfileOverlay.Enter(p, freshData: any?): boolean
	if not p or p.Overlay then
		return false
	end
	p.Normal = deepCopy(p.Data)
	p.Overlay = true
	if freshData then
		replaceInPlace(p.Data, freshData)
	end
	return true
end

function ProfileOverlay.Fresh(p, freshData: any): boolean
	if not p or not p.Overlay then
		return false
	end
	replaceInPlace(p.Data, freshData)
	return true
end

-- Restores the real profile exactly as it was when the overlay started.
function ProfileOverlay.Exit(p): boolean
	if not p or not p.Overlay or not p.Normal then
		return false
	end
	replaceInPlace(p.Data, p.Normal)
	p.Normal = nil
	p.Overlay = false
	return true
end

-- What a save may write: the real profile.
function ProfileOverlay.SaveSource(p)
	return p.Normal or p.Data
end

-- Overlay changes never make the real profile "dirty".
function ProfileOverlay.MarkDirty(p)
	if p and not p.Overlay then
		p.Dirty = true
	end
end

return ProfileOverlay
