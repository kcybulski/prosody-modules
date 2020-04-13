-- Track messages received by users of the MUC

-- We rewrite the 'id' attribute of outgoing stanzas to match the stanza (archive) id
-- This module is therefore incompatible with the muc#stable_id feature
-- We rewrite the id because XEP-0333 doesn't tell clients explicitly which id to use
-- in marker reports. However it implies the 'id' attribute through examples, and this
-- is what some clients implement.
-- Notably Conversations will ack the origin-id instead. We need to update the XEP to
-- clarify the correct behaviour.

local xmlns_markers = "urn:xmpp:chat-markers:0";

local muc_marker_map_store = module:open_store("muc_markers", "map");

local function get_stanza_id(stanza, by_jid)
	for tag in stanza:childtags("stanza-id", "urn:xmpp:sid:0") do
		if tag.attr.by == by_jid then
			return tag.attr.id;
		end
	end
	return nil;
end

module:hook("muc-broadcast-message", function (event)
	local stanza = event.stanza;

	local archive_id = get_stanza_id(stanza, event.room.jid);
	-- We are not interested in stanzas that didn't get archived
	if not archive_id then return; end

	-- Add stanza id as id attribute
	stanza.attr.id = archive_id;
	-- Add markable element to request markers from clients
	stanza:tag("markable", { xmlns = xmlns_markers }):up();
end, -1);

module:hook("muc-occupant-groupchat", function (event)
	local marker = event.stanza:get_child("received", xmlns_markers);
	if not marker then return; end

	-- Store the id that the user has received to
	module:log("warn", "New marker for %s: %s", event.occupant.bare_jid, marker.attr.id);
	muc_marker_map_store:set(event.occupant.bare_jid, event.room.jid, marker.attr.id);

	-- Prevent stanza from reaching the room (it's just noise)
	return true;
end);

-- Public API

function get_user_read_marker(user_jid, room_jid)
	return muc_marker_map_store:get(user_jid, room_jid);
end
