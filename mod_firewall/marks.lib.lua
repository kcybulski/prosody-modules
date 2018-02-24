local mark_storage = module:open_store("firewall_marks");

local user_sessions = prosody.hosts[module.host].sessions;

module:hook("resource-bind", function (event)
	local session = event.session;
	local username = session.username;
	local user = user_sessions[username];
	local marks = user.firewall_marks;
	if not marks then
		marks = mark_storage:get(username) or {};
		user.firewall_marks = marks; -- luacheck: ignore 122
	end
	session.firewall_marks = marks;
end);

module:hook("resource-unbind", function (event)
	local session = event.session;
	local username = session.username;
	local marks = session.firewall_marks;
	mark_storage:set(username, marks);
end);

