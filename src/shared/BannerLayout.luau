-- Pure layout for the centred announcement banner ("SOLD", "ARTIFACT SECURED", "SET COMPLETE!"). The client uses these numbers
-- directly, and tests/ui_layout_test.luau checks them at several window sizes, so the text can never be wider than its container.
-- Coordinates are in the HUD's virtual pixels: the HUD ScreenGui carries UIScale = clamp(viewportHeight / 720, 0.75, 1.4).
local BannerLayout = {}

local CHAR_W = 0.62 -- worst-case glyph advance / font size for the (bold, rounded) UI font; deliberately pessimistic
local MIN_TITLE, MAX_TITLE = 20, 56
local MIN_SUB, MAX_SUB = 14, 24
local SIDE_MARGIN = 28 -- virtual px kept free on each side of the screen
local PADDING = 22 -- inside the banner

function BannerLayout.HudScale(viewportY: number): number
	return math.clamp(viewportY / 720, 0.75, 1.4)
end

-- viewport in real pixels; titleChars / subChars = text lengths. Returns the banner box and font sizes.
function BannerLayout.Compute(viewportX: number, viewportY: number, titleChars: number, subChars: number)
	local scale = BannerLayout.HudScale(viewportY)
	local vw, vh = viewportX / scale, viewportY / scale
	local width = math.clamp(vw * 0.6, 260, math.min(720, vw - 2 * SIDE_MARGIN))
	local inner = width - 2 * PADDING

	-- title: as large as fits on ONE line; if even the minimum does not fit, wrap to two lines at the minimum
	local fit = inner / (math.max(titleChars, 1) * CHAR_W)
	local titleSize = math.floor(math.min(MAX_TITLE, fit))
	local titleLines = 1
	if titleSize < MIN_TITLE then
		titleSize, titleLines = MIN_TITLE, 2
	end
	local subFit = inner / (math.max(subChars, 1) * CHAR_W)
	local subSize = math.floor(math.min(MAX_SUB, subFit))
	local subLines = 1
	if subSize < MIN_SUB then
		subSize, subLines = MIN_SUB, 2
	end
	local height = PADDING + titleSize * 1.15 * titleLines + 6 + subSize * 1.2 * subLines + PADDING * 0.6
	-- under the top HUD text rows when there is room, but ALWAYS above the crosshair (screen centre): on very small windows it moves up
	-- (overlapping the HUD rows is the lesser evil) rather than ever covering the aim point
	local top = math.max(math.min(math.max(vh * 0.22, 180), vh / 2 - 12 - height), 40)
	return {
		Width = width, Height = height, Top = top, Bottom = top + height, TitleSize = titleSize, TitleLines = titleLines, SubSize = subSize,
		SubLines = subLines, Padding = PADDING, Inner = inner, VirtualWidth = vw, VirtualHeight = vh, Scale = scale,
	}
end

-- Conservative estimate of how wide `chars` characters of `size` pixel text are (used by the test, same constant as the layout).
function BannerLayout.TextWidth(chars: number, size: number): number
	return chars * size * CHAR_W
end

return BannerLayout
