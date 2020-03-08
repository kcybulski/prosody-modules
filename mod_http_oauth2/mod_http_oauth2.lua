local http = require "util.http";
local jid = require "util.jid";
local json = require "util.json";
local usermanager = require "core.usermanager";
local errors = require "util.error";

local tokens = module:depends("tokenauth");

local function oauth_error(err_name, err_desc)
	return errors.new({
		type = "modify";
		condition = "bad-request";
		code = err_name == "invalid_client" and 401 or 400;
		text = err_desc and (err_name..": "..err_desc) or err_name;
		context = { oauth2_response = { error = err_name, error_description = err_desc } };
	});
end

local function new_access_token(token_jid, scope, ttl)
	local token = tokens.create_jid_token(token_jid, token_jid, scope, ttl);
	return {
		token_type = "bearer";
		access_token = token;
		expires_in = ttl;
		-- TODO: include refresh_token when implemented
	};
end

local grant_type_handlers = {};

function grant_type_handlers.password(params)
	local request_jid = assert(params.username, oauth_error("invalid_request", "missing 'username' (JID)"));
	local request_password = assert(params.password, oauth_error("invalid_request", "missing 'password'"));
	local request_username, request_host, request_resource = jid.prepped_split(request_jid);
	if params.scope then
		return oauth_error("invalid_scope", "unknown scope requested");
	end
	if not (request_username and request_host) or request_host ~= module.host then
		return oauth_error("invalid_request", "invalid JID");
	end
	if usermanager.test_password(request_username, request_host, request_password) then
		local granted_jid = jid.join(request_username, request_host, request_resource);
		return json.encode(new_access_token(granted_jid, request_host, nil, nil));
	end
	return oauth_error("invalid_grant", "incorrect credentials");
end

if module:get_host_type() == "component" then
	local component_secret = assert(module:get_option_string("component_secret"), "'component_secret' is a required setting when loaded on a Component");

	function grant_type_handlers.password(params)
		local request_jid = assert(params.username, oauth_error("invalid_request", "missing 'username' (JID)"));
		local request_password = assert(params.password, oauth_error("invalid_request", "missing 'password'"));
		local request_username, request_host, request_resource = jid.prepped_split(request_jid);
		if params.scope then
			return oauth_error("invalid_scope", "unknown scope requested");
		end
		if not request_host or request_host ~= module.host then
			return oauth_error("invalid_request", "invalid JID");
		end
		if request_password == component_secret then
			local granted_jid = jid.join(request_username, request_host, request_resource);
			return json.encode(new_access_token(granted_jid, request_host, nil, nil));
		end
		return oauth_error("invalid_grant", "incorrect credentials");
	end
end

function handle_token_grant(event)
	event.response.headers.content_type = "application/json";
	local params = http.formdecode(event.request.body);
	if not params then
		return oauth_error("invalid_request");
	end
	local grant_type = params.grant_type
	local grant_handler = grant_type_handlers[grant_type];
	if not grant_handler then
		return oauth_error("unsupported_grant_type");
	end
	return grant_handler(params);
end

module:depends("http");
module:provides("http", {
	route = {
		["POST /token"] = handle_token_grant;
	};
});

local http_server = require "net.http.server";

module:hook_object_event(http_server, "http-error", function (event)
	local oauth2_response = event.error and event.error.context and event.error.context.oauth2_response;
	if not oauth2_response then
		return;
	end
	event.response.headers.content_type = "application/json";
	event.response.status_code = event.error.code or 400;
	return json.encode(oauth2_response);
end, 5);
