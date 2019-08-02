local bare_jid = require"util.jid".bare;
local st = require"util.stanza";

-- Support both old and new MUC code
local mod_muc = module:depends"muc";
local rooms = rawget(mod_muc, "rooms");
local get_room_from_jid = rawget(mod_muc, "get_room_from_jid") or
	function (jid)
		return rooms[jid];
	end

module:hook("message/full", function(event)
	local stanza, origin = event.stanza, event.origin;
	local to, from = stanza.attr.to, stanza.attr.from;
	local room = get_room_from_jid(bare_jid(to));
	local to_occupant = room and room._occupants[to];
	local from_occupant = room and room._occupants[room._jid_nick[from]]
	if not ( to_occupant and from_occupant ) then return end

	if from_occupant.affiliation then
		to_occupant._pm_block_override = true;
	elseif not from_occupant._pm_block_override then
		origin.send(st.error_reply(stanza, "cancel", "not-authorized", "Private messages are disabled"));
		return true;
	end
end, 1);
