module:depends("http");

local st = require "util.stanza";
local json = require "util.json";
local hmac_sha1 = require "util.hashes".hmac_sha1;

local pubsub_service = module:depends("pubsub").service;
local node = module:get_option("github_node", "github");
local secret = module:get_option("github_secret");

local error_mapping = {
	["forbidden"] = 403;
	["item-not-found"] = 404;
	["internal-server-error"] = 500;
	["conflict"] = 409;
};

function handle_POST(event)
	local request, response = event.request, event.response;
	if secret and ("sha1=" .. hmac_sha1(secret, request.body, true)) ~= request.headers.x_hub_signature then
		return 401;
	end
	local data = json.decode(request.body);
	if not data then
		response.status_code = 400;
		return "Invalid JSON. From you of all people...";
	end

	local github_event = request.headers.x_github_event
	if github_event == "push" then
		module:log("debug", "Handling 'push' event: \n%s\n", tostring(request.body));
	elseif github_event then
		module:log("debug", "Unsupported Github event %q", github_event);
		return 501;
	end -- else .. is this even github?

	for _, commit in ipairs(data.commits) do
		local ok, err = pubsub_service:publish(node, true, data.repository.name,
			st.stanza("item", { id = data.repository.name, xmlns = "http://jabber.org/protocol/pubsub" })
			:tag("entry", { xmlns = "http://www.w3.org/2005/Atom" })
				:tag("id"):text(commit.id):up()
				:tag("title"):text(commit.message):up()
				:tag("link", { rel = "alternate", href = commit.url }):up()
				:tag("published"):text(commit.timestamp):up()
				:tag("author")
					:tag("name"):text(commit.author.name):up()
					:tag("email"):text(commit.author.email):up()
					:up()
		);
		if not ok then
			return error_mapping[err] or 500;
		end
	end

	response.status_code = 202;
	return "Thank you Github!";
end

module:provides("http", {
	route = {
		POST = handle_POST;
	};
});

function module.load()
	if not pubsub_service.nodes[node] then
		local ok, err = pubsub_service:create(node, true);
		if not ok then
			module:log("error", "Error creating node: %s", err);
		else
			module:log("debug", "Node %q created", node);
		end
	end
end
