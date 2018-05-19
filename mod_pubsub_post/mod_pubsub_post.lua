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

local function publish_payload(node, item_id, payload)
	local post_item = st.stanza("item", { xmlns = "http://jabber.org/protocol/pubsub", id = item_id, })
		:add_child(payload);
	local ok, err = pubsub_service:publish(node, true, item_id, post_item);
	module:log("debug", ":publish(%q, true, %q, %s) -> %q", node, item_id, payload:top_tag(), err or "");
	if not ok then
		return error_mapping[err] or 500;
	end
	return 202;
end

local function handle_xml(node, payload)
	local xmlpayload, err = xml.parse(payload);
	if not xmlpayload then
		module:log("debug", "XML parse error: %s\n%q", err, payload);
		return { status_code = 400, body = tostring(err) };
	end
	return publish_payload(node, "current", xmlpayload);
end

function handle_POST(event, path)
	local request = event.request;
	module:log("debug", "Handling POST: \n%s\n", tostring(request.body));

	local content_type = request.headers.content_type or "application/octet-stream";

	if content_type == "application/xml" or content_type:sub(-4) == "+xml" then
		return handle_xml(path, request.body);
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
