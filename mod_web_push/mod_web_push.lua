-- XEP-XXXX: Web Push (aka: My mobile OS vendor won't let me have persistent TCP connections, take two)
-- Copyright (C) 2019 Maxime “pep” Buquet
--
-- Heavily based on mod_cloud_notify.
-- Copyright (C) 2015-2016 Kim Alvefur
-- Copyright (C) 2017-2018 Thilo Molitor


local st = require"util.stanza";
local dataform = require "util.dataforms";
local http = require "net.http";

local os_time = os.time;
local next = next;
local jid = require"util.jid";
local filters = require"util.filters";

local xmlns_webpush = "urn:xmpp:webpush:0";

local max_push_devices = module:get_option_number("push_max_devices", 5);
local dummy_body = module:get_option_string("push_notification_important_body", "New Message!");

local host_sessions = prosody.hosts[module.host].sessions;

-- TODO: Generate it at setup time. Obviously not to be used other than for
-- testing purposes, or at all.
-- ECDH keypair
local server_pubkey = "MFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAEhxZpb8yIVc/2hNesGLGAxEakyYy0MqEetjgL7BIOm8ybhVKxapKqNXjXJ+NOO5/b0Z0UuBg/HynGnf0xKKNhBQ==";
local server_privkey = "MHcCAQEEIPhZac9pQ8aVTx9a5JyRcqfk3nuQQUFy3PaDcSWleojzoAoGCCqGSM49AwEHoUQDQgAEhxZpb8yIVc/2hNesGLGAxEakyYy0MqEetjgL7BIOm8ybhVKxapKqNXjXJ+NOO5/b0Z0UuBg/HynGnf0xKKNhBQ==";

-- Advertize disco feature
local function account_disco_info(event)
	local form = dataform.new {
		{ name = "FORM_TYPE", type = "hidden", value = "http://jabber.org/protocol/webpush#public-key" };
		{ name = "webpush#public-key", value = server_pubkey };
	};
	(event.reply or event.stanza):tag("feature", {var=xmlns_webpush}):up()
	:add_child(form:form({}, "result"));
end
module:hook("account-disco-info", account_disco_info);

-- ordered table iterator, allow to iterate on the natural order of the keys of a table,
-- see http://lua-users.org/wiki/SortedIteration
local function __genOrderedIndex( t )
	local orderedIndex = {}
	for key in pairs(t) do
		table.insert( orderedIndex, key )
	end
	-- sort in reverse order (newest one first)
	table.sort( orderedIndex, function(a, b)
		if a == nil or t[a] == nil or b == nil or t[b] == nil then return false end
		-- only one timestamp given, this is the newer one
		if t[a].timestamp ~= nil and t[b].timestamp == nil then return true end
		if t[a].timestamp == nil and t[b].timestamp ~= nil then return false end
		-- both timestamps given, sort normally
		if t[a].timestamp ~= nil and t[b].timestamp ~= nil then return t[a].timestamp > t[b].timestamp end
		return false -- normally not reached
	end)
	return orderedIndex
end
local function orderedNext(t, state)
	-- Equivalent of the next function, but returns the keys in timestamp
	-- order. We use a temporary ordered key table that is stored in the
	-- table being iterated.

	local key = nil
	--print("orderedNext: state = "..tostring(state) )
	if state == nil then
		-- the first time, generate the index
		t.__orderedIndex = __genOrderedIndex( t )
		key = t.__orderedIndex[1]
	else
		-- fetch the next value
		for i = 1, #t.__orderedIndex do
			if t.__orderedIndex[i] == state then
				key = t.__orderedIndex[i+1]
			end
		end
	end

	if key then
		return key, t[key]
	end

	-- no more value to return, cleanup
	t.__orderedIndex = nil
	return
end
local function orderedPairs(t)
	-- Equivalent of the pairs() function on tables. Allows to iterate
	-- in order
	return orderedNext, t, nil
end

-- small helper function to return new table with only "maximum" elements containing only the newest entries
local function reduce_table(table, maximum)
	local count = 0;
	local result = {};
	for key, value in orderedPairs(table) do
		count = count + 1;
		if count > maximum then break end
		result[key] = value;
	end
	return result;
end

local push_store = (function()
	local store = module:open_store();
	local push_services = {};
	local api = {};
	function api:get(user)
		if not push_services[user] then
			local err;
			push_services[user], err = store:get(user);
			if not push_services[user] and err then
				module:log("warn", "Error reading web push notification storage for user '%s': %s", user, tostring(err));
				push_services[user] = {};
				return push_services[user], false;
			end
		end
		if not push_services[user] then push_services[user] = {} end
		return push_services[user], true;
	end
	function api:set(user, data)
		push_services[user] = reduce_table(data, max_push_devices);
		local ok, err = store:set(user, push_services[user]);
		if not ok then
			module:log("error", "Error writing web push notification storage for user '%s': %s", user, tostring(err));
			return false;
		end
		return true;
	end
	function api:set_identifier(user, push_identifier, data)
		local services = self:get(user);
		services[push_identifier] = data;
		return self:set(user, services);
	end
	return api;
end)();

local function push_enable(event)
	local origin, stanza = event.origin, event.stanza;
	local enable = stanza.tags[1];
	origin.log("debug", "Attempting to enable web push notifications");
	-- MUST contain a 'href' attribute of the XMPP Push Service being enabled
	local push_endpoint = nil;
	local push_auth = nil;
	local push_p256dh = nil;

	local endpoint_tag = enable:get_child('endpoint');
	if endpoint_tag ~= nil then
		push_endpoint = endpoint_tag:get_text();
	end
	local auth_tag = enable:get_child('auth');
	if auth_tag ~= nil then
		push_auth = auth_tag:get_text();
	end
	local p256dh_tag = enable:get_child('p256dh');
	if p256dh_tag ~= nil then
		push_p256dh = p256dh_tag:get_text();
	end
	if not push_endpoint or not push_auth or not push_p256dh then
		origin.log("debug", "Web Push notification enable request missing 'endpoint', 'auth', or 'p256dh' tags");
		origin.send(st.error_reply(stanza, "modify", "bad-request", "Missing enable child tag"));
		return true;
	end
	local push_identifier = "foo";
	local push_service = push_endpoint;
	local ok = push_store:set_identifier(origin.username, push_identifier, push_service);
	if not ok then
		origin.send(st.error_reply(stanza, "wait", "internal-server-error"));
	else
		origin.push_identifier = push_identifier;
		origin.push_settings = push_service;
		origin.log("info", "Web Push notifications enabled for %s (%s)", tostring(stanza.attr.from), tostring(origin.push_identifier));
		origin.send(st.reply(stanza));
	end
	return true;
end
module:hook("iq-set/self/"..xmlns_webpush..":enable", push_enable);

-- module:hook("iq-set/self/"..xmlns_webpush..":disable", push_disable);

-- small helper function to extract relevant push settings
local function get_push_settings(stanza, session)
	local to = stanza.attr.to;
	local node = to and jid.split(to) or session.username;
	local user_push_services = push_store:get(node);
	return node, user_push_services;
end

local function log_http_req(response_body, response_code, response)
	module:log("debug", "FOO: response_body: %s; response_code: %s; response: %s", response_body, tostring(response_code), tostring(response));
end

local function handle_notify_request(stanza, node, user_push_services, log_push_decline)
	local pushes = 0;
	if not user_push_services or next(user_push_services) == nil then return pushes end

	for push_identifier, push_info in pairs(user_push_services) do
		local send_push = true;		-- only send push to this node when not already done for this stanza or if no stanza is given at all
		if stanza then
			if not stanza._push_notify then stanza._push_notify = {}; end
			if stanza._push_notify[push_identifier] then
				if log_push_decline then
					module:log("debug", "Already sent push notification for %s@%s to %s", node, module.host, tostring(push_info));
				end
				send_push = false;
			end
			stanza._push_notify[push_identifier] = true;
		end

		if send_push then
			local headers = { TTL = "60" };
			http.request(push_info, { method = "POST", headers = headers }, log_http_req);
			pushes = pushes + 1;
		end
	end
	return pushes;
end

-- publish on offline message
module:hook("message/offline/handle", function(event)
	local node, user_push_services = get_push_settings(event.stanza, event.origin);
	module:log("debug", "Invoking web push handle_notify_request() for offline stanza");
	handle_notify_request(event.stanza, node, user_push_services, true);
end, 1);

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
		if st_type == "groupchat" and stanza:get_child_text("subject") then return false; end -- groupchat subjects are not important here
		return body ~= nil and body ~= ""; -- empty bodies are not important
	end
	return false; -- this stanza wasn't one of the above cases --> it is not important, too
end

-- publish on unacked smacks message
local function process_smacks_stanza(stanza, session)
	if session.push_identifier then
		session.log("debug", "Invoking web push handle_notify_request() for smacks queued stanza");
		local user_push_services = {[session.push_identifier] = session.push_settings};
		local node = get_push_settings(stanza, session);
		if handle_notify_request(stanza, node, user_push_services, true) ~= 0 then
			if session.hibernating and not session.first_hibernated_push then
				-- if important stanzas are treated differently (pushed with last-message-body field set to dummy string)
				-- and the message was important (e.g. had a last-message-body field) OR if we treat all pushes equally,
				-- then record the time of first push in the session for the smack module which will extend its hibernation
				-- timeout based on the value of session.first_hibernated_push
				if not dummy_body or (dummy_body and is_important(stanza)) then
					session.first_hibernated_push = os_time();
				end
			end
		end
	end
	return stanza;
end

local function process_smacks_queue(queue, session)
	if not session.push_identifier then return; end
	local user_push_services = {[session.push_identifier] = session.push_settings};
	local notified = { unimportant = false; important = false }
	for i=1, #queue do
		local stanza = queue[i];
		local node = get_push_settings(stanza, session);
		local stanza_type = "unimportant"
		if dummy_body and is_important(stanza) then stanza_type = "important"; end
		if not notified[stanza_type] then -- only notify if we didn't try to push for this stanza type already
			-- session.log("debug", "Invoking cloud handle_notify_request() for smacks queued stanza: %d", i);
			if handle_notify_request(stanza, node, user_push_services, false) ~= 0 then
				if session.hibernating and not session.first_hibernated_push then
					-- if important stanzas are treated differently (pushed with last-message-body field set to dummy string)
					-- and the message was important (e.g. had a last-message-body field) OR if we treat all pushes equally,
					-- then record the time of first push in the session for the smack module which will extend its hibernation
					-- timeout based on the value of session.first_hibernated_push
					if not dummy_body or (dummy_body and is_important(stanza)) then
						session.first_hibernated_push = os_time();
					end
				end
				session.log("debug", "Web Push handle_notify_request() > 0, not notifying for other queued stanzas of type %s", stanza_type);
				notified[stanza_type] = true
			end
		end
	end
end

-- smacks hibernation is started
local function hibernate_session(event)
	local session = event.origin;
	local queue = event.queue;
	session.first_hibernated_push = nil;
	-- process unacked stanzas
	process_smacks_queue(queue, session);
	-- process future unacked (hibernated) stanzas
	filters.add_filter(session, "stanzas/out", process_smacks_stanza, -990);
end

-- smacks hibernation is ended
local function restore_session(event)
	local session = event.resumed;
	if session then -- older smacks module versions send only the "intermediate" session in event.session and no session.resumed one
		filters.remove_filter(session, "stanzas/out", process_smacks_stanza);
		session.first_hibernated_push = nil;
	end
end

-- smacks ack is delayed
local function ack_delayed(event)
	local session = event.origin;
	local queue = event.queue;
	-- process unacked stanzas (handle_notify_request() will only send push requests for new stanzas)
	process_smacks_queue(queue, session);
end

-- archive message added
local function archive_message_added(event)
	-- event is: { origin = origin, stanza = stanza, for_user = store_user, id = id }
	-- only notify for new mam messages when at least one device is online
	if not event.for_user or not host_sessions[event.for_user] then return; end
	local stanza = event.stanza;
	local user_session = host_sessions[event.for_user].sessions;
	local to = stanza.attr.to;
	to = to and jid.split(to) or event.origin.username;

	-- only notify if the stanza destination is the mam user we store it for
	if event.for_user == to then
		local user_push_services = push_store:get(to);
		if next(user_push_services) == nil then return end

		-- only notify nodes with no active sessions (smacks is counted as active and handled separate)
		local notify_push_services = {};
		for identifier, push_info in pairs(user_push_services) do
			local identifier_found = nil;
			for _, session in pairs(user_session) do
				-- module:log("debug", "searching for '%s': identifier '%s' for session %s", tostring(identifier), tostring(session.push_identifier), tostring(session.full_jid));
				if session.push_identifier == identifier then
					identifier_found = session;
					break;
				end
			end
			if identifier_found then
				identifier_found.log("debug", "Not web push notifying '%s' of new MAM stanza (session still alive)", identifier);
			else
				notify_push_services[identifier] = push_info;
			end
		end

		handle_notify_request(event.stanza, to, notify_push_services, true);
	end
end

module:hook("smacks-hibernation-start", hibernate_session);
module:hook("smacks-hibernation-end", restore_session);
module:hook("smacks-ack-delayed", ack_delayed);
module:hook("archive-message-added", archive_message_added);

function module.command(arg)
  print("TODO: Generate server keypair")
end

module:log("info", "Module loaded");
function module.unload()
	if module.unhook then
		module:unhook("account-disco-info", account_disco_info);
		module:unhook("iq-set/self/"..xmlns_webpush..":enable", push_enable);
		-- module:unhook("iq-set/self/"..xmlns_webpush..":disable", push_disable);
	end

	module:log("info", "Module unloaded");
end
