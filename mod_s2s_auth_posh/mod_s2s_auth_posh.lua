-- Copyright (C) 2013 - 2014 Tobias Markmann
-- This file is MIT/X11 licensed.
--
-- Implements authentication via POSH (PKIX over Secure HTTP)
-- http://tools.ietf.org/html/draft-miller-posh-03
--
module:set_global();
--local https = require 'ssl.https'
--local http = require "socket.http";
local json = require 'util.json'
local serialization = require 'util.serialization'

local nameprep = require "util.encodings".stringprep.nameprep;
local to_unicode = require "util.encodings".idna.to_unicode;
local cert_verify_identity = require "util.x509".verify_identity;
local der2pem = require"util.x509".der2pem;
local base64 = require"util.encodings".base64;

local function posh_lookup(host_session, resume)
	-- do nothing if posh info already exists
	if host_session.posh ~= nil then return end

	(host_session.log or module._log)("debug", "DIRECTION: %s", tostring(host_session.direction));

	local target_host = false;
	if host_session.direction == "incoming" then
		target_host = host_session.from_host;
	elseif host_session.direction == "outgoing" then
		target_host = host_session.to_host;
	end

	local url = "https://"..target_host.."/.well-known/posh._xmpp-server._tcp.json"

	(host_session.log or module._log)("debug", "Request POSH information for %s", tostring(target_host));
	local request = http.request(url, nil, function(response, code, req)
				(host_session.log or module._log)("debug", "Received POSH response");
				local jwk = json.decode(response);
				if not jwk then
					(host_session.log or module._log)("error", "POSH response is not valid JSON!");
					(host_session.log or module._log)("debug", tostring(response));
				end
				host_session.posh = {};
				host_session.posh.jwk = jwk;
				resume()
		end)
	return true;
end

function module.add_host(module)
	local function on_new_s2s(event)
		local host_session = event.origin;
		if host_session.type == "s2sout" or host_session.type == "s2sin" or host_session.posh ~= nil then return end -- Already authenticated
		
		host_session.log("debug", "Pausing connection until POSH lookup is completed");
		host_session.conn:pause()
		local function resume()
				host_session.log("debug", "POSH lookup completed, resuming connection");
				host_session.conn:resume()
			end
		if not posh_lookup(host_session, resume) then
			resume();
		end
	end
	
	-- New outgoing connections
	module:hook("stanza/http://etherx.jabber.org/streams:features", on_new_s2s, 501);
	module:hook("s2sout-authenticate-legacy", on_new_s2s, 200);
	
	-- New incoming connections
	module:hook("s2s-stream-features", on_new_s2s, 10);

	module:hook("s2s-authenticated", function(event)
		local session = event.session;
		if session.posh and not session.secure then
			-- Bogus replies should trigger this path
			-- How does this interact with Dialback?
			session:close({
				condition = "policy-violation",
				text = "Secure server-to-server communication is required but was not "
					..((session.direction == "outgoing" and "offered") or "used")
			});
			return false;
		end
		-- Cleanup
		session.posh = nil;
	end);
end

-- Do POSH authentication
module:hook("s2s-check-certificate", function(event)
	local session, cert = event.session, event.cert;
	(session.log or module._log)("info", "Trying POSH authentication.");
	-- if session.cert_identity_status ~= "valid" and session.posh then
	if session.posh then
		local target_host = event.host;

		local jwk = session.posh.jwk;
 
		local connection_certs = session.conn:socket():getpeerchain();

		local x5c_table = jwk.keys[1].x5c;

		local wire_cert = connection_certs[1];
		local jwk_cert = ssl.x509.load(der2pem(base64.decode(x5c_table[1])));

		if (wire_cert and jwk_cert and
			wire_cert:digest("sha1") == jwk_cert:digest("sha1")) then
			session.cert_chain_status = "valid";
			session.cert_identity_status = "valid";
			(session.log or module._log)("debug", "POSH authentication succeeded!");
			return true;
		else
			(session.log or module._log)("debug", "POSH authentication failed!");
			(session.log or module._log)("debug", "(top wire sha1 vs top jwk sha1) = (%s vs %s)", wire_cert:digest("sha1"), jwk_cert:digest("sha1"));
			return false;
		end
	end
end);
