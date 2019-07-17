
-- Implementation of https://xmpp.org/extensions/inbox/occupant-id.html
-- XEP-XXXX: Anonymous unique occupant identifiers for MUCs

local uuid = require "util.uuid";
local hmac_sha256 = require "util.hashes".hmac_sha256;
local b64encode = require "util.encodings".base64.encode;

local xmlns_occupant_id = "urn:xmpp:occupant-id:0";

local function edit_occupant(event)
	local occupant, room = event.occupant, event.room;
	local bare = occupant.bare_jid;

	-- TODO: Move the salt on the MUC component. Setting the salt on the room
	-- can be problematic when the room is destroyed. Next time it's recreated
	-- the salt will be different and so will be the unique_id. Or maybe we want
	-- this anyway?
	if room._data.occupant_id_salt == nil then
		local salt = uuid.generate();
		room._data.occupant_id_salt = salt;
	end

	local unique_id = b64encode(hmac_sha256(bare, room._data.occupant_id_salt));

	-- TODO: Store this only once per bare jid and not once per occupant?
	local stanza = event.stanza;
	stanza:tag("occupant-id", { xmlns = xmlns_occupant_id })
		:text(unique_id)
		:up();
end

local function handle_stanza(event)
	local stanza, occupant = event.stanza, event.occupant;

	if stanza.name == "presence" and stanza.attr.type == "unavailable" then -- not required here
		return;
	end

	-- strip any existing <occupant-id/> tags to avoid forgery
	stanza:remove_children("occupant-id", xmlns_occupant_id);

	local unique_id = occupant.sessions[stanza.attr.from]
		:get_child("occupant-id", xmlns_occupant_id)
		:get_text();
	stanza:tag("occupant-id", { xmlns = xmlns_occupant_id })
		:text(unique_id)
		:up();
end

module:add_feature(xmlns_occupant_id);
module:hook("muc-disco#info", function (event)
	event.reply:tag("feature", { var = xmlns_occupant_id }):up();
end);

module:hook("muc-occupant-pre-join", edit_occupant);
module:hook("muc-occupant-groupchat", handle_stanza);
