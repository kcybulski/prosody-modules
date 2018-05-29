local st = require "util.stanza";
local dt = require "util.datetime";

local pubsub = module:depends"pubsub";

local actor = module.host .. "/modules/" .. module.name;

local function publish_stats(stats, stats_extra)
	local id = "current";
	local xitem = st.stanza("item", { id = id })
		:tag("query", { xmlns = "http://jabber.org/protocol/stats" });

	for name, value in pairs(stats) do
		local stat_extra = stats_extra[name];
		local unit = stat_extra and stat_extra.units;
		xitem:tag("stat", { name = name, unit = unit, value = tostring(value) }):up();
	end

	local ok, err = pubsub.service:publish("stats", actor, id, xitem);
	if not ok then
		module:log("error", "Error publishing stats: %s", err);
	end
end

function module.load()
	pubsub.service:create("stats", true);
	pubsub.service:set_affiliation("stats", true, actor, "publisher");
end

module:hook_global("stats-updated", function (event)
	publish_stats(event.stats, event.stats_extra);
end);

function module.unload()
	pubsub.service:delete("stats", true);
end
