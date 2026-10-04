-- First-person viewmodel placement, pure maths (testable). Everything is in CAMERA space (-Z forward, +X right,
-- +Y up). The viewmodel is the tool's own spec (Kit.BuildWelded) drawn at `Scale`, placed in the lower-right of the
-- view with the working end pointing forward/down-left, so the central aiming area is empty at rest.
local ViewmodelMath = {}

ViewmodelMath.Scale = 0.5 -- tools are drawn at half their world size in first person
ViewmodelMath.RestPosition = Vector3.new(1.05, -1.2, -2.0) -- where the tool's origin (mid-shaft) sits
ViewmodelMath.AxisDirection = Vector3.new(-0.14, -0.42, -1.0) -- where the tool's +Y (working end) points at rest
ViewmodelMath.Roll = math.rad(55) -- roll about the tool axis so the broad blade face is seen at an angle
ViewmodelMath.SwingPivot = Vector3.new(1.15, -1.1, -1.4) -- roughly where the hand is

-- Held artifact (carry): low and central so the view above and around it stays clear.
ViewmodelMath.ArtifactScale = 0.5
ViewmodelMath.ArtifactRest = CFrame.new(0, -1.05, -2.1)

-- Camera-space CFrame of the tool origin at rest.
function ViewmodelMath.Rest(): CFrame
	local u = ViewmodelMath.AxisDirection.Unit
	-- lookAt makes -Z point along u; the extra -90 degree pitch maps the tool's +Y onto that -Z.
	return CFrame.new(ViewmodelMath.RestPosition) * CFrame.lookAt(Vector3.zero, u)
		* CFrame.Angles(math.rad(-90), 0, 0) * CFrame.Angles(0, ViewmodelMath.Roll, 0)
end

local function ease(x: number): number
	return x * x * (3 - 2 * x)
end

local function lerp(a: number, b: number, t: number): number
	return a + (b - a) * t
end

-- Swing offset (camera space) for normalised time t in [0, 1]: a short pull-back, a forward thrust that tips the
-- blade slightly down, and a recovery. It is applied to the WHOLE assembly (one CFrame), never to single parts.
-- The thrust deliberately travels along the camera's forward axis and downward, NOT across the centre of the view,
-- so the blade never sweeps over the crosshair.
function ViewmodelMath.Swing(t: number): CFrame
	local angle, push
	if t <= 0 then
		return CFrame.identity
	elseif t < 0.3 then
		local a = ease(t / 0.3)
		angle, push = math.rad(14) * a, 0.25 * a
	elseif t < 0.5 then
		local a = ease((t - 0.3) / 0.2)
		angle, push = lerp(math.rad(14), -math.rad(9), a), lerp(0.25, -0.5, a)
	elseif t < 1 then
		local a = ease((t - 0.5) / 0.5)
		angle, push = lerp(-math.rad(9), 0, a), lerp(-0.5, 0, a)
	else
		return CFrame.identity
	end
	local pivot = ViewmodelMath.SwingPivot
	return CFrame.new(0, 0, push) * CFrame.new(pivot) * CFrame.Angles(angle, 0, 0) * CFrame.new(-pivot)
end

return ViewmodelMath
