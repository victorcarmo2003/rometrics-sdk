--!strict
-- Shared types. Mirrors the RoMetrics ingest wire format.

export type Options = {
	key: (string | Secret)?,
	endpoint: string?,
	flushInterval: number?,
	maxBatchSize: number?,
	maxQueueSize: number?,
	heartbeatInterval: number?,
	forwardToRobloxAnalytics: boolean?,
	debug: boolean?,
	enabledInStudio: boolean?,
}

export type Config = {
	key: string | Secret,
	endpoint: string,
	flushInterval: number,
	maxBatchSize: number,
	maxQueueSize: number,
	heartbeatInterval: number,
	forwardToRobloxAnalytics: boolean,
	debug: boolean,
	enabledInStudio: boolean,
	sdkVersion: string,
}

-- Wire event. `type` is one of: server_start, heartbeat, server_stop, player_join,
-- player_leave, player_platform, purchase, custom, economy, funnel, progression.
export type Event = {
	id: string,
	type: string,
	ts: number, -- epoch ms
	userId: number?,
	sessionId: string?,
	name: string?,
	value: number?,
	data: { [string]: any }?,
}

export type ServerInfo = {
	universeId: number,
	placeId: number,
	placeVersion: number,
	jobId: string,
	private: boolean,
	startedAt: number,
}

export type SessionInfo = {
	sessionId: string,
	userId: number,
	startedAt: number, -- epoch ms
	country: string?,
	platform: string?,
	launchCode: string?,
}

export type Transport = {
	-- Sends one batch. Returns "ok" | "drop" (bad request, discard) | "retry" | "fatal" (auth, disable SDK).
	send: (self: Transport, events: { Event }) -> "ok" | "drop" | "retry" | "fatal",
}

export type Queue = {
	push: (self: Queue, event: Event) -> (),
	-- Async flush (spawns). Safe to call often.
	flush: (self: Queue) -> (),
	-- Blocking flush used by BindToClose; stops after `timeout` seconds.
	flushSync: (self: Queue, timeout: number) -> (),
	stats: (self: Queue) -> { queued: number, dropped: number, sent: number },
	destroy: (self: Queue) -> (),
}

export type SessionTracker = {
	get: (self: SessionTracker, player: Player) -> SessionInfo?,
	destroy: (self: SessionTracker) -> (),
}

return nil
