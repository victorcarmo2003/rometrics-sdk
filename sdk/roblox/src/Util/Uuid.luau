--!strict
-- Lowercase RFC 4122 v4 UUID (no braces).
local HttpService = game:GetService("HttpService")

return function(): string
	return string.lower(HttpService:GenerateGUID(false))
end
