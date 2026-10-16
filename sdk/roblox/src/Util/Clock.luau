--!strict
-- Epoch milliseconds (integer), used for event `ts` and envelope `sentAt`.
return function(): number
	return DateTime.now().UnixTimestampMillis
end
