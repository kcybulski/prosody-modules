module:depends("cache_c2s_caps");

local st = require "util.stanza";

local function iq_stanza_handler(event)
	local origin, stanza = event.origin, event.stanza;
	local type = stanza.attr.type;

	local query = stanza:get_child("query", "http://jabber.org/protocol/disco#info");
	if type ~= "get" or query == nil then
		return;
	end

	local to = stanza.attr.to;
	local node = query.attr.node;

	local target_session = full_sessions[to];
	local disco_info = target_session.caps_cache;
	if disco_info ~= nil and (node == nil or node == disco_info.attr.node) then
		local iq = st.reply(stanza);
		iq:add_child(st.clone(disco_info));
		module:log("debug", "Answering disco#info on the behalf of the recipient")
		module:send(iq);
		return true;
	end
end

module:hook("iq/full", iq_stanza_handler, 1);
