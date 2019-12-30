-- RESTful API
--
-- Copyright (c) 2019 Kim Alvefur
--
-- This file is MIT/X11 licensed.

local errors = require "util.error";
local id = require "util.id";
local jid = require "util.jid";
local xml = require "util.xml";

local allow_any_source = module:get_host_type() == "component";
local validate_from_addresses = module:get_option_boolean("validate_from_addresses", true);

local function handle_post(event)
	local request, response = event.request, event.response;
	if request.headers.content_type ~= "application/xmpp+xml" then
		return errors.new({ code = 415, text = "'application/xmpp+xml' expected"  });
	end
	local payload, err = xml.parse(request.body);
	if not payload then
		-- parse fail
		return errors.new({ code = 400, text = err });
	end
	local to = jid.prep(payload.attr.to);
	if not to then
		return errors.new({ code = 400, text = "Invalid destination JID" });
	end
	local from = module.host;
	if allow_any_source and payload.attr.from then
		from = jid.prep(payload.attr.from);
		if not from then
			return errors.new({ code = 400, text = "Invalid source JID" });
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
	if payload.name == "iq" then
		if payload.attr.type ~= "get" and payload.attr.type ~= "set" then
			return errors.new({ code = 400, text = "'iq' stanza must be of type 'get' or 'set'" });
		end
		return module:send_iq(payload):next(
			function (result)
				response.headers.content_type = "application/xmpp+xml";
				return tostring(result.stanza);
			end,
			function (error)
				if error.context.stanza then
					response.headers.content_type = "application/xmpp+xml";
					return tostring(error.context.stanza);
				else
					return error;
				end
			end);
	elseif payload.name == "message" or payload.name == "presence" then
		if module:send(payload) then
			return 202;
		else
			return 500;
		end
	else
		return errors.new({ code = 400, text = "Invalid stanza, must be 'message', 'presence' or 'iq'." });
	end
end

-- Handle stanzas submitted via HTTP
module:depends("http");
module:provides("http", {
		route = {
			POST = handle_post;
		};
	});
