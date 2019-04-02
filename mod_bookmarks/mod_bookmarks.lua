local st = require "util.stanza";
local jid_split = require "util.jid".split;

local mod_pep = module:depends "pep";
local private_storage = module:open_store("private", "map");

local default_options = {
	["persist_items"] = true;
	["access_model"] = "whitelist";
};

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
	local jid = username.."@"..session.host;
	local service = mod_pep.get_pep_service(username);
	local ok, id, item = service:get_last_item("storage:bookmarks", session.full_jid);
	if not ok then
		if id == "item-not-found" then
			module:log("debug", "Got no PEP bookmarks item for %s, returning empty private bookmarks", jid);
			session.send(st.reply(stanza):add_child(query));
		else
			module:log("error", "Failed to retrieve PEP bookmarks of %s: %s", jid, id);
			session.send(st.error_reply(stanza, "cancel", "internal-server-error", "Failed to retrive bookmarks from PEP"));
		end
		return;
	end
	if not id or not item then
		module:log("debug", "Got no PEP bookmarks item for %s, returning empty private bookmarks", jid);
		session.send(st.reply(stanza):add_child(query));
		return
	end
	module:log("debug", "Got item %s: %s", id, item);

	local content = item.tags[1];
	module:log("debug", "Sending back private for %s: %s", jid, content);
	session.send(st.reply(stanza):query("jabber:iq:private"):add_child(content));
	return true;
end

function publish_to_pep(jid, bookmarks)
	local service = mod_pep.get_pep_service(jid_split(jid));
	local item = st.stanza("item", { xmlns = "http://jabber.org/protocol/pubsub", id = "current" })
		:add_child(bookmarks);
	return service:publish("storage:bookmarks", jid, "current", item, default_options);
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
	local ok, err = publish_to_pep(session.full_jid, bookmarks);
	if not ok then
		module:log("error", "Failed to publish to PEP bookmarks for %s@%s: %s", session.username, session.host, err);
		session.send(st.error_reply(stanza, "cancel", "internal-server-error", "Failed to store bookmarks to PEP"));
		return;
	end

	session.send(st.reply(stanza));
	return true;
end

local function on_resource_bind(event)
	local session = event.session;
	local username = session.username;
	local service = mod_pep.get_pep_service(username);
	local jid = username.."@"..session.host;

	local data, err = private_storage:get(username, "storage:storage:bookmarks");
	if not data then
		module:log("debug", "No existing Private XML bookmarks for %s, migration already done: %s", jid, err);
		local ok, id = service:get_last_item("storage:bookmarks", session.full_jid);
		if not ok or not id then
			module:log("debug", "Additionally, no PEP bookmarks were existing for %s", jid);
			module:fire_event("bookmarks/empty", { session = session });
		end
		return;
	end
	local bookmarks = st.deserialize(data);
	module:log("debug", "Got private bookmarks of %s: %s", jid, bookmarks);

	-- We don’t care if deleting succeeds or not, we only want to start with a non-existent node.
	module:log("debug", "Deleting possibly existing PEP item for %s", jid);
	service:delete("storage:bookmarks", jid);

	module:log("debug", "Going to store PEP item for %s", jid);
	local ok, err = publish_to_pep(session.full_jid, bookmarks);
	if not ok then
		module:log("error", "Failed to store bookmarks to PEP for %s, aborting migration: %s", jid, err);
		return;
	end
	module:log("debug", "Stored bookmarks to PEP for %s", jid);

	local ok, err = private_storage:set(username, "storage:storage:bookmarks", nil);
	if not ok then
		module:log("error", "Failed to remove private bookmarks of %s: %s", jid, err);
		return;
	end
	module:log("debug", "Removed private bookmarks of %s, migration done!", jid);
end

local function on_node_created(event)
	local service, node, actor = event.service, event.node, event.actor;
	if node ~= "storage:bookmarks" then
		return;
	end
	local ok, node_config = service:get_node_config(node, actor);
	if not ok then
		module:log("error", "Failed to get node config of %s: %s", node, node_config);
		return;
	end
	local changed = false;
	for config_field, value in pairs(default_options) do
		if node_config[config_field] ~= value then
			node_config[config_field] = value;
			changed = true;
		end
	end
	if not changed then
		return;
	end
	local ok, err = service:set_node_config(node, actor, node_config);
	if not ok then
		module:log("error", "Failed to set node config of %s: %s", node, err);
		return;
	end
end

module:hook("iq/bare/jabber:iq:private:query", function (event)
	if event.stanza.attr.type == "get" then
		return on_retrieve_private_xml(event);
	else
		return on_publish_private_xml(event);
	end
end, 1);
module:hook("resource-bind", on_resource_bind);
module:handle_items("pep-service", function (event)
	local service = event.item.service;
	module:hook_object_event(service.events, "node-created", on_node_created);
end, function () end, true);
