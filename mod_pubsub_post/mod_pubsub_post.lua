module:depends("http");

local st = require "util.stanza";
local json = require "util.json";
local xml = require "util.xml";
local uuid_generate = require "util.uuid".generate;
local timestamp_generate = require "util.datetime".datetime;

local pubsub_service = module:depends("pubsub").service;

local error_mapping = {
	["forbidden"] = 403;
	["item-not-found"] = 404;
	["internal-server-error"] = 500;
	["conflict"] = 409;
};

local function publish_payload(node, actor, item_id, payload)
	local post_item = st.stanza("item", { xmlns = "http://jabber.org/protocol/pubsub", id = item_id, })
		:add_child(payload);
	local ok, err = pubsub_service:publish(node, actor, item_id, post_item);
	module:log("debug", ":publish(%q, true, %q, %s) -> %q", node, item_id, payload:top_tag(), err or "");
	if not ok then
		return error_mapping[err] or 500;
	end
	return 202;
end

local function handle_json(node, actor, data)
	local parsed, err = json.decode(data);
	if not parsed then
		return { status_code = 400; body = tostring(err); }
	end
	if type(parsed) ~= "table" then
		return { status_code = 400; body = "object or array expected"; };
	end
	local wrapper = st.stanza("json", { xmlns="urn:xmpp:json:0" }):text(data);
	return publish_payload(node, actor, data.id or "current", wrapper);
end

local function publish_atom(node, actor, feed)
	for entry in feed:childtags("entry") do
		local item_id = entry:get_child_text("id");
		if not item_id then
			item_id = uuid_generate();
			entry:tag("id"):text(item_id):up();
		end
		if not entry:get_child_text("published") then
			entry:tag("published"):text(timestamp_generate()):up();
		end
		local resp = publish_payload(node, actor, item_id, entry);
		if resp ~= 202 then return resp; end
	end
	return 202;
end

local function handle_xml(node, actor, payload)
	local xmlpayload, err = xml.parse(payload);
	if not xmlpayload then
		module:log("debug", "XML parse error: %s\n%q", err, payload);
		return { status_code = 400, body = tostring(err) };
	end
	if xmlpayload.attr.xmlns == "http://www.w3.org/2005/Atom" and xmlpayload.name == "feed" then
		return publish_atom(node, actor, xmlpayload);
	else
		return publish_payload(node, actor, "current", xmlpayload);
	end
end

local actor_source = module:get_option_string("pubsub_post_actor", "superuser");

function handle_POST(event, path)
	local request = event.request;
	module:log("debug", "Handling POST: \n%s\n", tostring(request.body));

	local content_type = request.headers.content_type or "application/octet-stream";
	local actor = true;

	if actor_source == "request.ip" then
		actor = request.ip or request.conn:ip();
	elseif actor_source ~= "superuser" then
		module:log("error", "pubsub_post_actor set to unsupported value %q", actor_source);
		return 500;
	end

	if content_type == "application/xml" or content_type:sub(-4) == "+xml" then
		return handle_xml(path, actor, request.body);
	elseif content_type == "application/json" or content_type:sub(-5) == "+json" then
		return handle_json(path, actor, request.body);
	end

	module:log("debug", "Unsupported content-type: %q", content_type);
	return 415;
end

module:provides("http", {
	route = {
		["POST /*"] = handle_POST;
	};
});

function module.load()
	module:log("debug", "Loaded at %s", module:http_url());
end
