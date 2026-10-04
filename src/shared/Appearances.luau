-- Tool APPEARANCE is separate from tool STATS. A tool def (Defs.Tools) names a default Appearance id; a
-- cosmetic skin (later) can override it per player without touching balance. Models are built from these ids by
-- ToolModels, for both the held tool (server) and the shop preview (client), so they always match.
local Appearances = {}

-- Builder = which ToolModels builder draws it. Entries using "placeholder" are unfinished art (colour-coded
-- silhouettes) waiting for the polish pass.
Appearances.List = {
	shovel_rusty = { Builder = "rusty" }, -- family A: wooden-shaft hand tools (tiers 1-3)
	shovel_digging = { Builder = "digging" },
	shovel_heavy = { Builder = "heavy" },
	shovel_power = { Builder = "power" }, -- family B: reinforced excavation tools (tiers 4-6)
	jackhammer = { Builder = "jackhammer" },
	drill = { Builder = "drill" },
	drill_industrial = { Builder = "industrial" }, -- family C: manufactured industrial equipment (tiers 7-8)
	dynamite = { Builder = "dynamite" },
}

-- Cosmetic skins (none yet): [skinId] = { ToolType = "Shovel", Appearance = "<id in List>" }.
Appearances.Skins = {}

-- Resolves which appearance to draw: a valid owned-skin override, else the tool's default.
function Appearances.Resolve(toolDef, skinId: string?): string
	if skinId then
		local skin = Appearances.Skins[skinId]
		if skin and skin.ToolType == toolDef.ToolType and Appearances.List[skin.Appearance] then
			return skin.Appearance
		end
	end
	return toolDef.Appearance
end

return Appearances
