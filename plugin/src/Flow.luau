--!strict
-- Funnel step editing and the data behind the flow diagram. Pure.
local Registry = require(script.Parent.Registry)

local Flow = {}

export type Edge = {
	from: number,
	to: number,
	fromName: string,
	toName: string,
	events: { string }, -- events that lead from `from` to `to`
}

-- Moves the item at `from` to position `to` (1-based, clamped). Returns a new list.
function Flow.move<T>(list: { T }, from: number, to: number): { T }
	local out = table.clone(list)
	if from < 1 or from > #out then
		return out
	end
	to = math.clamp(to, 1, #out)
	if from == to then
		return out
	end
	local item = table.remove(out, from) :: T
	table.insert(out, to, item)
	return out
end

-- Drop index for a drag over a vertical list of equal rows (`y` relative to the list top).
function Flow.dropIndex(y: number, rowHeight: number, count: number): number
	if count <= 0 or rowHeight <= 0 then
		return 1
	end
	return math.clamp(math.floor(y / rowHeight) + 1, 1, count)
end

-- Edges between consecutive steps. The step's `event` is what leads into it; custom events with the
-- same name as a step are linked too, so a tag-driven event named like the step shows up.
function Flow.edges(registry: Registry.Registry, funnel: Registry.EventDef): { Edge }
	local edges: { Edge } = {}
	for index = 1, #funnel.steps - 1 do
		local fromStep = funnel.steps[index]
		local toStep = funnel.steps[index + 1]
		local events: { string } = {}
		if toStep.event then
			table.insert(events, toStep.event)
		end
		local sameName = Registry.find(registry, toStep.name)
		if sameName and sameName.kind == "custom" and not table.find(events, sameName.name) then
			table.insert(events, sameName.name)
		end
		table.insert(edges, {
			from = index,
			to = index + 1,
			fromName = fromStep.name,
			toName = toStep.name,
			events = events,
		})
	end
	return edges
end

-- Funnels where a given event leads into a step: { funnel name, step index }.
function Flow.usagesOf(registry: Registry.Registry, eventName: string): { { funnel: string, step: number } }
	local out = {}
	local lower = string.lower(eventName)
	for _, event in registry.events do
		for index, step in event.steps do
			if step.event and string.lower(step.event) == lower then
				table.insert(out, { funnel = event.name, step = index })
			end
		end
	end
	return out
end

return Flow
