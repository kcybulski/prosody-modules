local adns = require "net.adns";
local rbl = module:get_option_string("registration_rbl");

local function reverse(ip, suffix)
	local a,b,c,d = ip:match("^(%d+).(%d+).(%d+).(%d+)$");
	if not a then return end
	return ("%d.%d.%d.%d.%s"):format(d,c,b,a, suffix);
end

module:hook("user-registered", function (event)
	local session = event.session;
	local ip = session and session.ip;
	local rbl_ip = ip and reverse(ip, rbl);
	if rbl_ip then
		local registration_time = os.time();
		local log = session.log;
		adns.lookup(function (reply)
			if reply and reply[1] then
				log("warn", "Account %s@%s registered from IP %s found in RBL (%s)", event.username, event.host or module.host, ip, reply[1].a);
				local user = prosody.bare_sessions[event.username .. "@" .. module.host];
				if user and user.firewall_marks then
					user.firewall_marks.dnsbl_hit = registration_time;
				else
					module:open_store("firewall_marks", "map"):set(event.username, "dnsbl_hit", registration_time);
				end
			end
		end, rbl_ip);
	end
end);
