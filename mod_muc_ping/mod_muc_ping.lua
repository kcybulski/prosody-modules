local st = require "util.stanza";
local jid_bare = import("util.jid", "bare");

local mod_muc = module:depends"muc";
local rooms = rawget(mod_muc, "rooms");
if not rooms then
	module:log("warn", "mod_%s is compatible with Prosody up to 0.10.x", module.name);
	return;
end

module:hook("iq/full", function (event)
	local origin, stanza = event.origin, event.stanza;
	if stanza.attr.type ~= "get" or not stanza:get_child("ping", "urn:xmpp:ping") then
		return;
	end

	local from = stanza.attr.from;
	local room_nick = stanza.attr.to;
	local room_jid = jid_bare(room_nick);

	local room = rooms[room_jid];
	if not room then return; end

	if room._jid_nick[from] == room_nick then
		origin.send(st.reply(stanza));
		return true;
	end
end);

module:hook("muc-disco#info", function(event)
	event.reply:tag("feature", {var="urn:xmpp:ping"}):up();
end);
