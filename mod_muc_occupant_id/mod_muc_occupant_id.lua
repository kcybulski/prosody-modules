
-- Implementation of https://xmpp.org/extensions/inbox/occupant-id.html
-- XEP-0421: Anonymous unique occupant identifiers for MUCs

module:depends("muc");

local uuid = require "util.uuid";
local hmac_sha256 = require "util.hashes".hmac_sha256;
local b64encode = require "util.encodings".base64.encode;

local xmlns_occupant_id = "urn:xmpp:occupant-id:0";

local function generate_id(occupant, room)
	local bare = occupant.bare_jid;

	if room._data.occupant_id_salt == nil then
		room._data.occupant_id_salt = uuid.generate();
	end

	if room._data.occupant_ids == nil then
		room._data.occupant_ids = {};
	end

	if room._data.occupant_ids[bare] == nil then
		local unique_id = b64encode(hmac_sha256(bare, room._data.occupant_id_salt));
		room._data.occupant_ids[bare] = unique_id;
	end

	return room._data.occupant_ids[bare];
end

local function update_occupant(event)
	local stanza, occupant, room = event.stanza, event.occupant, event.room;

	-- strip any existing <occupant-id/> tags to avoid forgery
	stanza:remove_children("occupant-id", xmlns_occupant_id);

	local unique_id = generate_id(occupant, room);
	stanza:tag("occupant-id", { xmlns = xmlns_occupant_id })
		:text(unique_id)
		:up();
end

module:add_feature(xmlns_occupant_id);
module:hook("muc-disco#info", function (event)
	event.reply:tag("feature", { var = xmlns_occupant_id }):up();
end);

module:hook("muc-broadcast-presence", update_occupant);
module:hook("muc-occupant-pre-join", update_occupant);
module:hook("muc-occupant-groupchat", update_occupant);
