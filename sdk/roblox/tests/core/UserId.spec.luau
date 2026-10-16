--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserId = require(ReplicatedStorage.RoMetrics.Util.UserId)

return function()
	describe("normalize", function()
		it("keeps real ids", function()
			expect(UserId.normalize(1)).to.equal(1)
			expect(UserId.normalize(123456789)).to.equal(123456789)
		end)

		it("maps Studio test players (<= 0) into the reserved range", function()
			expect(UserId.normalize(-1)).to.equal(UserId.STUDIO_TEST_BASE + 1)
			expect(UserId.normalize(-2)).to.equal(UserId.STUDIO_TEST_BASE + 2)
			expect(UserId.normalize(0)).to.equal(UserId.STUDIO_TEST_BASE)
			expect(UserId.isStudioTest(UserId.normalize(-1) :: number)).to.equal(true)
			expect(UserId.isStudioTest(42)).to.equal(false)
		end)

		it("rejects non-numbers", function()
			expect(UserId.normalize(nil)).to.equal(nil)
			expect(UserId.normalize("1")).to.equal(nil)
			expect(UserId.normalize(0 / 0)).to.equal(nil)
		end)
	end)
end
