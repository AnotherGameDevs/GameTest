-- Builds tool models from Appearance ids. ONE spec drives both the held Tool (server) and the shop preview
-- (client), so what you preview is exactly what you hold. See docs/ART_STANDARD.md for the rules these follow.
local Kit = require(script.Parent.ModelKit)
local Appearances = require(script.Parent.Appearances)
local Config = require(script.Parent.Config)

local ToolModels = {}

local V = Vector3.new
local function hex(s: string): Color3
	return Color3.fromHex(s)
end

local P = Config.Palette
local WOOD, WOOD_DARK, LACQUER = hex("B07A45"), hex("7A5230"), hex("6B4A2E")
local RUST, RUST_DARK, RUST_LIGHT = hex("B5562F"), hex("7D3A22"), hex("D9803F")
local STEEL, STEEL_DARK, STEEL_LIGHT = hex("A9B7C6"), hex("6F7F91"), hex("D3DDE8")
local METAL = hex("9AA0A6")
local AMBER = hex("E8A33D") -- family B shafts / housings
local RUBBER = hex("23262B")
local GUNMETAL, GUNMETAL_LIGHT = hex("4A5560"), hex("6B7783") -- family B/C steel
local ORANGE, ORANGE_DARK = hex("E5602B"), hex("B84519") -- family C panels
local BOLT = hex("C3C8CE")
local DYNAMITE_RED, CREAM = hex("C23B2A"), P.Cream

-- TOOL AXIS CONVENTION (every model in this file follows it; docs/ART_STANDARD.md repeats it):
--   * Origin (0,0,0) = the invisible root part named "Handle" (a 0.4 cube). It is NEVER an oriented cylinder:
--     a cylinder carries its own axis rotation, and the welds of every other part would then be wrong.
--   * +Y = forward along the tool: the working end (blade / chisel / bit) is at +Y, the grip is at -Y.
--   * +X = width (blade width, cross-grip). +Z = thickness (the flat face of a blade faces +/-Z).
--   * Roblox cylinders run along their own X axis, so Kit.cyl rotates them (Y: roll 90 about Z; Z: yaw 90 about Y).
--   * Every other part is welded to "Handle" at its authored offset (BuildTool) or posed from the same offsets
--     (BuildPreview, BuildWelded viewmodel). There is exactly one source of truth: the Parts list below.
--   * Each spec also carries Checks (names of the shaft / socket / grip / working-end parts) used by
--     tests/tool_assembly_test.luau to prove the assembly is connected and correctly oriented.
-- Studs. First-person uses a separate viewmodel built from these same parts (see Viewmodel / ViewmodelMath).
local builders = {}

local function add(list, ...)
	for _, part in ipairs({ ... }) do
		table.insert(list, part)
	end
end

-- Closed D-grip (top bar, two posts, bottom bar, end caps) centred on x=0 at height y.
local function dGrip(list, y: number, width: number, thickness: number, color: Color3, material: Enum.Material?)
	local half = width / 2 - 0.1
	add(list,
		Kit.cyl("GripTop", "X", width, thickness, V(0, y, 0), color, material),
		Kit.block("PostL", V(thickness * 0.7, 0.7, thickness * 0.7), V(-half, y - 0.35, 0), color, material),
		Kit.block("PostR", V(thickness * 0.7, 0.7, thickness * 0.7), V(half, y - 0.35, 0), color, material),
		Kit.cyl("GripBottom", "X", width, thickness, V(0, y - 0.7, 0), color, material),
		Kit.ball("CapTL", thickness + 0.12, V(-half - 0.08, y, 0), color, material),
		Kit.ball("CapTR", thickness + 0.12, V(half + 0.08, y, 0), color, material))
end

-- Rounded-tip spade blade (rectangle + disc) with a lighter bevel inset and a centre rib. width = full blade width.
local function spadeBlade(list, y: number, width: number, h: number, thick: number, color: Color3, bevel: Color3, rib: Color3, material: Enum.Material?)
	local tipY = y + h / 2 + width / 2 - 0.1
	add(list,
		Kit.block("BladeTop", V(width, h, thick), V(0, y, 0), color, material),
		Kit.cyl("BladeTip", "Z", thick, width, V(0, y + h / 2, 0), color, material),
		Kit.block("BevelTop", V(width * 0.78, h * 0.9, thick + 0.04), V(0, y, 0), bevel, material),
		Kit.cyl("BevelTip", "Z", thick + 0.04, width * 0.78, V(0, y + h / 2, 0), bevel, material),
		Kit.block("Rib", V(0.28, h + width * 0.5, thick + 0.16), V(0, y + (width * 0.5) / 2 - 0.1, 0), rib, material))
	return tipY
end

------------------------------------------------------------------------------------------------------------------
-- FAMILY A: wooden-shaft hand tools (tiers 1-3). Wood shaft, hand-forged blade, T-grip -> D-grip.
------------------------------------------------------------------------------------------------------------------

-- Tier 1: weathered, chunky, obviously a starter. Rust-orange blade, plain wood, T-grip.
function builders.rusty(_)
	return {
		Checks = { Shaft = "Shaft", Socket = { "Ferrule" }, Grip = { "GripBar" }, WorkingEnd = { "BladeTip" } },
		Grip = CFrame.new(0, -1.2, 0),
		FPScale = 0.5,
		Parts = {
			Kit.cyl("Shaft", "Y", 4.4, 0.55, V(0, 0, 0), WOOD, Enum.Material.Wood),
			Kit.cyl("GripBar", "X", 1.5, 0.5, V(0, -2.3, 0), WOOD_DARK, Enum.Material.Wood),
			Kit.ball("GripCapL", 0.66, V(-0.78, -2.3, 0), WOOD_DARK, Enum.Material.Wood),
			Kit.ball("GripCapR", 0.66, V(0.78, -2.3, 0), WOOD_DARK, Enum.Material.Wood),
			Kit.cyl("Ferrule", "Y", 0.9, 0.85, V(0, 2.2, 0), RUST_DARK, Enum.Material.Metal),
			Kit.block("BladeTop", V(1.9, 1.0, 0.28), V(0, 2.9, 0), RUST),
			Kit.cyl("BladeTip", "Z", 0.28, 1.9, V(0, 3.4, 0), RUST),
			Kit.block("Rib", V(0.32, 1.9, 0.42), V(0, 3.1, 0), RUST_DARK),
			Kit.block("RustPatchA", V(0.5, 0.4, 0.32), V(0.5, 3.6, 0), RUST_LIGHT),
			Kit.block("RustPatchB", V(0.35, 0.32, 0.32), V(-0.55, 3.95, 0), RUST_DARK),
			Kit.ball("RivetL", 0.28, V(-0.6, 2.6, 0.16), METAL, Enum.Material.Metal),
			Kit.ball("RivetR", 0.28, V(0.6, 2.6, 0.16), METAL, Enum.Material.Metal),
		},
	}
end

-- Tier 2: clean steel, teal collar + wraps, closed D-grip, bevelled two-tone blade. Same size, clearly "bought".
function builders.digging(_)
	local parts = {
		Kit.cyl("Shaft", "Y", 4.4, 0.55, V(0, 0, 0), LACQUER, Enum.Material.Wood),
		Kit.cyl("WrapA", "Y", 0.45, 0.68, V(0, 0.9, 0), P.Teal),
		Kit.cyl("WrapB", "Y", 0.3, 0.66, V(0, 0.2, 0), P.Teal),
		Kit.cyl("Socket", "Y", 0.9, 0.82, V(0, 2.0, 0), STEEL_DARK, Enum.Material.Metal),
		Kit.block("Collar", V(2.1, 0.4, 0.5), V(0, 2.4, 0), P.Teal),
		Kit.ball("RivetL", 0.3, V(-0.8, 2.4, 0.27), P.Gold, Enum.Material.Metal),
		Kit.ball("RivetR", 0.3, V(0.8, 2.4, 0.27), P.Gold, Enum.Material.Metal),
	}
	dGrip(parts, -2.2, 1.6, 0.5, WOOD_DARK, Enum.Material.Wood)
	spadeBlade(parts, 2.95, 1.9, 1.0, 0.3, STEEL, STEEL_LIGHT, STEEL_DARK, Enum.Material.Metal)
	return { Checks = { Shaft = "Shaft", Socket = { "Socket" }, Grip = { "GripTop", "GripBottom" }, WorkingEnd = { "BladeTip" } },
		Grip = CFrame.new(0, -1.2, 0), FPScale = 0.5, Parts = parts }
end

-- Tier 3: same wooden family and D-grip, but a thicker shaft, a bigger scooped blade with turned-up side lips, and
-- strapped socket. Bigger scoop without being much longer.
function builders.heavy(_)
	local parts = {
		Kit.cyl("Shaft", "Y", 4.4, 0.68, V(0, 0, 0), LACQUER, Enum.Material.Wood),
		Kit.cyl("Socket", "Y", 1.1, 1.0, V(0, 2.0, 0), STEEL_DARK, Enum.Material.Metal),
		Kit.cyl("StrapA", "Y", 0.18, 1.1, V(0, 1.7, 0), STEEL_LIGHT, Enum.Material.Metal),
		Kit.cyl("StrapB", "Y", 0.18, 1.1, V(0, 2.3, 0), STEEL_LIGHT, Enum.Material.Metal),
		Kit.block("Collar", V(2.7, 0.45, 0.62), V(0, 2.55, 0), AMBER),
		Kit.ball("BoltL", 0.3, V(-1.05, 2.55, 0.33), BOLT, Enum.Material.Metal),
		Kit.ball("BoltR", 0.3, V(1.05, 2.55, 0.33), BOLT, Enum.Material.Metal),
		Kit.block("LipL", V(0.24, 1.3, 0.62), V(-1.15, 3.2, 0.12), STEEL_DARK, Enum.Material.Metal),
		Kit.block("LipR", V(0.24, 1.3, 0.62), V(1.15, 3.2, 0.12), STEEL_DARK, Enum.Material.Metal),
	}
	dGrip(parts, -2.2, 1.8, 0.6, WOOD_DARK, Enum.Material.Wood)
	spadeBlade(parts, 3.0, 2.4, 1.0, 0.34, GUNMETAL_LIGHT, STEEL_LIGHT, STEEL_DARK, Enum.Material.Metal)
	return { Checks = { Shaft = "Shaft", Socket = { "Socket" }, Grip = { "GripTop", "GripBottom" }, WorkingEnd = { "BladeTip" } },
		Grip = CFrame.new(0, -1.2, 0), FPScale = 0.5, Parts = parts }
end

------------------------------------------------------------------------------------------------------------------
-- FAMILY B: professional reinforced excavation tools (tiers 4-6). Amber fibreglass-style shafts, rubber grips,
-- bolted steel housings and welded reinforcing ribs.
------------------------------------------------------------------------------------------------------------------

-- Tier 4: a shovel rebuilt as a professional tool: amber shaft, rubber D-grip + hand sleeve, bolted steel socket
-- housing, welded ribs, and small side lugs that hint at its wider cut.
function builders.power(_)
	local parts = {
		Kit.cyl("Shaft", "Y", 4.4, 0.6, V(0, 0, 0), AMBER),
		Kit.cyl("HandSleeve", "Y", 1.1, 0.74, V(0, -1.4, 0), RUBBER),
		Kit.block("Housing", V(1.3, 1.1, 1.0), V(0, 2.0, 0), GUNMETAL, Enum.Material.Metal),
		Kit.block("BandA", V(1.42, 0.18, 1.12), V(0, 1.6, 0), GUNMETAL_LIGHT, Enum.Material.Metal),
		Kit.block("BandB", V(1.42, 0.18, 1.12), V(0, 2.4, 0), GUNMETAL_LIGHT, Enum.Material.Metal),
		Kit.ball("BoltL", 0.26, V(-0.5, 2.0, 0.52), BOLT, Enum.Material.Metal),
		Kit.ball("BoltR", 0.26, V(0.5, 2.0, 0.52), BOLT, Enum.Material.Metal),
		Kit.block("CollarPlate", V(2.2, 0.4, 0.55), V(0, 2.65, 0), GUNMETAL, Enum.Material.Metal),
		Kit.block("LugL", V(0.35, 0.6, 0.5), V(-1.15, 3.1, 0), AMBER),
		Kit.block("LugR", V(0.35, 0.6, 0.5), V(1.15, 3.1, 0), AMBER),
		Kit.block("RibL", V(0.2, 2.1, 0.5), V(-0.62, 3.4, 0), GUNMETAL, Enum.Material.Metal),
		Kit.block("RibR", V(0.2, 2.1, 0.5), V(0.62, 3.4, 0), GUNMETAL, Enum.Material.Metal),
	}
	dGrip(parts, -2.2, 1.7, 0.55, RUBBER)
	spadeBlade(parts, 3.2, 2.0, 1.0, 0.34, GUNMETAL_LIGHT, STEEL_LIGHT, GUNMETAL, Enum.Material.Metal)
	return { Checks = { Shaft = "Shaft", Socket = { "Housing" }, Grip = { "GripTop", "GripBottom" }, WorkingEnd = { "BladeTip" } },
		Grip = CFrame.new(0, -1.4, 0), FPScale = 0.5, Parts = parts }
end

-- Tier 5: a chisel tool. Amber housing on a steel core, rubber cross-grip, steel chisel with a separate bolted edge.
function builders.jackhammer(_)
	return {
		Checks = { Shaft = "Shaft", Socket = { "Collar", "ChiselBar" }, Grip = { "GripBar" }, WorkingEnd = { "ChiselHead", "EdgePlate" } },
		Grip = CFrame.new(0, -2.4, 0),
		FPScale = 0.46,
		Parts = {
			Kit.cyl("Shaft", "Y", 3.0, 0.9, V(0, 0, 0), GUNMETAL, Enum.Material.Metal),
			Kit.cyl("GripBar", "X", 2.4, 0.6, V(0, -2.4, 0), RUBBER),
			Kit.ball("GripCapL", 0.82, V(-1.25, -2.4, 0), RUBBER),
			Kit.ball("GripCapR", 0.82, V(1.25, -2.4, 0), RUBBER),
			Kit.block("Neck", V(0.8, 0.8, 0.8), V(0, -1.9, 0), GUNMETAL, Enum.Material.Metal),
			Kit.block("Housing", V(1.5, 2.4, 1.1), V(0, -0.5, 0), AMBER),
			Kit.block("VentL", V(0.12, 1.4, 0.9), V(-0.78, -0.5, 0), GUNMETAL, Enum.Material.Metal),
			Kit.block("VentR", V(0.12, 1.4, 0.9), V(0.78, -0.5, 0), GUNMETAL, Enum.Material.Metal),
			Kit.block("BandTop", V(1.62, 0.2, 1.22), V(0, 0.55, 0), GUNMETAL_LIGHT, Enum.Material.Metal),
			Kit.cyl("Collar", "Y", 0.5, 1.2, V(0, 0.95, 0), GUNMETAL_LIGHT, Enum.Material.Metal),
			Kit.cyl("ChiselBar", "Y", 1.6, 0.55, V(0, 1.9, 0), STEEL, Enum.Material.Metal),
			Kit.block("ChiselHead", V(1.4, 0.9, 0.28), V(0, 2.9, 0), STEEL_LIGHT, Enum.Material.Metal),
			Kit.block("EdgePlate", V(1.4, 0.22, 0.36), V(0, 3.32, 0), BOLT, Enum.Material.Metal),
			Kit.ball("EdgeBoltL", 0.2, V(-0.5, 3.32, 0.2), GUNMETAL, Enum.Material.Metal),
			Kit.ball("EdgeBoltR", 0.2, V(0.5, 3.32, 0.2), GUNMETAL, Enum.Material.Metal),
		},
	}
end

-- Tier 6: a tunnelling tool. Amber body, rubber D-grip + side handle, and a stepped steel boring head with bolted
-- carbide inserts. The head is a static stepped cone (no spiral, nothing that implies it spins).
function builders.drill(_)
	local parts = {
		Kit.cyl("Shaft", "Y", 3.2, 0.85, V(0, 0, 0), GUNMETAL, Enum.Material.Metal),
		Kit.block("Neck", V(0.7, 0.9, 0.7), V(0, -1.75, 0), GUNMETAL, Enum.Material.Metal),
		Kit.block("Body", V(1.4, 1.8, 1.2), V(0, 0.3, 0), AMBER),
		Kit.block("StripeA", V(1.5, 0.2, 1.26), V(0, 0.95, 0), GUNMETAL, Enum.Material.Metal),
		Kit.block("StripeB", V(1.5, 0.2, 1.26), V(0, -0.35, 0), GUNMETAL, Enum.Material.Metal),
		Kit.cyl("SideHandle", "X", 1.0, 0.45, V(-1.15, -0.4, 0), RUBBER),
		Kit.block("SideMount", V(0.5, 0.5, 0.5), V(-0.65, -0.4, 0), GUNMETAL, Enum.Material.Metal),
		Kit.ball("SideCap", 0.58, V(-1.7, -0.4, 0), RUBBER),
		Kit.cyl("Collar", "Y", 0.5, 1.3, V(0, 1.45, 0), GUNMETAL_LIGHT, Enum.Material.Metal),
		Kit.cyl("HeadStep1", "Y", 0.8, 1.25, V(0, 2.1, 0), STEEL, Enum.Material.Metal),
		Kit.cyl("HeadStep2", "Y", 0.7, 0.95, V(0, 2.85, 0), STEEL, Enum.Material.Metal),
		Kit.cyl("HeadStep3", "Y", 0.6, 0.65, V(0, 3.5, 0), STEEL_LIGHT, Enum.Material.Metal),
		Kit.ball("Tip", 0.45, V(0, 3.9, 0), BOLT, Enum.Material.Metal),
		Kit.block("InsertN", V(0.3, 0.5, 0.3), V(0, 2.15, 0.64), BOLT, Enum.Material.Metal),
		Kit.block("InsertS", V(0.3, 0.5, 0.3), V(0, 2.15, -0.64), BOLT, Enum.Material.Metal),
		Kit.block("InsertE", V(0.3, 0.5, 0.3), V(0.64, 2.15, 0), BOLT, Enum.Material.Metal),
		Kit.block("InsertW", V(0.3, 0.5, 0.3), V(-0.64, 2.15, 0), BOLT, Enum.Material.Metal),
	}
	dGrip(parts, -2.1, 1.7, 0.55, RUBBER)
	return { Checks = { Shaft = "Shaft", Socket = { "Body", "Collar" }, Grip = { "GripTop", "GripBottom" }, WorkingEnd = { "Tip" } },
		Grip = CFrame.new(0, -1.9, 0), FPScale = 0.46, Parts = parts }
end

------------------------------------------------------------------------------------------------------------------
-- FAMILY C: manufactured industrial equipment (tiers 7-8). Gunmetal housings with orange panels, reinforcing ribs,
-- guarded grip assemblies and bolted, replaceable cutting edges. Nothing here implies drive belts, batteries or cables.
------------------------------------------------------------------------------------------------------------------

-- Tier 7: heavy housing with ribbed side panels, a two-grip assembly and a wide bolted cutting head + edge plate.
function builders.industrial(_)
	local parts = {
		Kit.cyl("Shaft", "Y", 3.4, 1.0, V(0, 0, 0), GUNMETAL, Enum.Material.Metal),
		Kit.block("Housing", V(1.9, 2.6, 1.5), V(0, 0, 0), GUNMETAL, Enum.Material.Metal),
		Kit.block("PanelL", V(0.14, 2.0, 1.3), V(-1.0, 0, 0), ORANGE),
		Kit.block("PanelR", V(0.14, 2.0, 1.3), V(1.0, 0, 0), ORANGE),
		Kit.block("PanelFront", V(1.7, 2.0, 0.14), V(0, 0, -0.8), ORANGE_DARK),
		Kit.block("PanelBack", V(1.7, 2.0, 0.14), V(0, 0, 0.8), ORANGE_DARK),
		-- reinforcing ribs
		Kit.block("RibL1", V(0.3, 0.28, 1.6), V(-1.05, -0.9, 0), GUNMETAL_LIGHT, Enum.Material.Metal),
		Kit.block("RibL2", V(0.3, 0.28, 1.6), V(-1.05, 0, 0), GUNMETAL_LIGHT, Enum.Material.Metal),
		Kit.block("RibL3", V(0.3, 0.28, 1.6), V(-1.05, 0.9, 0), GUNMETAL_LIGHT, Enum.Material.Metal),
		Kit.block("RibR1", V(0.3, 0.28, 1.6), V(1.05, -0.9, 0), GUNMETAL_LIGHT, Enum.Material.Metal),
		Kit.block("RibR2", V(0.3, 0.28, 1.6), V(1.05, 0, 0), GUNMETAL_LIGHT, Enum.Material.Metal),
		Kit.block("RibR3", V(0.3, 0.28, 1.6), V(1.05, 0.9, 0), GUNMETAL_LIGHT, Enum.Material.Metal),
		-- grip assembly: guarded rear cross-grip + a front hand grip
		Kit.cyl("GripBar", "X", 2.6, 0.62, V(0, -2.2, 0), RUBBER),
		Kit.block("GuardL", V(0.45, 0.9, 0.45), V(-1.05, -1.75, 0), GUNMETAL, Enum.Material.Metal),
		Kit.block("GuardR", V(0.45, 0.9, 0.45), V(1.05, -1.75, 0), GUNMETAL, Enum.Material.Metal),
		Kit.block("GuardMid", V(0.6, 0.9, 0.6), V(0, -1.75, 0), GUNMETAL, Enum.Material.Metal),
		Kit.ball("GripCapL", 0.8, V(-1.35, -2.2, 0), RUBBER),
		Kit.ball("GripCapR", 0.8, V(1.35, -2.2, 0), RUBBER),
		Kit.cyl("FrontGrip", "X", 2.2, 0.5, V(0, 0.95, -1.1), RUBBER),
		Kit.block("FrontMountL", V(0.3, 0.3, 0.6), V(-0.7, 0.95, -0.85), GUNMETAL, Enum.Material.Metal),
		Kit.block("FrontMountR", V(0.3, 0.3, 0.6), V(0.7, 0.95, -0.85), GUNMETAL, Enum.Material.Metal),
		-- socket housing + replaceable cutting head
		Kit.cyl("Socket", "Y", 1.0, 1.7, V(0, 1.75, 0), GUNMETAL_LIGHT, Enum.Material.Metal),
		Kit.cyl("SocketRing", "Y", 0.2, 1.9, V(0, 1.3, 0), ORANGE),
		Kit.block("HeadBody", V(2.2, 1.1, 0.7), V(0, 2.6, 0), STEEL, Enum.Material.Metal),
		Kit.block("EdgePlate", V(2.2, 0.35, 0.46), V(0, 3.25, 0), BOLT, Enum.Material.Metal),
		Kit.block("ToothL", V(0.42, 0.4, 0.5), V(-0.7, 3.5, 0), STEEL_LIGHT, Enum.Material.Metal),
		Kit.block("ToothM", V(0.42, 0.4, 0.5), V(0, 3.5, 0), STEEL_LIGHT, Enum.Material.Metal),
		Kit.block("ToothR", V(0.42, 0.4, 0.5), V(0.7, 3.5, 0), STEEL_LIGHT, Enum.Material.Metal),
		Kit.ball("EdgeBoltA", 0.26, V(-0.85, 3.25, 0.26), GUNMETAL, Enum.Material.Metal),
		Kit.ball("EdgeBoltB", 0.26, V(-0.28, 3.25, 0.26), GUNMETAL, Enum.Material.Metal),
		Kit.ball("EdgeBoltC", 0.26, V(0.28, 3.25, 0.26), GUNMETAL, Enum.Material.Metal),
		Kit.ball("EdgeBoltD", 0.26, V(0.85, 3.25, 0.26), GUNMETAL, Enum.Material.Metal),
	}
	return { Checks = { Shaft = "Shaft", Socket = { "Housing", "Socket" }, Grip = { "GripBar" }, WorkingEnd = { "EdgePlate", "ToothM" } },
		Grip = CFrame.new(0, -2.2, 0), FPScale = 0.4, Parts = parts }
end

-- Tier 8 (consumable): a bundle of three charges held with steel bands and a stencilled label; one fuse.
function builders.dynamite(_)
	local parts = {}
	local centres = { V(0, 0, 0), V(0.86, 0, 0), V(0.43, 0, 0.75) }
	for i, c in ipairs(centres) do
		table.insert(parts, Kit.cyl("Stick" .. i, "Y", 3.0, 0.85, c, DYNAMITE_RED))
		table.insert(parts, Kit.cyl("Label" .. i, "Y", 1.0, 0.89, c, CREAM))
		table.insert(parts, Kit.cyl("BandLo" .. i, "Y", 0.22, 0.92, c + V(0, -1.05, 0), BOLT, Enum.Material.Metal))
		table.insert(parts, Kit.cyl("BandHi" .. i, "Y", 0.22, 0.92, c + V(0, 1.05, 0), BOLT, Enum.Material.Metal))
	end
	add(parts,
		Kit.cyl("Fuse", "Y", 0.7, 0.12, V(0.43, 1.85, 0.25), RUBBER),
		Kit.ball("FuseTip", 0.22, V(0.43, 2.25, 0.25), ORANGE, Enum.Material.Neon))
	return { Grip = CFrame.new(0, 0, 0), FPScale = 0.5, Parts = parts }
end

-- Spec = { Parts, Grip, FPScale, Checks }. Parts[1] is ALWAYS the invisible root cube "Handle" at the origin.
function ToolModels.GetSpec(appearanceId: string)
	local ap = Appearances.List[appearanceId] or Appearances.List.shovel_rusty
	local builder = builders[ap.Builder] or builders.rusty
	local spec = builder(ap)
	local root = Kit.block("Handle", V(0.4, 0.4, 0.4), V(0, 0, 0), METAL)
	root.Transparency = 1
	table.insert(spec.Parts, 1, root)
	return spec
end

local function harden(p: Part)
	p.CanCollide = false -- decorative: never collides
	p.CanQuery = false -- ...and never intercepts a mining/targeting ray
	p.CanTouch = false
	p.Massless = true
end

-- The held Tool (server). Root "Handle" is an invisible cube; EVERY other part (shaft included) is welded to it at
-- its authored offset, so the tool is one rigid assembly whichever way the character animates its hand.
-- Tool.Grip is only a position along the shaft where the hand holds it (no rotation: hand +Y = tool +Y).
function ToolModels.BuildTool(appearanceId: string): Tool
	local spec = ToolModels.GetSpec(appearanceId)
	local tool = Instance.new("Tool")
	tool.Name = "Shovel" -- stable internal name every script looks up, whatever the tool looks like
	tool.CanBeDropped = false
	tool.ManualActivationOnly = true
	tool.RequiresHandle = true
	tool.Grip = spec.Grip
	tool:SetAttribute("AppearanceId", appearanceId)

	local handle = Kit.make(spec.Parts[1])
	harden(handle)
	handle.Parent = tool
	for i = 2, #spec.Parts do
		local ps = spec.Parts[i]
		local p = Kit.make(ps)
		harden(p)
		p.Parent = tool
		local w = Instance.new("Weld")
		w.Name = "Weld_" .. ps.Name
		w.Part0 = handle
		w.Part1 = p
		w.C0 = ps.Offset
		w.Parent = p
	end
	return tool
end

-- The same tool as an anchored Model for the shop's rotating preview.
function ToolModels.BuildPreview(appearanceId: string): Model
	local spec = ToolModels.GetSpec(appearanceId)
	return Kit.BuildModel(spec.Parts, "ToolPreview")
end

-- A physics-ready copy for thrown items (dynamite): every part collides as one welded body around the invisible root.
function ToolModels.BuildProjectile(appearanceId: string): Model
	local spec = ToolModels.GetSpec(appearanceId)
	local model = Instance.new("Model")
	model.Name = "Projectile"
	local handle = Kit.make(spec.Parts[1])
	handle.CanCollide = false
	handle.CanTouch = false
	handle.Parent = model
	model.PrimaryPart = handle
	for i = 2, #spec.Parts do
		local ps = spec.Parts[i]
		local p = Kit.make(ps)
		p.CanCollide = true
		p.CanTouch = false
		p.Parent = model
		local w = Instance.new("Weld")
		w.Part0 = handle
		w.Part1 = p
		w.C0 = ps.Offset
		w.Parent = p
	end
	return model
end

return ToolModels
