--!strict
-- ScriptScan, Snippets, Flow and Lint (pure modules).
local src = script.Parent.Parent.src
local Registry = require(src.Registry) :: any
local ScriptScan = require(src.ScriptScan) :: any
local Snippets = require(src.Snippets) :: any
local Flow = require(src.Flow) :: any
local Lint = require(src.Lint) :: any
local Installer = require(src.Installer) :: any

return function()
	local function sampleRegistry()
		local registry = Registry.empty()
		local boss = Registry.newEvent("BossKilled")
		boss.props = { { key = "boss", type = "string" }, { key = "hits", type = "number" } }
		Registry.upsert(registry, boss)
		local shop = Registry.newEvent("ShopOpened")
		shop.trigger = "tag"
		Registry.upsert(registry, shop)
		local funnel = Registry.newEvent("Tutorial", "funnel")
		funnel.steps = { { name = "Spawn" }, { name = "OpenShop", event = "ShopOpened" }, { name = "Buy" } }
		Registry.upsert(registry, funnel)
		Registry.upsert(registry, Registry.newEvent("Level", "progression"))
		Registry.upsert(registry, Registry.newEvent("Coins", "economy"))
		return registry
	end

	describe("ScriptScan", function()
		it("finds every call kind with line numbers", function()
			local source = table.concat({
				"local RoMetrics = require(path)",
				'RoMetrics:LogCustomEvent(player, "BossKilled", 1, { boss = "Dragon" })',
				"RoMetrics:track('ServerStarted')",
				'RoMetrics:LogFunnelStepEvent(plr, "Tutorial", nil, 2, "OpenShop")',
				'RoMetrics:LogProgressionEvent(player, "Level", Enum.AnalyticsProgressionType.Start, 1)',
				'RoMetrics:LogEconomyEvent(player, Enum.AnalyticsEconomyFlowType.Sink, "Coins", 10, 90, "Shop")',
				"backtrack('NotAnEvent')",
				"RoMetrics:LogCustomEvent(player, eventNameVariable)",
			}, "\n")
			local usages = ScriptScan.scan(source)
			expect(#usages).to.equal(5)
			expect(usages[1].name).to.equal("BossKilled")
			expect(usages[1].kind).to.equal("custom")
			expect(usages[1].line).to.equal(2)
			expect(usages[2].name).to.equal("ServerStarted")
			expect(usages[3].kind).to.equal("funnel")
			expect(usages[4].name).to.equal("Level")
			expect(usages[5].name).to.equal("Coins")
			expect(usages[5].line).to.equal(6)
		end)

		it("does not pair a call with a string on a later line", function()
			local usages = ScriptScan.scan('RoMetrics:LogCustomEvent(player)\nfoo(a, "Nope")')
			expect(#usages).to.equal(0)
		end)
	end)

	describe("Snippets", function()
		local ctx = {
			sdkPath = "ReplicatedStorage.Packages.RoMetrics",
			secretName = "rometrics_key",
			endpoint = "https://ingest.rometrics.app",
			event = nil :: any,
		}

		it("every snippet compiles for every matching event", function()
			local registry = sampleRegistry()
			for _, snippet in Snippets.list do
				local events = { false }
				if snippet.kind then
					for _, event in Registry.byKind(registry, snippet.kind) do
						table.insert(events, event)
					end
				end
				for _, event in events do
					ctx.event = if event then event else nil
					local code = Snippets.render(snippet.build(ctx))
					local ok, err = pcall(luauCompile, code)
					if not ok then
						error(`{snippet.id} does not compile: {err}\n{code}`)
					end
				end
			end
		end)

		it("uses registry names and prop schema", function()
			ctx.event = Registry.find(sampleRegistry(), "BossKilled")
			local out = Snippets.get("custom").build(ctx)
			expect(string.find(out.body, 'LogCustomEvent(player, "BossKilled", 1, { boss = "", hits = 0 })', 1, true)).to.be.ok()
			ctx.event = Registry.find(sampleRegistry(), "Tutorial")
			local funnel = Snippets.get("funnel").build(ctx).body
			expect(string.find(funnel, "openShop = 2", 1, true)).to.be.ok()
			expect(string.find(funnel, "reached via ShopOpened", 1, true)).to.be.ok()
		end)

		it("builds require expressions from the SDK path", function()
			local service, expr = Snippets.requireParts("ServerScriptService.Libs.Ro Metrics")
			expect(service).to.equal("ServerScriptService")
			expect(expr).to.equal('ServerScriptService.Libs["Ro Metrics"]')
			service, expr = Snippets.requireParts("")
			expect(expr).to.equal("ReplicatedStorage.Packages.RoMetrics")
		end)

		it("merge adds only missing header lines and appends the body", function()
			ctx.event = nil
			local out = Snippets.get("custom").build(ctx)
			local existing = table.concat({
				"--!strict",
				'local ReplicatedStorage = game:GetService("ReplicatedStorage")',
				"local x = 1",
			}, "\n")
			local merged = Snippets.merge(existing, out)
			local _, count = string.gsub(merged, 'local ReplicatedStorage = game:GetService%("ReplicatedStorage"%)', "")
			expect(count).to.equal(1)
			local requireAt = string.find(merged, "local RoMetrics = require", 1, true)
			local xAt = string.find(merged, "local x = 1", 1, true)
			expect(requireAt < xAt).to.equal(true)
			expect(string.find(merged, "LogCustomEvent", 1, true) > xAt).to.equal(true)
			luauCompile(merged)
			-- Merging twice keeps a single header.
			local twice = Snippets.merge(merged, out)
			_, count = string.gsub(twice, "local RoMetrics = require", "")
			expect(count).to.equal(1)
			expect(Snippets.merge("", out)).to.equal(Snippets.render(out))
		end)
	end)

	describe("Flow", function()
		it("move reorders and clamps", function()
			local list = { "a", "b", "c", "d" }
			expect(table.concat(Flow.move(list, 1, 3))).to.equal("bcad")
			expect(table.concat(Flow.move(list, 4, 1))).to.equal("dabc")
			expect(table.concat(Flow.move(list, 2, 99))).to.equal("acdb")
			expect(table.concat(Flow.move(list, 9, 1))).to.equal("abcd")
			expect(table.concat(list)).to.equal("abcd")
		end)

		it("dropIndex maps y to a row", function()
			expect(Flow.dropIndex(-5, 30, 4)).to.equal(1)
			expect(Flow.dropIndex(31, 30, 4)).to.equal(2)
			expect(Flow.dropIndex(500, 30, 4)).to.equal(4)
		end)

		it("edges list the events leading into each step", function()
			local registry = sampleRegistry()
			Registry.upsert(registry, Registry.newEvent("Buy"))
			local edges = Flow.edges(registry, Registry.find(registry, "Tutorial"))
			expect(#edges).to.equal(2)
			expect(edges[1].events[1]).to.equal("ShopOpened")
			expect(edges[2].events[1]).to.equal("Buy")
			expect(#Flow.usagesOf(registry, "shopopened")).to.equal(1)
		end)
	end)

	describe("Lint", function()
		local function tagged(attributes: { [string]: any }, overrides: { [string]: any }?)
			local info = {
				ref = {},
				path = "Workspace.Thing",
				className = "Part",
				attributes = attributes,
				isPart = true,
				isContainer = false,
				hasParts = false,
				hasPrompt = false,
				hasDetector = false,
				isTool = false,
			}
			for key, value in overrides or {} do
				(info :: any)[key] = value
			end
			return info
		end

		local function codes(issues: { any }): { [string]: number }
			local out = {}
			for _, issue in issues do
				out[issue.code] = (out[issue.code] or 0) + 1
			end
			return out
		end

		it("a clean registry with matching usages has no errors or warnings", function()
			local registry = sampleRegistry()
			local usages = {
				{ ref = {}, path = "S", method = "LogCustomEvent", kind = "custom", name = "BossKilled", line = 1 },
				{ ref = {}, path = "S", method = "LogFunnelStepEvent", kind = "funnel", name = "Tutorial", line = 2 },
				{
					ref = {},
					path = "S",
					method = "LogProgressionEvent",
					kind = "progression",
					name = "Level",
					line = 3,
				},
				{ ref = {}, path = "S", method = "LogEconomyEvent", kind = "economy", name = "Coins", line = 4 },
			}
			local issues = Lint.run(registry, { tagged({ RM_Event = "ShopOpened" }) }, usages)
			local counts = Lint.counts(issues)
			expect(counts.error).to.equal(0)
			expect(counts.warning).to.equal(0)
		end)

		it("flags registry problems", function()
			local registry = sampleRegistry()
			table.insert(registry.events, Registry.newEvent("bad name"))
			table.insert(registry.events, Registry.newEvent("bosskilled"))
			local empty = Registry.newEvent("Empty", "funnel")
			table.insert(registry.events, empty)
			local f = Registry.find(registry, "Tutorial")
			table.insert(f.steps, { name = "Spawn" })
			table.insert(f.steps, { name = "X", event = "Ghost" })
			Registry.find(registry, "BossKilled").props[2].key = "1bad"
			local result = codes(Lint.run(registry, {}, {}))
			expect(result.invalid_name).to.equal(1)
			expect(result.duplicate_name).to.equal(1)
			expect(result.funnel_no_steps).to.equal(1)
			expect(result.duplicate_step).to.equal(1)
			expect(result.step_event_unregistered).to.equal(1)
			expect(result.invalid_prop_key).to.equal(1)
		end)

		it("flags orphan and broken tags", function()
			local registry = sampleRegistry()
			local result = codes(Lint.run(registry, {
				tagged({}),
				tagged({ RM_Event = "bad name" }),
				tagged({ RM_Event = "Ghost" }),
				tagged({ RM_Event = "Tutorial" }),
				tagged({ RM_Event = "BossKilled" }),
				tagged({ RM_Event = "ShopOpened", RM_Trigger = "GuiButton" }),
				tagged({ RM_Event = "ShopOpened", RM_Trigger = "Activated" }),
				tagged({ RM_Event = "ShopOpened", RM_Trigger = "ProximityPrompt" }),
				tagged({ RM_Event = "ShopOpened" }, { className = "Configuration", isPart = false }),
				tagged({ RM_Event = "ShopOpened", ["RM_Prop_bad-key"] = 1 }),
			}, {}))
			expect(result.tag_missing_event).to.equal(1)
			expect(result.tag_invalid_name).to.equal(1)
			expect(result.tag_unregistered).to.equal(1)
			expect(result.tag_kind_mismatch).to.equal(1)
			expect(result.tag_trigger_code).to.equal(1)
			expect(result.tag_bad_trigger).to.equal(1)
			expect(result.tag_no_target).to.equal(2)
			expect(result.tag_no_trigger).to.equal(1)
			expect(result.tag_bad_prop).to.equal(1)
		end)

		it("flags unregistered usages, kind mismatches and unused events; sorts by severity", function()
			local registry = sampleRegistry()
			local issues = Lint.run(registry, {}, {
				{ ref = {}, path = "S", method = "LogCustomEvent", kind = "custom", name = "Ghost", line = 1 },
				{ ref = {}, path = "S", method = "LogCustomEvent", kind = "custom", name = "Level", line = 2 },
				{ ref = {}, path = "S", method = "track", kind = "custom", name = "bad name", line = 3 },
			})
			local result = codes(issues)
			expect(result.usage_unregistered).to.equal(1)
			expect(result.usage_kind_mismatch).to.equal(1)
			expect(result.usage_invalid_name).to.equal(1)
			expect(result.unused).to.equal(3) -- BossKilled, Tutorial, Coins (ShopOpened is linked by a step)
			expect(issues[1].severity).to.equal("error")
			expect(issues[#issues].severity).to.equal("info")
		end)
	end)

	describe("Installer.plan", function()
		it("builds the Rojo-style tree from repo paths", function()
			local plan = Installer.plan({
				"README.md",
				"sdk/roblox/src/init.luau",
				"sdk/roblox/src/Config.luau",
				"sdk/roblox/src/Util/Clock.luau",
				"sdk/roblox/src/Client/RoMetricsClient.client.luau",
				"sdk/roblox/src/Client/Bridge.luau",
				"sdk/roblox/tests/run.luau",
				"plugin/src/init.server.luau",
			})
			expect(plan).to.be.ok()
			expect(plan.name).to.equal("RoMetrics")
			expect(plan.className).to.equal("ModuleScript")
			expect(plan.file).to.equal("sdk/roblox/src/init.luau")
			local byName = {}
			for _, child in plan.children do
				byName[child.name] = child
			end
			expect(byName.Config.className).to.equal("ModuleScript")
			expect(byName.Util.className).to.equal("Folder")
			expect(byName.Util.children[1].name).to.equal("Clock")
			local client = {}
			for _, child in byName.Client.children do
				client[child.name] = child.className
			end
			expect(client.RoMetricsClient).to.equal("LocalScript")
			expect(client.Bridge).to.equal("ModuleScript")
			expect(#Installer.files(plan)).to.equal(5)
		end)

		it("turns a folder with init.luau into a ModuleScript", function()
			local plan = Installer.plan({ "s/init.luau", "s/Net/init.luau", "s/Net/Http.luau" }, "s")
			expect(plan.children[1].name).to.equal("Net")
			expect(plan.children[1].className).to.equal("ModuleScript")
			expect(plan.children[1].children[1].name).to.equal("Http")
		end)

		it("rejects trees without a root init.luau", function()
			expect(Installer.plan({ "sdk/roblox/src/Config.luau" })).never.to.be.ok()
		end)
	end)
end
