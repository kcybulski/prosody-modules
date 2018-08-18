-- Prosody IM
-- Copyright (C) 2008-2010 Matthew Wild
-- Copyright (C) 2008-2010 Waqas Hussain
-- Copyright (C) 2011 Kim Alvefur
-- Copyright (C) 2018 Emmanuel Gil Peyrot
--
-- This project is MIT/X11 licensed. Please see the
-- COPYING file in the source package for more information.
--

local st = require "util.stanza"
local dm_load = require "util.datamanager".load
local jid_split = require "util.jid".split

-- COMPAT w/trunk
local is_on_trunk = false;
local mm = require "core.modulemanager";
if mm.get_modules_for_host then
	if mm.get_modules_for_host(module.host):contains("bookmarks") then
		is_on_trunk = true;
	end
end

local function get_default_bookmarks(nickname)
	local bookmarks = module:get_option("default_bookmarks");
	if not bookmarks or #bookmarks == 0 then
		return false;
	end
	local reply = st.stanza("storage", { xmlns = "storage:bookmarks" });
	local nick = nickname and st.stanza("nick"):text(nickname);
	for _, bookmark in ipairs(bookmarks) do
		if type(bookmark) ~= "table" then -- assume it's only a jid
			bookmark = { jid = bookmark, name = jid_split(bookmark) };
		end
		reply:tag("conference", {
			jid = bookmark.jid,
			name = bookmark.name,
			autojoin = "1",
		});
		if nick then
			reply:add_child(nick):up();
		end
		reply:up();
	end
	return reply;
end

if is_on_trunk then
	local mod_bookmarks = module:depends "bookmarks";
	local function on_bookmarks_empty(event)
		local session = event.session;
		local bookmarks = get_default_bookmarks(session.username);
		if bookmarks then
			mod_bookmarks.publish_to_pep(session.full_jid, bookmarks);
		end
	end
	module:hook("bookmarks/empty", on_bookmarks_empty);
else
	local function on_private_xml_get(event)
		local origin, stanza = event.origin, event.stanza;
		local tag = stanza.tags[1].tags[1];
		local key = tag.name..":"..tag.attr.xmlns;
		if key ~= "storage:storage:bookmarks" then
			return;
		end

		local data, err = dm_load(origin.username, origin.host, "private");
		if data and data[key] then
			return;
		end

		local bookmarks = get_default_bookmarks(origin.username);
		if not bookmarks then
			return;
		end;

		local reply = st.reply(stanza):tag("query", { xmlns = "jabber:iq:private" })
			:add_child(bookmarks);
		origin.send(reply);
		return true;
	end
	module:hook("iq-get/self/jabber:iq:private:query", on_private_xml_get, 1);
end
