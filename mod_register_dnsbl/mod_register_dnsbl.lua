local adns = require "net.adns";
local async = require "util.async";

local rbl = module:get_option_string("registration_rbl");

local function reverse(ip, suffix)
	local a,b,c,d = ip:match("^(%d+).(%d+).(%d+).(%d+)$");
	if not a then return end
	return ("%d.%d.%d.%d.%s"):format(d,c,b,a, suffix);
end

module:hook("user-registering", function (event)
	local session, ip = event.session, event.ip;
	if not ip then
		session.log("debug", "Unable to check DNSBL when IP is unknown");
		return;
	end
	local rbl_ip, err = reverse(ip, rbl);
	if not rbl_ip then
		session.log("debug", "Unable to check DNSBL for ip %s: %s", ip, err);
		return;
	end

	local wait, done = async.waiter();
	adns.lookup(function (reply)
		if reply and reply[1] and reply[1].a then
			session.log("debug", "DNSBL response: %s IN A %s", rbl_ip, reply[1].a);
			session.log("info", "Blocking %s from registering %s (dnsbl hit)", ip, event.username);
			event.allowed = false;
			event.reason = "Blocked by DNSBL";
		end
		done();
	end, rbl_ip);
	wait();
end);
