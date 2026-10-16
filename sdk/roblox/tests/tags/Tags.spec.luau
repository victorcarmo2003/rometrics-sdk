--!strict
-- TestEZ-style spec for Tags (tag/attribute-driven auto events).

local RoMetrics = script.Parent.Parent.Parent.RoMetrics
local Tags = require(RoMetrics.Tags) :: any
local Fakes = require(script.Parent.Fakes) :: any

return function()
	local function setup(registry: { [string]: boolean }?)
		local collection = Fakes.collection()
		local alice, aliceLimb = Fakes.player(1)
		local bob, bobLimb = Fakes.player(2)
		local players = Fakes.players({ alice, bob })
		local sessions = Fakes.sessions()
		sessions:set(alice, "s-alice-1")
		sessions:set(bob, "s-bob-1")
		local clock = Fakes.clock()
		local recorder = Fakes.recorder()
		local env = {
			collection = collection,
			players = players,
			sessions = sessions,
			clock = clock,
			recorder = recorder,
			alice = alice,
			aliceLimb = aliceLimb,
			bob = bob,
			bobLimb = bobLimb,
			controller = nil :: any,
		}
		env.controller = Tags.new(sessions, recorder.log, {
			collection = collection,
			players = players,
			now = clock.now,
			registry = registry,
		})
		return env
	end

	local function tagged(env: any, className: string, attributes: { [string]: any }, parent: any?): any
		local inst = Fakes.instance(className, "Thing", parent)
		for key, value in attributes do
			inst.attributes[key] = value
		end
		env.collection:AddTag(inst)
		return inst
	end

	describe("isValidName", function()
		it("accepts the ingest charset and rejects the rest", function()
			expect(Tags.isValidName("Boss.Killed:v2-x_1")).to.equal(true)
			expect(Tags.isValidName("")).to.equal(false)
			expect(Tags.isValidName("has space")).to.equal(false)
			expect(Tags.isValidName(string.rep("a", 65))).to.equal(false)
			expect(Tags.isValidName(42)).to.equal(false)
		end)
	end)

	describe("readSpec", function()
		it("infers the trigger from the class", function()
			local prompt = Fakes.instance("ProximityPrompt")
			prompt.attributes.RM_Event = "Opened"
			expect(Tags.readSpec(prompt).trigger).to.equal("ProximityPrompt")
			local tool = Fakes.instance("Tool")
			tool.attributes.RM_Event = "Swing"
			expect(Tags.readSpec(tool).trigger).to.equal("Activated")
			local part = Fakes.instance("Part")
			part.attributes.RM_Event = "Step"
			expect(Tags.readSpec(part).trigger).to.equal("Touched")
		end)

		it("collects RM_Prop_* and coerces non-primitive values", function()
			local part = Fakes.instance("Part")
			part.attributes = {
				RM_Event = "Zone",
				RM_Value = 3,
				RM_Cooldown = 5,
				RM_Once = true,
				RM_Prop_zone = "Lobby",
				RM_Prop_tier = 2,
				RM_Prop_pos = { x = 1 },
			}
			local spec = Tags.readSpec(part)
			expect(spec.value).to.equal(3)
			expect(spec.cooldown).to.equal(5)
			expect(spec.once).to.equal(true)
			expect(spec.props.zone).to.equal("Lobby")
			expect(spec.props.tier).to.equal(2)
			expect(type(spec.props.pos)).to.equal("string")
		end)

		it("rejects invalid names and unknown triggers", function()
			local part = Fakes.instance("Part")
			part.attributes.RM_Event = "bad name"
			local spec, reason = Tags.readSpec(part)
			expect(spec).to.equal(nil)
			expect(type(reason)).to.equal("string")
			part.attributes.RM_Event = "Ok"
			part.attributes.RM_Trigger = "GuiButton"
			expect(Tags.readSpec(part)).to.equal(nil)
		end)
	end)

	describe("Touched", function()
		it("fires for the player whose character touches the part", function()
			local env = setup()
			local part = tagged(env, "Part", { RM_Event = "Checkpoint", RM_Value = 2, RM_Prop_stage = 4 })
			part.Touched:Fire(env.aliceLimb)
			expect(#env.recorder.calls).to.equal(1)
			local call = env.recorder.calls[1]
			expect(call.player).to.equal(env.alice)
			expect(call.name).to.equal("Checkpoint")
			expect(call.value).to.equal(2)
			expect(call.props.stage).to.equal(4)
			expect(call.props.trigger).to.equal("Touched")
			expect(call.props.instance).to.equal("Thing")
		end)

		it("ignores parts that are not part of a character", function()
			local env = setup()
			local part = tagged(env, "Part", { RM_Event = "Checkpoint" })
			part.Touched:Fire(Fakes.instance("Part", "Debris"))
			expect(#env.recorder.calls).to.equal(0)
		end)

		it("applies the 1 s minimum cooldown per player", function()
			local env = setup()
			local part = tagged(env, "Part", { RM_Event = "Checkpoint" })
			part.Touched:Fire(env.aliceLimb)
			part.Touched:Fire(env.aliceLimb)
			part.Touched:Fire(env.bobLimb)
			expect(#env.recorder.calls).to.equal(2)
			env.clock.t += 1.5
			part.Touched:Fire(env.aliceLimb)
			expect(#env.recorder.calls).to.equal(3)
		end)

		it("binds every BasePart under a Model, including parts added later", function()
			local env = setup()
			local model = tagged(env, "Model", { RM_Event = "Door" })
			local early = Fakes.instance("Part", "A", model)
			-- `early` was added after tagging too; both paths must work.
			local late = Fakes.instance("Part", "B", model)
			early.Touched:Fire(env.aliceLimb)
			late.Touched:Fire(env.bobLimb)
			expect(#env.recorder.calls).to.equal(2)
		end)
	end)

	describe("cooldown and once", function()
		it("respects RM_Cooldown per player", function()
			local env = setup()
			local prompt = tagged(env, "ProximityPrompt", { RM_Event = "Shop", RM_Cooldown = 10 })
			prompt.Triggered:Fire(env.alice)
			env.clock.t += 5
			prompt.Triggered:Fire(env.alice)
			prompt.Triggered:Fire(env.bob)
			expect(#env.recorder.calls).to.equal(2)
			env.clock.t += 6
			prompt.Triggered:Fire(env.alice)
			expect(#env.recorder.calls).to.equal(3)
		end)

		it("RM_Once fires once per session and again after a new session", function()
			local env = setup()
			local detector = tagged(env, "ClickDetector", { RM_Event = "Secret", RM_Once = true })
			detector.MouseClick:Fire(env.alice)
			env.clock.t += 100
			detector.MouseClick:Fire(env.alice)
			expect(#env.recorder.calls).to.equal(1)
			env.sessions:set(env.alice, "s-alice-2")
			detector.MouseClick:Fire(env.alice)
			expect(#env.recorder.calls).to.equal(2)
		end)

		it("clears per-player state on PlayerRemoving", function()
			local env = setup()
			local detector = tagged(env, "ClickDetector", { RM_Event = "Secret", RM_Once = true })
			detector.MouseClick:Fire(env.alice)
			env.players.PlayerRemoving:Fire(env.alice)
			detector.MouseClick:Fire(env.alice)
			expect(#env.recorder.calls).to.equal(2)
		end)
	end)

	describe("other triggers", function()
		it("finds a ProximityPrompt under a tagged part, waiting for it if needed", function()
			local env = setup()
			local part = tagged(env, "Part", { RM_Event = "Talk", RM_Trigger = "ProximityPrompt" })
			expect(#env.recorder.calls).to.equal(0)
			local prompt = Fakes.instance("ProximityPrompt", "Prompt", part)
			prompt.Triggered:Fire(env.bob)
			expect(#env.recorder.calls).to.equal(1)
			expect(env.recorder.calls[1].player).to.equal(env.bob)
		end)

		it("Tool Activated resolves the holder from the character", function()
			local env = setup()
			local tool = tagged(env, "Tool", { RM_Event = "Swing" })
			tool.Parent = env.alice.Character
			tool.Activated:Fire()
			expect(#env.recorder.calls).to.equal(1)
			expect(env.recorder.calls[1].player).to.equal(env.alice)
			-- In the backpack: no character, no event.
			tool.Parent = Fakes.instance("Backpack")
			tool.Activated:Fire()
			expect(#env.recorder.calls).to.equal(1)
		end)

		it("ignores Activated on non-Tools without throwing", function()
			local env = setup()
			tagged(env, "Part", { RM_Event = "X", RM_Trigger = "Activated" })
			expect(env.controller:count()).to.equal(1)
		end)
	end)

	describe("runtime changes", function()
		it("binds instances already tagged at start", function()
			local collection = Fakes.collection()
			local part = Fakes.instance("Part")
			part.attributes.RM_Event = "Pre"
			table.insert(collection.tagged, part)
			local recorder = Fakes.recorder()
			local alice, limb = Fakes.player(1)
			local controller = Tags.new(Fakes.sessions(), recorder.log, {
				collection = collection,
				players = Fakes.players({ alice }),
				now = Fakes.clock().now,
			})
			expect(controller:isBound(part)).to.equal(true)
			part.Touched:Fire(limb)
			expect(#recorder.calls).to.equal(1)
		end)

		it("unbinds when the tag is removed", function()
			local env = setup()
			local part = tagged(env, "Part", { RM_Event = "Gone" })
			env.collection:RemoveTag(part)
			part.Touched:Fire(env.aliceLimb)
			expect(#env.recorder.calls).to.equal(0)
			expect(part.Touched:count()).to.equal(0)
			expect(part.AttributeChanged:count()).to.equal(0)
		end)

		it("rebinds when an RM_* attribute changes", function()
			local env = setup()
			local part = tagged(env, "Part", { RM_Event = "Old" })
			part:SetAttribute("RM_Event", "New")
			part.Touched:Fire(env.aliceLimb)
			expect(#env.recorder.calls).to.equal(1)
			expect(env.recorder.calls[1].name).to.equal("New")
			-- One Touched + one AttributeChanged connection after the rebind, no leaks.
			expect(part.Touched:count()).to.equal(1)
			expect(part.AttributeChanged:count()).to.equal(1)
		end)

		it("an invalid instance becomes valid after fixing its attributes", function()
			local env = setup()
			local part = tagged(env, "Part", { RM_Event = "bad name" })
			expect(env.controller:isBound(part)).to.equal(false)
			part:SetAttribute("RM_Event", "Fixed")
			expect(env.controller:isBound(part)).to.equal(true)
		end)

		it("a throwing log function never escapes", function()
			local env = setup()
			local part = Fakes.instance("Part")
			part.attributes.RM_Event = "Boom"
			local controller = Tags.new(env.sessions, function()
				error("game code exploded")
			end, { collection = env.collection, players = env.players, now = env.clock.now })
			env.collection:AddTag(part)
			expect(function()
				part.Touched:Fire(env.aliceLimb)
			end).never.to.throw()
			controller:destroy()
		end)

		it("destroy disconnects everything", function()
			local env = setup()
			local part = tagged(env, "Part", { RM_Event = "Bye" })
			env.controller:destroy()
			expect(env.controller:count()).to.equal(0)
			expect(part.Touched:count()).to.equal(0)
			expect(env.collection.added:count()).to.equal(0)
		end)
	end)

	describe("registryNames", function()
		it("lower-cases names and tolerates junk", function()
			local names = Tags.registryNames({ events = { { name = "BossKilled" }, "junk", { name = 3 } } :: { any } })
			expect(names.bosskilled).to.equal(true)
			expect(Tags.registryNames(nil)).to.equal(nil)
			expect(Tags.registryNames({ events = 1 })).to.equal(nil)
		end)
	end)
end
