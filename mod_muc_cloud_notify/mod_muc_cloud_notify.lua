-- XEP-XXX: MUC Push Notifications
-- Copyright (C) 2015-2016 Kim Alvefur
-- Copyright (C) 2017-2018 Thilo Molitor
--
-- This file is MIT/X11 licensed.

local s_match = string.match;
local s_sub = string.sub;
local os_time = os.time;
local next = next;
local st = require"util.stanza";
local jid = require"util.jid";
local dataform = require"util.dataforms".new;
local hashes = require"util.hashes";

local xmlns_push = "urn:xmpp:push:0";

-- configuration
local include_body = module:get_option_boolean("push_notification_with_body", false);
local include_sender = module:get_option_boolean("push_notification_with_sender", false);
local max_push_errors = module:get_option_number("push_max_errors", 16);
local max_push_devices = module:get_option_number("push_max_devices", 5);
local dummy_body = module:get_option_string("push_notification_important_body", "New Message!");

local host_sessions = prosody.hosts[module.host].sessions;
local push_errors = {};
local id2room = {}
local id2user = {};

module:depends("muc");

-- For keeping state across reloads while caching reads
local push_store = (function()
	local store = module:open_store();
	local push_services = {};
	local api = {};
	local function load_room(room)
		if not push_services[room] then
			local err;
			push_services[room], err = store:get(room);
			if not push_services[room] and err then
				module:log("warn", "Error reading push notification storage for room '%s': %s", room, tostring(err));
				push_services[room] = {};
				return false;
			end
		end
		return true;
	end
	function api:get(room, user)
		load_room(room);
		if not push_services[room] then push_services[room] = {}; push_services[room][user] = {}; end
		return push_services[room][user], true;
	end
	function api:set(room, user, data)
		push_services[room][user] = data;
		local ok, err = store:set(room, push_services[room]);
		if not ok then
			module:log("error", "Error writing push notification storage for room '%s' on behalf of user '%s': %s", room, user, tostring(err));
			return false;
		end
		return true;
	end
	function api:get_room_users(room)
		local users = {};
		load_room(room);
		for k, v in pairs(push_services[room]) do
			table.insert(users, k);
		end
		return users;
	end
	return api;
end)();


-- Forward declarations, as both functions need to reference each other
local handle_push_success, handle_push_error;

function handle_push_error(event)
	local stanza = event.stanza;
	local error_type, condition = stanza:get_error();
	local room = id2room[stanza.attr.id];
	local user = id2user[stanza.attr.id];
	if room == nil or user == nil then return false; end		-- unknown stanza? Ignore for now!
	local push_service = push_store:get(room, user);
	local push_identifier = room.."<"..user..">";
	
	local stanza_id = hashes.sha256(push_identifier, true);
	if stanza_id == stanza.attr.id then
		if push_service and push_service.push_jid == stanza.attr.from and error_type ~= "wait" then
			push_errors[push_identifier] = push_errors[push_identifier] + 1;
			module:log("info", "Got error of type '%s' (%s) for identifier '%s': "
				.."error count for this identifier is now at %s", error_type, condition, push_identifier,
				tostring(push_errors[push_identifier]));
			if push_errors[push_identifier] >= max_push_errors then
				module:log("warn", "Disabling push notifications for identifier '%s'", push_identifier);
				-- save changed global config
				push_store:set(room, user, nil);
				push_errors[push_identifier] = nil;
				-- unhook iq handlers for this identifier (if possible)
				if module.unhook then
					module:unhook("iq-error/host/"..stanza_id, handle_push_error);
					module:unhook("iq-result/host/"..stanza_id, handle_push_success);
					id2room[stanza_id] = nil;
					id2user[stanza_id] = nil;
				end
			end
		elseif push_service and push_service.push_jid == stanza.attr.from and error_type == "wait" then
			module:log("debug", "Got error of type '%s' (%s) for identifier '%s': "
				.."NOT increasing error count for this identifier", error_type, condition, push_identifier);
		end
	end
	return true;
end

function handle_push_success(event)
	local stanza = event.stanza;
	local room = id2room[stanza.attr.id];
	local user = id2user[stanza.attr.id];
	if room == nil or user == nil then return false; end		-- unknown stanza? Ignore for now!
	local push_service = push_store:get(room, user);
	local push_identifier = room.."<"..user..">";
	
	if hashes.sha256(push_identifier, true) == stanza.attr.id then
		if push_service and push_service.push_jid == stanza.attr.from and push_errors[push_identifier] > 0 then
			push_errors[push_identifier] = 0;
			-- unhook iq handlers for this identifier (if possible)
			if module.unhook then
				module:unhook("iq-error/host/"..stanza.attr.id, handle_push_error);
				module:unhook("iq-result/host/"..stanza.attr.id, handle_push_success);
				id2room[stanza.attr.id] = nil;
				id2user[stanza.attr.id] = nil;
			end
			module:log("debug", "Push succeeded, error count for identifier '%s' is now at %s again", push_identifier, tostring(push_errors[push_identifier]));
		end
	end
	return true;
end

-- http://xmpp.org/extensions/xep-xxxx.html#disco
module:hook("muc-disco#info", function(event)
	(event.reply or event.stanza):tag("feature", {var=xmlns_push}):up();
end);

-- http://xmpp.org/extensions/xep-0357.html#enabling
local function push_enable(event)
	local origin, stanza = event.origin, event.stanza;
	local room = jid.split(stanza.attr.to);
	local enable = stanza.tags[1];
	origin.log("debug", "Attempting to enable push notifications");
	-- MUST contain a 'jid' attribute of the XMPP Push Service being enabled
	local push_jid = enable.attr.jid;
	if not push_jid then
		origin.log("debug", "MUC Push notification enable request missing the 'jid' field");
		origin.send(st.error_reply(stanza, "modify", "bad-request", "Missing jid"));
		return true;
	end
	local publish_options = enable:get_child("x", "jabber:x:data");
	if not publish_options then
		-- Could be intentional
		origin.log("debug", "No publish options in request");
	end
	local push_service = {
		push_jid = push_jid;
		device = stanza.attr.from;
		options = publish_options and st.preserialize(publish_options);
		timestamp = os_time();
	};
	
	local ok = push_store:set(room, stanza.attr.from, push_service);
	if not ok then
		origin.send(st.error_reply(stanza, "wait", "internal-server-error"));
	else
		origin.log("info", "MUC Push notifications enabled for room %s by %s (%s)",
			 tostring(room),
			 tostring(stanza.attr.from),
			 tostring(push_jid)
			);
		origin.send(st.reply(stanza));
	end
	return true;
end
module:hook("iq-set/host/"..xmlns_push..":enable", push_enable);


-- http://xmpp.org/extensions/xep-0357.html#disabling
local function push_disable(event)
	local origin, stanza = event.origin, event.stanza;
	local room = jid.split(stanza.attr.to);
	local push_jid = stanza.tags[1].attr.jid; -- MUST include a 'jid' attribute
	if not push_jid then
		origin.send(st.error_reply(stanza, "modify", "bad-request", "Missing jid"));
		return true;
	end
	local push_identifier = room.."<"..stanza.attr.from..">";
	local push_service = push_store:get(room, stanza.attr.from);
	local ok = true;
	if push_service.push_jid == push_jid then
		origin.log("info", "Push notifications disabled for room %s by %s (%s)",
			tostring(room),
			sotring(stanza.attr.from),
			tostring(push_jid)
		);
		ok = push_store:set(room, stanza.attr.from, nil);
		push_errors[push_identifier] = nil;
		if module.unhook then
			local stanza_id = hashes.sha256(push_identifier, true);
			module:unhook("iq-error/host/"..stanza_id, handle_push_error);
			module:unhook("iq-result/host/"..stanza_id, handle_push_success);
			id2room[stanza_id] = nil;
			id2user[stanza_id] = nil;
		end
	end
	if not ok then
		origin.send(st.error_reply(stanza, "wait", "internal-server-error"));
	else
		origin.send(st.reply(stanza));
	end
	return true;
end
module:hook("iq-set/host/"..xmlns_push..":disable", push_disable);

-- Patched version of util.stanza:find() that supports giving stanza names
-- without their namespace, allowing for every namespace.
local function find(self, path)
	local pos = 1;
	local len = #path + 1;

	repeat
		local xmlns, name, text;
		local char = s_sub(path, pos, pos);
		if char == "@" then
			return self.attr[s_sub(path, pos + 1)];
		elseif char == "{" then
			xmlns, pos = s_match(path, "^([^}]+)}()", pos + 1);
		end
		name, text, pos = s_match(path, "^([^@/#]*)([/#]?)()", pos);
		name = name ~= "" and name or nil;
		if pos == len then
			if text == "#" then
				local child = xmlns ~= nil and self:get_child(name, xmlns) or self:child_with_name(name);
				return child and child:get_text() or nil;
			end
			return xmlns ~= nil and self:get_child(name, xmlns) or self:child_with_name(name);
		end
		self = xmlns ~= nil and self:get_child(name, xmlns) or self:child_with_name(name);
	until not self
	return nil;
end

-- is this push a high priority one (this is needed for ios apps not using voip pushes)
local function is_important(stanza)
	local st_name = stanza and stanza.name or nil;
	if not st_name then return false; end	-- nonzas are never important here
	if st_name == "presence" then
		return false;						-- same for presences
	elseif st_name == "message" then
		-- unpack carbon copies
		local stanza_direction = "in";
		local carbon;
		local st_type;
		-- support carbon copied message stanzas having an arbitrary message-namespace or no message-namespace at all
		if not carbon then carbon = find(stanza, "{urn:xmpp:carbons:2}/forwarded/message"); end
		if not carbon then carbon = find(stanza, "{urn:xmpp:carbons:1}/forwarded/message"); end
		stanza_direction = carbon and stanza:child_with_name("sent") and "out" or "in";
		if carbon then stanza = carbon; end
		st_type = stanza.attr.type;
		
		-- headline message are always not important
		if st_type == "headline" then return false; end
		
		-- carbon copied outgoing messages are not important
		if carbon and stanza_direction == "out" then return false; end
		
		-- We can't check for body contents in encrypted messages, so let's treat them as important
		-- Some clients don't even set a body or an empty body for encrypted messages
		
		-- check omemo https://xmpp.org/extensions/inbox/omemo.html
		if stanza:get_child("encrypted", "eu.siacs.conversations.axolotl") or stanza:get_child("encrypted", "urn:xmpp:omemo:0") then return true; end
		
		-- check xep27 pgp https://xmpp.org/extensions/xep-0027.html
		if stanza:get_child("x", "jabber:x:encrypted") then return true; end
		
		-- check xep373 pgp (OX) https://xmpp.org/extensions/xep-0373.html
		if stanza:get_child("openpgp", "urn:xmpp:openpgp:0") then return true; end
		
		local body = stanza:get_child_text("body");
		if st_type == "groupchat" and stanza:get_child_text("subject") then return false; end		-- groupchat subjects are not important here
		return body ~= nil and body ~= "";			-- empty bodies are not important
	end
	return false;		-- this stanza wasn't one of the above cases --> it is not important, too
end

local push_form = dataform {
	{ name = "FORM_TYPE"; type = "hidden"; value = "urn:xmpp:muc_push:summary"; };
	--{ name = "dummy"; type = "text-single"; };
};

-- http://xmpp.org/extensions/xep-0357.html#publishing
local function handle_notify_request(stanza, user, user_push_services)
	local pushes = 0;
	if not user_push_services or next(user_push_services) == nil then return pushes end
	
	for push_identifier, push_info in pairs(user_push_services) do
		local send_push = true;		-- only send push to this node when not already done for this stanza or if no stanza is given at all
		if stanza then
			if not stanza._push_notify then stanza._push_notify = {}; end
			if stanza._push_notify[push_identifier] then
				if log_push_decline then
					module:log("debug", "Already sent push notification for %s to %s (%s)", user, push_info.push_jid, tostring(push_info.node));
				end
				send_push = false;
			end
			stanza._push_notify[push_identifier] = true;
		end
		
		if send_push then
			-- construct push stanza
			local stanza_id = hashes.sha256(push_identifier, true);
			local push_publish = st.iq({ to = push_info.jid, from = module.host, type = "set", id = stanza_id })
				:tag("pubsub", { xmlns = "http://jabber.org/protocol/pubsub" })
					:tag("publish", { node = push_info.node })
						:tag("item")
							:tag("notification", { xmlns = xmlns_push });
			local form_data = {
				-- hardcode to 1 because other numbers are just meaningless (the XEP does not specify *what exactly* to count)
				["message-count"] = "1";
			};
			if stanza and include_sender then
				form_data["last-message-sender"] = stanza.attr.from;
			end
			if stanza and include_body then
				form_data["last-message-body"] = stanza:get_child_text("body");
			elseif stanza and dummy_body and is_important(stanza) then
				form_data["last-message-body"] = tostring(dummy_body);
			end
			push_publish:add_child(push_form:form(form_data));
			push_publish:up(); -- / notification
			push_publish:up(); -- / publish
			push_publish:up(); -- / pubsub
			if push_info.options then
				push_publish:tag("publish-options"):add_child(st.deserialize(push_info.options));
			end
			-- send out push
			module:log("debug", "Sending%s push notification for %s@%s to %s (%s)", form_data["last-message-body"] and " important" or "", node, module.host, push_info.jid, tostring(push_info.node));
			-- module:log("debug", "PUSH STANZA: %s", tostring(push_publish));
			-- handle push errors for this node
			if push_errors[push_identifier] == nil then
				push_errors[push_identifier] = 0;
				module:hook("iq-error/host/"..stanza_id, handle_push_error);
				module:hook("iq-result/host/"..stanza_id, handle_push_success);
				id2node[stanza_id] = node;
			end
			module:send(push_publish);
			pushes = pushes + 1;
		end
	end
	return pushes;
end

local function extract_reference(text, i, j)
        -- COMPAT w/ pre-Lua 5.3
        local c, pos, p1 = 0, 0, nil;
        for char in text:gmatch("([%z\1-\127\194-\244][\128-\191]*)") do
                c, pos = c + 1, pos + #char;
                if not p1 and i < c then
                        p1 = pos;
                end
                if c == j then
                        return text:sub(p1, pos);
                end
        end
end

-- archive message added
local function archive_message_added(event)
	-- event is: { origin = origin, stanza = stanza, for_user = store_user, id = id }
	local room = event.room;
	local stanza = event.stanza;
	local room_name = jid.split(room.jid);
	
	-- extract all real ocupant jids in room
	occupants = {};
	for nick, occupant in room:each_occupant() do
		for jid in occupant:each_session() do
			occupants[jid] = true;
		end
	end
	
	-- check all push registered users against occupants list
	for _, user in pairs(push_store:get_room_users(room_name)) do
		-- send push if not found in occupants list
		if not occupants[user] then
			local push_service = push_store:get(room_name, user);
			handle_notify_request(event.stanza, user, push_service);
		end
	end
	
	
	
	
	liste der registrierten push user eines raumes durchgehen
		jeder user der NICHT im muc ist, wird gepusht
	
	
	handle_notify_request(event.stanza, jid, user_push_services, true);
	
	
	
	for reference in stanza:childtags("reference", "urn:xmpp:reference:0") do
		if reference.attr['type'] == 'mention' and reference.attr['begin'] and reference.attr['end'] then
			local nick = extract_reference(body, reference.attr['begin'], reference.attr['end']);
			local jid = room:get_registered_jid(nick);

			if room._occupants[room.jid..'/'..nick] then
				-- We only notify for members not currently in the room
				module:log("debug", "Not notifying %s, because he's currently in the room", jid);
			else
				-- We only need to notify once, even when there are multiple mentions.
				local user_push_services = push_store:get(jid);
				handle_notify_request(event.stanza, jid, user_push_services, true);
				return
			end
		end
	end
end

module:hook("muc-add-history", archive_message_added);

local function send_ping(event)
	local push_services = event.push_services;
	if not push_services then
		local room = event.room;
		local user = event.user;
		push_services = push_store:get(room, user);
	end
	handle_notify_request(nil, user, push_services, true);
end
-- can be used by other modules to ping one or more (or all) push endpoints
module:hook("muc-cloud-notify-ping", send_ping);

module:log("info", "Module loaded");
function module.unload()
	if module.unhook then
		module:unhook("account-disco-info", account_dico_info);
		module:unhook("iq-set/host/"..xmlns_push..":enable", push_enable);
		module:unhook("iq-set/host/"..xmlns_push..":disable", push_disable);

		module:unhook("muc-add-history", archive_message_added);
		module:unhook("cloud-notify-ping", send_ping);

		for push_identifier, _ in pairs(push_errors) do
			local stanza_id = hashes.sha256(push_identifier, true);
			module:unhook("iq-error/host/"..stanza_id, handle_push_error);
			module:unhook("iq-result/host/"..stanza_id, handle_push_success);
			id2room[stanza_id] = nil;
			id2user[stanza_id] = nil;
		end
	end

	module:log("info", "Module unloaded");
end
