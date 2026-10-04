-- All sound ids live in this one table so real audio can be swapped in without touching gameplay code.
-- The defaults are Roblox's built-in client sounds (placeholders). Set Id = "" to silence one.
local SoundService = game:GetService("SoundService")
local Debris = game:GetService("Debris")

local Audio = {}

Audio.Sounds = {
	Impact = { Id = "rbxasset://sounds/action_jump_land.mp3", Volume = 0.8, Pitch = 0.8 },
	Break = { Id = "rbxasset://sounds/snap.mp3", Volume = 0.9, Pitch = 0.7 },
	Coin = { Id = "rbxasset://sounds/electronicpingshort.wav", Volume = 0.5, Pitch = 1.3 },
	Reveal = { Id = "rbxasset://sounds/electronicpingshort.wav", Volume = 0.8, Pitch = 1.0 },
	Sell = { Id = "rbxasset://sounds/electronicpingshort.wav", Volume = 0.9, Pitch = 0.8 },
	Buy = { Id = "rbxasset://sounds/electronicpingshort.wav", Volume = 0.9, Pitch = 1.5 },
	Error = { Id = "rbxasset://sounds/uuhhh.mp3", Volume = 0.4, Pitch = 1.2 },
	UI = { Id = "rbxasset://sounds/switch.wav", Volume = 0.5, Pitch = 1.0 },
}

function Audio.Play(name: string, pitchMul: number?, volumeMul: number?)
	local def = Audio.Sounds[name]
	if not def or def.Id == "" then
		return
	end
	local s = Instance.new("Sound")
	s.SoundId = def.Id
	s.Volume = def.Volume * (volumeMul or 1)
	s.PlaybackSpeed = def.Pitch * (pitchMul or 1)
	s.Parent = SoundService
	s:Play()
	Debris:AddItem(s, 4)
end

return Audio
