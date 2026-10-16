--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Queue = require(ReplicatedStorage.RoMetrics.Queue)
local Fakes = require(script.Parent.Fakes)

return function()
	local function setup(overrides: { [string]: any }?, default: string?)
		local clock = Fakes.clock()
		local transport = Fakes.transport(default)
		local queue = Queue.new(Fakes.config(overrides), transport :: any, Fakes.queueDeps(clock) :: any)
		return queue, transport, clock
	end

	describe("batching", function()
		it("sends a batch once maxBatchSize events are queued", function()
			local queue, transport = setup()
			queue:push(Fakes.event())
			queue:push(Fakes.event())
			expect(#transport.calls).to.equal(0)
			queue:push(Fakes.event())
			expect(#transport.calls).to.equal(1)
			expect(#transport.calls[1]).to.equal(3)
			expect(queue:stats().sent).to.equal(3)
			expect(queue:stats().queued).to.equal(0)
		end)

		it("flush drains everything in maxBatchSize chunks, spaced by the min send interval", function()
			local queue, transport, clock = setup({ maxBatchSize = 3 })
			local t0 = clock.t
			queue:push(Fakes.event())
			queue:push(Fakes.event())
			queue:flush()
			expect(#transport.calls).to.equal(1)
			-- 7 more: two full batches go out by size, one event is left for flush()
			for _ = 1, 7 do
				queue:push(Fakes.event())
			end
			queue:flush()
			expect(#transport.calls).to.equal(4)
			expect(#transport.calls[4]).to.equal(1)
			expect(queue:stats().sent).to.equal(9)
			expect(clock.t - t0 >= 3 * Queue.MIN_SEND_INTERVAL_S).to.equal(true)
		end)

		it("flush is a no-op when empty", function()
			local queue, transport = setup()
			queue:flush()
			expect(#transport.calls).to.equal(0)
		end)

		it("keeps event order across batches", function()
			local queue, transport = setup({ maxBatchSize = 2 })
			local a, b, c = Fakes.event(), Fakes.event(), Fakes.event()
			queue:push(a)
			queue:push(b)
			queue:push(c)
			queue:flush()
			expect(transport.calls[1][1].id).to.equal(a.id)
			expect(transport.calls[1][2].id).to.equal(b.id)
			expect(transport.calls[2][1].id).to.equal(c.id)
		end)
	end)

	describe("overflow", function()
		it("drops the oldest events above maxQueueSize and counts them", function()
			local queue, transport = setup({ maxBatchSize = 100, maxQueueSize = 5 })
			local events = {}
			for i = 1, 8 do
				events[i] = Fakes.event()
				queue:push(events[i])
			end
			expect(queue:stats().queued).to.equal(5)
			expect(queue:stats().dropped).to.equal(3)
			queue:flush()
			expect(transport.calls[1][1].id).to.equal(events[4].id)
			expect(transport.calls[1][5].id).to.equal(events[8].id)
		end)
	end)

	describe("backoffDelay", function()
		it("grows exponentially from 2 s and caps at 60 s", function()
			expect(Queue.backoffDelay(1, 0.5, nil)).to.equal(2)
			expect(Queue.backoffDelay(2, 0.5, nil)).to.equal(4)
			expect(Queue.backoffDelay(3, 0.5, nil)).to.equal(8)
			expect(Queue.backoffDelay(10, 0.5, nil)).to.equal(60)
		end)

		it("applies jitter within [2, 60]", function()
			expect(Queue.backoffDelay(1, 0, nil)).to.equal(2)
			expect(Queue.backoffDelay(3, 0, nil)).to.equal(6)
			expect(Queue.backoffDelay(3, 1, nil)).to.equal(10)
			expect(Queue.backoffDelay(10, 1, nil)).to.equal(60)
		end)

		it("honours retry-after, capped", function()
			expect(Queue.backoffDelay(1, 0.5, 30)).to.equal(30)
			expect(Queue.backoffDelay(5, 0.5, 1)).to.equal(32)
			expect(Queue.backoffDelay(1, 0.5, 10000)).to.equal(Queue.RETRY_AFTER_MAX_S)
		end)
	end)

	describe("retry", function()
		it("puts the batch back at the front and waits for the backoff", function()
			local queue, transport, clock = setup({ maxBatchSize = 2 })
			table.insert(transport.script, "retry")
			local a, b = Fakes.event(), Fakes.event()
			queue:push(a)
			queue:push(b) -- triggers a send -> retry
			expect(#transport.calls).to.equal(1)
			expect(queue:stats().queued).to.equal(2)

			local c = Fakes.event()
			queue:push(c) -- backoff active: no send
			expect(#transport.calls).to.equal(1)

			clock.advance(2.5)
			queue:flush()
			expect(#transport.calls).to.equal(3)
			expect(transport.calls[2][1].id).to.equal(a.id)
			expect(transport.calls[2][2].id).to.equal(b.id)
			expect(transport.calls[3][1].id).to.equal(c.id)
			expect(queue:stats().sent).to.equal(3)
		end)

		it("respects the transport retry-after hint", function()
			local queue, transport, clock = setup({ maxBatchSize = 1 })
			table.insert(transport.script, "retry")
			transport.retryAfter = 30
			queue:push(Fakes.event())
			transport.retryAfter = nil
			clock.advance(20)
			queue:flush()
			expect(#transport.calls).to.equal(1)
			clock.advance(11)
			queue:flush()
			expect(#transport.calls).to.equal(2)
		end)

		it("treats a throwing transport as retry", function()
			local queue, transport = setup({ maxBatchSize = 1 })
			transport.throws = true
			queue:push(Fakes.event())
			expect(#transport.calls).to.equal(1)
			expect(queue:stats().queued).to.equal(1)
			expect(queue:stats().dropped).to.equal(0)
		end)
	end)

	describe("circuit breaker", function()
		it("opens after 5 consecutive failures for 60 s", function()
			local queue, transport, clock = setup({ maxBatchSize = 1 }, "retry")
			queue:push(Fakes.event())
			for _ = 2, Queue.BREAKER_THRESHOLD do
				clock.advance(Queue.BACKOFF_MAX_S + 1)
				queue:flush()
			end
			expect(#transport.calls).to.equal(Queue.BREAKER_THRESHOLD)

			-- The backoff after the 5th failure is 32 s, but the breaker holds for 60 s.
			clock.advance(40)
			queue:flush()
			expect(#transport.calls).to.equal(Queue.BREAKER_THRESHOLD)

			transport.default = "ok"
			clock.advance(21)
			queue:flush()
			expect(#transport.calls).to.equal(Queue.BREAKER_THRESHOLD + 1)
			expect(queue:stats().sent).to.equal(1)
		end)

		it("resets the failure count after a success", function()
			local queue, transport, clock = setup({ maxBatchSize = 1 })
			for _ = 1, 4 do
				table.insert(transport.script, "retry")
			end
			table.insert(transport.script, "ok")
			for _ = 1, 4 do
				table.insert(transport.script, "retry")
			end
			queue:push(Fakes.event())
			for _ = 1, 4 do
				clock.advance(Queue.BACKOFF_MAX_S + 1)
				queue:flush()
			end
			expect(queue:stats().sent).to.equal(1)
			-- 4 more failures stay below the threshold, so the 5th attempt is not blocked.
			queue:push(Fakes.event())
			for _ = 1, 4 do
				clock.advance(Queue.BACKOFF_MAX_S + 1)
				queue:flush()
			end
			expect(queue:stats().sent).to.equal(2)
		end)
	end)

	describe("drop and fatal", function()
		it("discards a batch the server rejects and keeps going", function()
			local queue, transport = setup({ maxBatchSize = 2 })
			table.insert(transport.script, "drop")
			for _ = 1, 4 do
				queue:push(Fakes.event())
			end
			expect(#transport.calls).to.equal(2)
			expect(queue:stats().dropped).to.equal(2)
			expect(queue:stats().sent).to.equal(2)
		end)

		it("disables the queue on fatal", function()
			local queue, transport, clock = setup({ maxBatchSize = 2 }, "fatal")
			queue:push(Fakes.event())
			queue:push(Fakes.event())
			expect(#transport.calls).to.equal(1)
			queue:push(Fakes.event())
			queue:push(Fakes.event())
			clock.advance(1000)
			queue:flush()
			queue:flushSync(5)
			expect(#transport.calls).to.equal(1)
			expect(queue:stats().queued).to.equal(0)
			expect(queue:stats().dropped).to.equal(2)
		end)
	end)

	describe("flushSync", function()
		it("drains everything with large batches", function()
			local queue, transport = setup({ maxBatchSize = 2000, maxQueueSize = 2000 })
			for _ = 1, 1200 do
				queue:push(Fakes.event())
			end
			queue:flushSync(25)
			expect(#transport.calls).to.equal(3)
			expect(#transport.calls[1]).to.equal(Queue.SYNC_BATCH_SIZE)
			expect(queue:stats().sent).to.equal(1200)
			expect(queue:stats().queued).to.equal(0)
		end)

		it("ignores an open breaker", function()
			local queue, transport, clock = setup({ maxBatchSize = 1 }, "retry")
			queue:push(Fakes.event())
			for _ = 2, Queue.BREAKER_THRESHOLD do
				clock.advance(Queue.BACKOFF_MAX_S + 1)
				queue:flush()
			end
			transport.default = "ok"
			clock.advance(Queue.BACKOFF_MAX_S + 1) -- backoff over, breaker still open
			queue:flushSync(25)
			expect(queue:stats().sent).to.equal(1)
		end)

		it("gives up at the timeout while the server keeps failing", function()
			local queue, transport, clock = setup({ maxBatchSize = 100 }, "retry")
			queue:push(Fakes.event())
			local t0 = clock.t
			queue:flushSync(25)
			expect(clock.t - t0 <= 25 + 1e-6).to.equal(true)
			expect(#transport.calls > 1).to.equal(true)
			expect(queue:stats().queued).to.equal(1)
		end)
	end)
end
