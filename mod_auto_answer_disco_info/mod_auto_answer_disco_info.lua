module:depends("cache_c2s_caps");

local st = require "util.stanza";

local function iq_stanza_handler(event)
	local stanza = event.stanza;
	local type = stanza.attr.type;

	local query = stanza:get_child("query", "http://jabber.org/protocol/disco#info");
	if type ~= "get" or query == nil then
		return;
	end

	local to = stanza.attr.to;
	local node = query.attr.node;

	local target_session = prosody.full_sessions[to];
	if target_session == nil then
		return;
	end

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
