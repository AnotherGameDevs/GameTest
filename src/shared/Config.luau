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
	Depth = 20, -- cells deep (four layers of five rows, 20 studs each)
	Center = Vector3.new(0, 0, 0), -- world XZ centre of the site, Y of the surface
	Seed = 1337, -- change for a different (seeded) layout
	StudsPerMeter = 3.5, -- for the depth readout
	BorderHeight = 6, -- decorative rim
}

-- Depth layers, ordered shallow -> deep. FromCell is the first cell-depth index (0 = top row).
-- MinToolTier: the lowest tool tier that can break blocks of this layer (docs/MINE_SHIFT.md, 'Layer gating'). It keeps
-- a starter shovel from diving straight to the most valuable layer, so every tier has content that is new to it.
Config.Layers = {
	{ Id = "Soil", Name = "SOIL", FromCell = 0, Color = Config.Palette.Dirt, Health = 24, TreasureChance = 0.20, MinToolTier = 1 },
	{ Id = "Clay", Name = "CLAY", FromCell = 5, Color = Config.Palette.Clay, Health = 42, TreasureChance = 0.26, MinToolTier = 1 },
	{ Id = "Stone", Name = "STONE", FromCell = 10, Color = Config.Palette.Rock, Health = 72, TreasureChance = 0.30, MinToolTier = 3 },
	{ Id = "Ruins", Name = "RUINS", FromCell = 15, Color = Config.Palette.Sandstone, Health = 110, TreasureChance = 0.30, MinToolTier = 5 },
}

Config.Dig = {
	ReachTolerance = 2, -- studs of slack the SERVER adds to tool Reach (movement/latency). Client indicator uses none.
	CooldownTolerance = 0.80, -- server accepts hits at >= 80% of the tool's nominal interval
	MaxBroadcastDistance = 220, -- only clients within this distance get hit feedback
}

Config.Backpack = {
	AutoSellEnabled = true, -- stepping onto the Sell Zone sells everything
	SellCooldown = 1.0,
}

-- Map boundary: invisible walls stand at +-BoundaryExtent. Ground, slabs and landforms are built relative to it.
Config.World = {
	BoundaryExtent = 170,
}

-- Base Camp. Every location other systems act on (spawn, return-to-camp, shop, selling, deposit) comes from here, so moving a
-- station means changing ONE value; the model, the prompt and the server check all follow.
-- The camp floor starts exactly at the shaft/elevator edge (z = 56) and runs south, away from the mine.
-- Layout (z increases away from the mine): mine rim z=48 -> entrance gate z=58.5 -> stations beside the route -> spawn z=98.
Config.Camp = {
	Position = Vector3.new(0, 0, 82), -- centre of the camp floor (surface level)
	Size = Vector3.new(80, 2, 52), -- floor spans x -40..40, z 56..108
	SpawnPosition = Vector3.new(0, 0, 98), -- ~39.5 studs of straight walking from the entrance gate
	EntranceZ = 58.5, -- the mine entrance gate (EntranceZ is where "walking distance to the mine" ends)
	SellZoneCenter = Vector3.new(-18, 0, 82), -- logic centre of the sell trigger; the appraisal stall stands 12 studs north of it
	SellZoneRadius = 9,
	ShopPosition = Vector3.new(20, 0, 88),
	ShopReach = 34, -- server-side purchase range (the client closes the shop at 30)
	ReceivingPosition = Vector3.new(24, 0, 73), -- artifact receiving table (a short walk from the elevator exit)
	LostFoundPosition = Vector3.new(31, 0, 73), -- beside the table
	-- Declared footprints (half-extents on X and Z) of what each builder actually builds; used by the layout test and
	-- by any future placement tool. Keep in step with WorldCamp.
	Footprints = {
		Shop = { Center = Vector3.new(20, 0, 88), HalfX = 7.0, HalfZ = 4.8 },
		Appraisal = { Center = Vector3.new(-18, 0, 70), HalfX = 6.5, HalfZ = 4.2 },
		Receiving = { Center = Vector3.new(24, 0, 73), HalfX = 3.7, HalfZ = 2.6 },
		Shelf = { Center = Vector3.new(-30, 0, 96), HalfX = 1.2, HalfZ = 4.9 }, -- personal display (client-side, Config.Collection)
	},
	-- Required clear spaces (checked by tests/camp_layout_test.luau)
	ArrivalHalfSize = 8, -- 16 x 16 clear area around the spawn
	MinStationGap = 12, -- walking width between the stations either side of the route
	MinRimClearance = 8, -- station structures to the mine rim
}

-- "Important" artifacts (Defs.Treasure[...].RequiresCarry = true) must be physically carried to camp.
Config.Artifacts = {
	SpawnDelay = 1.3, -- seconds after discovery before the physical artifact appears (lets the reveal play first)
	PickupReach = 14, -- studs from player to artifact for a pickup
	DepositReach = 16, -- studs from player to the receiving table for a deposit
	PlaceReach = 8, -- max horizontal distance a placed artifact may land from the player
	CarryScale = 0.7, -- the held model is drawn at this fraction of its world size
	CarryRotation = Vector3.new(90, 0, 0), -- degrees applied to the held model (tune after seeing the pose)
	CarryGrip = CFrame.new(0, -0.8, 0), -- Tool.Grip for the held artifact
	DisplaySeconds = 3, -- how long a deposited artifact sits on the receiving table
}

-- Fixed physical exit from the mine: a ladder shaft outside the destructible grid, on the camp (south) edge.
Config.Exit = {
	Enabled = true,
	CenterX = 28, -- world X of the shaft centre (edges must land on cell boundaries: 4-stud multiples). Right of the pit.
	Width = 16, -- left half = ladder + landings, right half = elevator car
	Run = 8, -- studs the shaft extends south from the grid edge
}

-- Collection journal + camp display (docs/COLLECTION.md).
Config.Collection = {
	DisplaySlots = 4, -- artifacts a player can show on their camp shelf
	ShelfPosition = Vector3.new(-30, 0, 96), -- personal display shelf (client-side, local player's picks only)
	ShelfReach = 12, -- the shelf is only built/visible when the player is this close
}

-- Mine appearance and buried discoveries (docs/MINE_DETAIL.md). All placement is a pure function of (cell, layer, seed).
Config.Mine = {
	AmbientChance = { Soil = 0.07, Clay = 0.06, Stone = 0.07, Ruins = 0.07 }, -- chance an exposed non-loot cell carries an ambient remnant
	TellChance = 0.45, -- chance a cell holding one of the "tellable" rewards shows its real reward when its face is exposed
	PocketChance = 0.55, -- chance a non-loot cell INSIDE a pocket carries that pocket's remnant
	MaxDetails = 220, -- hard cap on live detail objects in the whole mine
	Pockets = { Cache = 3, Fossil = 3, Masonry = 2 }, -- discovery pockets per generation
}

-- Shared-mine replenishment ("Fresh Dig", docs/MINE_SHIFT.md).
Config.Shift = {
	Enabled = true,
	TriggerFraction = 0.55, -- fraction of ALL cells dug that triggers a refresh
	DeepLayerFraction = 0.70, -- ...or this fraction of the deepest layer dug (nothing left to reach)
	MaxAgeMinutes = 60, -- ...or the mine is this old and at least MinFractionForAge of it has been dug
	MinFractionForAge = 0.10,
	CheckInterval = 5, -- seconds between depletion checks
	WarningSeconds = 45, -- countdown shown to everyone before the refresh
	CarryDeferSeconds = 120, -- how long a refresh waits for carriers still inside the mine before dropping their artifact
	SeedStep = 7919, -- each refresh uses Seed + count * SeedStep
}

Config.Shop = {
	SequentialTools = true, -- a tool tier can only be bought once the previous tier is owned
}

-- Server-side balance telemetry (printed to the server Output). Used to measure blocks/min and cash/min.
Config.Metrics = {
	Enabled = false, -- development telemetry; Studio sessions force it on (see MetricsService)
	PrintInterval = 60, -- seconds per reporting window
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
	CurrentVersion = 3, -- v2: eight-tier tool progression; v3: collection display + onboarding progress
}

Config.RateLimits = { -- { max calls, per seconds }
	DigHit = { 14, 1 },
	RequestPurchase = { 5, 2 },
	ReturnToCamp = { 2, 5 },
	ClientReady = { 3, 5 },
	RequestEquip = { 5, 2 },
	PlaceArtifact = { 3, 3 },
	ThrowDynamite = { 4, 3 },
	UpdateSettings = { 6, 3 },
	GuideDone = { 10, 5 },
	GuideControl = { 3, 5 },
	SetDisplay = { 6, 3 },
}

return Config
