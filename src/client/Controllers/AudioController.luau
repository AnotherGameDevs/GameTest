-- All sound ids live in this one table so real audio can be swapped in without touching gameplay code.
-- The defaults are Roblox's built-in client sounds (PLACEHOLDERS - see docs/RELEASE_CANDIDATE.md "Audio"): events are told
-- apart by pitch and by short note sequences until proper assets are supplied. Set Id = "" to silence one.
-- Voice limiting: a per-sound minimum gap and a global cap on simultaneous voices stop long digging sessions from
-- stacking dozens of overlapping sounds.
local SoundService = game:GetService("SoundService")
local Debris = game:GetService("Debris")
local Settings = require(script.Parent.Settings)

local Audio = {}

local PING = "rbxasset://sounds/electronicpingshort.wav"

-- Notes = { pitch, ... } played as a quick sequence (NoteGap seconds apart). MinGap = seconds before the same sound may replay.
Audio.Sounds = {
	Impact = { Id = "rbxasset://sounds/action_jump_land.mp3", Volume = 0.8, Pitch = 0.8, MinGap = 0.05 },
	Break = { Id = "rbxasset://sounds/snap.mp3", Volume = 0.9, Pitch = 0.7, MinGap = 0.04 },
	Coin = { Id = PING, Volume = 0.5, Pitch = 1.3, MinGap = 0.08 },
	Reveal = { Id = PING, Volume = 0.8, Pitch = 1.0, MinGap = 0.15 },
	Sell = { Id = PING, Volume = 0.9, Pitch = 1.0, Notes = { 0.8, 1.0, 1.25 }, NoteGap = 0.07, MinGap = 0.2 },
	Buy = { Id = PING, Volume = 0.9, Pitch = 1.0, Notes = { 1.2, 1.6 }, NoteGap = 0.08, MinGap = 0.2 },
	Deposit = { Id = PING, Volume = 1.0, Pitch = 1.0, Notes = { 0.7, 0.9, 1.1, 1.4 }, NoteGap = 0.09, MinGap = 0.3 },
	SetComplete = { Id = PING, Volume = 1.0, Pitch = 1.0, Notes = { 1.0, 1.25, 1.5, 2.0 }, NoteGap = 0.11, MinGap = 0.5 },
	Error = { Id = "rbxasset://sounds/uuhhh.mp3", Volume = 0.4, Pitch = 1.2, MinGap = 0.25 },
	UI = { Id = "rbxasset://sounds/switch.wav", Volume = 0.5, Pitch = 1.0, MinGap = 0.05 },
}

local MAX_VOICES = 10
local active = 0
local lastPlayed: { [string]: number } = {}

local function voice(def, pitch: number, volume: number, delay: number)
	task.delay(delay, function()
		if active >= MAX_VOICES then
			return
		end
		active += 1
		local s = Instance.new("Sound")
		s.SoundId = def.Id
		s.Volume = volume
		s.PlaybackSpeed = pitch
		s.Parent = SoundService
		local released = false
		local function release()
			if not released then
				released = true
				active -= 1
			end
		end
		s.Ended:Once(release)
		s:Play()
		Debris:AddItem(s, 4) -- frees the instance even if Ended never fires
		task.delay(4, release)
	end)
end

function Audio.Play(name: string, pitchMul: number?, volumeMul: number?)
	local def = Audio.Sounds[name]
	if not def or def.Id == "" then
		return
	end
	local now = os.clock()
	if now - (lastPlayed[name] or -1) < (def.MinGap or 0) then
		return
	end
	lastPlayed[name] = now
	local volume = def.Volume * (volumeMul or 1) * Settings.Get("MasterVolume")
	if volume <= 0 then
		return
	end
	if def.Notes then
		for i, note in ipairs(def.Notes) do
			voice(def, note * (pitchMul or 1), volume, (i - 1) * (def.NoteGap or 0.08))
		end
	else
		voice(def, def.Pitch * (pitchMul or 1), volume, 0)
	end
end

-- Rarity ladder for discoveries: Common stays quiet; each step up is higher and adds notes (order 1..6).
function Audio.PlayReveal(rarityOrder: number)
	if rarityOrder <= 1 then
		Audio.Play("Coin")
		return
	end
	local notes = math.clamp(rarityOrder - 1, 1, 4)
	local def = Audio.Sounds.Reveal
	local now = os.clock()
	if now - (lastPlayed.Reveal or -1) < (def.MinGap or 0) then
		return
	end
	lastPlayed.Reveal = now
	local volume = def.Volume * Settings.Get("MasterVolume") * (0.7 + 0.1 * rarityOrder)
	if volume <= 0 or def.Id == "" then
		return
	end
	for i = 1, notes do
		voice(def, 0.9 + 0.22 * i + 0.06 * rarityOrder, volume, (i - 1) * 0.09)
	end
end

return Audio
