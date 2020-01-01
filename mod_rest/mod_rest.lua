-- RESTful API
--
-- Copyright (c) 2019-2020 Kim Alvefur
--
-- This file is MIT/X11 licensed.

local errors = require "util.error";
local http = require "net.http";
local id = require "util.id";
local jid = require "util.jid";
local st = require "util.stanza";
local xml = require "util.xml";

local allow_any_source = module:get_host_type() == "component";
local validate_from_addresses = module:get_option_boolean("validate_from_addresses", true);
local secret = assert(module:get_option_string("rest_credentials"), "rest_credentials is a required setting");
local auth_type = assert(secret:match("^%S+"), "Format of rest_credentials MUST be like 'Bearer secret'");
assert(auth_type == "Bearer", "Only 'Bearer' is supported in rest_credentials");

-- Bearer token
local function check_credentials(request)
	return request.headers.authorization == secret;
end

local function handle_post(event)
	local request, response = event.request, event.response;
	if not request.headers.authorization then
		response.headers.www_authenticate = ("%s realm=%q"):format(auth_type, module.host.."/"..module.name);
		return 401;
	elseif not check_credentials(request) then
		return 401;
	end
	if request.headers.content_type ~= "application/xmpp+xml" then
		return errors.new({ code = 415, text = "'application/xmpp+xml' expected"  });
	end
	local payload, err = xml.parse(request.body);
	if not payload then
		-- parse fail
		return errors.new({ code = 400, text = err });
	end
	if payload.attr.xmlns then
		return errors.new({ code = 422, text = "'xmlns' attribute must be empty" });
	elseif payload.name ~= "message" and payload.name ~= "presence" and payload.name ~= "iq" then
		return errors.new({ code = 422, text = "Invalid stanza, must be 'message', 'presence' or 'iq'." });
	end
	local to = jid.prep(payload.attr.to);
	if not to then
		return errors.new({ code = 422, text = "Invalid destination JID" });
	end
	local from = module.host;
	if allow_any_source and payload.attr.from then
		from = jid.prep(payload.attr.from);
		if not from then
			return errors.new({ code = 422, text = "Invalid source JID" });
		end
		if validate_from_addresses and not jid.compare(from, module.host) then
			return errors.new({ code = 403, text = "Source JID must belong to current host" });
		end
	end
	payload.attr = {
		from = from,
		to = to,
		id = payload.attr.id or id.medium(),
		type = payload.attr.type,
		["xml:lang"] = payload.attr["xml:lang"],
	};
	module:log("debug", "Received[rest]: %s", payload:top_tag());
	if payload.name == "iq" then
		if payload.attr.type ~= "get" and payload.attr.type ~= "set" then
			return errors.new({ code = 422, text = "'iq' stanza must be of type 'get' or 'set'" });
		end
		return module:send_iq(payload):next(
			function (result)
				response.headers.content_type = "application/xmpp+xml";
				module:log("debug", "Sending[rest]: %s", result.stanza:top_tag());
				return tostring(result.stanza);
			end,
			function (error)
				if error.context.stanza then
					response.headers.content_type = "application/xmpp+xml";
					module:log("debug", "Sending[rest]: %s", error.context.stanza:top_tag());
					return tostring(error.context.stanza);
				else
					return error;
				end
			end);
	else
		local origin = {};
		function origin.send(stanza)
			module:log("debug", "Sending[rest]: %s", stanza:top_tag());
			response:send(tostring(stanza));
			return true;
		end
		response.headers.content_type = "application/xmpp+xml";
		if module:send(payload, origin) then
			return 202;
		else
			return 500;
		end
	end
end

-- Handle stanzas submitted via HTTP
module:depends("http");
module:provides("http", {
		route = {
			POST = handle_post;
		};
	});

-- Forward stanzas from XMPP to HTTP and return any reply
local rest_url = module:get_option_string("rest_callback_url", nil);
if rest_url then

	local code2err = {
		[400] = { condition = "bad-request"; type = "modify" };
		[401] = { condition = "not-authorized"; type = "auth" };
		[402] = { condition = "not-authorized"; type = "auth" };
		[403] = { condition = "forbidden"; type = "auth" };
		[404] = { condition = "item-not-found"; type = "cancel" };
		[406] = { condition = "not-acceptable"; type = "modify" };
		[408] = { condition = "remote-server-timeout"; type = "wait" };
		[409] = { condition = "conflict"; type = "cancel" };
		[410] = { condition = "gone"; type = "cancel" };
		[411] = { condition = "bad-request"; type = "modify" };
		[412] = { condition = "bad-request"; type = "modify" };
		[413] = { condition = "resource-constraint"; type = "modify" };
		[414] = { condition = "resource-constraint"; type = "modify" };
		[415] = { condition = "bad-request"; type = "modify" };
		[429] = { condition = "resource-constraint"; type = "wait" };
		[431] = { condition = "resource-constraint"; type = "wait" };

		[500] = { condition = "internal-server-error"; type = "cancel" };
		[501] = { condition = "feature-not-implemented"; type = "modify" };
		[502] = { condition = "remote-server-timeout"; type = "wait" };
		[503] = { condition = "service-unavailable"; type = "cancel" };
		[504] = { condition = "remote-server-timeout"; type = "wait" };
		[507] = { condition = "resource-constraint"; type = "wait" };
	};

	local function handle_stanza(event)
		local stanza, origin = event.stanza, event.origin;
		local reply_needed = stanza.name == "iq";
		local receipt;

		if stanza.name == "message" and stanza.attr.id and stanza:get_child("urn:xmpp:receipts", "request") then
			reply_needed = true;
			receipt = st.stanza("received", { xmlns = "urn:xmpp:receipts", id = stanza.id });
		end

		local request_body = tostring(stanza);

		-- Keep only the top level element and let the rest be GC'd
		stanza = st.clone(stanza, true);

		module:log("debug", "Sending[rest]: %s", stanza:top_tag());
		http.request(rest_url, {
				body = request_body,
				headers = {
					["Content-Type"] = "application/xmpp+xml",
					["Content-Language"] = stanza.attr["xml:lang"],
					Accept = "application/xmpp+xml, text/plain",
				},
			}, function (body, code, response)
				if (code == 202 or code == 204) and not reply_needed then
					-- Delivered, no reply
					return;
				end
				local reply, reply_text;

				if response.headers["content-type"] == "application/xmpp+xml" then
					local parsed, err = xml.parse(body);
					if not parsed then
						module:log("warn", "REST callback responded with invalid XML: %s, %q", err, body);
					elseif parsed.name ~= stanza.name then
						module:log("warn", "REST callback responded with the wrong stanza type, got %s but expected %s", parsed.name, stanza.name);
					else
						parsed.attr.to, parsed.attr.from = stanza.attr.from, stanza.attr.to;
						if parsed.name == "iq" then
							parsed.attr.id = stanza.attr.id;
						end
						reply = parsed;
					end
				elseif response.headers["content-type"] == "text/plain" then
					reply = st.reply(stanza);
					if body ~= "" then
						reply_text = body;
					end
				elseif body ~= "" then -- ignore empty body
					module:log("debug", "Callback returned response of unhandled type %q", response.headers["content-type"]);
				end

				if not reply then
					local code_hundreds = code - (code % 100);
					if code_hundreds == 200 then
						reply = st.reply(stanza);
						if stanza.name ~= "iq" then
							reply.attr.id = id.medium();
						end
						if reply_text and reply.name == "message" then
							reply:body(reply_text, { ["xml:lang"] = response.headers["content-language"] });
						end
						-- TODO presence/status=body ?
					elseif code2err[code] then
						reply = st.error_reply(stanza, errors.new(code, nil, code2err));
					elseif code_hundreds == 400 then
						reply = st.error_reply(stanza, "modify", "bad-request", reply_text);
					elseif code_hundreds == 500 then
						reply = st.error_reply(stanza, "cancel", "internal-server-error", reply_text);
					else
						reply = st.error_reply(stanza, "cancel", "undefined-condition", reply_text);
					end
				end

				if receipt then
					reply:add_direct_child(receipt);
				end

				module:log("debug", "Received[rest]: %s", reply:top_tag());

				origin.send(reply);
			end);

		return true;
	end

	if module:get_host_type() == "component" then
		module:hook("iq/bare", handle_stanza, -1);
		module:hook("message/bare", handle_stanza, -1);
		module:hook("presence/bare", handle_stanza, -1);
		module:hook("iq/full", handle_stanza, -1);
		module:hook("message/full", handle_stanza, -1);
		module:hook("presence/full", handle_stanza, -1);
		module:hook("iq/host", handle_stanza, -1);
		module:hook("message/host", handle_stanza, -1);
		module:hook("presence/host", handle_stanza, -1);
	else
		-- Don't override everything on normal VirtualHosts
		module:hook("iq/host", handle_stanza, -1);
		module:hook("message/host", handle_stanza, -1);
		module:hook("presence/host", handle_stanza, -1);
	end
end
