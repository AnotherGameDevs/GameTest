-- Sliding-window per-player, per-remote rate limiting. Limits come from Config.RateLimits.
local Config = require(game:GetService("ReplicatedStorage").Shared.Config)

local RateLimiter = {}
local buckets: { [Player]: { [string]: { number } } } = {}

function RateLimiter.Check(player: Player, name: string): boolean
	local limit = Config.RateLimits[name]
	if not limit then
		return true
	end
	local maxCalls, window = limit[1], limit[2]
	local perPlayer = buckets[player]
	if not perPlayer then
		perPlayer = {}
		buckets[player] = perPlayer
	end
	local log = perPlayer[name]
	if not log then
		log = {}
		perPlayer[name] = log
	end
	local now = os.clock()
	local keep = {}
	for _, t in ipairs(log) do
		if now - t < window then
			table.insert(keep, t)
		end
	end
	if #keep >= maxCalls then
		perPlayer[name] = keep
		return false
	end
	table.insert(keep, now)
	perPlayer[name] = keep
	return true
end

function RateLimiter.Forget(player: Player)
	buckets[player] = nil
end

return RateLimiter
