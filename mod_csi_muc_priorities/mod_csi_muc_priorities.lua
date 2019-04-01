local jid = require "util.jid";

module:hook("csi-is-stanza-important", function (event)
	local stanza, session = event.stanza, event.session;
	if stanza.name == "message" then
		if stanza.attr.type == "groupchat" then
			local body = stanza:get_child_text("body");
			if not body then return end

			local rooms = session.rooms_joined;
			if not rooms then return; end

			local room_nick = rooms[jid.bare(stanza.attr.from)];
			if room_nick and body:find(room_nick, 1, true) then return true; end

			return false;
		end
	end
end);

