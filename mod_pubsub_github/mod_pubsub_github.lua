module:depends("http");

local st = require "util.stanza";
local json = require "util.json";
local formdecode = require "net.http".formdecode;
local hmac_sha1 = require "util.hashes".hmac_sha1;

local pubsub_service = module:depends("pubsub").service;
local node = module:get_option("github_node", "github");
local secret = module:get_option("github_secret");

function handle_POST(event)
	local request = event.request;
	if secret and ("sha1=" .. hmac_sha1(secret, request.body, true)) ~= request.headers.x_hub_signature then
		return 401;
	end
	local data = json.decode(request.body);
	if not data then
		return "Invalid JSON. From you of all people...";
	end

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
	end

	module:log("debug", "Handled POST: \n%s\n", tostring(request.body));
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
