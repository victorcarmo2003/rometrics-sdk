--!strict
-- Names + Registry: validation, normalization, editing and serialization round-trip.
local src = script.Parent.Parent.src
local Names = require(src.Names) :: any
local Registry = require(src.Registry) :: any

return function()
	describe("Names", function()
		it("validates event names like the ingest contract", function()
			expect(Names.isValidEventName("Boss.Killed:v2-x_1")).to.equal(true)
			expect(Names.isValidEventName(string.rep("a", 64))).to.equal(true)
			expect(Names.isValidEventName(string.rep("a", 65))).to.equal(false)
			expect(Names.isValidEventName("with space")).to.equal(false)
			expect(Names.isValidEventName("ção")).to.equal(false)
			expect(Names.eventNameError("a b")).to.be.ok()
			expect(Names.eventNameError("ok")).to.equal(nil)
		end)

		it("sanitizes and builds identifiers", function()
			expect(Names.sanitize("  Boss Killed! ")).to.equal("Boss_Killed_")
			expect(Names.identifier("boss.killed")).to.equal("bossKilled")
			expect(Names.identifier("Shop-Opened")).to.equal("shopOpened")
			expect(Names.identifier("1st")).to.equal("event1st")
		end)

		it("validates prop keys", function()
			expect(Names.isValidPropKey("boss_id")).to.equal(true)
			expect(Names.isValidPropKey("1x")).to.equal(false)
			expect(Names.isValidPropKey("a-b")).to.equal(false)
		end)
	end)

	describe("normalize", function()
		it("fills defaults and drops junk with notes", function()
			local registry, notes = Registry.normalize({
				events = {
					{ name = "A", kind = "weird", props = { "boss", { key = "n", type = "number" }, 3 } },
					{ kind = "custom" },
					"junk",
					{
						name = "F",
						kind = "funnel",
						steps = { "One", { name = "Two", event = "A" }, { name = "Three", event = "" } },
					},
				},
			})
			expect(#registry.events).to.equal(2)
			local a = registry.events[1]
			expect(a.kind).to.equal("custom")
			expect(a.trigger).to.equal("code")
			expect(a.description).to.equal("")
			expect(#a.props).to.equal(2)
			expect(a.props[1].type).to.equal("string")
			expect(a.props[2].type).to.equal("number")
			local f = registry.events[2]
			expect(#f.steps).to.equal(3)
			expect(f.steps[2].event).to.equal("A")
			expect(f.steps[3].event).to.equal(nil)
			expect(#notes).to.equal(2)
		end)

		it("survives non-table input", function()
			local registry, notes = Registry.normalize(nil)
			expect(#registry.events).to.equal(0)
			expect(#notes).to.equal(1)
		end)
	end)

	describe("editing", function()
		local function sample()
			local registry = Registry.empty()
			Registry.upsert(registry, Registry.newEvent("ShopOpened"))
			local funnel = Registry.newEvent("Tutorial", "funnel")
			funnel.steps = { { name = "Spawn" }, { name = "Shop", event = "ShopOpened" } }
			Registry.upsert(registry, funnel)
			return registry
		end

		it("add rejects invalid and duplicate names (case-insensitive)", function()
			local registry = sample()
			expect(Registry.add(registry, Registry.newEvent("bad name"))).to.be.ok()
			expect(Registry.add(registry, Registry.newEvent("shopopened"))).to.be.ok()
			expect(Registry.upsert(registry, Registry.newEvent("Tutorial"), "ShopOpened")).to.be.ok()
			expect(#registry.events).to.equal(2)
		end)

		it("upsert replaces the event named by previousName", function()
			local registry = sample()
			local edited = Registry.newEvent("ShopOpened")
			edited.description = "changed"
			expect(Registry.upsert(registry, edited, "ShopOpened")).to.equal(nil)
			expect(#registry.events).to.equal(2)
			expect(Registry.find(registry, "shopopened").description).to.equal("changed")
		end)

		it("rename updates funnel step references", function()
			local registry = sample()
			expect(Registry.rename(registry, "ShopOpened", "StoreOpened")).to.equal(nil)
			expect(Registry.find(registry, "ShopOpened")).to.equal(nil)
			expect(Registry.find(registry, "Tutorial").steps[2].event).to.equal("StoreOpened")
			expect(Registry.rename(registry, "StoreOpened", "Tutorial")).to.be.ok()
			expect(Registry.rename(registry, "Missing", "X")).to.be.ok()
		end)

		it("remove unlinks funnel steps", function()
			local registry = sample()
			expect(Registry.remove(registry, "shopOPENED")).to.equal(true)
			expect(Registry.find(registry, "Tutorial").steps[2].event).to.equal(nil)
			expect(Registry.remove(registry, "nope")).to.equal(false)
		end)

		it("clone is deep for props and steps", function()
			local registry = sample()
			local copy = Registry.clone(registry)
			copy.events[2].steps[1].name = "Changed"
			expect(registry.events[2].steps[1].name).to.equal("Spawn")
		end)
	end)

	describe("serialize", function()
		it("round-trips through Luau source, escaping strings", function()
			local registry = Registry.empty()
			local event = Registry.newEvent("Boss.Killed")
			event.description = 'Quote " backslash \\ newline\n tab\t and {braces}'
			event.trigger = "tag"
			event.props = { { key = "boss", type = "string" }, { key = "dmg", type = "number" } }
			Registry.upsert(registry, event)
			local funnel = Registry.newEvent("Tutorial", "funnel")
			funnel.steps = { { name = "Spawn" }, { name = "Shop", event = "Boss.Killed" } }
			Registry.upsert(registry, funnel)
			Registry.upsert(registry, Registry.newEvent("Coins", "economy"))

			local source = Registry.serialize(registry)
			expect(string.sub(source, 1, 9)).to.equal("--!strict")
			local parsed, notes = Registry.normalize(luauEval(source))
			expect(#notes).to.equal(0)
			expect(#parsed.events).to.equal(3)
			expect(parsed.events[1].description).to.equal(event.description)
			expect(parsed.events[1].trigger).to.equal("tag")
			expect(parsed.events[1].props[2].type).to.equal("number")
			expect(parsed.events[2].steps[2].event).to.equal("Boss.Killed")
			expect(parsed.events[3].kind).to.equal("economy")
			-- Deterministic output: serializing again gives the same text.
			expect(Registry.serialize(parsed)).to.equal(source)
		end)

		it("round-trips an empty registry", function()
			local parsed, notes = Registry.normalize(luauEval(Registry.serialize(Registry.empty())))
			expect(#notes).to.equal(0)
			expect(#parsed.events).to.equal(0)
		end)

		it("round-trips a large registry", function()
			local registry = Registry.empty()
			for i = 1, 2000 do
				local event = Registry.newEvent(`Event_{i}`, if i % 4 == 0 then "funnel" else "custom")
				event.props = { { key = "a", type = "string" }, { key = "b", type = "number" } }
				if event.kind == "funnel" then
					event.steps = { { name = "One" }, { name = "Two", event = `Event_{i - 1}` } }
				end
				table.insert(registry.events, event)
			end
			local parsed, notes = Registry.normalize(luauEval(Registry.serialize(registry)))
			expect(#notes).to.equal(0)
			expect(#parsed.events).to.equal(2000)
			expect(parsed.events[2000].steps[2].event).to.equal("Event_1999")
		end)
	end)
end
