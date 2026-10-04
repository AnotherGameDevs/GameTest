-- Single place that declares every remote. Server creates them; client waits for them.
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = {}

local EVENTS = {
	"ClientReady", -- C->S  client finished loading, wants initial state
	"DigHit", -- C->S  (x, y, z) request to hit a cell
	"RequestPurchase", -- C->S  (kind, id)
	"RequestEquip", -- C->S  (kind, id)  equip an already-owned tool
	"ReturnToCamp", -- C->S
	"PlayerState", -- S->C  full state snapshot
	"DigResult", -- S->C  { hits = {...}, depth }
	"TreasureFound", -- S->C  treasure reveal
	"Sold", -- S->C  (amount, count)
	"Notify", -- S->C  (text, kind)
	"ReturnResult", -- S->C  (ok, secondsUntilReady, reason?)
	"PlaceArtifact", -- C->S  put the carried artifact down
	"UpdateSettings", -- C->S  player settings table (validated + clamped by the server)
	"ThrowDynamite", -- C->S  (dx, dy, dz) aim direction; the server decides everything else
	"Explosion", -- S->C  (position) cosmetic blast feedback
	"ArtifactDeposited", -- S->C  (name, value)
}

local folder: Folder
if RunService:IsServer() then
	folder = ReplicatedStorage:FindFirstChild("Remotes") or Instance.new("Folder")
	folder.Name = "Remotes"
	folder.Parent = ReplicatedStorage
	for _, name in ipairs(EVENTS) do
		if not folder:FindFirstChild(name) then
			local ev = Instance.new("RemoteEvent")
			ev.Name = name
			ev.Parent = folder
		end
	end
else
	folder = ReplicatedStorage:WaitForChild("Remotes")
end

function Remotes.Get(name: string): RemoteEvent
	return folder:WaitForChild(name) :: RemoteEvent
end

return Remotes
