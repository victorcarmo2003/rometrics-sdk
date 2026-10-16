--!strict
-- Receipts (ProcessReceipt detection/wrap) and Codegen (assistant code + insertion).
local src = script.Parent.Parent.src
local Receipts = require(src.Receipts) :: any
local Codegen = require(src.Codegen) :: any

return function()
	describe("Receipts.find", function()
		it("finds a multi-line function assignment and its end", function()
			local source = table.concat({
				"local MarketplaceService = game:GetService(\"MarketplaceService\")",
				"-- MarketplaceService.ProcessReceipt = nope (comment)",
				"local s = \"MarketplaceService.ProcessReceipt = nope\"",
				"MarketplaceService.ProcessReceipt = function(receiptInfo)",
				"\tif receiptInfo.ProductId == 1 then",
				"\t\treturn Enum.ProductPurchaseDecision.PurchaseGranted",
				"\tend",
				"\treturn Enum.ProductPurchaseDecision.NotProcessedYet",
				"end",
				"print('after')",
			}, "\n")
			local found = Receipts.find(source)
			expect(#found).to.equal(1)
			local a = found[1]
			expect(a.form).to.equal("assign")
			expect(a.line).to.equal(4)
			expect(a.endLine).to.equal(9)
			expect(a.wrapped).to.equal(false)
			expect(string.sub(source, a.s, a.e)).to.equal(string.sub(source, string.find(source, "function(receiptInfo)", 1, true) :: number, (string.find(source, "\nprint", 1, true) :: number) - 1))
			local wrapped = Receipts.wrap(source, a, "RoMetrics")
			luauCompile(wrapped)
			expect(string.find(wrapped, "ProcessReceipt = RoMetrics.wrapProcessReceipt(function(receiptInfo)", 1, true)).to.be.ok()
			expect(string.find(wrapped, "\nend)\nprint('after')", 1, true)).to.be.ok()
			-- Wrapping is detected afterwards.
			expect(Receipts.find(wrapped)[1].wrapped).to.equal(true)
		end)

		it("handles a handler variable, aliases and GetService targets", function()
			local source = table.concat({
				"local MPS = game:GetService('MarketplaceService')",
				"local function handle(r) return Enum.ProductPurchaseDecision.PurchaseGranted end",
				"MPS.ProcessReceipt = handle",
				"game:GetService(\"MarketplaceService\").ProcessReceipt = handle;",
				"ShopService.ProcessReceipt = handle -- own table, not MarketplaceService",
			}, "\n")
			local found = Receipts.find(source)
			expect(#found).to.equal(2)
			expect(found[1].target).to.equal("MPS.ProcessReceipt")
			expect(string.sub(source, found[1].s, found[1].e)).to.equal("handle")
			expect(found[2].target).to.equal('game:GetService("MarketplaceService").ProcessReceipt')
			local wrapped = Receipts.wrap(source, found[2], "RM")
			expect(string.find(wrapped, '.ProcessReceipt = RM.wrapProcessReceipt(handle);', 1, true)).to.be.ok()
			luauCompile(wrapped)
		end)

		it("wraps the Modux-style call inside OnStart and keeps the rest", function()
			local source = table.concat({
				"local MarketplaceService = game:GetService(\"MarketplaceService\")",
				"ShopService:OnStart(function(self)",
				"\tMarketplaceService.ProcessReceipt = function(receipt: any): Enum.ProductPurchaseDecision",
				"\t\tlocal ok, decision = pcall(self.ProcessReceipt, self, receipt)",
				"\t\tif not ok then",
				"\t\t\treturn Enum.ProductPurchaseDecision.NotProcessedYet",
				"\t\tend",
				"\t\treturn decision",
				"\tend",
				"end)",
			}, "\n")
			local found = Receipts.find(source)
			expect(#found).to.equal(1)
			expect(found[1].endLine).to.equal(9)
			local wrapped = Receipts.wrap(source, found[1], "RoMetrics")
			expect(string.find(wrapped, "\tend)\nend)", 1, true)).to.be.ok()
			luauCompile(wrapped)
		end)

		it("rewrites a function declaration", function()
			local source = table.concat({
				"local MarketplaceService = game:GetService(\"MarketplaceService\")",
				"function MarketplaceService.ProcessReceipt(info)",
				"\tRoMetrics.trackReceipt(info)",
				"\treturn Enum.ProductPurchaseDecision.PurchaseGranted",
				"end",
			}, "\n")
			local found = Receipts.find(source)
			expect(#found).to.equal(1)
			expect(found[1].form).to.equal("function")
			expect(found[1].tracked).to.equal(true)
			local wrapped = Receipts.wrap(source, found[1], "RoMetrics")
			expect(string.find(wrapped, "MarketplaceService.ProcessReceipt = RoMetrics.wrapProcessReceipt(function(info)", 1, true)).to.be.ok()
			expect(string.sub(wrapped, -4)).to.equal("end)")
			luauCompile(wrapped)
		end)

		it("finds the SDK variable and diffs only the changed lines", function()
			expect(Receipts.sdkVariable("local RM = require(ReplicatedStorage.Packages.RoMetrics)")).to.equal("RM")
			expect(Receipts.sdkVariable("local X = require(script.Other)")).to.equal(nil)
			local diff = Receipts.diff("a\nb\nc\nd\ne\nf", "a\nb\nc\nD\ne\nf", 1)
			local kinds = {}
			for _, line in diff do
				table.insert(kinds, line.kind)
			end
			expect(table.concat(kinds, ",")).to.equal("gap,same,remove,add,same,gap")
			-- Two separate changes become two hunks with a gap between them.
			local before = "a\nb\nc\nd\ne\nf\ng\nh"
			local after = "a\nX\nb\nc\nd\ne\nf\ng\nH"
			kinds = {}
			for _, line in Receipts.diff(before, after, 1) do
				table.insert(kinds, line.kind)
			end
			expect(table.concat(kinds, ",")).to.equal("same,add,same,gap,same,remove,add")
		end)
	end)

	describe("Codegen", function()
		it("reads values like Luau", function()
			expect(Codegen.value("price", "0")).to.equal("price")
			expect(Codegen.value("coins - price", "0")).to.equal("coins - price")
			expect(Codegen.value("10", "0")).to.equal("10")
			expect(Codegen.value('"Lobby"', "nil")).to.equal('"Lobby"')
			expect(Codegen.value("Lobby principal", "nil")).to.equal('"Lobby principal"')
			expect(Codegen.value("", "0")).to.equal("0")
		end)

		it("builds every call so it compiles", function()
			local calls = {
				Codegen.custom({ sdk = "RoMetrics", name = "BossKilled", props = { { key = "boss", value = '"Dragon"' } } }),
				Codegen.custom({ sdk = "RoMetrics", name = "Jumped" }),
				Codegen.economy({ sdk = "RoMetrics", flow = "Sink", currency = "Coins", amount = "price", balance = "coins", reason = "Shop", item = '"Sword"' }),
				Codegen.funnel({ sdk = "RoMetrics", funnel = "Tutorial", step = 2, stepName = "OpenShop" }),
				Codegen.progression({ sdk = "RoMetrics", path = "World1", status = "Complete", level = "level" }),
				Codegen.trackReceipt("RoMetrics", "receipt"),
			}
			expect(calls[1]).to.equal('RoMetrics:LogCustomEvent(player, "BossKilled", nil, { boss = "Dragon" })')
			expect(calls[2]).to.equal('RoMetrics:LogCustomEvent(player, "Jumped")')
			expect(calls[3]).to.equal(
				'RoMetrics:LogEconomyEvent(player, Enum.AnalyticsEconomyFlowType.Sink, "Coins", price, coins, "Shop", "Sword")'
			)
			for _, call in calls do
				luauCompile("local RoMetrics, player, price, coins, level, receipt\n" .. call)
			end
		end)

		it("inserts after the cursor line with the right indentation and header", function()
			local source = table.concat({
				"--!strict",
				'local Players = game:GetService("Players")',
				"",
				"Players.PlayerAdded:Connect(function(player)",
				"\tprint(player)",
				"end)",
			}, "\n")
			local header = {
				'local ReplicatedStorage = game:GetService("ReplicatedStorage")',
				"local RoMetrics = require(ReplicatedStorage.RoMetrics)",
			}
			local out, at = Codegen.insert(source, header, 'RoMetrics:LogCustomEvent(player, "Joined")', 4)
			local lines = string.split(out, "\n")
			expect(at).to.equal(7)
			expect(lines[at]).to.equal('\tRoMetrics:LogCustomEvent(player, "Joined")')
			expect(lines[3]).to.equal(header[1])
			luauCompile(out)
			-- Same line again: header not repeated.
			local again = Codegen.insert(out, header, "x()", 8)
			local _, count = string.gsub(again, "local RoMetrics = require", "")
			expect(count).to.equal(1)
			-- No line: appended at the end.
			local tail, tailAt = Codegen.insert("print(1)\n\n", {}, "y()", nil)
			expect(tail).to.equal("print(1)\n\ny()\n")
			expect(tailAt).to.equal(3)
		end)

		it("detects block openers", function()
			expect(Codegen.opensBlock("if x then")).to.equal(true)
			expect(Codegen.opensBlock("\tfor i = 1, 3 do -- loop")).to.equal(true)
			expect(Codegen.opensBlock("Players.PlayerAdded:Connect(function(player)")).to.equal(true)
			expect(Codegen.opensBlock("local function buy(player: Player, id: number): boolean")).to.equal(true)
			expect(Codegen.opensBlock("print('then')")).to.equal(false)
			expect(Codegen.opensBlock("task.spawn(function() end)")).to.equal(false)
		end)
	end)
end
