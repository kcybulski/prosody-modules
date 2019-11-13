local mm = require "core.modulemanager";
if mm.get_modules_for_host(module.host):contains("bookmarks") then
	error("mod_bookmarks2 and mod_bookmarks are conflicting, please disable one of them.", 0);
end

local st = require "util.stanza";
local jid_split = require "util.jid".split;

local mod_pep = module:depends "pep";
local private_storage = module:open_store("private", "map");

local legacy_ns = "storage:bookmarks";
local ns = "urn:xmpp:bookmarks:0";

local default_options = {
	["persist_items"] = true;
	-- This should be much higher, the XEP recommends 10000 but mod_pep rejects that.
	["max_items"] = 255;
	["send_last_published_item"] = "never";
	["access_model"] = "whitelist";
};

module:hook("account-disco-info", function (event)
	-- This Time it’s Serious!
	event.reply:tag("feature", { var = "urn:xmpp:bookmarks:0#compat" }):up();
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
	local ok, ret = service:get_items("urn:xmpp:bookmarks:0", session.full_jid);
	if not ok then
		if ret == "item-not-found" then
			module:log("debug", "Got no PEP bookmarks item for %s, returning empty private bookmarks", jid);
			session.send(st.reply(stanza):add_child(query));
		else
			module:log("error", "Failed to retrieve PEP bookmarks of %s: %s", jid, id);
			session.send(st.error_reply(stanza, "cancel", "internal-server-error", "Failed to retrive bookmarks from PEP"));
		end
		return true;
	end

	local storage = st.stanza("storage", { xmlns = "storage:bookmarks" });
	for _, item_id in ipairs(ret) do
		local item = ret[item_id];
		local conference = st.stanza("conference");
		conference.attr.jid = item.attr.id;
		local bookmark = item:get_child("conference", "urn:xmpp:bookmarks:0");
		conference.attr.name = bookmark.attr.name;
		conference.attr.autojoin = bookmark.attr.autojoin;
		local nick = bookmark:get_child_text("nick", "urn:xmpp:bookmarks:0");
		if nick ~= nil then
			conference:text_tag("nick", nick, { xmlns = "storage:bookmarks" }):up();
		end
		local password = bookmark:get_child_text("password", "urn:xmpp:bookmarks:0");
		if password ~= nil then
			conference:text_tag("password", password):up();
		end
		storage:add_child(conference);
	end

	module:log("debug", "Sending back private for %s: %s", jid, storage);
	session.send(st.reply(stanza):query("jabber:iq:private"):add_child(storage));
	return true;
end

local function compare_bookmark2(a, b)
	if a == nil or b == nil then
		return false;
	end
	local a_conference = a:get_child("conference", "urn:xmpp:bookmarks:0");
	local b_conference = b:get_child("conference", "urn:xmpp:bookmarks:0");
	local a_nick = a:get_child_text("nick", "urn:xmpp:bookmarks:0");
	local b_nick = b:get_child_text("nick", "urn:xmpp:bookmarks:0");
	local a_password = a:get_child_text("password", "urn:xmpp:bookmarks:0");
	local b_password = b:get_child_text("password", "urn:xmpp:bookmarks:0");
	return (a.attr.id == b.attr.id and
	        a_conference.attr.name == b_conference.attr.name and
	        a_conference.attr.autojoin == b_conference.attr.autojoin and
	        a_nick == b_nick and
	        a_password == b_password);
end

local function publish_to_pep(jid, bookmarks, synchronise)
	local service = mod_pep.get_pep_service(jid_split(jid));

	if #bookmarks.tags == 0 then
		if synchronise then
			-- If we set zero legacy bookmarks, purge the bookmarks 2 node.
			module:log("debug", "No bookmark in the set, purging instead.");
			return service:purge("urn:xmpp:bookmarks:0", jid, true);
		else
			return true;
		end
	end

	-- Retrieve the current bookmarks2.
	module:log("debug", "Retrieving the current bookmarks 2.");
	local has_bookmarks2, ret = service:get_items("urn:xmpp:bookmarks:0", jid);
	local bookmarks2;
	if not has_bookmarks2 and ret == "item-not-found" then
		module:log("debug", "Got item-not-found, assuming it was empty until now, creating.");
		local ok, err = service:create("urn:xmpp:bookmarks:0", jid, default_options);
		if not ok then
			module:log("error", "Creating bookmarks 2 node failed: %s", err);
			return ok, err;
		end
		bookmarks2 = {};
	elseif not has_bookmarks2 then
		module:log("debug", "Got %s error, aborting.", ret);
		return false, ret;
	else
		module:log("debug", "Got existing bookmarks2.");
		bookmarks2 = ret;
	end

	-- Get a list of all items we may want to remove.
	local to_remove = {};
	for i in ipairs(bookmarks2) do
		to_remove[bookmarks2[i]] = true;
	end

	for bookmark in bookmarks:childtags("conference", "storage:bookmarks") do
		-- Create the new conference element by copying everything from the legacy one.
		local conference = st.stanza("conference", { xmlns = "urn:xmpp:bookmarks:0" });
		conference.attr.name = bookmark.attr.name;
		conference.attr.autojoin = bookmark.attr.autojoin;
		local nick = bookmark:get_child_text("nick", "storage:bookmarks");
		if nick ~= nil then
			conference:text_tag("nick", nick, { xmlns = "urn:xmpp:bookmarks:0" }):up();
		end
		local password = bookmark:get_child_text("password", "storage:bookmarks");
		if password ~= nil then
			conference:text_tag("password", password, { xmlns = "urn:xmpp:bookmarks:0" }):up();
		end

		-- Create its wrapper.
		local item = st.stanza("item", { xmlns = "http://jabber.org/protocol/pubsub", id = bookmark.attr.jid })
			:add_child(conference);

		-- Then publish it only if it’s a new one or updating a previous one.
		if compare_bookmark2(item, bookmarks2[bookmark.attr.jid]) then
			module:log("debug", "Item %s identical to the previous one, skipping.", item.attr.id);
			to_remove[bookmark.attr.jid] = nil;
		else
			if bookmarks2[bookmark.attr.jid] == nil then
				module:log("debug", "Item %s not existing previously, publishing.", item.attr.id);
			else
				module:log("debug", "Item %s different from the previous one, publishing.", item.attr.id);
				to_remove[bookmark.attr.jid] = nil;
			end
			local ok, err = service:publish("urn:xmpp:bookmarks:0", jid, bookmark.attr.jid, item, default_options);
			if not ok then
				module:log("error", "Publishing item %s failed: %s", item.attr.id, err);
				return ok, err;
			end
		end
	end

	-- Now handle retracting items that have been removed.
	if synchronise then
		for id in pairs(to_remove) do
			module:log("debug", "Item %s removed from bookmarks.", id);
			local ok, err = service:retract("urn:xmpp:bookmarks:0", jid, id, st.stanza("retract", { id = id }));
			if not ok then
				module:log("error", "Retracting item %s failed: %s", id, err);
				return ok, err;
			end
		end
	end
	return true;
end

-- Synchronise Private XML to PEP.
local function on_publish_private_xml(event)
	local stanza, session = event.stanza, event.origin;
	local query = stanza:get_child("query", "jabber:iq:private");
	if query == nil then
		return;
	end

	local bookmarks = query:get_child("storage", legacy_ns);
	if bookmarks == nil then
		return;
	end

	module:log("debug", "Private bookmarks set by client, publishing to pep.");

	local ok, err = publish_to_pep(session.full_jid, bookmarks, true);
	if not ok then
		module:log("error", "Failed to publish to PEP bookmarks for %s@%s: %s", session.username, session.host, err);
		session.send(st.error_reply(stanza, "cancel", "internal-server-error", "Failed to store bookmarks to PEP"));
		return true;
	end

	session.send(st.reply(stanza));
	return true;
end

local function migrate_legacy_bookmarks(event)
	local session = event.session;
	local username = session.username;
	local service = mod_pep.get_pep_service(username);
	local jid = username.."@"..session.host;

	local data, err = private_storage:get(username, "storage:storage:bookmarks");
	if not data then
		module:log("debug", "No existing legacy bookmarks for %s, migration already done: %s", jid, err);
		local ok, ret = service:get_items("urn:xmpp:bookmarks:0", session.full_jid);
		if not ok or not ret then
			module:log("debug", "Additionally, no bookmarks 2 were existing for %s, assuming empty.", jid);
			module:fire_event("bookmarks/empty", { session = session });
		end
		return;
	end
	local bookmarks = st.deserialize(data);
	module:log("debug", "Got legacy bookmarks of %s: %s", jid, bookmarks);

	module:log("debug", "Going to store PEP item for %s.", jid);
	local ok, err = publish_to_pep(session.full_jid, bookmarks, false);
	if not ok then
		module:log("error", "Failed to store bookmarks to PEP for %s, aborting migration: %s", jid, err);
		return;
	end
	module:log("debug", "Stored bookmarks to PEP for %s.", jid);

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
module:hook("resource-bind", migrate_legacy_bookmarks);
module:handle_items("pep-service", function (event)
	local service = event.item.service;
	module:hook_object_event(service.events, "node-created", on_node_created);
end, function () end, true);
