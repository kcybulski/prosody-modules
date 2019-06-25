local json = require "util.json";
local array = require "util.array";

module:depends("http");

local total_users = 0;
for _ in require "core.usermanager".users(module.host) do
	total_users = total_users + 1;
end

module:provides("http", {
	default_path = "/.well-known/x-nodeinfo2";
	route = {
		GET = function (event)
			event.response.headers.content_type = "application/json";
			return json.encode({
				version = "1.0";
				server = {
					baseUrl = module:http_url("","/");
					name = module.host;
					software = "Prosody";
					version = prosody.version;
				};
				--[[
				organization = {
					name = "";
					contact = "";
					account = "";
				};
				--]]
				protocols = array {
					"xmpp",
				};
				--[[
				services = {
					inbound = array {
						"irc";
					};
					outbound = array {
					};
				};
				--]]
				openRegistrations = module:get_option_boolean("allow_registration", false);
				usage = {
					users = {
						total = total_users;
						-- activeHalfyear = 1;
						-- activeMonth = 1;
						-- activeWeek = 1;
					};
					-- localPosts = 0;
					-- localComments = 0;
				};
			});
		end;
	}
});

