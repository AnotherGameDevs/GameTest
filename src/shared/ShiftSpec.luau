-- Pure decision rule for the shared-mine refresh ("Fresh Dig"). Tested in tests/collection_test.luau.
local ShiftSpec = {}

-- depletion = { Total = fraction of all cells dug, ByLayer = { [layerId] = fraction }, AgeMinutes }
function ShiftSpec.ShouldRefresh(depletion, cfg, deepestLayerId: string): boolean
	if depletion.Total >= cfg.TriggerFraction then
		return true
	end
	if (depletion.ByLayer[deepestLayerId] or 0) >= cfg.DeepLayerFraction then
		return true
	end
	return depletion.AgeMinutes >= cfg.MaxAgeMinutes and depletion.Total >= cfg.MinFractionForAge
end

return ShiftSpec
