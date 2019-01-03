-- HTTP Access to PEP -> microblog
-- By Kim Alvefur <zash@zash.se>

local mod_pep = module:depends"pep";

local nodeprep = require "util.encodings".stringprep.nodeprep;
local st = require "util.stanza";

module:depends("http")
module:provides("http", {
	route = {
		["GET /*"] = function (event, user)
			local request, response = event.request, event.response;
			local actor = request.ip;

			user = nodeprep(user);
			if not user then return 400; end

			local pubsub_service = mod_pep.get_pep_service(user);
			local ok, items = pubsub_service:get_items("urn:xmpp:microblog:0", actor);
			if ok then
				response.headers.content_type = "application/xml";
				local feed = st.stanza("feed", { xmlns = "http://www.w3.org/2005/Atom" })
					:text_tag("generator", "Prosody", { uri = "xmpp:prosody.im", version = prosody.version })
					:text_tag("title", pubsub_service.nodes["urn:xmpp:microblog:0"].config.title or "Microblog feed")
					:text_tag("subtitle", pubsub_service.nodes["urn:xmpp:microblog:0"].config.description)
					:tag("author")
						:text_tag("name", user)
						:text_tag("preferredUsername", user, { xmlns = "http://portablecontacts.net/spec/1.0" });
				local ok, _, nick = pubsub_service:get_last_item("http://jabber.org/protocol/nick", actor);
				if ok and nick then
					feed:text_tag("displayName", nick.tags[1][1], { xmlns = "http://portablecontacts.net/spec/1.0" });
				end

				feed:reset();

				for i = #items, 1, -1 do
					feed:add_direct_child(items[items[i]].tags[1]);
				end
				return tostring(feed);
			elseif items == "forbidden" then
				return 403;
			elseif items == "item-not-found" then
				return 404;
			end
		end;
	}
});
