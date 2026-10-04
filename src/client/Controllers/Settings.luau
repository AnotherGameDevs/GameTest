-- Client copy of the player's settings. Loaded from the server profile once, applied immediately on change, and saved
-- back (debounced) through the existing player-data architecture (data.Settings). Values are clamped by SettingsSpec.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SettingsSpec = require(ReplicatedStorage.Shared.SettingsSpec)
local Remotes = require(ReplicatedStorage.Shared.Remotes)

local Settings = {}

local values = SettingsSpec.Defaults()
local loaded = false
local listeners: { (string, any) -> () } = {}
local saveToken = 0

local function save()
	saveToken += 1
	local token = saveToken
	task.delay(0.6, function()
		if token == saveToken then
			Remotes.Get("UpdateSettings"):FireServer(values)
		end
	end)
end

function Settings.Get(key: string): any
	return values[key]
end

function Settings.OnChanged(cb: (string, any) -> ())
	table.insert(listeners, cb)
end

local function apply(key: string, value: any)
	local clean = SettingsSpec.Clamp(key, value)
	if clean == nil or values[key] == clean then
		return false
	end
	values[key] = clean
	for _, cb in ipairs(listeners) do
		task.spawn(cb, key, clean)
	end
	return true
end

-- Applies immediately, then schedules a save.
function Settings.Set(key: string, value: any)
	if apply(key, value) then
		save()
	end
end

function Settings.Reset(key: string)
	Settings.Set(key, SettingsSpec.Defs[key].Default)
end

-- First server snapshot: adopt the saved values (without echoing them back as a save).
function Settings.Load(fromServer: any)
	if loaded then
		return
	end
	loaded = true
	local clean = SettingsSpec.Sanitize(fromServer)
	for _, key in ipairs(SettingsSpec.Order) do
		apply(key, clean[key])
	end
end

return Settings
