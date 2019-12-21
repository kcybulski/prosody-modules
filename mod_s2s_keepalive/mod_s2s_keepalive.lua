local st = require "util.stanza";

local keepalive_servers = module:get_option_set("keepalive_servers");
local keepalive_interval = module:get_option_number("keepalive_interval", 60);

local host = module.host;
local s2sout = prosody.hosts[host].s2sout;

local function send_pings()
	local ping_hosts = {};

	for remote_domain, session in pairs(s2sout) do
		if session.type == "s2sout" -- as opposed to _unauthed
		and (not(keepalive_servers) or keepalive_servers:contains(remote_domain)) then
			session.sends2s(st.iq({ to = remote_domain, type = "get", from = host, id = "keepalive" })
				:tag("ping", { xmlns = "urn:xmpp:ping" })
			);
			-- Note: We don't actually check if this comes back.
		end
	end

	for session in pairs(prosody.incoming_s2s) do
		if session.type == "s2sin" -- as opposed to _unauthed
		and (not(keepalive_servers) or keepalive_servers:contains(session.from_host)) then
			if not s2sout[session.from_host] then ping_hosts[session.from_host] = true; end
			session.sends2s " ";
			-- If the connection is dead, this should make it time out.
		end
	end

	-- ping remotes we only have s2sin from
	for remote_domain in pairs(ping_hosts) do
		module:send(st.iq({ to = remote_domain, type = "get", from = host, id = "keepalive" })
			:tag("ping", { xmlns = "urn:xmpp:ping" })
		);
	end

	return keepalive_interval;
end

module:add_timer(keepalive_interval, send_pings);
