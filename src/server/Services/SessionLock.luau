-- Pure session-lock rules for DataService (tests/saving_test.luau). A profile records which server (JobId) owns it and when it last
-- refreshed that claim. A second server may not load a profile that another LIVE server holds; a lock older than `timeout` is treated
-- as dead (crash / lost release) so players are never locked out forever.
local SessionLock = {}

function SessionLock.IsLockedByOther(record, jobId: string, now: number, timeout: number): boolean
	local lock = type(record) == "table" and record.SessionLock
	return type(lock) == "table" and lock.JobId ~= jobId and (now - (tonumber(lock.At) or 0)) < timeout
end

-- The lock to write when this server keeps the profile (or nil to release it).
function SessionLock.Claim(jobId: string, now: number)
	return { JobId = jobId, At = now }
end

return SessionLock
