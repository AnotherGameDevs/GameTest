local Util = {}

function Util.FormatCash(n: number): string
	n = math.floor(n + 0.5)
	local s = tostring(n)
	local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	if out:sub(1, 1) == "," then
		out = out:sub(2)
	end
	return "$" .. out
end

function Util.FormatCashShort(n: number): string
	if n >= 1e6 then
		return string.format("$%.1fM", n / 1e6)
	elseif n >= 1e4 then
		return string.format("$%.0fK", n / 1e3)
	end
	return Util.FormatCash(n)
end

function Util.DeepCopy(t)
	if type(t) ~= "table" then
		return t
	end
	local c = {}
	for k, v in pairs(t) do
		c[k] = Util.DeepCopy(v)
	end
	return c
end

-- Adds any keys missing from `data` using `template`, recursively. Never overwrites existing values.
function Util.Reconcile(data, template)
	for k, v in pairs(template) do
		if data[k] == nil then
			data[k] = Util.DeepCopy(v)
		elseif type(data[k]) == "table" and type(v) == "table" then
			Util.Reconcile(data[k], v)
		end
	end
end

return Util
