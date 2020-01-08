local statsman = require "core.statsmanager";
local st = require "util.stanza";

module:hook("iq/host/http://jabber.org/protocol/stats:query", function (event)
	local origin, stanza = event.origin, event.stanza;
	local stats, _, extra = statsman.get_stats();
	local reply = st.reply(event.stanza);
	reply:tag("query", { xmlns = "http://jabber.org/protocol/stats" });
	for stat, value in pairs(stats) do
		local unit = extra[stat] and extra[stat].units;
		reply:tag("stat", { name = stat, unit = unit, value = tostring(value) }):up();
	end
	origin.send(reply);
	return true;
end)
