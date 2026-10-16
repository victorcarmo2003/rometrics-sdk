--!strict
-- Plugin preferences (plugin:GetSetting/SetSetting, stored per Studio user, not in the place).

local Settings = {}

export type Values = {
	endpoint: string,
	secretName: string,
	sdkPath: string,
	dashboardUrl: string,
	highlight: boolean,
	lastTab: string,
}

local DEFAULTS: Values = {
	endpoint = "https://ingest.rometrics.app",
	secretName = "rometrics_key",
	sdkPath = "ReplicatedStorage.Packages.RoMetrics",
	dashboardUrl = "https://app.rometrics.app",
	highlight = false,
	lastTab = "home",
}
Settings.DEFAULTS = DEFAULTS

local PREFIX = "RoMetrics_"

export type Store = {
	get: (self: Store, key: string) -> any,
	set: (self: Store, key: string, value: any) -> (),
	values: (self: Store) -> Values,
}

function Settings.new(plugin: Plugin): Store
	local cache: { [string]: any } = {}
	local store = {} :: Store

	function store.get(_: Store, key: string): any
		if cache[key] ~= nil then
			return cache[key]
		end
		local default = (Settings.DEFAULTS :: any)[key]
		local ok, value = pcall(function()
			return plugin:GetSetting(PREFIX .. key)
		end)
		if not ok or value == nil or type(value) ~= type(default) then
			value = default
		end
		cache[key] = value
		return value
	end

	function store.set(_: Store, key: string, value: any)
		cache[key] = value
		pcall(function()
			plugin:SetSetting(PREFIX .. key, value)
		end)
	end

	function store.values(self: Store): Values
		local out = {}
		for key in Settings.DEFAULTS :: any do
			out[key] = self:get(key)
		end
		return (out :: any) :: Values
	end

	return store
end

return Settings
