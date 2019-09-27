-- Prosody IM
-- Copyright (C) 2019 Kim Alvefur
--
-- This project is MIT/X11 licensed. Please see the
-- COPYING file in the source package for more information.
--
-- XEP-0388: Extensible SASL Profile
--

local st = require "util.stanza";
local errors = require "util.error";
local base64 = require "util.encodings".base64;
local jid_join = require "util.jid".join;

local usermanager_get_sasl_handler = require "core.usermanager".get_sasl_handler;
local sm_make_authenticated = require "core.sessionmanager".make_authenticated;

local xmlns_sasl2 = "urn:xmpp:sasl:1";

local allow_unencrypted_plain_auth = module:get_option_boolean("allow_unencrypted_plain_auth", false)
local insecure_mechanisms = module:get_option_set("insecure_sasl_mechanisms", allow_unencrypted_plain_auth and {} or {"PLAIN", "LOGIN"});
local disabled_mechanisms = module:get_option_set("disable_sasl_mechanisms", { "DIGEST-MD5" });

local host = module.host;

local function tls_unique(self)
	return self.userdata["tls-unique"]:getpeerfinished();
end

module:hook("stream-features", function(event)
	local origin, features = event.origin, event.features;
	local log = origin.log or module._log;

	if origin.type ~= "c2s_unauthed" then
		log("debug", "Already authenticated");
		return
	end

	local sasl_handler = usermanager_get_sasl_handler(host, origin)
	origin.sasl_handler = sasl_handler;

	if sasl_handler.add_cb_handler then
		local socket = origin.conn:socket();
		if socket.getpeerfinished then
			sasl_handler:add_cb_handler("tls-unique", tls_unique);
		end
		sasl_handler["userdata"] = {
			["tls-unique"] = socket;
		};
	end

	local mechanisms = st.stanza("mechanisms", { xmlns = xmlns_sasl2 });

	local available_mechanisms = sasl_handler:mechanisms()
	for mechanism in pairs(available_mechanisms) do
		if disabled_mechanisms:contains(mechanism) then
			log("debug", "Not offering disabled mechanism %s", mechanism);
		elseif not origin.secure and insecure_mechanisms:contains(mechanism) then
			log("debug", "Not offering mechanism %s on insecure connection", mechanism);
		else
			log("debug", "Offering mechanism %s", mechanism);
			mechanisms:text_tag("mechanism", mechanism);
		end
	end

	features:add_direct_child(mechanisms);
end, 1);

local function handle_status(session, status, ret, err_msg)
	local err = nil;
	if status == "error" then
		ret, err = nil, ret;
		if not errors.is_err(err) then
			err = errors.new({ condition = err, text = err_msg }, { session = session });
		end
	end

	module:fire_event("sasl2/"..session.base_type.."/"..status, {
			session = session,
			message = ret;
			error = err;
		});
end

module:hook("sasl2/c2s/failure", function (event)
	local session = event.session
	session.send(st.stanza("failure", { xmlns = xmlns_sasl2 })
		:tag(event.error.condition));
	return true;
end);

module:hook("sasl2/c2s/challenge", function (event)
	local session = event.session;
	session.send(st.stanza("challenge", { xmlns = xmlns_sasl2 })
		:text_tag(event.message));
end);

module:hook("sasl2/c2s/success", function (event)
	local session = event.session
	local ok, err = sm_make_authenticated(session, session.sasl_handler.username);
	if not ok then
		handle_status(session, "failure", err);
		return true;
	end
	event.success = st.stanza("success", { xmlns = xmlns_sasl2 });
end, 1000);

module:hook("sasl2/c2s/success", function (event)
	local session = event.session
	event.success:text_tag("authorization-identifier", jid_join(session.username, session.host, session.resource));
	session.send(event.success);
	local features = st.stanza("stream:features");
	module:fire_event("stream-features", { origin = session, features = features });
	session.send(features);
end, -1000);

local function process_cdata(session, cdata)
	if cdata then
		cdata = base64.decode(cdata);
		if not cdata then
			return handle_status(session, "failure");
		end
	end
	return handle_status(session, session.sasl_handler:process(cdata));
end

module:hook_tag(xmlns_sasl2, "authenticate", function (session, auth)
	local sasl_handler = session.sasl_handler;
	if not sasl_handler then
		sasl_handler = usermanager_get_sasl_handler(host, session);
		session.sasl_handler = sasl_handler;
	end
	local mechanism = assert(auth.attr.mechanism);
	if not sasl_handler:select(mechanism) then
		return handle_status(session, "failure");
	end
	local initial = auth:get_child_text("initial-response");
	return process_cdata(session, initial);
end);

module:hook_tag(xmlns_sasl2, "response", function (session, response)
	local sasl_handler = session.sasl_handler;
	if not sasl_handler or not sasl_handler.selected then
		return handle_status(session, "failure");
	end
	return process_cdata(session, response:get_text());
end);
