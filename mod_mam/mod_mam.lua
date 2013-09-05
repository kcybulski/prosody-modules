-- XEP-0313: Message Archive Management for Prosody
-- Copyright (C) 2011-2012 Kim Alvefur
--
-- This file is MIT/X11 licensed.

local xmlns_mam     = "urn:xmpp:mam:tmp";
local xmlns_delay   = "urn:xmpp:delay";
local xmlns_forward = "urn:xmpp:forward:0";

local st = require "util.stanza";
local rsm = module:require "rsm";
local prefs = module:require"mamprefs";
local prefsxml = module:require"mamprefsxml";
local set_prefs, get_prefs = prefs.set, prefs.get;
local prefs_to_stanza, prefs_from_stanza = prefsxml.tostanza, prefsxml.fromstanza;
local jid_bare = require "util.jid".bare;
local jid_split = require "util.jid".split;
local jid_prep = require "util.jid".prep;
local host = module.host;

local rm_load_roster = require "core.rostermanager".load_roster;

local getmetatable = getmetatable;
local function is_stanza(x)
	return getmetatable(x) == st.stanza_mt;
end

local tostring = tostring;
local time_now = os.time;
local m_min = math.min;
local timestamp, timestamp_parse = require "util.datetime".datetime, require "util.datetime".parse;
local default_max_items, max_max_items = 20, module:get_option_number("max_archive_query_results", 50);
local global_default_policy = module:get_option("default_archive_policy", false);

local archive_store = "archive2";
local archive = module:open_store(archive_store, "archive");
if not archive then
	module:log("error", "Could not open archive storage");
	return
elseif not archive.find then
	module:log("error", "mod_%s does not support archiving, switch to mod_storage_sql2", archive._provided_by);
	return
end

-- Handle prefs.
module:hook("iq/self/"..xmlns_mam..":prefs", function(event)
	local origin, stanza = event.origin, event.stanza;
	local user = origin.username;
	if stanza.attr.type == "get" then
		local prefs = prefs_to_stanza(get_prefs(user));
		local reply = st.reply(stanza):add_child(prefs);
		return origin.send(reply);
	else -- type == "set"
		local new_prefs = stanza:get_child("prefs", xmlns_mam);
		local prefs = prefs_from_stanza(new_prefs);
		local ok, err = set_prefs(user, prefs);
		if not ok then
			return origin.send(st.error_reply(stanza, "cancel", "internal-server-error", "Error storing preferences: "..tostring(err)));
		end
		return origin.send(st.reply(stanza));
	end
end);

-- Handle archive queries
module:hook("iq-get/self/"..xmlns_mam..":query", function(event)
	local origin, stanza = event.origin, event.stanza;
	local query = stanza.tags[1];
	local qid = query.attr.queryid;

	-- Search query parameters
	local qwith = query:get_child_text("with");
	local qstart = query:get_child_text("start");
	local qend = query:get_child_text("end");
	module:log("debug", "Archive query, id %s with %s from %s until %s)",
		tostring(qid), qwith or "anyone", qstart or "the dawn of time", qend or "now");

	if qstart or qend then -- Validate timestamps
		local vstart, vend = (qstart and timestamp_parse(qstart)), (qend and timestamp_parse(qend))
		if (qstart and not vstart) or (qend and not vend) then
			origin.send(st.error_reply(stanza, "modify", "bad-request", "Invalid timestamp"))
			return true
		end
		qstart, qend = vstart, vend;
	end

	if qwith then -- Validate the 'with' jid
		local pwith = qwith and jid_prep(qwith);
		if pwith and not qwith then -- it failed prepping
			origin.send(st.error_reply(stanza, "modify", "bad-request", "Invalid JID"))
			return true
		end
		qwith = jid_bare(pwith);
	end

	-- RSM stuff
	local qset = rsm.get(query);
	local qmax = m_min(qset and qset.max or default_max_items, max_max_items);
	local reverse = qset and qset.before or false;
	local before, after = qset and qset.before, qset and qset.after;
	if type(before) ~= "string" then before = nil; end


	-- Load all the data!
	local data, err = archive:find(origin.username, {
		start = qstart; ["end"] = qend; -- Time range
		with = qwith;
		limit = qmax;
		before = before; after = after;
		reverse = reverse;
		total = true;
	});

	if not data then
		return origin.send(st.error_reply(stanza, "cancel", "internal-server-error"));
	end
	local count = err;

	-- Wrap it in stuff and deliver
	local first, last;
	for id, item, when in data do
		local fwd_st = st.message{ to = origin.full_jid }
			:tag("result", { xmlns = xmlns_mam, queryid = qid, id = id })
				:tag("forwarded", { xmlns = xmlns_forward })
					:tag("delay", { xmlns = xmlns_delay, stamp = timestamp(when) }):up();

		if not is_stanza(item) then
			item = st.deserialize(item);
		end
		item.attr.xmlns = "jabber:client";
		fwd_st:add_child(item);

		if not first then first = id; end
		last = id;

		origin.send(fwd_st);
	end
	-- That's all folks!
	module:log("debug", "Archive query %s completed", tostring(qid));

	if reverse then first, last = last, first; end
	return origin.send(st.reply(stanza)
		:query(xmlns_mam):add_child(rsm.generate {
			first = first, last = last, count = count }));
end);

local function has_in_roster(user, who)
	local roster = rm_load_roster(user, host);
	module:log("debug", "%s has %s in roster? %s", user, who, roster[who] and "yes" or "no");
	return roster[who];
end

local function shall_store(user, who)
	-- TODO Cache this?
	local prefs = get_prefs(user);
	local rule = prefs[who];
	module:log("debug", "%s's rule for %s is %s", user, who, tostring(rule))
	if rule ~= nil then
		return rule;
	else -- Below could be done by a metatable
		local default = prefs[false];
		module:log("debug", "%s's default rule is %s", user, tostring(default))
		if default == nil then
			default = global_default_policy;
			module:log("debug", "Using global default rule, %s", tostring(default))
		end
		if default == "roster" then
			return has_in_roster(user, who);
		end
		return default;
	end
end

-- Handle messages
local function message_handler(event, c2s)
	local origin, stanza = event.origin, event.stanza;
	local orig_type = stanza.attr.type or "normal";
	local orig_from = stanza.attr.from;
	local orig_to = stanza.attr.to or orig_from;
	-- Stanza without 'to' are treated as if it was to their own bare jid

	-- We don't store messages of these types
	if orig_type == "error"
	or orig_type == "headline"
	or orig_type == "groupchat"
	-- or that don't have a <body/>
	or not stanza:get_child("body")
	-- or if hints suggest we shouldn't
	or stanza:get_child("no-permanent-store", "urn:xmpp:hints")
	or stanza:get_child("no-store", "urn:xmpp:hints") then
		module:log("debug", "Not archiving stanza: %s (content)", stanza:top_tag());
		return;
	end

	-- Whos storage do we put it in?
	local store_user = c2s and origin.username or jid_split(orig_to);
	-- And who are they chatting with?
	local with = jid_bare(c2s and orig_to or orig_from);

	-- Check with the users preferences
	if shall_store(store_user, with) then
		module:log("debug", "Archiving stanza: %s", stanza:top_tag());

		-- And stash it
		local ok, id = archive:append(store_user, time_now(), with, stanza);
		if ok and not c2s then
			stanza:tag("archived", { xmlns = xmlns_mam, by = store_user.."@"..host, id = id }):up();
		end
	else
		module:log("debug", "Not archiving stanza: %s (prefs)", stanza:top_tag());
	end
end

local function c2s_message_handler(event)
	return message_handler(event, true);
end

-- Stanzas sent by local clients
module:hook("pre-message/bare", c2s_message_handler, 2);
module:hook("pre-message/full", c2s_message_handler, 2);
-- Stanszas to local clients
module:hook("message/bare", message_handler, 2);
module:hook("message/full", message_handler, 2);

module:add_feature(xmlns_mam);

