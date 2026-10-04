-- All tunable balance/feel values live here. Nothing in the services should hardcode these.
local Config = {}

Config.GameName = "DIG & RUN!"

Config.Palette = {
	Dirt = Color3.fromHex("9A623A"),
	Clay = Color3.fromHex("C97846"),
	Sandstone = Color3.fromHex("D8B678"),
	Rock = Color3.fromHex("68717C"),
	Dark = Color3.fromHex("262A30"),
	Cream = Color3.fromHex("EFE2C3"),
	Gold = Color3.fromHex("F5B942"),
	Teal = Color3.fromHex("41BDAE"),
	Danger = Color3.fromHex("EF5944"),
}

-- Excavation grid. Surface of the site is Y = 0, the site extends downward.
Config.Site = {
	CellSize = 4, -- studs per dig cell
	SizeX = 24, -- cells
	SizeZ = 24,
	Depth = 14, -- cells deep
	Center = Vector3.new(0, 0, 0), -- world XZ centre of the site, Y of the surface
	Seed = 1337, -- change for a different (seeded) layout
	StudsPerMeter = 3.5, -- for the depth readout
	BorderHeight = 6, -- decorative rim
}

-- Depth layers, ordered shallow -> deep. FromCell is the first cell-depth index (0 = top row).
Config.Layers = {
	{ Id = "Soil", Name = "SOIL", FromCell = 0, Color = Config.Palette.Dirt, Health = 24, TreasureChance = 0.20 },
	{ Id = "Clay", Name = "CLAY", FromCell = 4, Color = Config.Palette.Clay, Health = 42, TreasureChance = 0.26 },
	{ Id = "Stone", Name = "STONE", FromCell = 8, Color = Config.Palette.Rock, Health = 70, TreasureChance = 0.30 },
	{ Id = "Ruins", Name = "RUINS", FromCell = 11, Color = Config.Palette.Sandstone, Health = 100, TreasureChance = 0.34 },
}

Config.Dig = {
	ReachPadding = 4, -- studs added to tool reach for server distance check (lag tolerance)
	CooldownTolerance = 0.80, -- server accepts hits at >= 80% of the tool's nominal interval
	SplashFraction = 0.55, -- damage fraction applied to neighbours when tool DigRadius > 0
	MaxBroadcastDistance = 220, -- only clients within this distance get hit feedback
}

Config.Backpack = {
	AutoSellEnabled = true, -- stepping onto the Sell Zone sells everything
	SellCooldown = 1.0,
}

Config.Camp = {
	Position = Vector3.new(0, 0, 78), -- centre of Base Camp floor (surface level)
	Size = Vector3.new(60, 2, 44),
	SellZoneOffset = Vector3.new(-14, 0, 0),
	ShopOffset = Vector3.new(14, 0, -4),
	SellZoneRadius = 9,
}

Config.ReturnToCamp = {
	Enabled = true,
	Cooldown = 8,
}

Config.Starting = {
	Cash = 0,
	ToolId = "rusty_shovel",
	BackpackId = "pouch",
}

Config.Data = {
	Enabled = true, -- false = never touch DataStore (everything in memory)
	StoreName = "DigAndRun_PlayerData_v1",
	AutosaveInterval = 60,
	CurrentVersion = 1,
}

Config.RateLimits = { -- { max calls, per seconds }
	DigHit = { 14, 1 },
	RequestPurchase = { 5, 2 },
	ReturnToCamp = { 2, 5 },
	ClientReady = { 3, 5 },
}

return Config
