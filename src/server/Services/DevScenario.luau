-- Remembers which shared-world artifacts / relic events were created by the developer panel, so that a reward for one can never be paid
-- into a profile that is NOT in test mode. A leaf module (no requires): RelicService / ArtifactService ask it at deposit time.
local DevScenario = {}

local marked: { [string]: boolean } = {}

function DevScenario.Mark(id: string?)
	if id then
		marked[id] = true
	end
end

function DevScenario.IsTest(id: string?): boolean
	return id ~= nil and marked[id] == true
end

function DevScenario.Clear(id: string?)
	if id then
		marked[id] = nil
	end
end

function DevScenario.Reset()
	table.clear(marked)
end

return DevScenario
