-- Player settings: one definition used by the client (UI + clamping) and the server (validation before saving).
-- Pure, so it is unit-tested outside Roblox (tests/settings_test.luau).
local SettingsSpec = {}

SettingsSpec.Order = { "MouseSensitivity", "MasterVolume", "CameraShake", "InvertY" }

SettingsSpec.Defs = {
	-- Multiplier on the first-person mouse-look baseline (see CameraController). Provisional default; needs playtesting.
	MouseSensitivity = { Type = "number", Default = 0.30, Min = 0.05, Max = 2.00, Step = 0.01 },
	MasterVolume = { Type = "number", Default = 1.0, Min = 0, Max = 1, Step = 0.05 },
	CameraShake = { Type = "boolean", Default = true },
	InvertY = { Type = "boolean", Default = false },
}

local function round4(n: number): number
	return math.floor(n * 10000 + 0.5) / 10000
end

-- Returns a valid value for `key`: wrong type / NaN / inf -> default; numbers clamped to range and snapped to Step.
function SettingsSpec.Clamp(key: string, value: any): any
	local def = SettingsSpec.Defs[key]
	if not def then
		return nil
	end
	if def.Type == "boolean" then
		if type(value) == "boolean" then
			return value
		end
		return def.Default
	end
	if type(value) ~= "number" or value ~= value or value == math.huge or value == -math.huge then
		return def.Default
	end
	local v = math.clamp(value, def.Min, def.Max)
	v = round4(math.floor(v / def.Step + 0.5) * def.Step)
	return math.clamp(v, def.Min, def.Max)
end

function SettingsSpec.Defaults()
	local out = {}
	for _, key in ipairs(SettingsSpec.Order) do
		out[key] = SettingsSpec.Defs[key].Default
	end
	return out
end

-- Takes anything (saved data, a remote payload) and returns a complete, valid settings table. Unknown keys dropped.
function SettingsSpec.Sanitize(input: any)
	local out = {}
	local src = type(input) == "table" and input or {}
	for _, key in ipairs(SettingsSpec.Order) do
		out[key] = SettingsSpec.Clamp(key, src[key])
	end
	return out
end

return SettingsSpec
