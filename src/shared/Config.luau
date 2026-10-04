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
	Seed = 1337, -- base for COSMETIC variation only (colours/remnants). Loot is placed from a fresh random server-only seed per generation.
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
	RecoveryPosition = Vector3.new(-14, 0, 59), -- owner-claimed recovery area beside the mine entrance gate, far outside the deposit zone
	LostFoundPosition = Vector3.new(31, 0, 73), -- beside the table
	-- Declared footprints (half-extents on X and Z) of what each builder actually builds; used by the layout test and
	-- by any future placement tool. Keep in step with WorldCamp.
	Footprints = {
		Shop = { Center = Vector3.new(20, 0, 88), HalfX = 7.0, HalfZ = 4.8 },
		Appraisal = { Center = Vector3.new(-18, 0, 70), HalfX = 6.5, HalfZ = 4.2 },
		Receiving = { Center = Vector3.new(24, 0, 73), HalfX = 3.7, HalfZ = 2.6 },
		Recovery = { Center = Vector3.new(-14, 0, 59), HalfX = 4.0, HalfZ = 2.8 },
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

-- Server relic: the ONE contested, carry-home PvP event (docs/RELIC_PVP.md). Only treasures flagged `Relic = true` in Defs take
-- part; ordinary loot and personal important artifacts keep their peaceful rules. All values are provisional until multiplayer
-- playtests. Combat strength never depends on tool stats.
Config.Relic = {
	Enabled = true,
	MaxControl = 100, -- the carrier's relic-control meter; at 0 the relic drops
	ControlPerHit = 25, -- control lost per validated hit (4 hits)
	AttackRange = 7, -- studs, attacker to carrier
	AttackCooldown = 1.0, -- seconds between a player's strikes
	RequestGap = 0.25, -- minimum seconds between ANY two attack requests from one player, accepted or not (anti-spam)
	StrikeKnockback = 9, -- studs/s pushed onto the carrier by a hit (one clamped velocity set, never stacked)
	ShoveRange = 7, -- the carrier's defensive shove
	ShoveCooldown = 4.0,
	ShoveKnockback = 20,
	ShoveEngageSeconds = 12, -- only players who struck at the carrier this recently can be shoved (no unrelated targets)
	MaxKnockbackH = 24, -- hard caps on any knockback, studs/s
	MaxKnockbackUp = 7,
	PickupProtection = 3.0, -- seconds a new carrier cannot lose control (short, so it never covers the escape route)
	PickupReach = 12,
	RegrabLockout = 5.0, -- the player who just dropped/placed it can not re-grab it for this long (no control reset by place + re-pickup)
	PlaceReach = 8,
	SafeBoundaryZ = 64, -- the camp's safe zone starts at this z (camp side); PvP and control loss stop there
	CampGraceSeconds = 20, -- CUMULATIVE time in the safe zone without depositing -> the relic returns to the recovery point (leaving only decays it at half speed)
	RecoveryPoint = Vector3.new(0, 0, 53), -- on the entrance boardwalk, inside the contested area, outside the safe zone
	UnreachableBelowY = -90, -- a dropped relic below this (or outside the map) is returned to the recovery point
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

-- Imported artifact meshes (docs/ARTIFACT_MESHES.md). EMPTY until the OBJ files in assets/artifact_meshes/ have been imported in
-- Roblox Studio and uploaded. While an artifact has no entry here the game uses its primitive-part model, which is a
-- documented FALLBACK for the artifacts listed in TreasureModels.MeshRequired (their silhouette requirement is not met by parts).
-- Entry: Config.MeshAssets[treasureId] = { { Name = "outer", MeshId = "rbxassetid://123", Color = "B5683F", Material = "SmoothPlastic",
--   Size = Vector3.new(x, y, z) (the mesh's native bounding size in studs, from assets/artifact_meshes/manifest.json) }, ... }
Config.MeshAssets = {}

-- Mine appearance and buried discoveries (docs/MINE_DETAIL.md). All placement is a pure function of (cell, layer, seed).
Config.Mine = {
	TellChance = { Common = 0.35, Uncommon = 0.5, Rare = 0.65, Epic = 1, Legendary = 1 }, -- chance a buried reward shows part of ITSELF once its face is exposed
	TellProtrude = 0.7, -- studs of the real artifact that stand out of the wall
	AmbientChance = { Soil = 0.07, Clay = 0.06, Stone = 0.07, Ruins = 0.07 }, -- chance an exposed non-loot cell carries an ambient remnant
	PocketChance = 0.55, -- chance a non-loot cell INSIDE a pocket carries that pocket's remnant
	MaxDetails = 160, -- hard cap on live detail objects in the whole mine
	MaxDetailParts = 1800, -- ...and on the parts they use
	Pockets = { Cache = 3, Fossil = 3, Masonry = 2 }, -- discovery pockets per generation
}

-- Mine reset lifecycle (docs/MINE_RESET.md). One server-controlled state machine:
--   Active -> Warning -> Evacuating -> Regenerating -> Active.
-- PROVISIONAL playtest values. Nothing a client sends can start, delay or repeat a reset.
Config.Reset = {
	Enabled = true,
	IntervalMinutes = 20, -- scheduled reset after this much ACTIVE time (the clock pauses while the server is empty)
	DepletionFraction = 0.70, -- earlier reset once this fraction of the DIGGABLE cells is gone (diggable = layers the best online tool can break)
	MinLifetimeMinutes = 10, -- depletion can never trigger a reset before the generation is this old
	WarningSeconds = 60, -- countdown before the reset; the last 10 s are called out
	FinalCountdownSeconds = 10,
	EvacuateSeconds = 3, -- pause between "stop accepting requests" and the new mine (players are moved, artifacts recovered)
	CheckInterval = 1,
	RelicHoldSeconds = 90, -- a reset waits at most this long (after the countdown) for an active relic event to finish, then expires it
}

-- Buried loot (docs/LOOT.md). Placement is rolled ONCE per mine generation from a fresh server-only seed.
Config.Loot = {
	-- Important (carry-home) artifacts: at most this many exist in one generation (each is claimed once). Extra rolls become
	-- ordinary finds. Individually configurable.
	ImportantLimits = { fossil_claw = 4, golden_scarab = 2, sun_mask = 1 },
	DefaultImportantLimit = 2,
	ExitClearCells = 2, -- important artifacts keep this many cells away from the elevator shaft side of the grid
	ReplaceTries = 8,
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
	RelicAttack = { 6, 2 },
	RelicPickup = { 4, 3 },
	RelicPlace = { 3, 3 },
	ArtifactPickup = { 4, 3 },
	GuideDone = { 10, 5 },
	GuideControl = { 3, 5 },
	SetDisplay = { 6, 3 },
}

return Config
