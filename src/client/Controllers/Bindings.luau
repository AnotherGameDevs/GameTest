-- The ONE place gameplay keys are defined. Controllers read these; the Controls page of the menu displays them, so
-- what the menu shows is always what is actually bound.
local UserInputService = game:GetService("UserInputService")

local Bindings = {}

Bindings.FreeCursor = Enum.KeyCode.LeftAlt -- toggle mining mode <-> free cursor (first person)
Bindings.CameraToggle = Enum.KeyCode.V -- first <-> third person
Bindings.ReturnToCamp = Enum.KeyCode.R
Bindings.PlaceArtifact = Enum.KeyCode.X
Bindings.ThrowDynamite = Enum.KeyCode.G
Bindings.Menu = Enum.KeyCode.P
Bindings.Journal = Enum.KeyCode.J
Bindings.DevPanel = Enum.KeyCode.BackSlash -- developer test panel (only exists for server-authorised accounts)
Bindings.RelicStrike = Enum.KeyCode.F -- contested relic only: strike the carrier / shove attackers (never a mining click)

function Bindings.Name(keyCode: Enum.KeyCode): string
	local ok, name = pcall(function()
		return UserInputService:GetStringForKeyCode(keyCode)
	end)
	if ok and name and name ~= "" then
		return name
	end
	return keyCode.Name
end

return Bindings
