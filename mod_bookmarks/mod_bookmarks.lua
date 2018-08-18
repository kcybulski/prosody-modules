local st = require "util.stanza"

local mod_pep = module:depends "pep";
local private_storage = module:open_store("private", "map");

module:hook("account-disco-info", function (event)
	event.reply:tag("feature", { var = "urn:xmpp:bookmarks-conversion:0" }):up();
end);

local function on_retrieve_private_xml(event)
	local stanza, session = event.stanza, event.origin;
	local query = stanza:get_child("query", "jabber:iq:private");
	if query == nil then
		return;
	end

	local bookmarks = query:get_child("storage", "storage:bookmarks");
	if bookmarks == nil then
		return;
	end

	module:log("debug", "Getting private bookmarks: %s", bookmarks);

	local username = session.username;
	local service = mod_pep.get_pep_service(username);
	module:log("debug", "%s", session.full_jid);
	local ok, id, item = service:get_last_item("storage:bookmarks", session.full_jid);
	if not ok then
		module:log("error", "Failed to retrieve PEP bookmarks of %s: %s", username, id);
		session.send(st.error_reply(stanza, "cancel", "internal-server-error", "Failed to retrive bookmarks from PEP"));
		return;
	end

	local content = item.tags[1];
	module:log("debug", "Sending back private for %s: %s", username, content);
	session.send(st.reply(stanza):query("jabber:iq:private"):add_child(content));
	return true;
end

local function publish_to_pep(username, jid, bookmarks)
	local service = mod_pep.get_pep_service(username);
	local item = st.stanza("item", { xmlns = "http://jabber.org/protocol/pubsub", id = "current" })
		:add_child(bookmarks);
	local options = {
		["persist_items"] = true;
		["access_model"] = "whitelist";
	};
	return service:publish("storage:bookmarks", jid, "current", item, options);
end

-- Synchronise Private XML to PEP.
local function on_publish_private_xml(event)
	local stanza, session = event.stanza, event.origin;
	local query = stanza:get_child("query", "jabber:iq:private");
	if query == nil then
		return;
	end

	local bookmarks = query:get_child("storage", "storage:bookmarks");
	if bookmarks == nil then
		return;
	end

	module:log("debug", "Private bookmarks set by client, publishing to pep");
	local ok, err = publish_to_pep(session.username, session.full_jid, bookmarks);
	if not ok then
		module:log("error", "Failed to publish to PEP bookmarks for %s: %s", session.username, err);
		session.send(st.error_reply(stanza, "cancel", "internal-server-error", "Failed to store bookmarks to PEP"));
		return;
	end

	session.send(st.reply(stanza));
	return true;
end

local function on_resource_bind(event)
	local session = event.session;
	local username = session.username;

	local data, err = private_storage:get(username, "storage:storage:bookmarks");
	if not data then
		module:log("debug", "No existing Private XML bookmarks for %s, migration already done: %s", username, err);
		return;
	end
	local bookmarks = st.deserialize(data);
	module:log("debug", "Got private bookmarks of %s: %s", username, bookmarks);

	module:log("debug", "Going to store PEP item for %s", username);
	local ok, err = publish_to_pep(username, session.host, bookmarks);
	if not ok then
		module:log("error", "Failed to store bookmarks to PEP for %s, aborting migration: %s", username, err);
		return;
	end
	module:log("debug", "Stored bookmarks to PEP for %s", username);

	local ok, err = private_storage:set(username, "storage:storage:bookmarks", nil);
	if not ok then
		module:log("error", "Failed to remove private bookmarks of %s: %s", username, err);
		return;
	end
	module:log("debug", "Removed private bookmarks of %s, migration done!", username);
end

module:hook("iq-get/bare/jabber:iq:private:query", on_retrieve_private_xml)
module:hook("iq-set/bare/jabber:iq:private:query", on_publish_private_xml)
module:hook("resource-bind", on_resource_bind)
