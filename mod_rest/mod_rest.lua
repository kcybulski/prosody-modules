-- RESTful API
--
-- Copyright (c) 2019-2020 Kim Alvefur
--
-- This file is MIT/X11 licensed.

local errors = require "util.error";
local http = require "net.http";
local id = require "util.id";
local jid = require "util.jid";
local json = require "util.json";
local st = require "util.stanza";
local xml = require "util.xml";

local allow_any_source = module:get_host_type() == "component";
local validate_from_addresses = module:get_option_boolean("validate_from_addresses", true);
local secret = assert(module:get_option_string("rest_credentials"), "rest_credentials is a required setting");
local auth_type = assert(secret:match("^%S+"), "Format of rest_credentials MUST be like 'Bearer secret'");
assert(auth_type == "Bearer", "Only 'Bearer' is supported in rest_credentials");

local jsonmap = module:require"jsonmap";
-- Bearer token
local function check_credentials(request)
	return request.headers.authorization == secret;
end

local function parse(mimetype, data)
	mimetype = mimetype and mimetype:match("^[^; ]*");
	if mimetype == "application/xmpp+xml" then
		return xml.parse(data);
	elseif mimetype == "application/json" then
		local parsed, err = json.decode(data);
		if not parsed then
			return parsed, err;
		end
		return jsonmap.json2st(parsed);
	elseif mimetype == "text/plain" then
		return st.message({ type = "chat" }, data);
	end
	return nil, "unknown-payload-type";
end

local supported_types = { "application/xmpp+xml", "application/json" };

local function decide_type(accept)
	-- assumes the accept header is sorted
	local ret = supported_types[1];
	for i = 2, #supported_types do
		if (accept:find(supported_types[i], 1, true) or 1000) < (accept:find(ret, 1, true) or 1000) then
			ret = supported_types[i];
		end
	end
	return ret;
end

local function encode(type, s)
	if type == "application/json" then
		return json.encode(jsonmap.st2json(s));
	elseif type == "text/plain" then
		return s:get_child_text("body") or "";
	end
	return tostring(s);
end

local function handle_post(event)
	local request, response = event.request, event.response;
	if not request.headers.authorization then
		response.headers.www_authenticate = ("%s realm=%q"):format(auth_type, module.host.."/"..module.name);
		return 401;
	elseif not check_credentials(request) then
		return 401;
	end
	local payload, err = parse(request.headers.content_type, request.body);
	if not payload then
		-- parse fail
		return errors.new({ code = 400, text = "Failed to parse payload" }, { error = err, type = request.headers.content_type, data = request.body });
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
	local send_type = decide_type((request.headers.accept or "") ..",".. request.headers.content_type)
	if payload.name == "iq" then
		if payload.attr.type ~= "get" and payload.attr.type ~= "set" then
			return errors.new({ code = 422, text = "'iq' stanza must be of type 'get' or 'set'" });
		elseif #payload.tags ~= 1 then
			return errors.new({ code = 422, text = "'iq' stanza must have exactly one child tag" });
		end
		return module:send_iq(payload):next(
			function (result)
				module:log("debug", "Sending[rest]: %s", result.stanza:top_tag());
				response.headers.content_type = send_type;
				return encode(send_type, result.stanza);
			end,
			function (error)
				if error.context.stanza then
					response.headers.content_type = send_type;
					module:log("debug", "Sending[rest]: %s", error.context.stanza:top_tag());
					return encode(send_type, error.context.stanza);
				else
					return error;
				end
			end);
	else
		local origin = {};
		function origin.send(stanza)
			module:log("debug", "Sending[rest]: %s", stanza:top_tag());
			response.headers.content_type = send_type;
			response:send(encode(send_type, stanza));
			return true;
		end
		module:send(payload, origin);
		return 202;
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
	local send_type = module:get_option_string("rest_callback_content_type", "application/xmpp+xml");
	if send_type == "json" then
		send_type = "application/json";
	end

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

		if stanza.attr.type == "error" then
			reply_needed = false;
		end

		if stanza.name == "message" and stanza.attr.id and stanza:get_child("urn:xmpp:receipts", "request") then
			reply_needed = true;
			receipt = st.stanza("received", { xmlns = "urn:xmpp:receipts", id = stanza.id });
		end

		local request_body = encode(send_type, stanza);

		-- Keep only the top level element and let the rest be GC'd
		stanza = st.clone(stanza, true);

		module:log("debug", "Sending[rest]: %s", stanza:top_tag());
		http.request(rest_url, {
				body = request_body,
				headers = {
					["Content-Type"] = send_type,
					["Content-Language"] = stanza.attr["xml:lang"],
					Accept = table.concat(supported_types, ", ");
				},
			}, function (body, code, response)
				if (code == 202 or code == 204) and not reply_needed then
					-- Delivered, no reply
					return;
				end
				local reply;

				local parsed, err = parse(response.headers["content-type"], body);
				if not parsed then
					module:log("warn", "Failed parsing data from REST callback: %s, %q", err, body);
				elseif parsed.name ~= stanza.name then
					module:log("warn", "REST callback responded with the wrong stanza type, got %s but expected %s", parsed.name, stanza.name);
				else
					parsed.attr = {
						from = stanza.attr.to,
						to = stanza.attr.from,
						id = parsed.attr.id or id.medium();
						type = parsed.attr.type,
						["xml:lang"] = parsed.attr["xml:lang"],
					};
					if parsed.name == "message" and parsed.attr.type == "groupchat" then
						parsed.attr.to = jid.bare(stanza.attr.from);
					end
					if not stanza.attr.type and parsed:get_child("error") then
						parsed.attr.type = "error";
					end
					if parsed.attr.type == "error" then
						parsed.attr.id = stanza.attr.id;
					elseif parsed.name == "iq" then
						parsed.attr.id = stanza.attr.id;
						parsed.attr.type = "result";
					end
					reply = parsed;
				end

				if not reply then
					local code_hundreds = code - (code % 100);
					if code_hundreds == 200 then
						reply = st.reply(stanza);
						if stanza.name ~= "iq" then
							reply.attr.id = id.medium();
						end
						-- TODO presence/status=body ?
					elseif code2err[code] then
						reply = st.error_reply(stanza, errors.new(code, nil, code2err));
					elseif code_hundreds == 400 then
						reply = st.error_reply(stanza, "modify", "bad-request", body);
					elseif code_hundreds == 500 then
						reply = st.error_reply(stanza, "cancel", "internal-server-error", body);
					else
						reply = st.error_reply(stanza, "cancel", "undefined-condition", body);
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

local http_server = require "net.http.server";
module:hook_object_event(http_server, "http-error", function (event)
	local request, response = event.request, event.response;
	if true or decide_type(request and request.headers.accept or "") == "application/json" then
		if response then
			response.headers.content_type = "application/json";
		end
		return json.encode({
				type = "error",
				error = event.error,
				code = event.code,
			});
	end
end, 10);
