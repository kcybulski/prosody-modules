module:set_global();

local measure = require"core.statsmanager".measure;

local disco_ns = "http://jabber.org/protocol/disco#info";

local counters = {
	total = measure("amount", "client_features.total");
};

module:hook("stats-update", function ()
	local total = 0;
	local buckets = {};
	for _, session in pairs(prosody.full_sessions) do
		local disco_info = session.caps_cache;
		if disco_info ~= nil then
			for feature in disco_info:childtags("feature", disco_ns) do
				local var = feature.attr.var;
				if var ~= nil then
					if buckets[var] == nil then
						buckets[var] = 0;
					end
					buckets[var] = buckets[var] + 1;
				end
			end
			total = total + 1;
		end
	end
	for bucket, count in pairs(buckets) do
		if counters[bucket] == nil then
			counters[bucket] = measure("amount", "client_features."..bucket);
		end
		counters[bucket](count);
	end
	counters.total(total);
end)
