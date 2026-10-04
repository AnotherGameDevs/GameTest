-- Thin abstraction so real analytics (AnalyticsService:LogEconomyEvent, custom funnels...) can be swapped in later.
local AnalyticsService = {}

AnalyticsService.Verbose = false

function AnalyticsService.Log(player: Player?, event: string, data: { [string]: any }?)
	if AnalyticsService.Verbose then
		print(("[Analytics] %s %s"):format(player and player.Name or "server", event), data)
	end
end

return AnalyticsService
