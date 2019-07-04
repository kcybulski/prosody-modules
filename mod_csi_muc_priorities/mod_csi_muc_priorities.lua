local jid_bare, jid_split = import("util.jid", "bare", "split");

-- luacheck: ignore 122
local user_sessions = prosody.hosts[module.host].sessions;

module:hook("csi-is-stanza-important", function (event)
	local stanza, session = event.stanza, event.session;
	if stanza.name == "message" then
		if stanza.attr.type == "groupchat" then
			local body = stanza:get_child_text("body");
			if not body then return end

			local room_jid = jid_bare(stanza.attr.from);

			local username = session.username;
			local priorities = user_sessions[username].csi_muc_priorities;

			if not priorities or priorities[room_jid] ~= false then
				return nil;
			end

			-- Look for mention
			local rooms = session.rooms_joined;
			if rooms then
				local room_nick = rooms[room_jid];
				if room_nick then
					if body:find(room_nick, 1, true) then
						return true;
					end
					if stanza.attr.from == (room_jid .. "/" .. room_nick) then
						return true;
					end
				end
			elseif session.directed and session.directed[stanza.attr.from] then
				-- fallback if no mod_track_muc_joins
				return true;
			end

			-- Unimportant and no mention
			return false;
		end
	end
end);

module:depends("adhoc");

local dataform = require"util.dataforms";
local adhoc_inital_data = require "util.adhoc".new_initial_data_form;
local instructions = [[
These settings affect battery optimizations performed by the server
while your client has indicated that it is inactive.
]]

local priority_settings_form = dataform.new {
	title = "Prioritize addresses of group chats";
	instructions = instructions;
	{
		type = "hidden";
		name = "FORM_TYPE";
		value = "xmpp:modules.prosody.im/mod_"..module.name;
	};
	{
		type = "jid-multi";
		name = "unimportant";
		label = "Lower priority";
		desc = "E.g. large noisy public channels";
	};
}

local store = module:open_store();
module:hook("resource-bind", function (event)
	local username = event.session.username;
	user_sessions[username].csi_muc_priorities = store:get(username);
end);

local adhoc_command_handler = adhoc_inital_data(priority_settings_form, function (data)
	local username = jid_split(data.from);
	local prioritized_jids = user_sessions[username].csi_muc_priorities or store:get(username);
	local unimportant = {};
	if prioritized_jids then
		for jid in pairs(prioritized_jids) do
			table.insert(unimportant, jid);
		end
		table.sort(unimportant);
	end
	return { unimportant = unimportant };
end, function(fields, form_err, data)
	if form_err then
		return { status = "completed", error = { message = "Problem in submitted form" } };
	end
	local prioritized_jids = {};
	if fields.unimportant then
		for _, jid in ipairs(fields.unimportant) do
			prioritized_jids[jid] = false;
		end
	end

	local username = jid_split(data.from);
	local ok, err = store:set(username, prioritized_jids);
	if ok then
		user_sessions[username].csi_muc_priorities = prioritized_jids;
		return { status = "completed", info = "Priorities updated" };
	else
		return { status = "completed", error = { message = "Error saving priorities: "..err } };
	end
end);

module:add_item("adhoc", module:require "adhoc".new("Configure group chat priorities",
	"xmpp:modules.prosody.im/mod_"..module.name, adhoc_command_handler, "local_user"));
