-- Minimal Vector3 / CFrame / Color3 / Enum stand-ins so the pure modelling and viewmodel maths can run outside Roblox.
-- Only the API subset used by ModelKit, ToolModels, ViewmodelMath and the tests is implemented.
local M = {}

local V3 = {}
V3.__index = V3
local function v3(x, y, z) return setmetatable({ X = x, Y = y, Z = z }, V3) end
V3.__add = function(a, b) return v3(a.X + b.X, a.Y + b.Y, a.Z + b.Z) end
V3.__sub = function(a, b) return v3(a.X - b.X, a.Y - b.Y, a.Z - b.Z) end
V3.__unm = function(a) return v3(-a.X, -a.Y, -a.Z) end
V3.__mul = function(a, b)
	if type(a) == "number" then return v3(a * b.X, a * b.Y, a * b.Z) end
	if type(b) == "number" then return v3(a.X * b, a.Y * b, a.Z * b) end
	return v3(a.X * b.X, a.Y * b.Y, a.Z * b.Z)
end
V3.__div = function(a, b) return v3(a.X / b, a.Y / b, a.Z / b) end
function V3:Dot(o) return self.X * o.X + self.Y * o.Y + self.Z * o.Z end
function V3:Cross(o) return v3(self.Y * o.Z - self.Z * o.Y, self.Z * o.X - self.X * o.Z, self.X * o.Y - self.Y * o.X) end
V3.__index = function(t, k)
	if k == "Magnitude" then return math.sqrt(t.X * t.X + t.Y * t.Y + t.Z * t.Z) end
	if k == "Unit" then local m = math.sqrt(t.X * t.X + t.Y * t.Y + t.Z * t.Z); return v3(t.X / m, t.Y / m, t.Z / m) end
	return V3[k]
end
M.Vector3 = { new = function(x, y, z) return v3(x or 0, y or 0, z or 0) end, zero = v3(0, 0, 0), one = v3(1, 1, 1),
	xAxis = v3(1, 0, 0), yAxis = v3(0, 1, 0), zAxis = v3(0, 0, 1) }

-- CFrame: position p (V3) + rotation matrix r (row-major 3x3, columns are the local axes in world space)
local CF = {}
local function cf(p, r) return setmetatable({ p = p, r = r }, CF) end
local I = { 1, 0, 0, 0, 1, 0, 0, 0, 1 }
local function matmul(a, b)
	local o = {}
	for i = 0, 2 do
		for j = 0, 2 do
			o[i * 3 + j + 1] = a[i * 3 + 1] * b[j + 1] + a[i * 3 + 2] * b[3 + j + 1] + a[i * 3 + 3] * b[6 + j + 1]
		end
	end
	return o
end
local function rot(r, v) return v3(r[1] * v.X + r[2] * v.Y + r[3] * v.Z, r[4] * v.X + r[5] * v.Y + r[6] * v.Z, r[7] * v.X + r[8] * v.Y + r[9] * v.Z) end
CF.__mul = function(a, b)
	if getmetatable(b) == V3 then return a.p + rot(a.r, b) end
	return cf(a.p + rot(a.r, b.p), matmul(a.r, b.r))
end
CF.__sub = function(a, b) return cf(a.p - b.p, a.r) end -- only used as (cframe - cframe.Position)
CF.__index = function(t, k)
	if k == "Position" then return t.p end
	if k == "LookVector" then return rot(t.r, v3(0, 0, -1)) end
	return CF[k]
end
local function Rx(a) local c, s = math.cos(a), math.sin(a); return { 1, 0, 0, 0, c, -s, 0, s, c } end
local function Ry(a) local c, s = math.cos(a), math.sin(a); return { c, 0, s, 0, 1, 0, -s, 0, c } end
local function Rz(a) local c, s = math.cos(a), math.sin(a); return { c, -s, 0, s, c, 0, 0, 0, 1 } end
M.CFrame = {
	new = function(x, y, z)
		if getmetatable(x) == V3 then return cf(x, I) end
		return cf(v3(x or 0, y or 0, z or 0), I)
	end,
	Angles = function(rx, ry, rz) return cf(v3(0, 0, 0), matmul(matmul(Rx(rx), Ry(ry)), Rz(rz))) end,
	lookAt = function(from, to)
		local look = (to - from).Unit
		local back = -look
		local right = v3(0, 1, 0):Cross(back)
		if right.Magnitude < 1e-6 then right = v3(1, 0, 0) end
		right = right.Unit
		local up = back:Cross(right)
		return cf(from, { right.X, up.X, back.X, right.Y, up.Y, back.Y, right.Z, up.Z, back.Z })
	end,
	identity = cf(v3(0, 0, 0), I),
}

local Color = { fromHex = function(h) return { Hex = h } end, new = function(r, g, b) return { r, g, b } end }
M.Color3 = Color
-- Enum.X.Y just returns a descriptive string
M.Enum = setmetatable({}, { __index = function(_, a) return setmetatable({}, { __index = function(_, b) return a .. "." .. b end }) end })
return M
