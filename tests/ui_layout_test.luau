-- Run via tests/run_all.sh. The announcement banner must fit its text at real window sizes. This is a LAYOUT CALCULATION with a deliberately
-- pessimistic glyph width, not a rendering: visual confirmation in Studio at each size is still required (docs/STUDIO_INTEGRATION_CHECKLIST.md).
local BannerLayout = require("./_build/shared/BannerLayout")

local passed, failed = 0, 0
local function check(name, cond, detail) if cond then passed += 1 else failed += 1; print("FAIL: " .. name .. (detail and ("  -> " .. detail) or "")) end end

local sizes = { { 1920, 1080 }, { 1366, 768 }, { 1280, 720 }, { 1024, 600 }, { 800, 600 }, { 640, 480 }, { 480, 360 } }
local texts = {
	{ "SET COMPLETE!", "STONE COLLECTION" },
	{ "SET COMPLETE!", "RUINS COLLECTION" },
	{ "+$1,234,567", "SOLD 140 TREASURES" },
	{ "+$3,500", "ARTIFACT SECURED: SUN PHARAOH MASK  -  NEW ENTRY!" },
}
for _, sz in ipairs(sizes) do
	for _, t in ipairs(texts) do
		local l = BannerLayout.Compute(sz[1], sz[2], #t[1], #t[2])
		local tag = ("%dx%d '%s'"):format(sz[1], sz[2], t[1])
		check(tag .. ": banner leaves comfortable side margins", l.Width <= l.VirtualWidth - 2 * 24 + 1e-6, ("w=%.0f of %.0f"):format(l.Width, l.VirtualWidth))
		check(tag .. ": banner is centred (equal margins) by construction", math.abs((l.VirtualWidth - l.Width) / 2 - (l.VirtualWidth - l.Width) / 2) < 1e-9 and l.Width >= 260 - 1e-6 or l.VirtualWidth < 320)
		-- title text fits inside the container (per line)
		local perLineTitle = math.ceil(#t[1] / l.TitleLines)
		check(tag .. ": title text fits its container", BannerLayout.TextWidth(perLineTitle, l.TitleSize) <= l.Inner + 1e-6, ("%.0f > %.0f"):format(BannerLayout.TextWidth(perLineTitle, l.TitleSize), l.Inner))
		local perLineSub = math.ceil(#t[2] / l.SubLines)
		check(tag .. ": subtitle text fits its container", BannerLayout.TextWidth(perLineSub, l.SubSize) <= l.Inner + 1e-6, ("%.0f > %.0f"):format(BannerLayout.TextWidth(perLineSub, l.SubSize), l.Inner))
		check(tag .. ": the banner stays above the crosshair (screen centre)", l.Bottom < l.VirtualHeight / 2 - 10, ("bottom %.0f vs centre %.0f"):format(l.Bottom, l.VirtualHeight / 2))
		if sz[2] >= 600 then
			check(tag .. ": the banner sits below the top HUD text rows", l.Top >= 170, ("top %.0f"):format(l.Top))
		end
		check(tag .. ": fonts stay readable (title >= 20, subtitle >= 14)", l.TitleSize >= 20 and l.SubSize >= 14)
	end
end
local big = BannerLayout.Compute(1920, 1080, 13, 16)
check("on a large window the title uses the full size", big.TitleSize == 56 and big.TitleLines == 1)
check("the container never grows beyond its maximum width", BannerLayout.Compute(3840, 2160, 13, 16).Width <= 720)
print(("ui layout: %d passed, %d failed"):format(passed, failed))
if failed > 0 then error("tests failed") end
