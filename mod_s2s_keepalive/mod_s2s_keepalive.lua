local st = require "util.stanza";
local watchdog = require "util.watchdog";

local keepalive_servers = module:get_option_set("keepalive_servers");
local keepalive_interval = module:get_option_number("keepalive_interval", 60);
local keepalive_timeout = module:get_option_number("keepalive_timeout", 593);

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

module:hook("s2sin-established", function (event)
	local session = event.session;
	if session.watchdog_keepalive then return end -- in case mod_bidi fires this twice
	session.watchdog_keepalive = watchdog.new(keepalive_timeout, function ()
		session.log("info", "Keepalive ping timed out, closing connection");
		session:close("connection-timeout");
	end);
end);

module:hook("s2sout-established", function (event)
	local session = event.session;
	if session.watchdog_keepalive then return end -- in case mod_bidi fires this twice
	session.watchdog_keepalive = watchdog.new(keepalive_timeout, function ()
		session.log("info", "Keepalive ping timed out, closing connection");
		session:close("connection-timeout");
	end);
end);

module:hook("iq-result/host/keepalive", function (event)
	local origin = event.origin;
	if origin.watchdog_keepalive then
		origin.watchdog_keepalive:reset();
	end
	if s2sout[origin.from_host] and s2sout[origin.from_host].watchdog_keepalive then
		s2sout[origin.from_host].watchdog_keepalive:reset();
	end
	return true;
end);

module:hook("iq-error/host/keepalive", function (event)
	local origin = event.origin;
	if origin.dummy then return end -- Probably a sendq bounce

	if origin.type == "s2sin" or origin.type == "s2sout" then
		-- An error from the remote means connectivity is ok,
		-- so treat it the same as a result
		return module:fire_event("iq-result/host/keepalive", event);
	end
end);

module:add_timer(keepalive_interval, send_pings);
