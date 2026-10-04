-- Run: luau tests/settings_test.luau
local S = require("../src/shared/SettingsSpec")
local passed, failed = 0, 0
local function check(name, cond) if cond then passed += 1 else failed += 1; print("FAIL: " .. name) end end

check("default sensitivity is 0.30", S.Defaults().MouseSensitivity == 0.30)
check("clamp below min", S.Clamp("MouseSensitivity", 0.001) == 0.05)
check("clamp above max", S.Clamp("MouseSensitivity", 50) == 2.00)
check("step snaps to 0.01", S.Clamp("MouseSensitivity", 0.337) == 0.34)
check("exact value kept", S.Clamp("MouseSensitivity", 1.23) == 1.23)
check("NaN -> default", S.Clamp("MouseSensitivity", 0 / 0) == 0.30)
check("inf -> default", S.Clamp("MouseSensitivity", math.huge) == 0.30)
check("string -> default", S.Clamp("MouseSensitivity", "fast") == 0.30)
check("nil -> default", S.Clamp("MouseSensitivity", nil) == 0.30)
check("volume clamps", S.Clamp("MasterVolume", 3) == 1 and S.Clamp("MasterVolume", -1) == 0)
check("volume steps", S.Clamp("MasterVolume", 0.52) == 0.5)
check("boolean kept", S.Clamp("CameraShake", false) == false and S.Clamp("InvertY", true) == true)
check("bad boolean -> default", S.Clamp("CameraShake", "no") == true and S.Clamp("InvertY", 1) == false)
check("unknown key -> nil", S.Clamp("Nope", 1) == nil)
local clean = S.Sanitize({ MouseSensitivity = 99, MasterVolume = "x", CameraShake = false, Extra = 5 })
check("sanitize clamps + defaults + drops unknown", clean.MouseSensitivity == 2 and clean.MasterVolume == 1 and clean.CameraShake == false and clean.InvertY == false and clean.Extra == nil)
check("sanitize non-table", S.Sanitize(nil).MouseSensitivity == 0.30 and S.Sanitize(12).CameraShake == true)
print(("settings tests: %d passed, %d failed"):format(passed, failed))
if failed > 0 then error("tests failed") end
